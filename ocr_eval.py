"""Сверка OCR-распознавания отсканированных счетов с расшифровками-эталонами.

Расшифровки лежат рядом с PDF (example_data — gitignored): «<стем>.txt»
(pipe-таблица, мсм) или «<стем>.xlsx» (перфорация). Счета без расшифровки
прогоняются «вслепую»: печатаем инварианты для просмотра пользователем.

Режимы:
  module — быстрый цикл итераций: прямой вызов ocr_recog + normalizer
           (пока без сайдкара; supplier-логика продублирована до рефакторины
           extract_supplier_from_text);
  sidecar — честный контракт: subprocess sidecar.py --action=recognize.

Выход: отчёт по-ячейково; код 1, если эталонный счёт «перфорации» не прошёл
критерии приёмки (19/19 позиций, точные qty/unit/sum, ИНН/КПП).
"""

import argparse
import difflib
import json
import os
import re
import subprocess
import sys

import pandas as pd

REPO = os.path.dirname(os.path.abspath(__file__))
DATA_DEFAULT = os.path.join(REPO, "example_data", "scanned_docs")

# Критерии приёмки (из плана): эталонная «перфорация» должна быть зелёной.
NAME_SIM_MIN = 0.9
SUM_TOL = 0.01


# ---------------------------------------------------------------- эталоны

def _gt_num(s):
    """Число из расшифровки: ' — и разряды, и (перед двумя цифрами) десятичная."""
    s = str(s).strip().replace("\xa0", "").replace(" ", "")
    if not s or s.lower() in ("nan", "none"):
        return None
    s = re.sub(r"'(?=\d{2}$)", ".", s)
    s = s.replace("'", "").replace(",", ".")
    try:
        return round(float(s), 2)
    except ValueError:
        return None


def _norm_name(s):
    return re.sub(r"\s+", " ", str(s).lower()).strip()


def _norm_unit(s):
    return re.sub(r"[\s.]+", "", str(s).lower())


def name_sim(a, b):
    return difflib.SequenceMatcher(None, _norm_name(a), _norm_name(b)).ratio()


def _load_gt_txt(path):
    """Расшифровка в pipe-формате (мсм): ИНН/КПП + строки «N | name | ...»."""
    text = open(path, encoding="utf-8").read()
    inn = re.search(r"ИНН\s*(\d+)", text)
    kpp = re.search(r"КПП\s*(\d+)", text)
    items = []
    for line in text.splitlines():
        if "|" not in line:
            continue
        parts = [p.strip() for p in line.split("|")]
        if len(parts) < 7 or not re.fullmatch(r"\d+", parts[0]):
            continue
        items.append({
            "num": int(parts[0]),
            "name": parts[1],
            "qty": _gt_num(parts[4]),
            "unit": parts[5],
            "sum": _gt_num(parts[6]),
        })
    first_line = text.splitlines()[0].strip() if text.splitlines() else ""
    return {"inn": inn.group(1) if inn else None,
            "kpp": kpp.group(1) if kpp else None,
            "supplier": first_line,
            "items": items,
            "strict": False}  # мсм — best-effort, гейт не блокирует


def _load_gt_xlsx(path):
    """Расшифровка-таблица (перфорация): ИНН/КПП в A1/B1, шапка со «№», строки ниже."""
    df = pd.read_excel(path, header=None, dtype=object).fillna("")
    inn = kpp = None
    for _, row in df.iterrows():
        for cell in row:
            m = re.search(r"ИНН\s*(\d+)", str(cell))
            if m and inn is None:
                inn = m.group(1)
            m = re.search(r"КПП\s*(\d+)", str(cell))
            if m and kpp is None:
                kpp = m.group(1)
    supplier = ""
    header_idx = None
    for i, row in df.iterrows():
        if str(row[0]).strip() == "№":
            header_idx = i
            break
        if not supplier and "ООО" in str(row[0]):
            supplier = str(row[0]).strip()
    items = []
    if header_idx is not None:
        for i in range(header_idx + 1, len(df)):
            row = df.iloc[i]
            if not str(row[0]).strip():
                continue
            items.append({
                "num": int(row[0]),
                "name": str(row[1]).strip(),   # B — Товар
                "qty": _gt_num(row[4]),        # E — Кол-во (итоговое!)
                "unit": str(row[5]).strip(),   # F — Ед.
                "sum": _gt_num(row[7]),         # H — Сумма
            })
    return {"inn": inn, "kpp": kpp, "supplier": supplier,
            "items": items, "strict": True}


