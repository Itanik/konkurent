"""Python sidecar for KonkurentApp (Flutter Desktop).

Bridges the Flutter UI and the recognition engine in recog.py / normalizer.py.
Communication is one JSON object per invocation: the result is the last line on
stdout (all engine prints are redirected to stderr), errors are reported as
{"status": "error"} inside the JSON.

Usage:
    python sidecar.py --action=recognize --file=/abs/path/to/invoice.pdf
    python sidecar.py --action=export --output=/abs/path/to/out.xlsx   < state.json
    python sidecar.py --action=import --file=/abs/path/to/saved.xlsx
"""

import os
import sys
import json
import shutil
import argparse
import contextlib

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

# Ссылка на исходный stdout: результат должен попасть сюда даже внутри
# redirect_stdout (recog печатает в stderr, но _fail может вызываться из
# обёрнутого блока).
_REAL_STDOUT = sys.stdout

META_LABEL_TO_KEY = {
    "Договор:": "contract",
    "Сроки поставки:": "deliveryTime",
    "Доставка:": "delivery",
    "Условия оплаты:": "paymentTerms",
    "Комментарий:": "comment",
}
META_KEY_TO_LABEL = {v: k for k, v in META_LABEL_TO_KEY.items()}


class _Table:
    """Mimics the camelot table interface expected by normalizer."""

    def __init__(self, df):
        self.df = df


def _configure_stdio():
    # On Windows the default stdio encoding is the ANSI code page; the Flutter
    # bridge expects UTF-8 on both stdout (JSON result) and stderr (recog/camelot
    # logs). Force all three streams to UTF-8.
    for stream in (sys.stdout, sys.stderr, sys.stdin):
        try:
            stream.reconfigure(encoding="utf-8")
        except Exception:
            pass


def _emit(obj):
    try:
        text = json.dumps(obj, ensure_ascii=False)
        _REAL_STDOUT.write(text + "\n")
    except (UnicodeEncodeError, ValueError):
        _REAL_STDOUT.write(json.dumps(obj, ensure_ascii=True) + "\n")
    _REAL_STDOUT.flush()


@contextlib.contextmanager
def _stdout_to_stderr():
    """Keep stdout reserved for the single JSON result; recog's prints go to stderr."""
    with contextlib.redirect_stdout(sys.stderr):
        yield


def _fail(message):
    _emit({"status": "error", "message": message})
    sys.exit(1)


def _gs_hint(path):
    # camelot'у для lattice-режима нужен Ghostscript; без него остаётся только
    # stream. Поэтому не фейлим заранее, а добавляем подсказку к ошибке
    # распознавания PDF.
    if os.path.splitext(path)[1].lower() != ".pdf":
        return ""
    if shutil.which("gs") is None and shutil.which("gswin64c") is None:
        return ("; вероятно, не хватает Ghostscript (gs/gswin64c не найдены в PATH)"
                " — без него доступен только stream-режим распознавания")
    return ""


def _scan_hint(path):
    # У отсканированного PDF нет текстового слоя — распознавание без OCR
    # обречено. Проверяем дёшево (первые страницы), только для PDF.
    if os.path.splitext(path)[1].lower() != ".pdf":
        return ""
    try:
        from supplier_extract import extract_text
        if len(extract_text(path, max_pages=2).strip()) < 10:
            return ("; похоже, документ отсканирован (нет текстового слоя)"
                    " — OCR не поддерживается")
    except Exception:
        pass
    return ""


def _cell_str(value):
    if value is None:
        return ""
    return str(value).strip()


def _num_or_none(value):
    if value is None:
        return None
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        return round(float(value), 2)
    s = str(value).strip().replace("\xa0", "").replace(" ", "").replace(",", ".")
    if not s or s.lower() in ("nan", "none", "-"):
        return None
    try:
        return round(float(s), 2)
    except (ValueError, TypeError):
        return None


def _fmt_num(value):
    if value is None:
        return ""
    return value


def load_config():
    with open(os.path.join(SCRIPT_DIR, "config.json"), "r", encoding="utf-8") as f:
        return json.load(f)


