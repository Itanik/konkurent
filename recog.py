import os
import json
import argparse
import pandas as pd
from glob import glob

from copy import copy

from openpyxl import Workbook
from openpyxl.utils import get_column_letter
from openpyxl.styles import Font, Border, Side, Alignment

from normalizer import process_pdf_tables, STANDARD_COLUMNS


def extract_with_camelot(pdf_path):
    import camelot
    tables = []
    print(f"  Camelot (lattice)...")
    try:
        lattice_tables = camelot.read_pdf(pdf_path, pages="all", flavor="lattice")
        if len(lattice_tables) > 0:
            print(f"    Найдено {len(lattice_tables)} таблиц(а) методом lattice")
            tables.extend(lattice_tables)
    except Exception as e:
        print(f"    Ошибка lattice: {e}")

    # Stream пробуем всегда, а не только при пустом lattice: у счетов без
    # линеек (типовая верстка 1С) lattice не видит таблицу позиций вовсе или
    # возвращает мусор, а normalizer выбирает лучшую таблицу по скору шапки.
    print(f"  Camelot (stream)...")
    try:
        stream_tables = camelot.read_pdf(pdf_path, pages="all", flavor="stream")
        if len(stream_tables) > 0:
            print(f"    Найдено {len(stream_tables)} таблиц(а) методом stream")
            tables.extend(stream_tables)
    except Exception as e:
        print(f"    Ошибка stream: {e}")

    return tables


def load_config(path):
    with open(path, "r", encoding="utf-8") as f:
        cfg = json.load(f)

    block_size = len(cfg["block_columns"])
    fixed_len = len(cfg["fixed_columns"])
    cfg["_block_size"] = block_size
    cfg["_fixed_len"] = fixed_len

    for i, m in enumerate(cfg["row"].get("meta", [])):
        m.setdefault("value_row", None)

    return cfg


def build_workbook(config, n_suppliers, request_name=""):
    wb = Workbook()
    ws = wb.active
    ws.title = config["sheet_name"]

    n_fixed = config["_fixed_len"]
    block_size = config["_block_size"]
    defaults = config["defaults"]

    thin_border = Border(
        left=Side(style="thin"),
        right=Side(style="thin"),
        top=Side(style="thin"),
        bottom=Side(style="thin"),
    )
    font_size = defaults.get("font_size", 11)
    font_name = defaults.get("font_name", "Calibri")
    bold_font = Font(name=font_name, size=font_size, bold=True)
    normal_font = Font(name=font_name, size=font_size)

    for i, col_cfg in enumerate(config["fixed_columns"]):
        cl = get_column_letter(i + 1)
        if col_cfg.get("width"):
            ws.column_dimensions[cl].width = col_cfg["width"]

    for b_idx in range(n_suppliers):
        for col_offset, col_cfg in enumerate(config["block_columns"]):
            col = n_fixed + b_idx * block_size + col_offset + 1
            cl = get_column_letter(col)
            if col_cfg.get("width"):
                ws.column_dimensions[cl].width = col_cfg["width"]
            if col_cfg.get("hidden"):
                ws.column_dimensions[cl].hidden = True

    center_align = Alignment(horizontal="center", vertical="center")
    for c in range(1, n_fixed + 1):
        ws.cell(row=1, column=c).border = thin_border
    ws.cell(row=1, column=1).value = f"Заявка: {request_name}"
    ws.cell(row=1, column=1).font = bold_font
    ws.cell(row=1, column=1).alignment = center_align
    ws.merge_cells(start_row=1, start_column=1, end_row=1, end_column=n_fixed)
    for b_idx in range(n_suppliers):
        sc = n_fixed + b_idx * block_size + 1
        ec = sc + block_size - 1
        for c in range(sc, ec + 1):
            ws.cell(row=1, column=c).border = thin_border
        ws.merge_cells(start_row=1, start_column=sc, end_row=1, end_column=ec)
        cell = ws.cell(row=1, column=sc)
        cell.font = bold_font
        cell.alignment = center_align

    for i, col_cfg in enumerate(config["fixed_columns"]):
        cell = ws.cell(row=2, column=i + 1)
        cell.value = col_cfg["header"]
        cell.font = bold_font
        cell.border = thin_border
    for b_idx in range(n_suppliers):
        for col_offset, col_cfg in enumerate(config["block_columns"]):
            col = n_fixed + b_idx * block_size + col_offset + 1
            cell = ws.cell(row=2, column=col)
            cell.value = col_cfg["header"]
            cell.font = bold_font
            cell.border = thin_border

    row_cfg = config["row"]
    data_start = row_cfg["data_start"]
    n_data = row_cfg["data_rows"]
    for r in range(data_start, data_start + n_data):
        for c in range(1, n_fixed + n_suppliers * block_size + 1):
            cell = ws.cell(row=r, column=c)
            cell.font = normal_font
            cell.border = thin_border

    meta_labels = [m["label"] for m in row_cfg["meta"]]
    meta_start = data_start + n_data
    for i, label in enumerate(meta_labels):
        row = meta_start + i
        for c in range(1, n_fixed + 1):
            ws.cell(row=row, column=c).border = thin_border
        ws.merge_cells(start_row=row, start_column=1, end_row=row, end_column=n_fixed)
        cell = ws.cell(row=row, column=1)
        cell.value = label
        cell.font = normal_font
        cell.alignment = Alignment(horizontal="center", vertical="center")
        cell.border = thin_border
        for b_idx in range(n_suppliers):
            sc = n_fixed + b_idx * block_size + 1
            ec = sc + block_size - 1
            for c in range(sc, ec + 1):
                cell = ws.cell(row=row, column=c)
                cell.font = normal_font
                cell.alignment = Alignment(horizontal="center", vertical="center")
                cell.border = thin_border
            ws.merge_cells(start_row=row, start_column=sc, end_row=row, end_column=ec)

    total_row = meta_start + len(meta_labels)
    for c in range(1, n_fixed + 1):
        ws.cell(row=total_row, column=c).border = thin_border
    ws.merge_cells(start_row=total_row, start_column=1, end_row=total_row, end_column=n_fixed)

    for b_idx in range(n_suppliers):
        sc = n_fixed + b_idx * block_size + 1
        ec = sc + block_size - 1
        for c in range(sc, ec + 1):
            ws.cell(row=total_row, column=c).border = thin_border
        if block_size >= 4:
            ws.merge_cells(start_row=total_row, start_column=sc,
                           end_row=total_row, end_column=sc + 3)
        cell = ws.cell(row=total_row, column=ec)
        cell.value = "Сумма"
        cell.font = bold_font

    wrap_align = Alignment(wrap_text=True, vertical="center")
    for r in range(2, total_row + 1):
        for c in range(1, n_fixed + n_suppliers * block_size + 1):
            ws.cell(row=r, column=c).alignment = wrap_align

    meta_font = Font(name=font_name, size=14)
    meta_center = Alignment(horizontal="center", vertical="center", wrap_text=True)
    for mr in range(meta_start, total_row):
        for mc in range(1, n_fixed + n_suppliers * block_size + 1):
            cell = ws.cell(row=mr, column=mc)
            cell.font = meta_font
            cell.alignment = meta_center

    ws.page_setup.orientation = 'landscape'
    ws.page_setup.fitToWidth = 1
    ws.page_setup.fitToHeight = 1
    ws.page_setup.fitToPage = True

    return wb, ws, data_start, n_data, meta_start, total_row