def load_ground_truth(data_dir):
    """{имя_pdf: эталон} — только для PDF, у которых есть расшифровка."""
    gt = {}
    for name in sorted(os.listdir(data_dir)):
        stem, ext = os.path.splitext(name)
        if ext.lower() != ".pdf":
            continue
        for pair_ext, loader in ((".txt", _load_gt_txt), (".xlsx", _load_gt_xlsx)):
            pair = os.path.join(data_dir, stem + pair_ext)
            if os.path.isfile(pair):
                gt[name] = loader(pair)
                break
    return gt


# ------------------------------------------------------------ распознавание

def _num(v):
    if v is None:
        return None
    if isinstance(v, (int, float)):
        return round(float(v), 2)
    s = str(v).strip().replace("\xa0", "").replace(" ", "")
    if not s or s.lower() in ("nan", "none", "-"):
        return None
    try:
        return round(float(s.replace(",", ".")), 2)
    except ValueError:
        return None


def _supplier_from_ocr_text(text):
    """Реквизиты из OCR-текста — как это будет делать sidecar."""
    from supplier_extract import extract_supplier_from_text
    return extract_supplier_from_text(text, None)


def recognize_module(pdf_path, dump=None):
    import ocr_recog
    from normalizer import process_pdf_tables
    tables, text = ocr_recog.extract_with_ocr(pdf_path)
    if dump:
        for i, t in enumerate(tables):
            print(f"--- dump: таблица {i + 1} ---")
            for row in t.df.values.tolist():
                print(" | ".join(str(c) for c in row))
    filename = os.path.basename(pdf_path)
    df, _orig, _bez = process_pdf_tables(tables, filename)
    offers = []
    for i in range(len(df)):
        row = {col: df.iloc[i][(filename, col)] for col in
               ("№", "Товар", "Кол-во", "Ед. изм", "Сумма")}
        offers.append({"itemName": str(row["Товар"]).strip(),
                       "qty": _num(row["Кол-во"]),
                       "unit": str(row["Ед. изм"]).strip(),
                       "sum": _num(row["Сумма"])})
    supplier = _supplier_from_ocr_text(text)
    return {"supplier": supplier, "offers": offers}


def recognize_sidecar(pdf_path):
    cmd = [sys.executable, os.path.join(REPO, "sidecar.py"),
           "--action=recognize", f"--file={pdf_path}"]
    res = subprocess.run(cmd, capture_output=True, timeout=600, cwd=REPO)
    line = res.stdout.decode("utf-8", "replace").strip().splitlines()
    if not line:
        raise RuntimeError(f"sidecar пусто: {res.stderr.decode('utf-8', 'replace')}")
    data = json.loads(line[-1])
    if data.get("status") != "ok":
        raise RuntimeError(f"sidecar: {data.get('message')}")
    supplier = {"name": data.get("supplierName"), "inn": data.get("inn"),
                "kpp": data.get("kpp")}
    # JSON сайдкара называет сумму sumWithVat — приводим к общей форме.
    offers = [{"itemName": o.get("itemName"), "qty": o.get("qty"),
               "unit": o.get("unit"), "sum": o.get("sumWithVat")}
              for o in data.get("offers", [])]
    return {"supplier": supplier, "offers": offers}


# ------------------------------------------------------------------- отчёт

def _fmt(v):
    return "?" if v is None else v


