"""OCR отсканированных счетов: image-only PDF → таблицы позиций.

Пайплайн (двойной, как у camelot lattice/stream):

1. pypdfium2 рендерит страницы (реальные сканы часто нативно ~96 DPI,
   поэтому обязателен апскейл RENDER_SCALE).
2. cv2-морфология находит линейки таблицы; они задают сетку колонок/строк
   И стираются с изображения — рамки отравляют tesseract (одиночная
   цифра рядом с линией не читается вовсе, проверено на фикстурах).
3. Полный проход tesseract (psm 4) по очищенной странице даёт слова для
   текста страниц (реквизиты) и базовую сборку ячеек.
4. Заголовочный бэнд перечитывается отдельно (psm 11 + апскейл ×2) —
   мелкий двухстрочный заголовок полным проходом разваливается.
5. Каждая колонка перечитывается вертикальной полосой (psm 6, с полями;
   чужие слова отбрасываются центром): числовым — whitelist цифр,
   единицам — whitelist кириллицы. Изолированная колонка без рамок
   читается на порядок чище полной страницы.
6. Страница без заголовка таблицы — продолжение таблицы предыдущей
   страницы (camelot между страницами не склеивает, OCR должен сам).
   Строки до заголовка normalizer отбрасывает сам.

Второй результат — накопленный текст страниц: sidecar передаёт его в
supplier_extract для реквизитов (у image-only PDF playa текста не даёт).
"""

import os
import re
import shutil
import subprocess
import tempfile

import pandas as pd

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

RENDER_SCALE = 4.0      # 96 DPI скан → ~4x апскейл для tesseract
TESS_LANG = "rus+eng"   # eng нужен: латиница в названиях (DIN, HIMTEX...)
NAME_LANG = "rus_best+eng_best"  # best-модели снимают неоднозначность глифов
NAME_UPSCALE = 2        # best-моделям нужно более высокое разрешение
TESS_PSM = 4            # полный проход: страница с таблицей и шапкой
STRIP_PSM = 6           # полоса колонки: однородный блок
HEADER_PSM = 11         # заголовок: разрежённый текст
HEADER_UPSCALE = 2      # заголовочный бэнд мелкий — удваиваем
UNIT_PSM = 7            # ячейка единиц: одна короткая строка
UNIT_UPSCALE = 3        # глифы «шт» крошечные — утраиваем
UNIT_INSET = 4          # px отступ от границ ячейки при кропе
STRIP_MARGIN = 40       # px за границу колонки (числа шире центра линейки)
WORD_MIN_CONF = 0       # в TSV -1 у пустых слов
LINE_CLUSTER_TOL = 6    # px: разброс линий одной границы (при scale 4)
TABLE_GROUP_GAP = 200   # px: разрыв по y между таблицами/блоками страницы
ERASE_DILATE = 3        # px расширение маски линеек при стирании
GRID_MIN_COLS = 4       # минимальное число границ колонок
GRID_MIN_ROWS = 3       # таблица = шапка + хотя бы одна строка данных
STREAM_COL_GAP = 1.5    # без линеек: разрыв > gap*высота_слова = граница ячеек
HEADER_ACCEPT_SCORE = 3  # как в normalizer.process_pdf_tables
BAND_HEADER_MIN_SCORE = 2  # кандидат на заголовочный бэнд для перечитывания
NUMERIC_CELL_FRACTION = 0.7  # доля числовых ячеек для колонки-числа
# Хвост счёта ниже позиций («Итого», «Всего наименований», вес/объём) —
# выкидываем по полному тексту бэнда: в normalizer ключевые слова могут
# попасть в незамапленную колонку (замечено на реальном счёте).
TAIL_BAND_KEYWORDS = ("итого", "всего наименований", "вес по счету",
                      "объем по счету", "к оплате", "в том числе")

DIGIT_WHITELIST = "0123456789.,' "
UNIT_WHITELIST = ("абвгдежзийклмнопрстуфхцчшщъыьэюя"
                  "АБВГДЕЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ./")