def _tables_for(path):
    ext = os.path.splitext(path)[1].lower()
    if ext == ".pdf":
        import recog
        return recog.extract_with_camelot(path)

    if ext in (".xlsx", ".xls", ".xlsm"):
        import pandas as pd
        sheets = pd.read_excel(path, sheet_name=None, header=None, dtype=object)
        tables = []
        for _, df in sheets.items():
            tables.append(_Table(df.fillna("")))
        return tables

    if ext == ".docx":
        import pandas as pd
        try:
            from docx import Document
        except ImportError:
            _fail("Для распознавания DOCX установите python-docx")
        doc = Document(path)
        tables = []
        for t in doc.tables:
            rows = [[cell.text for cell in row.cells] for row in t.rows]
            if rows:
                tables.append(_Table(pd.DataFrame(rows)))
        return tables

    _fail(f"Неподдерживаемый формат: {ext or 'без расширения'}")


def action_recognize(path, legal_forms_path=None):
    if not os.path.isfile(path):
        _fail(f"Файл не найден: {path}")

    from normalizer import process_pdf_tables, STANDARD_COLUMNS

    filename = os.path.basename(path)
    with _stdout_to_stderr():
        tables = _tables_for(path)
    if not tables:
        _fail("Таблицы в файле не найдены" + _gs_hint(path) + _scan_hint(path))

    df, _orig, bez_nds = process_pdf_tables(tables, filename)
    if df.shape[0] == 0:
        _fail("Не удалось распознать позиции в файле" + _gs_hint(path)
              + _scan_hint(path))

    offers = []
    for i in range(len(df)):
        row = {col: df.iloc[i][(filename, col)] for col in STANDARD_COLUMNS}
        offers.append({
            "itemName": _cell_str(row.get("Товар")),
            "qty": _num_or_none(row.get("Кол-во")),
            "unit": _cell_str(row.get("Ед. изм")),
            "sumWithVat": _num_or_none(row.get("Сумма")),
            "sumWithoutVat": _num_or_none(bez_nds[i] if i < len(bez_nds) else None),
        })

    # Реквизиты поставщика из «шапки» счёта (юридическая форма, ИНН/КПП/ОГРН).
    # Сбой извлечения не должен валить распознавание позиций.
    supplier_name = os.path.splitext(filename)[0]
    inn = kpp = ogrn = None
    try:
        from supplier_extract import extract_supplier, load_legal_forms
        forms = load_legal_forms(legal_forms_path) if legal_forms_path else None
        info = extract_supplier(path, forms)
        if info.get("name"):
            supplier_name = info["name"]
        inn, kpp, ogrn = info.get("inn"), info.get("kpp"), info.get("ogrn")
    except Exception as e:
        print(f"  Извлечение реквизитов не удалось: {e}")

    _emit({
        "status": "ok",
        "supplierName": supplier_name,
        "sourceFileName": filename,
        "inn": inn,
        "kpp": kpp,
        "ogrn": ogrn,
        "offers": offers,
    })


def action_export(output):
    raw_bytes = sys.stdin.buffer.read() if hasattr(sys.stdin, "buffer") else b""
    try:
        raw = raw_bytes.decode("utf-8")
    except UnicodeDecodeError:
        raw = raw_bytes.decode("utf-8", "replace")
    if not raw.strip():
        _fail("Пустое состояние на stdin")
    try:
        state = json.loads(raw)
    except json.JSONDecodeError as e:
        _fail(f"Некорректный JSON состояния: {e}")

    import recog

    # Нормализация state: оставляем только то, что понимает движок.
    clean = {
        "requestName": (state.get("requestName") or "").strip() or "Заявка",
        "requestItems": [
            {
                "id": it.get("id"),
                "name": str(it.get("name", "")).strip(),
                "qty": str(it.get("qty", "")).strip(),
                "unit": str(it.get("unit", "")).strip(),
            }
            for it in state.get("requestItems", [])
            if str(it.get("name", "")).strip()
        ],
        "suppliers": [],
        "bestVariants": state.get("bestVariants") or [],
    }
    for sup in state.get("suppliers", []):
        meta = sup.get("meta") or {}
        clean["suppliers"].append({
            "id": sup.get("id"),
            "displayName": (sup.get("displayName") or "").strip(),
            "inn": sup.get("inn"),
            "withoutVat": bool(sup.get("withoutVat")),
            "sourceFileNames": (sup.get("sourceFileNames")
                                or ([sup["sourceFileName"]]
                                    if sup.get("sourceFileName") else [])),
            "meta": {k: str(meta.get(k, "") or "") for k in META_KEY_TO_LABEL},
            "offers": [
                {
                    "itemName": off.get("itemName") or "",
                    "qty": _num_or_none(off.get("qty")),
                    "unit": off.get("unit") or "",
                    "sumWithVat": _num_or_none(off.get("sumWithVat")),
                    "sumWithoutVat": _num_or_none(off.get("sumWithoutVat")),
                    "priceWithVat": _num_or_none(off.get("priceWithVat")),
                    "priceWithoutVat": _num_or_none(off.get("priceWithoutVat")),
                    "priceDriver": off.get("priceDriver") or "sum",
                    "linkedRequestItemId": off.get("linkedRequestItemId"),
                }
                for off in sup.get("offers", [])
            ],
        })

    output = os.path.abspath(output)
    with _stdout_to_stderr():
        recog.build_comparison_xlsx(clean, SCRIPT_DIR, output)

    _emit({"status": "ok", "path": output})