def _copy_style(src, dst):
    try:
        dst.font = copy(src.font)
    except Exception:
        pass
    try:
        dst.fill = copy(src.fill)
    except Exception:
        pass
    try:
        dst.border = copy(src.border)
    except Exception:
        pass
    try:
        dst.alignment = copy(src.alignment)
    except Exception:
        pass
    try:
        dst.number_format = src.number_format
    except Exception:
        pass


def _copy_block_formatting(ws, dst_start, src_start, max_row, block_size):
    for row in range(1, max_row + 1):
        for i in range(block_size):
            _copy_style(ws.cell(row=row, column=src_start + i),
                        ws.cell(row=row, column=dst_start + i))


# Колонки, ширина которых остаётся фиксированной (из config.json), а не
# подгоняется по содержимому: длинные названия переносятся по строкам.
FIXED_WIDTH_HEADERS = {"Название позиции", "Предложено"}

MAX_AUTO_WIDTH = 60


def _cell_display_len(cell):
    value = cell.value
    if value is None:
        return 0
    text = str(value)
    if text.startswith("="):
        # Формулы (Ц/ед, SUM) не должны задавать ширину по своему тексту.
        return 0
    number_format = cell.number_format or ""
    if isinstance(value, (int, float)) and "0.00" in number_format:
        return len(f"{value:,.2f}".replace(",", " "))
    return len(text)


def _auto_fit_column(ws, col, rows):
    max_len = 0
    for r in rows:
        max_len = max(max_len, _cell_display_len(ws.cell(row=r, column=col)))
    ws.column_dimensions[get_column_letter(col)].width = min(
        max_len + 2, MAX_AUTO_WIDTH
    )


def _auto_fit_columns(ws, config, n_fixed, block_size, blocks,
                      data_start, data_end, total_row):
    header_row = data_start - 1
    data_rows = list(range(data_start, data_end + 1))

    for i, col_cfg in enumerate(config["fixed_columns"]):
        if col_cfg["header"] in FIXED_WIDTH_HEADERS:
            continue
        _auto_fit_column(ws, i + 1, [header_row] + data_rows)

    for b in blocks:
        for offset, col_cfg in enumerate(config["block_columns"]):
            if col_cfg["header"] in FIXED_WIDTH_HEADERS:
                continue
            rows = [header_row] + data_rows
            if offset == block_size - 1:
                rows.append(total_row)
            _auto_fit_column(ws, b["start"] + offset, rows)