# Tesseract путает кириллицу с латиницей: «ООО» читается как «OOO» (латиница)
# или «000», и юрформы поставщика не находятся — единственным кандидатом
# становится покупатель. Текст страниц сворачиваем в кириллицу: он идёт
# только на извлечение реквизитов, имена позиций это не затрагивает.
_HOMOGLYPHS = str.maketrans("ABCEHKOPTXYMbcekmoptyax", "АВСЕНКОРТХМУбсекмортуах")


class OcrError(Exception):
    """OCR невозможен (tesseract не установлен и т.п.) — sidecar даёт подсказку."""


class _Table:
    """Аналог sidecar._Table: normalizer'у нужен только атрибут .df."""

    def __init__(self, df):
        self.df = df


def is_scanned(pdf_path, max_pages=2, min_chars=10):
    """True, если у PDF нет текстового слоя (проверяем первые max_pages)."""
    try:
        from supplier_extract import extract_text
        return len(extract_text(pdf_path, max_pages=max_pages).strip()) < min_chars
    except Exception:
        return False


def _tesseract():
    exe = shutil.which("tesseract")
    if exe is None:
        raise OcrError("Tesseract не найден в PATH")
    return exe


def _tessdata_args(lang):
    """Бандл tessdata/ рядом со скриптом перекрывает системную (frozen: _MEIPASS)."""
    bundled = os.path.join(SCRIPT_DIR, "tessdata")
    if all(os.path.isfile(os.path.join(bundled, f"{part}.traineddata"))
           for part in lang.split("+")):
        return ["--tessdata-dir", bundled]
    return []


def _resolve_lang(lang):
    """«rus_best» без локальной модели → системная «rus» (свежий checkout
    без tessdata/ и CI с apt-моделями должны работать, хоть и хуже)."""
    bundled = os.path.join(SCRIPT_DIR, "tessdata")
    parts = []
    for part in lang.split("+"):
        if os.path.isfile(os.path.join(bundled, f"{part}.traineddata")):
            parts.append(part)
        else:
            parts.append(part.split("_")[0])
    return "+".join(parts)


def _render_pages(pdf_path, scale):
    import pypdfium2 as pdfium
    doc = pdfium.PdfDocument(pdf_path)
    return [page.render(scale=scale, grayscale=True).to_pil() for page in doc]


def _ocr_words(pil, lang=TESS_LANG, psm=TESS_PSM, extra=()):
    """Слова через tesseract TSV: text, conf, бокс, строка tesseract'а."""
    import csv
    exe = _tesseract()
    lang = _resolve_lang(lang)
    with tempfile.TemporaryDirectory(prefix="ocr_") as tmp:
        img = os.path.join(tmp, "page.png")
        out = os.path.join(tmp, "out")
        pil.save(img)
        cmd = [exe, img, out]
        cmd += _tessdata_args(lang)
        cmd += ["-l", lang, "--psm", str(psm), *extra,
                "-c", "tessedit_create_tsv=1"]
        # stdout/stderr перехватываем обязательно: у sidecar stdout занят JSON.
        proc = subprocess.run(cmd, capture_output=True, timeout=300)
        if proc.returncode != 0:
            detail = proc.stderr.decode("utf-8", "replace").strip()
            raise OcrError(f"tesseract завершился с кодом {proc.returncode}: {detail}")
        words = []
        with open(out + ".tsv", encoding="utf-8") as f:
            for row in csv.DictReader(f, delimiter="\t"):
                if int(row["level"]) != 5:
                    continue
                text = (row["text"] or "").strip()
                conf = float(row["conf"])
                if not text or conf < WORD_MIN_CONF:
                    continue
                x0, y0 = int(row["left"]), int(row["top"])
                words.append({
                    "text": text,
                    "conf": conf,
                    "x0": x0, "y0": y0,
                    "x1": x0 + int(row["width"]),
                    "y1": y0 + int(row["height"]),
                    "line": (int(row["block_num"]), int(row["par_num"]),
                             int(row["line_num"])),
                })
    # Линейки и прочий мусор tesseract читает как «слова» из палки/чёрточек;
    # «+» оставляем — в названиях бывает («+ 1 насадка»).
    return [w for w in words
            if w["text"] == "+" or re.search(r"[0-9A-Za-zА-Яа-яЁё]", w["text"])]