def action_import(path):
    if not os.path.isfile(path):
        _fail(f"Файл не найден: {path}")

    from openpyxl import load_workbook

    config = load_config()
    sheet_name = config["sheet_name"]

    # Двойное чтение: data_only=True даёт кэшированные значения формул,
    # data_only=False — сами формулы и объединения.
    wb_vals = load_workbook(path, data_only=True)
    if sheet_name not in wb_vals.sheetnames:
        _emit({"status": "foreign"})
        return
    ws = wb_vals[sheet_name]

    a1 = ws.cell(row=1, column=1).value
    if not (isinstance(a1, str) and a1.strip().startswith("Заявка:")):
        _emit({"status": "foreign"})
        return

    request_name = a1.split(":", 1)[1].strip()
    wb = load_workbook(path, data_only=False)
    wsf = wb[sheet_name]

    n_fixed = len(config["fixed_columns"])
    block_size = len(config["block_columns"])
    meta_labels = [m["label"] for m in config["row"]["meta"]]
    fixed_header = config["fixed_columns"][0]["header"]

    header_row = None
    for r in range(1, ws.max_row + 1):
        if _cell_str(ws.cell(row=r, column=1).value) == fixed_header:
            header_row = r
            break
    if header_row is None:
        _fail("Не найдена строка заголовков в файле")

    data_start = header_row + 1
    inn_row = 2
    files_row = 3

    meta_start = None
    if meta_labels:
        for r in range(data_start, ws.max_row + 1):
            if _cell_str(ws.cell(row=r, column=1).value) == meta_labels[0]:
                meta_start = r
                break
    if meta_start is None:
        meta_start = data_start

    blocks = []
    col = n_fixed + 1
    while col <= ws.max_column:
        name = ws.cell(row=1, column=col).value
        if name in (None, ""):
            break
        blocks.append({"start": col, "name": _cell_str(name)})
        col += block_size

    # Группы позиций заявки: вертикальное объединение в колонке 2 (название).
    group_ranges = []  # (first_row, last_row)
    for mc in wsf.merged_cells.ranges:
        if mc.min_col == 2 and mc.max_col == 2 and mc.min_row >= data_start \
                and mc.max_row < meta_start:
            group_ranges.append((mc.min_row, mc.max_row))
    group_ranges.sort()

    # Сопоставление строкам групп id позиции заявки: import не сохраняет
    # исходные uuid — генерируем при чтении по порядку групп.
    import uuid as _uuid

    def new_id():
        return str(_uuid.uuid4())

    request_items = []
    group_ids = {}  # first_row -> id
    cursor = data_start
    for first, last in group_ranges:
        if first < cursor:
            continue
        name = _cell_str(ws.cell(row=first, column=2).value)
        qty = _cell_str(ws.cell(row=first, column=3).value)
        unit = _cell_str(ws.cell(row=first, column=4).value)
        rid = new_id()
        group_ids[first] = rid
        request_items.append({"id": rid, "name": name, "qty": qty,
                              "unit": unit})
        cursor = last + 1
    # Позиции вне групп (файлы старого формата или без merge).
    covered = set()
    for first, last in group_ranges:
        covered.update(range(first, last + 1))
    for r in range(data_start, meta_start):
        if r in covered:
            continue
        name = _cell_str(ws.cell(row=r, column=2).value)
        if not name:
            continue
        rid = new_id()
        group_ids[r] = rid
        request_items.append({
            "id": rid,
            "name": name,
            "qty": _cell_str(ws.cell(row=r, column=3).value),
            "unit": _cell_str(ws.cell(row=r, column=4).value),
        })

    def row_group_id(r):
        """id группы для строки r (по диапазонам merge)."""
        for first, last in group_ranges:
            if first <= r <= last:
                return group_ids.get(first)
        return group_ids.get(r)

    suppliers = []
    for b in blocks:
        cs = b["start"]
        # Название блока без хвоста «(n/z)».
        display = b["name"]
        if display.endswith(")") and " (" in display:
            display = display.rsplit(" (", 1)[0]

        files_raw = _cell_str(ws.cell(row=files_row, column=cs).value)
        files = [f.strip() for f in files_raw.split(";") if f.strip()] \
            if files_raw else []

        offers = []
        for r in range(data_start, meta_start):
            item = ws.cell(row=r, column=cs).value
            qty = ws.cell(row=r, column=cs + 1).value
            unit = ws.cell(row=r, column=cs + 2).value
            # ws — data_only книга: формулы дают кэшированные значения.
            sum_wo = ws.cell(row=r, column=cs + 4).value
            sum_w_val = ws.cell(row=r, column=cs + 5).value
            if item in (None, "") and qty in (None, "") \
                    and sum_w_val in (None, ""):
                continue
            is_price_value = price_driver_is_value(wsf, r, cs + 3)
            price = _num_or_none(wsf.cell(row=r, column=cs + 3).value) \
                if is_price_value else None
            offers.append({
                "itemName": _cell_str(item),
                "qty": _num_or_none(qty),
                "unit": _cell_str(unit),
                "sumWithVat": _num_or_none(sum_w_val),
                "sumWithoutVat": _num_or_none(sum_wo),
                "priceWithVat": price,
                "priceDriver": "price" if is_price_value else "sum",
                "linkedRequestItemId": row_group_id(r),
            })

        meta = {}
        for i, label in enumerate(meta_labels):
            v = ws.cell(row=meta_start + i, column=cs).value
            key = META_LABEL_TO_KEY.get(label)
            if key:
                meta[key] = _cell_str(v)

        suppliers.append({
            "id": new_id(),
            "displayName": display,
            "inn": _cell_str(ws.cell(row=inn_row, column=cs).value) or None,
            "sourceFileNames": files,
            "offers": offers,
            "meta": meta,
        })

    _emit({
        "status": "ok",
        "requestName": request_name,
        "requestItems": request_items,
        "suppliers": suppliers,
    })


def price_driver_is_value(wsf, row, col_offset_plus_3):
    """Цена — введённое значение (driver=price), если это не формула."""
    v = wsf.cell(row=row, column=col_offset_plus_3).value
    return not (isinstance(v, str) and v.startswith("="))


def main():
    _configure_stdio()
    parser = argparse.ArgumentParser(description="KonkurentApp Python sidecar")
    parser.add_argument("--action", required=True,
                        choices=["recognize", "export", "import"])
    parser.add_argument("--file")
    parser.add_argument("--output")
    parser.add_argument("--legal-forms",
                        help="JSON-файл со списком юридических форм для "
                             "распознавания названия поставщика")
    args = parser.parse_args()

    try:
        if args.action == "recognize":
            if not args.file:
                _fail("--file обязателен для recognize")
            action_recognize(args.file, args.legal_forms)
        elif args.action == "export":
            if not args.output:
                _fail("--output обязателен для export")
            action_export(args.output)
        elif args.action == "import":
            if not args.file:
                _fail("--file обязателен для import")
            action_import(args.file)
    except SystemExit:
        raise
    except Exception as e:
        _fail(f"{type(e).__name__}: {e}")


if __name__ == "__main__":
    main()