def _find_or_create_block(ws, existing_blocks, config):
    for b in existing_blocks:
        if not b["name"]:
            b["name"] = "PLACEHOLDER"
            return b

    block_size = config["_block_size"]
    n_fixed = config["_fixed_len"]

    if existing_blocks:
        last = max(b["end"] for b in existing_blocks)
        start = last + 1
    else:
        start = n_fixed + 1
    end = start + block_size - 1

    ws.merge_cells(start_row=1, start_column=start, end_row=1, end_column=end)

    bold_font = Font(name=config["defaults"].get("font_name", "Calibri"),
                     size=config["defaults"].get("font_size", 11), bold=True)
    thin_border = Border(
        left=Side(style="thin"), right=Side(style="thin"),
        top=Side(style="thin"), bottom=Side(style="thin"),
    )
    for i, col_cfg in enumerate(config["block_columns"]):
        cell = ws.cell(row=2, column=start + i)
        cell.value = col_cfg["header"]
        cell.font = bold_font
        cell.border = thin_border

    wrap_align = Alignment(wrap_text=True, vertical="center")
    first_col = start
    for r in range(3, ws.max_row + 1):
        ws.cell(row=r, column=first_col).alignment = wrap_align

    for col_offset, col_cfg in enumerate(config["block_columns"]):
        cl = get_column_letter(start + col_offset)
        if col_cfg.get("width"):
            ws.column_dimensions[cl].width = col_cfg["width"]
        if col_cfg.get("hidden"):
            ws.column_dimensions[cl].hidden = True

    block = {"start": start, "end": end, "name": "PLACEHOLDER", "filename": None}
    existing_blocks.append(block)
    existing_blocks.sort(key=lambda b: b["start"])
    return block


def _to_num(val):
    if val is None:
        return None
    s = str(val).strip()
    if not s or s in ("nan", "None", ""):
        return None
    try:
        return float(s.replace(",", "."))
    except (ValueError, TypeError):
        return None


def _fill_data_row(ws, row_idx, block_start, row_data, bez_nds, price=None):
    ws.cell(row=row_idx, column=block_start).value = row_data.get("Товар")
    ws.cell(row=row_idx, column=block_start + 1).value = _to_num(row_data.get("Кол-во"))
    ws.cell(row=row_idx, column=block_start + 2).value = row_data.get("Ед. изм")

    sum_col = get_column_letter(block_start + 5)
    qty_col = get_column_letter(block_start + 1)
    price_col = get_column_letter(block_start + 3)
    if price is not None:
        # Введённая вручную цена — источник истины: она пишется значением,
        # а сумма становится формулой «цена × кол-во».
        ws.cell(row=row_idx, column=block_start + 3).value = _to_num(price)
        ws.cell(row=row_idx, column=block_start + 5).value = (
            f'=IFERROR({price_col}{row_idx}*{qty_col}{row_idx},"")'
        )
    else:
        ws.cell(row=row_idx, column=block_start + 3).value = (
            f'=IFERROR({sum_col}{row_idx}/{qty_col}{row_idx},"")'
        )
        ws.cell(row=row_idx, column=block_start + 5).value = _to_num(row_data.get("Сумма"))

    ws.cell(row=row_idx, column=block_start + 4).value = _to_num(bez_nds)

    for off in (3, 4, 5):
        ws.cell(row=row_idx, column=block_start + off).number_format = "#,##0.00"


def _maybe_add_hidden_filename_row(ws, config, block_names, pdf_data_list):
    if not block_names:
        return False
    ws.insert_rows(2)
    n_fixed = config["_fixed_len"]
    block_size = config["_block_size"]
    defaults = config["defaults"]
    thin_border = Border(
        left=Side(style="thin"),
        right=Side(style="thin"),
        top=Side(style="thin"),
        bottom=Side(style="thin"),
    )
    normal_font = Font(
        name=defaults.get("font_name", "Calibri"),
        size=defaults.get("font_size", 11),
    )

    for c in range(1, n_fixed + 1):
        ws.cell(row=2, column=c).border = thin_border
    ws.merge_cells(start_row=2, start_column=1, end_row=2, end_column=n_fixed)

    for b_idx, entry in enumerate(pdf_data_list):
        df = entry[0]
        filename = df.columns.get_level_values(0)[0]
        sc = n_fixed + b_idx * block_size + 1
        ec = sc + block_size - 1
        for c in range(sc, ec + 1):
            ws.cell(row=2, column=c).border = thin_border
        if block_size > 1:
            ws.merge_cells(start_row=2, start_column=sc, end_row=2, end_column=ec)
        cell = ws.cell(row=2, column=sc)
        cell.value = filename
        cell.font = normal_font

    ws.row_dimensions[2].hidden = True
    return True