def _page_text(words):
    """Текст страницы из слов (по строкам tesseract'а) — для реквизитов."""
    lines = {}
    for w in words:
        lines.setdefault(w["line"], []).append(w)
    ordered = sorted(lines.values(), key=lambda ws: min(w["y0"] for w in ws))
    return "\n".join(
        " ".join(w["text"] for w in sorted(ws, key=lambda w: w["x0"]))
        for ws in ordered)


# --------------------------------------------------------------- сетка линеек

def _line_masks(gray):
    """Маски вертикальных/горизонтальных линеек морфологическим открытием."""
    import cv2
    thr = cv2.adaptiveThreshold(gray, 255, cv2.ADAPTIVE_THRESH_MEAN_C,
                                cv2.THRESH_BINARY_INV, 25, 15)
    h, w = thr.shape
    vkernel = cv2.getStructuringElement(cv2.MORPH_RECT, (1, max(15, h // 40)))
    vmask = cv2.morphologyEx(thr, cv2.MORPH_OPEN, vkernel)
    hkernel = cv2.getStructuringElement(cv2.MORPH_RECT, (max(15, w // 40), 1))
    hmask = cv2.morphologyEx(thr, cv2.MORPH_OPEN, hkernel)
    return vmask, hmask


def _line_components(mask, axis, min_len):
    """Компоненты линеек: [{pos, lo, hi}] — длиннее min_len."""
    import cv2
    n, _, stats, _ = cv2.connectedComponentsWithStats(mask, 8)
    out = []
    for x, y, w, h, _area in stats[1:]:
        if axis == "v":
            if h >= min_len:
                out.append({"pos": x + w / 2, "lo": y, "hi": y + h})
        else:
            if w >= min_len:
                out.append({"pos": y + h / 2, "lo": x, "hi": x + w})
    return out


def _cluster_positions(positions, tol):
    clusters = []
    for pos in sorted(positions):
        if clusters and pos - clusters[-1][-1] <= tol:
            clusters[-1].append(pos)
        else:
            clusters.append([pos])
    return [sum(c) / len(c) for c in clusters]


def _detect_grid(gray):
    """Сетка главной таблицы страницы: (границы колонок, границы строк) | None.

    Линии таблицы — не «самые длинные на странице» (у короткого счёта
    рамки банковского блока ВЫШЕ и длиннее), а те, что пересекают
    ≥ GRID_MIN_COLS вертикалей. Из таких берём крупнейшую близкую по y
    группу (главная таблица), вертикали — покрывающие её высоту.
    """
    vmask, hmask = _line_masks(gray)
    h, w = gray.shape
    v_comps = _line_components(vmask, "v", h // 25)
    h_comps = _line_components(hmask, "h", w // 25)
    if not v_comps or not h_comps:
        return None, vmask, hmask
    for hc in h_comps:
        hc["cross"] = sum(1 for vc in v_comps
                          if vc["lo"] <= hc["pos"] <= vc["hi"]
                          and hc["lo"] <= vc["pos"] <= hc["hi"])
    table_h = sorted((hc for hc in h_comps if hc["cross"] >= GRID_MIN_COLS),
                     key=lambda c: c["pos"])
    if len(table_h) < GRID_MIN_ROWS:
        return None, vmask, hmask
    groups, cur = [], [table_h[0]]
    for hc in table_h[1:]:
        if hc["pos"] - cur[-1]["pos"] > TABLE_GROUP_GAP:
            groups.append(cur)
            cur = [hc]
        else:
            cur.append(hc)
    groups.append(cur)
    # Главная группа — по сумме пересечений (у таблицы их на порядок больше,
    # чем у рамок шапки), при равенстве — по числу линий.
    main = max(groups,
               key=lambda g: (sum(c["cross"] for c in g), len(g)))
    if len(main) < GRID_MIN_ROWS:
        return None, vmask, hmask
    y_lo = min(c["pos"] for c in main)
    y_hi = max(c["pos"] for c in main)
    x_lo = min(c["lo"] for c in main)
    x_hi = max(c["hi"] for c in main)
    rows = _cluster_positions([c["pos"] for c in main], LINE_CLUSTER_TOL)
    span = y_hi - y_lo
    table_v = [vc for vc in v_comps
               if x_lo <= vc["pos"] <= x_hi
               and min(vc["hi"], y_hi) - max(vc["lo"], y_lo) >= 0.6 * span]
    cols = _cluster_positions([vc["pos"] for vc in table_v], LINE_CLUSTER_TOL)
    if len(cols) < GRID_MIN_COLS or len(rows) < GRID_MIN_ROWS:
        return None, vmask, hmask
    return (cols, rows), vmask, hmask


def _erase_lines(gray, vmask, hmask):
    """Стираем линейки (с запасом) — рамки отравляют чтение ячеек."""
    import cv2
    import numpy as np
    lines = cv2.dilate(vmask | hmask,
                       np.ones((2 * ERASE_DILATE + 1,) * 2, np.uint8))
    out = gray.copy()
    out[lines > 0] = 255
    return out


# --------------------------------------------------------------- сборка ячеек

def _span_index(bounds, lo, hi):
    """Индекс промежутка между границами с максимальным перекрытием [lo, hi)."""
    best, best_ov = None, 0
    for i in range(len(bounds) - 1):
        ov = min(hi, bounds[i + 1]) - max(lo, bounds[i])
        if ov > best_ov:
            best, best_ov = i, ov
    return best


def _band_index(rows, y):
    """Номер бэнда по вертикальной координате (центр слова)."""
    for i in range(len(rows) - 1):
        if rows[i] <= y < rows[i + 1]:
            return i
    return None


def _cell_text(cell_words):
    """Текст ячейки: слова группируются в визуальные строки (иначе
    перенесённые имена склеятся в кашу), внутри строки — порядок по x."""
    if not cell_words:
        return ""
    ws = sorted(cell_words, key=lambda w: w["y0"])
    heights = sorted(w["y1"] - w["y0"] for w in ws)
    med_h = heights[len(heights) // 2]
    lines, cur, prev_y0 = [], [], None
    for w in ws:
        if prev_y0 is not None and w["y0"] - prev_y0 > med_h * 0.6:
            lines.append(cur)
            cur = []
        cur.append(w)
        prev_y0 = w["y0"]
    if cur:
        lines.append(cur)
    return " ".join(
        " ".join(w["text"] for w in sorted(line, key=lambda w: w["x0"]))
        for line in lines)


def _cells_from_words(words, cols, rows):
    """Базовая сетка ячеек из слов полного прохода (списки слов)."""
    cells = [[[] for _ in range(len(cols) - 1)] for _ in range(len(rows) - 1)]
    for w in words:
        col = _span_index(cols, w["x0"], w["x1"])
        row = _span_index(rows, w["y0"], w["y1"])
        if col is None or row is None:
            continue
        cells[row][col].append(w)
    return cells


def _looks_numeric(text):
    return bool(re.fullmatch(r"[-0-9][0-9'.,\s]*", text or ""))


def _classify_columns(text_rows, mapping, n_cols):
    """(колонки-числа, колонки-единицы): по маппингу заголовка + эвристика."""
    numeric, units = set(), set()
    for role in ("№", "Кол-во", "Сумма"):
        if role in mapping:
            numeric.add(mapping[role])
    if "Ед. изм" in mapping:
        units.add(mapping["Ед. изм"])
    for j in range(n_cols):
        if j in units:
            continue
        vals = [r[j] for r in text_rows if j < len(r) and r[j].strip()]
        if vals and (sum(_looks_numeric(v) for v in vals) / len(vals)
                     >= NUMERIC_CELL_FRACTION):
            numeric.add(j)
    return numeric, units


def _cell_ocr(pil, x_lo, x_hi, y_lo, y_hi, psm, upscale, lang=TESS_LANG,
              whitelist=None, inset_x=UNIT_INSET, inset_y=UNIT_INSET):
    """OCR кропа одной ячейки (с отступом от стёртых линий)."""
    from PIL import Image
    crop = pil.crop((int(x_lo) + inset_x, int(y_lo) + inset_y,
                     int(x_hi) - inset_x, int(y_hi) - inset_y))
    if upscale != 1:
        crop = crop.resize((int(crop.width * upscale),
                            int(crop.height * upscale)), Image.LANCZOS)
    extra = ()
    if whitelist is not None:
        extra = ("-c", f"tessedit_char_whitelist={whitelist}")
    words = _ocr_words(crop, lang=lang, psm=psm, extra=extra)
    return _cell_text(words)


def _strip_column(pil, col_lo, col_hi, y_lo, y_hi, whitelist, lang=TESS_LANG,
                  upscale=1):
    """Слова вертикальной полосы колонки (с полями, вне таблицы — отсекаем)."""
    from PIL import Image
    x_off = max(0, col_lo - STRIP_MARGIN)
    y_off = max(0, y_lo)
    crop = pil.crop((x_off, y_off, col_hi + STRIP_MARGIN, y_hi))
    if upscale != 1:
        crop = crop.resize((int(crop.width * upscale),
                            int(crop.height * upscale)), Image.LANCZOS)
    extra = ()
    if whitelist is not None:
        extra = ("-c", f"tessedit_char_whitelist={whitelist}")
    words = _ocr_words(crop, lang=lang, psm=STRIP_PSM, extra=extra)
    for w in words:
        w["x0"] = x_off + w["x0"] / upscale
        w["x1"] = x_off + w["x1"] / upscale
        w["y0"] = y_off + w["y0"] / upscale
        w["y1"] = y_off + w["y1"] / upscale
    # Чужие слова из полей (хвосты соседних колонок) отбрасываем центром.
    return [w for w in words if col_lo <= (w["x0"] + w["x1"]) / 2 <= col_hi]


def _reread_header(pil, cols, rows, band):
    """Перечитываем заголовочный бэнд (psm 11 + апскейл): мелкий и двухстрочный.

    Читаем дважды — fast- и best-моделями: у специфичных шрифтов (мсм)
    «Сумма» читается только best-моделью, а «Кол-во» — только fast
    («Kon-Bo» латиницей не маппится). Возвращаем оба варианта по-колоночно.
    """
    from PIL import Image
    x0 = max(0, int(cols[0] - STRIP_MARGIN))
    y0 = max(0, int(rows[band] - 15))
    crop = pil.crop((x0, y0, int(cols[-1] + STRIP_MARGIN),
                     int(rows[band + 1] + 15)))
    crop = crop.resize((crop.width * HEADER_UPSCALE,
                        crop.height * HEADER_UPSCALE), Image.LANCZOS)
    variants = []
    for lang in (TESS_LANG, NAME_LANG):
        buckets = [[] for _ in range(len(cols) - 1)]
        for w in _ocr_words(crop, lang=lang, psm=HEADER_PSM):
            col = _span_index(cols, x0 + w["x0"] / HEADER_UPSCALE,
                              x0 + w["x1"] / HEADER_UPSCALE)
            if col is not None:
                buckets[col].append(w)
        variants.append([_cell_text(b) for b in buckets])
    return variants


def _pick_header_cells(fast_cells, best_cells):
    """По-колоночно лучший из двух прочтений заголовка: тот, что точнее
    называет какую-либо стандартную роль (точное совпадение + паттерны).
    Финальная строка заголовка одна — normalizer замапит её так же."""
    from normalizer import COLUMN_PATTERNS

    def cell_score(cell):
        cell = str(cell).lower().strip()
        best = 0
        for role, patterns in COLUMN_PATTERNS.items():
            score = sum(1 for p in patterns if p in cell)
            if cell == role.lower():
                score += 2
            best = max(best, score)
        return best

    out = []
    for idx in range(len(fast_cells)):
        fast, best = fast_cells[idx], best_cells[idx]
        out.append(best if cell_score(best) > cell_score(fast) else fast)
    return out


def _rows_from_grid(pil, words, grid):
    """Финальные строки: полный проход + перечитанный заголовок + полосы колонок."""
    from normalizer import map_columns, score_header_row

    cols, rows = grid
    n_cols = len(cols) - 1
    cells = _cells_from_words(words, cols, rows)
    text_rows = [[_cell_text(c) for c in row] for row in cells]

    # Заголовочный бэнд: лучший по score, затем перечитываем отдельно.
    scores = [score_header_row(r) for r in text_rows]
    best = max(range(len(text_rows)), key=lambda i: scores[i])
    mapping = {}
    if scores[best] >= BAND_HEADER_MIN_SCORE:
        fast_cells, best_cells = _reread_header(pil, cols, rows, best)
        text_rows[best] = _pick_header_cells(fast_cells, best_cells)
        mapping = map_columns(text_rows[best])

    numeric, units = _classify_columns(text_rows, mapping, n_cols)
    name_col = mapping.get("Товар")

    # Перечитывание по роли колонки: единицы — по-ячеечно (psm 7 + апскейл;
    # стрипом глифы «шт» не читаются), «Товар» — по-ячеечно на best-моделях
    # (снимает путаницу латиницы с кириллицей), числа — полосой с whitelist
    # цифр, прочее — полосой. Всё от низа заголовочного бэнда.
    header_found = scores[best] >= BAND_HEADER_MIN_SCORE
    y_lo = int(rows[best + 1]) if header_found else int(rows[0])
    strip_cells = [[[] for _ in range(n_cols)] for _ in range(len(rows) - 1)]
    cell_texts = {}
    for j in range(n_cols):
        if j in units:
            for band in range(best + 1, len(rows) - 1):
                cell_texts[(band, j)] = _cell_ocr(
                    pil, cols[j], cols[j + 1], rows[band], rows[band + 1],
                    psm=UNIT_PSM, upscale=UNIT_UPSCALE,
                    whitelist=UNIT_WHITELIST)
        elif j == name_col:
            for band in range(best + 1, len(rows) - 1):
                cell_texts[(band, j)] = _cell_ocr(
                    pil, cols[j], cols[j + 1], rows[band], rows[band + 1],
                    psm=STRIP_PSM, upscale=NAME_UPSCALE, lang=NAME_LANG,
                    inset_x=6, inset_y=4)
        else:
            whitelist = DIGIT_WHITELIST if j in numeric else None
            strip_words = _strip_column(pil, cols[j], cols[j + 1], y_lo,
                                        int(rows[-1]), whitelist)
            for w in strip_words:
                band = _band_index(rows, (w["y0"] + w["y1"]) / 2)
                if band is not None:
                    strip_cells[band][j].append(w)
    out = []
    for band in range(len(rows) - 1):
        row = []
        for j in range(n_cols):
            if (band, j) in cell_texts:
                row.append(cell_texts[(band, j)])
            elif strip_cells[band][j]:
                row.append(_cell_text(strip_cells[band][j]))
            else:
                row.append(text_rows[band][j])
        joined = " ".join(row).lower()
        if band > best and any(k in joined for k in TAIL_BAND_KEYWORDS):
            continue  # хвост счёта: итоги, вес/объём, «всего наименований»
        out.append(row)
    return out


def _rows_from_stream(words):
    """Без линеек: строки по y-кластерам, ячейки по большим x-разрывам."""
    if not words:
        return []
    heights = sorted(w["y1"] - w["y0"] for w in words)
    med_h = heights[len(heights) // 2]
    lines, cur, cur_y = [], [], None
    for w in sorted(words, key=lambda w: ((w["y0"] + w["y1"]) / 2, w["x0"])):
        cy = (w["y0"] + w["y1"]) / 2
        if cur_y is None or cy - cur_y <= med_h * 0.7:
            cur.append(w)
        else:
            lines.append(cur)
            cur = [w]
        cur_y = cy
    if cur:
        lines.append(cur)

    # Ячейки внутри строки: разрыв между словами больше STREAM_COL_GAP*med_h.
    row_cells = []
    for line in lines:
        cells_seq, cur, prev = [], [line[0]], line[0]
        for w in line[1:]:
            if w["x0"] - prev["x1"] > STREAM_COL_GAP * med_h:
                cells_seq.append(cur)
                cur = [w]
            else:
                cur.append(w)
            prev = w
        if cur:
            cells_seq.append(cur)
        row_cells.append([(min(w["x0"] for w in c), max(w["x1"] for w in c),
                           _cell_text(c)) for c in cells_seq])

    # Колонки: объединяем перекрывающиеся интервалы ячеек всех строк —
    # каждая группа = отдельная колонка.
    intervals = sorted((c[0], c[1]) for cells in row_cells for c in cells)
    if not intervals:
        return []
    merged = []
    for lo, hi in intervals:
        if merged and lo <= merged[-1][1]:
            merged[-1][1] = max(merged[-1][1], hi)
        else:
            merged.append([lo, hi])
    bounds = [m[0] for m in merged] + [merged[-1][1]]

    out = []
    for cells in row_cells:
        row = [""] * (len(bounds) - 1)
        for lo, hi, text in cells:
            idx = _span_index(bounds, lo, hi)
            if idx is None:
                continue
            row[idx] = (row[idx] + " " + text).strip()
        out.append(row)
    return out


def _to_df(rows):
    width = max((len(r) for r in rows), default=0)
    if width == 0:
        return pd.DataFrame()
    padded = [list(r) + [""] * (width - len(r)) for r in rows]
    return pd.DataFrame(padded)


def extract_with_ocr(pdf_path, scale=RENDER_SCALE, lang=TESS_LANG, psm=TESS_PSM):
    """([таблицы-кандидаты с .df], текст всех страниц)."""
    import numpy as np
    from PIL import Image
    from normalizer import score_header_row

    tables = []  # каждый элемент: список строк (списки ячеек)
    texts = []
    for pil in _render_pages(pdf_path, scale):
        gray = np.asarray(pil)
        grid, vmask, hmask = _detect_grid(gray)
        if grid:
            clean = Image.fromarray(_erase_lines(gray, vmask, hmask))
        else:
            clean = pil
        words = _ocr_words(clean, lang=lang, psm=psm)
        texts.append(_page_text(words).translate(_HOMOGLYPHS))
        rows = (_rows_from_grid(clean, words, grid) if grid
                else _rows_from_stream(words))
        rows = [r for r in rows if any(str(c).strip() for c in r)]
        has_header = any(score_header_row(r) >= HEADER_ACCEPT_SCORE for r in rows)
        if tables and rows and not has_header:
            tables[-1].extend(rows)  # продолжение таблицы предыдущей страницы
        elif rows:
            tables.append(rows)
    result = [_Table(_to_df(rows)) for rows in tables if rows]
    return result, "\n".join(texts)


if __name__ == "__main__":
    import sys
    tables, text = extract_with_ocr(sys.argv[1])
    print("=== ТЕКСТ СТРАНИЦ ===")
    print(text)
    for i, t in enumerate(tables):
        print(f"=== ТАБЛИЦА {i + 1} ({len(t.df)} строк) ===")
        print(t.df.to_string(index=False, header=False))