def eval_transcribed(pdf_path, gt, rec):
    print(f"\n=== {os.path.basename(pdf_path)} (эталон) ===")
    sup = rec["supplier"]
    inn_ok = sup["inn"] == gt["inn"]
    kpp_ok = sup["kpp"] == gt["kpp"]
    inn_note = "ok" if inn_ok else f"ожидался {gt['inn']}, получен {_fmt(sup['inn'])}"
    kpp_note = "ok" if kpp_ok else f"ожидался {gt['kpp']}, получен {_fmt(sup['kpp'])}"
    print(f"Поставщик: ИНН {inn_note}")
    print(f"           КПП {kpp_note}")
    sim = name_sim(sup["name"] or "", gt["supplier"] or "")
    print(f"           имя: «{sup['name']}» vs «{gt['supplier']}» (схожесть {sim:.2f})")

    expected, got = gt["items"], rec["offers"]
    # Пары: жадно по схожести имён.
    pairs = []
    used = set()
    for e in expected:
        best, best_sim = None, -1.0
        for j, o in enumerate(got):
            if j in used:
                continue
            s = name_sim(e["name"], o.get("itemName") or "")
            if s > best_sim:
                best, best_sim = j, s
        if best is not None and best_sim >= 0.3:
            used.add(best)
            pairs.append((e, got[best], best_sim))
        else:
            pairs.append((e, None, 0.0))

    bad = 0
    for e, o, sim in pairs:
        if o is None:
            print(f"  [ПРОПУСК] №{e['num']} «{e['name']}» — позиции нет в результате")
            bad += 1
            continue
        issues = []
        if sim < NAME_SIM_MIN:
            issues.append(f"имя {sim:.2f}: «{o['itemName']}»")
        if e["qty"] is not None and o["qty"] != e["qty"]:
            issues.append(f"кол-во {o['qty']} ≠ {e['qty']}")
        if _norm_unit(o["unit"] or "") != _norm_unit(e["unit"] or ""):
            issues.append(f"ед. «{o['unit']}» ≠ «{e['unit']}»")
        if e["sum"] is not None and (o["sum"] is None or abs(o["sum"] - e["sum"]) > SUM_TOL):
            issues.append(f"сумма {o['sum']} ≠ {e['sum']}")
        if issues:
            bad += 1
            print(f"  [{e['num']:>2}] " + "; ".join(issues))
    print(f"Позиции: {len(expected) - bad}/{len(expected)}"
          f" (распознано {len(got)}), ИНН {'ok' if inn_ok else 'FAIL'},"
          f" КПП {'ok' if kpp_ok else 'FAIL'}")
    ok = inn_ok and kpp_ok and bad == 0
    if gt["strict"]:
        return ok
    print("  (мсм — best-effort: в гейт не входит)")
    return True


def eval_blind(pdf_path, rec):
    print(f"\n=== {os.path.basename(pdf_path)} (слепой — инварианты) ===")
    sup = rec["supplier"]
    print(f"Поставщик: «{sup['name']}» ИНН {sup['inn']} КПП {sup['kpp']}")
    offers = rec["offers"]
    print(f"Позиций: {len(offers)}")
    for i, o in enumerate(offers, 1):
        flags = []
        if not o.get("itemName"):
            flags.append("пустое имя")
        if not o.get("qty"):
            flags.append("нет кол-ва")
        if not o.get("sum"):
            flags.append("нет суммы")
        mark = " !!" if flags else ""
        print(f"  [{i:>2}] {o.get('itemName', '')[:70]!r:<70}"
              f" qty={o.get('qty')} ед={o.get('unit')!r} сумма={o.get('sum')}{mark}")
        if flags:
            print(f"        подозрительно: {', '.join(flags)}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", default=DATA_DEFAULT)
    ap.add_argument("--mode", choices=["module", "sidecar"], default="module")
    ap.add_argument("--file", help="один PDF (по имени в --data)")
    ap.add_argument("--dump", action="store_true", help="печать собранной сетки")
    args = ap.parse_args()

    gt = load_ground_truth(args.data)
    pdfs = sorted(f for f in os.listdir(args.data) if f.lower().endswith(".pdf"))
    if args.file:
        pdfs = [f for f in pdfs if args.file in f]
    if not pdfs:
        print("Нет PDF в", args.data)
        return 2

    ok = True
    for name in pdfs:
        path = os.path.join(args.data, name)
        try:
            rec = (recognize_module(path, dump=args.dump)
                   if args.mode == "module" else recognize_sidecar(path))
        except Exception as e:
            print(f"\n=== {name} ===\n  ОШИБКА РАСПОЗНАВАНИЯ: {e}")
            ok = False
            continue
        if name in gt:
            ok = eval_transcribed(path, gt[name], rec) and ok
        else:
            eval_blind(path, rec)
    print("\nИТОГ: " + ("ПРИЁМКА ПРОЙДЕНА" if ok else "ЕСТЬ РАСХОЖДЕНИЯ"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