def fill_template(pdf_data_list, target_dir, script_dir, output_path=None,
                  block_names=None, request_name="", request_items=None,
                  meta_values=None):
    config = load_config(os.path.join(script_dir, "config.json"))

    n_fixed = config["_fixed_len"]
    block_size = config["_block_size"]
    bold_font = Font(name=config["defaults"].get("font_name", "Calibri"),
                     size=config["defaults"].get("font_size", 11), bold=True)

    if output_path is None:
        folder_basename = os.path.basename(target_dir)
        output_name = f"конкурент {folder_basename}.xlsx"
        output_path = os.path.join(target_dir, output_name)
    else:
        output_name = os.path.basename(output_path)

    wb, ws, data_start, n_data_rows, meta_start, total_row = \
        build_workbook(config, len(pdf_data_list), request_name)

    if _maybe_add_hidden_filename_row(ws, config, block_names, pdf_data_list):
        data_start += 1
        meta_start += 1
        total_row += 1

    existing_blocks = []
    for b_idx in range(len(pdf_data_list)):
        sc = n_fixed + b_idx * block_size + 1
        ec = sc + block_size - 1
        existing_blocks.append({"start": sc, "end": ec, "name": "", "filename": None})

    data_end = meta_start - 1
    ref_block_start = existing_blocks[0]["start"] if existing_blocks else None
    original_block_count = len(existing_blocks)

    if request_items:
        for i, (name, qty) in enumerate(request_items):
            row_idx = data_start + i
            if row_idx > data_end:
                ws.insert_rows(row_idx, 1)
                data_end += 1
                total_row += 1
                meta_start += 1
                for b in existing_blocks:
                    for col_offset in range(block_size):
                        _copy_style(
                            ws.cell(row=data_start, column=b["start"] + col_offset),
                            ws.cell(row=row_idx, column=b["start"] + col_offset),
                        )
                for col in range(1, n_fixed + 1):
                    _copy_style(ws.cell(row=data_start, column=col),
                                ws.cell(row=row_idx, column=col))
            ws.cell(row=row_idx, column=1, value=i + 1)
            ws.cell(row=row_idx, column=2, value=name)
            ws.cell(row=row_idx, column=3, value=qty)

    for entry in pdf_data_list:
        df, bez_nds = entry[0], entry[2]
        # Четвёртый элемент (опционально) — цены, введённые вручную:
        # тогда сумма строки в xlsx становится формулой «цена × кол-во».
        prices = entry[3] if len(entry) > 3 else None
        if df.shape[0] == 0:
            continue

        filename = df.columns.get_level_values(0)[0]

        already_exists = any(
            b["name"] and filename in b["name"]
            for b in existing_blocks
        )
        if already_exists:
            continue

        block = _find_or_create_block(ws, existing_blocks, config)
        block["filename"] = filename
        effective_name = (block_names or {}).get(filename, filename)
        block["name"] = effective_name

        cell = ws.cell(row=1, column=block["start"])
        cell.value = effective_name

        max_data_rows = data_end - data_start + 1
        for i in range(min(len(df), max_data_rows)):
            row_idx = data_start + i
            row_data = {col: df.iloc[i][(filename, col)] for col in STANDARD_COLUMNS}
            bv = bez_nds[i] if i < len(bez_nds) else None
            pv = prices[i] if prices and i < len(prices) else None
            _fill_data_row(ws, row_idx, block["start"], row_data, bv, price=pv)

        if len(df) > max_data_rows:
            extra = len(df) - max_data_rows
            ws.insert_rows(data_end + 1, extra)

            for i in range(max_data_rows, len(df)):
                row_idx = data_start + i
                row_data = {col: df.iloc[i][(filename, col)] for col in STANDARD_COLUMNS}
                bv = bez_nds[i] if i < len(bez_nds) else None
                pv = prices[i] if prices and i < len(prices) else None
                _fill_data_row(ws, row_idx, block["start"], row_data, bv, price=pv)

            total_row += extra
            data_end += extra
            meta_start += extra
            for r in range(data_end - extra + 1, data_end + 1):
                for b in existing_blocks:
                    for col_offset in range(block_size):
                        _copy_style(
                            ws.cell(row=data_start, column=b["start"] + col_offset),
                            ws.cell(row=r, column=b["start"] + col_offset),
                        )
                for col in range(1, n_fixed + 1):
                    _copy_style(ws.cell(row=data_start, column=col),
                                ws.cell(row=r, column=col))

    for b in existing_blocks:
        ws.merge_cells(start_row=total_row, start_column=b["start"],
                       end_row=total_row, end_column=b["start"] + 3)

        for col_offset, col_cfg in enumerate(config["block_columns"]):
            if col_cfg.get("hidden"):
                cl = get_column_letter(b["start"] + col_offset)
                ws.column_dimensions[cl].hidden = True

        ws.cell(row=total_row, column=b["start"] + block_size - 1).value = "Сумма"

        total_col_letter = get_column_letter(b["start"] + block_size - 1)
        sum_cell = ws.cell(row=total_row + 1, column=b["start"] + block_size - 1)
        sum_cell.value = f"=SUM({total_col_letter}{data_start}:{total_col_letter}{data_end})"
        sum_cell.font = bold_font
        sum_cell.number_format = "#,##0.00"

    ws.merge_cells(start_row=total_row, start_column=1,
                   end_row=total_row, end_column=n_fixed)

    new_blocks = existing_blocks[original_block_count:] if ref_block_start else []
    for b in new_blocks:
        _copy_block_formatting(ws, b["start"], ref_block_start, total_row + 1, block_size)

    stale_ranges = list(ws.merged_cells.ranges)
    for mc in stale_ranges:
        if mc.min_row < total_row and mc.min_row >= data_start:
            ws.merged_cells.remove(mc)

    meta_start_actual = meta_start
    meta_end_actual = total_row - 1
    for mr in range(meta_start_actual, meta_end_actual + 1):
        ws.merge_cells(start_row=mr, start_column=1, end_row=mr, end_column=n_fixed)
        for b in existing_blocks:
            ws.merge_cells(start_row=mr, start_column=b["start"],
                           end_row=mr, end_column=b["end"])
    meta_font = Font(name=config["defaults"].get("font_name", "Calibri"), size=14)
    meta_center = Alignment(horizontal="center", vertical="center", wrap_text=True)
    for mr in range(meta_start_actual, meta_end_actual + 1):
        for mc in range(1, n_fixed + len(existing_blocks) * block_size + 1):
            cell = ws.cell(row=mr, column=mc)
            cell.font = meta_font
            cell.alignment = meta_center

    _auto_fit_columns(ws, config, n_fixed, block_size, existing_blocks,
                      data_start, data_end, total_row)

    if meta_values:
        meta_labels = [m["label"] for m in config["row"]["meta"]]
        for b in existing_blocks:
            fn = b.get("filename")
            if not fn:
                continue
            vals = meta_values.get(fn)
            if not vals:
                continue
            for i, label in enumerate(meta_labels):
                mr = meta_start_actual + i
                if mr > meta_end_actual:
                    break
                cell = ws.cell(row=mr, column=b["start"])
                cell.value = vals.get(label, "")
                cell.font = meta_font
                cell.alignment = meta_center

    wb.save(output_path)
    print(f"\nГотово! Конкурентная таблица сохранена как '{output_name}'")
    return output_path


def process_pdf_file(pdf_path, file_data_list):
    print(f"\nОбработка: {os.path.basename(pdf_path)}")
    tables = extract_with_camelot(pdf_path)
    filename = os.path.basename(pdf_path)

    if tables:
        df, orig, bez_nds = process_pdf_tables(tables, filename)
        n_rows = len(df)
        if n_rows > 0:
            print(f"    Извлечено строк: {n_rows}")
        else:
            print(f"    Таблица не найдена (пустой результат)")
        file_data_list.append((df, orig, bez_nds))
    else:
        print(f"    Не удалось извлечь таблицы")
        empty = pd.DataFrame(columns=pd.MultiIndex.from_product([[filename], STANDARD_COLUMNS]))
        orig = {col: col for col in STANDARD_COLUMNS}
        file_data_list.append((empty, orig, []))


def main():
    parser = argparse.ArgumentParser(
        description="Извлечение таблиц из всех PDF-файлов в папке и заполнение конкурентной таблицы."
    )
    parser.add_argument("folder_path", help="Путь к папке с PDF-файлами")
    args = parser.parse_args()

    if not os.path.isdir(args.folder_path):
        print(f"Ошибка: Папка '{args.folder_path}' не найдена.")
        return

    pdf_files = sorted(glob(os.path.join(args.folder_path, "*.[pP][dD][fF]")))
    if not pdf_files:
        print(f"В папке '{args.folder_path}' не найдено PDF-файлов.")
        return

    print(f"Найдено PDF-файлов: {len(pdf_files)}")
    file_data_list = []

    for pdf_path in pdf_files:
        process_pdf_file(pdf_path, file_data_list)

    if not file_data_list:
        print("Не удалось извлечь ни одной таблицы.")
        return

    script_dir = os.path.dirname(os.path.abspath(__file__))
    fill_template(file_data_list, args.folder_path, script_dir)


if __name__ == "__main__":
    main()


# ---------------------------------------------------------------------------
# Экспорт для Flutter-sidecar: раскладка вычисляется заранее (группы позиций
# заявки с вертикальными объединениями, строка ИНН, скрытая строка файлов,
# лист «Суммы»), вставки строк и компенсации merge не нужны.
# ---------------------------------------------------------------------------

def _thin_border():
    return Border(
        left=Side(style="thin"), right=Side(style="thin"),
        top=Side(style="thin"), bottom=Side(style="thin"),
    )


def build_comparison_xlsx(
    state,
    script_dir,
    output_path,
    request_name="",
):
    """Строит книгу по AppState из sidecar (см. sidecar.action_export).

    state: {"requestName", "requestItems": [{name, qty, unit}],
            "suppliers": [{displayName, sourceFileNames, inn, withoutVat,
                           meta{...},
                           offers: [{itemName, qty, unit, sumWithVat,
                                     sumWithoutVat, priceWithVat,
                                     priceWithoutVat, priceDriver,
                                     linkedRequestItemId}]}]}
    """
    config = load_config(os.path.join(script_dir, "config.json"))
    n_fixed = config["_fixed_len"]
    block_size = config["_block_size"]
    meta_cfg = config["row"]["meta"]

    font_name = config["defaults"].get("font_name", "Calibri")
    font_size = config["defaults"].get("font_size", 14)
    bold_font = Font(name=font_name, size=font_size, bold=True)
    normal_font = Font(name=font_name, size=font_size)
    thin = _thin_border()
    wrap = Alignment(horizontal="left", vertical="top", wrap_text=True)
    center_wrap = Alignment(horizontal="center", vertical="center",
                            wrap_text=True)

    request_name = request_name or state.get("requestName") or "Заявка"
    items = state.get("requestItems", [])
    suppliers = state.get("suppliers", [])

    # --- структура строк -------------------------------------------------------
    # 1 имя заявки / названия блоков+покрытие, 2 ИНН, 3 скрытые файлы,
    # 4 заголовки, далее группы позиций, зона без привязки, мета, «Сумма»,
    # строка =SUM, строки вариантов.
    groups = []  # (item, rows_count)
    for it in items:
        name = str(it.get("name", "")).strip()
        if not name:
            continue
        max_rows = 1
        rid = it.get("id")
        for sup in suppliers:
            linked = [o for o in sup.get("offers", [])
                      if o.get("linkedRequestItemId") == rid]
            if len(linked) > max_rows:
                max_rows = len(linked)
        groups.append((it, max_rows))

    unlinked_rows = 1
    for sup in suppliers:
        n = len([o for o in sup.get("offers", [])
                 if not o.get("linkedRequestItemId")])
        unlinked_rows = max(unlinked_rows, n + 1)

    header_row = 4
    data_start = 5
    group_rows = sum(r for _, r in groups)
    unlinked_start = data_start + group_rows
    meta_start = unlinked_start + unlinked_rows
    total_row = meta_start + len(meta_cfg)
    sum_row = total_row + 1
    variants_start = sum_row + 1

    variants = state.get("bestVariants") or []
    last_row = variants_start + len(variants) - 1

    wb = Workbook()

    # --- лист «Заявка» ---------------------------------------------------------
    ws = wb.active
    ws.title = config["sheet_name"]

    def put(row, col, value, font=None, align=None, border=True, fmt=None):
        cell = ws.cell(row=row, column=col)
        if value is not None:
            cell.value = value
        if font:
            cell.font = font
        if align:
            cell.alignment = align
        if border:
            cell.border = thin
        if fmt:
            cell.number_format = fmt
        return cell

    # Строка 1: заявка + названия блоков (+ покрытие).
    put(1, 1, f"Заявка: {request_name}", bold_font,
        Alignment(horizontal="center", vertical="center"))
    ws.merge_cells(start_row=1, start_column=1, end_row=1, end_column=n_fixed)

    # Строка 2: ИНН (метка в фикс. части).
    put(2, 1, "ИНН поставщика:", normal_font,
        Alignment(horizontal="center", vertical="center"))

    for b_idx, sup in enumerate(suppliers):
        sc = n_fixed + b_idx * block_size + 1
        ec = sc + block_size - 1
        display = str(sup.get("displayName", "")).strip() or "Поставщик"
        rid = sup.get("id")
        items_count = len(groups)
        if items_count:
            req = state.get("requestItems", [])
            covered = 0
            for it, _r in groups:
                linked = [o for o in sup.get("offers", [])
                          if o.get("linkedRequestItemId") == it.get("id")]
                qty = None
                try:
                    qty = float(str(it.get("qty", "")).replace(",", ".")
                                .replace(" ", "") or "nan")
                except (ValueError, TypeError):
                    qty = None
                got = sum(float(o.get("qty") or 0) for o in linked)
                if linked and (qty is None or qty <= 0 or got >= qty):
                    covered += 1
            display = f"{display} ({covered}/{items_count})"
        put(1, sc, display, bold_font, center_wrap)
        ws.merge_cells(start_row=1, start_column=sc, end_row=1, end_column=ec)

        inn = str(sup.get("inn") or "").strip()
        put(2, sc, inn or None, normal_font, center_wrap)
        ws.merge_cells(start_row=2, start_column=sc, end_row=2, end_column=ec)

        files = sup.get("sourceFileNames") or []
        if files:
            put(3, sc, "; ".join(str(f) for f in files), normal_font)
            ws.merge_cells(start_row=3, start_column=sc, end_row=3,
                           end_column=ec)

    ws.row_dimensions[3].hidden = True

    # Строка 4: заголовки.
    for c, col_cfg in enumerate(config["fixed_columns"], start=1):
        put(header_row, c, col_cfg["header"], bold_font, center_wrap)
    for b_idx in range(len(suppliers)):
        sc = n_fixed + b_idx * block_size + 1
        for c, col_cfg in enumerate(config["block_columns"]):
            put(header_row, sc + c, col_cfg["header"], bold_font, center_wrap)

    # Ширины колонок.
    for c, col_cfg in enumerate(config["fixed_columns"], start=1):
        ws.column_dimensions[get_column_letter(c)].width = col_cfg["width"]
    for b_idx in range(len(suppliers)):
        sc = n_fixed + b_idx * block_size + 1
        for c, col_cfg in enumerate(config["block_columns"]):
            ws.column_dimensions[get_column_letter(sc + c)].width = \
                col_cfg["width"]

    # Группы: ячейки заявки объединены на высоту группы; предложения
    # поставщика построчно; поставщик с одним предложением — merge на группу.
    row = data_start
    for it, rows_n in groups:
        rid = it.get("id")
        put(row, 1, None)
        for c, key in ((2, "name"), (3, "qty"), (4, "unit")):
            put(row, c, str(it.get(key, "") or "") or None, normal_font,
                wrap if key == "name" else center_wrap)
        for c in range(1, n_fixed + 1):
            ws.merge_cells(start_row=row, start_column=c,
                           end_row=row + rows_n - 1, end_column=c)

        for b_idx, sup in enumerate(suppliers):
            sc = n_fixed + b_idx * block_size + 1
            offers = [o for o in sup.get("offers", [])
                      if o.get("linkedRequestItemId") == rid][:rows_n]
            if len(offers) <= 1:
                _write_offer_rows(ws, sc, row, rows_n, offers or [None],
                                  normal_font, thin, put, config)
                if not offers:
                    ws.merge_cells(start_row=row, start_column=sc,
                                   end_row=row + rows_n - 1, end_column=sc)
            else:
                for j, off in enumerate(offers):
                    _write_offer_rows(ws, sc, row + j, 1, [off],
                                      normal_font, thin, put, config)

        row += rows_n

    # Зона без привязки: непривязанные предложения + пустые строки.
    for j in range(unlinked_rows):
        for b_idx, sup in enumerate(suppliers):
            sc = n_fixed + b_idx * block_size + 1
            unlinked = [o for o in sup.get("offers", [])
                        if not o.get("linkedRequestItemId")]
            off = unlinked[j] if j < len(unlinked) else None
            _write_offer_rows(ws, sc, unlinked_start + j, 1,
                              [off] if off else [None],
                              normal_font, thin, put, config)

    # Мета.
    meta_font = Font(name=font_name, size=font_size)
    for i, m in enumerate(meta_cfg):
        r = meta_start + i
        put(r, 1, m["label"], meta_font, center_wrap)
        ws.merge_cells(start_row=r, start_column=1, end_row=r,
                       end_column=n_fixed)
        for b_idx, sup in enumerate(suppliers):
            sc = n_fixed + b_idx * block_size + 1
            ec = sc + block_size - 1
            meta = sup.get("meta") or {}
            val = str(meta.get(_meta_key(m["label"]), "") or "")
            put(r, sc, val or None, meta_font, center_wrap)
            ws.merge_cells(start_row=r, start_column=sc, end_row=r,
                           end_column=ec)

    # Итог: метка + =SUM строкой ниже (сохраняем старую конвенцию).
    put(total_row, 1, "Сумма", bold_font,
        Alignment(horizontal="center", vertical="center"))
    ws.merge_cells(start_row=total_row, start_column=1, end_row=total_row,
                   end_column=n_fixed)
    for b_idx, sup in enumerate(suppliers):
        sc = n_fixed + b_idx * block_size + 1
        ec = sc + block_size - 1
        sum_col_letter = get_column_letter(ec)
        put(total_row, sc, "Сумма", bold_font, center_wrap)
        ws.merge_cells(start_row=total_row, start_column=sc, end_row=total_row,
                       end_column=ec)
        cell = put(sum_row, ec,
                   f"=SUM({sum_col_letter}{data_start}:"
                   f"{sum_col_letter}{meta_start - 1})",
                   bold_font, border=True, fmt="#,##0.00")
        cell.value = f"=SUM({sum_col_letter}{data_start}:{sum_col_letter}{meta_start - 1})"

    # Скрытая колонка «Сумма, без НДС».
    for b_idx in range(len(suppliers)):
        sc = n_fixed + b_idx * block_size + 1
        for c, col_cfg in enumerate(config["block_columns"]):
            if col_cfg.get("hidden"):
                ws.column_dimensions[get_column_letter(sc + c)].hidden = True

    # Варианты закупки (если переданы): название в col 2, сумма формулой
    # в объединённых 3..4.
    for i, v in enumerate(variants):
        r = variants_start + i
        label = str(v.get("label", ""))
        cells = v.get("cells") or []  # [[col, row], ...] абсолютные координаты
        formula = "=" + "+".join(
            f"{get_column_letter(c)}{r0}" for c, r0 in cells) if cells else None
        put(r, 2, label, bold_font, wrap)
        if formula:
            put(r, 3, formula, bold_font, border=True, fmt="#,##0.00")
            ws.merge_cells(start_row=r, start_column=3, end_row=r,
                           end_column=4)

    ws.freeze_panes = ws.cell(row=data_start, column=n_fixed + 1)
    ws.page_setup.orientation = "landscape"
    ws.page_setup.fitToWidth = 1
    ws.sheet_properties.pageSetUpPr.fitToPage = True

    # --- лист «Суммы»: копия «Заявки» со скрытыми колонками -------------------
    ws2 = wb.copy_worksheet(ws)
    ws2.title = "Суммы"
    for b_idx in range(len(suppliers)):
        sc = n_fixed + b_idx * block_size + 1
        sum_col = sc + block_size - 1
        for c in range(sc, sum_col):
            ws2.column_dimensions[get_column_letter(c)].hidden = True
    ws2.sheet_view.tabSelected = False

    os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)
    wb.save(output_path)
    print(f"Готово! Конкурентная таблица сохранена как '{output_path}'")
    return output_path


_META_LABEL_TO_KEY = {
    "Договор:": "contract",
    "Сроки поставки:": "deliveryTime",
    "Доставка:": "delivery",
    "Условия оплаты:": "paymentTerms",
    "Комментарий:": "comment",
}


def _meta_key(label):
    return _META_LABEL_TO_KEY.get(label, "")


def _write_offer_rows(ws, block_start, row, span, offers, normal_font, thin,
                      put, config):
    """Записывает 1..span строк предложений блока; пустая строка — рамки.

    При span>1 и одном предложении ячейки не объединяются здесь (merge делает
    вызывающий код), но рамки проставляются на весь диапазон до объединения.
    """
    n = len(offers)
    for j in range(span):
        r = row + j
        off = offers[j] if j < n else None
        _write_offer_row(ws, block_start, r, off, normal_font, thin, put,
                         config)


def _write_offer_row(ws, block_start, row, offer, normal_font, thin, put,
                     config):
    bez_nds_col = None
    price_col = None
    sum_col = None
    for c, col_cfg in enumerate(config["block_columns"]):
        header = col_cfg["header"]
        if col_cfg.get("hidden"):
            bez_nds_col = block_start + c
        if header.startswith("Ц/ед"):
            price_col = block_start + c
        if header.startswith("Сумма, с"):
            sum_col = block_start + c
    qty_col = block_start + 1

    if not offer:
        for c in range(block_start, block_start + len(config["block_columns"])):
            put(row, c, None)
        return

    put(row, block_start, str(offer.get("itemName", "")) or None,
        normal_font, Alignment(horizontal="left", vertical="top",
                               wrap_text=True))
    qty = offer.get("qty")
    put(row, qty_col, qty, normal_font,
        Alignment(horizontal="center", vertical="center"), fmt="#,##0.00")
    put(row, block_start + 2, str(offer.get("unit", "")) or None,
        normal_font, Alignment(horizontal="center", vertical="center"))

    price_driver = offer.get("priceDriver") or "sum"
    price_w = offer.get("priceWithVat")
    price_wo = offer.get("priceWithoutVat")
    sum_letter = get_column_letter(sum_col)
    qty_letter = get_column_letter(qty_col)
    price_letter = get_column_letter(price_col)

    if price_driver == "price" and (price_w is not None or price_wo is not None):
        price_val = price_w if price_w is not None else price_wo
        put(row, price_col, price_val, normal_font,
            Alignment(horizontal="right", vertical="center"),
            fmt="#,##0.00")
        put(row, sum_col,
            f'=IFERROR({price_letter}{row}*{qty_letter}{row},"")',
            normal_font, Alignment(horizontal="right", vertical="center"),
            fmt="#,##0.00")
    else:
        put(row, price_col,
            f'=IFERROR({sum_letter}{row}/{qty_letter}{row},"")',
            normal_font, Alignment(horizontal="right", vertical="center"),
            fmt="#,##0.00")
        put(row, sum_col, offer.get("sumWithVat"), normal_font,
            Alignment(horizontal="right", vertical="center"),
            fmt="#,##0.00")

    if bez_nds_col:
        put(row, bez_nds_col, offer.get("sumWithoutVat"), normal_font,
            Alignment(horizontal="right", vertical="center"),
            fmt="#,##0.00")
