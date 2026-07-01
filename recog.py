import os
import sys
import argparse
import shutil
import pandas as pd
import camelot
from glob import glob

from copy import copy

from openpyxl import load_workbook
from openpyxl.utils import get_column_letter

from normalizer import process_pdf_tables, STANDARD_COLUMNS


def extract_with_camelot(pdf_path):
    tables = []
    print(f"  Camelot (lattice)...")
    try:
        lattice_tables = camelot.read_pdf(pdf_path, pages="all", flavor="lattice")
        if len(lattice_tables) > 0:
            print(f"    Найдено {len(lattice_tables)} таблиц(а) методом lattice")
            tables.extend(lattice_tables)
    except Exception as e:
        print(f"    Ошибка lattice: {e}")

    if not tables:
        print(f"  Camelot (stream)...")
        try:
            stream_tables = camelot.read_pdf(pdf_path, pages="all", flavor="stream")
            if len(stream_tables) > 0:
                print(f"    Найдено {len(stream_tables)} таблиц(а) методом stream")
                tables.extend(stream_tables)
        except Exception as e:
            print(f"    Ошибка stream: {e}")

    return tables


BLOCK_SIZE = 6
META_KEYWORDS = ("Договор", "Сроки", "Доставк", "Условия", "Комментар")


def _find_first_meta_row(ws):
    for row in range(3, ws.max_row + 1):
        val_a = ws.cell(row=row, column=1).value
        if val_a and str(val_a).strip().startswith(META_KEYWORDS):
            return row
    return ws.max_row + 1


def _find_total_row(ws):
    for row in range(3, ws.max_row + 1):
        val_a = ws.cell(row=row, column=1).value
        if val_a and str(val_a).strip() == "Сумма":
            return row
    for row in range(3, ws.max_row + 1):
        for c in (9, 15):
            val = ws.cell(row=row, column=c).value
            if val and str(val).strip() == "Сумма":
                return row
    return ws.max_row


def _parse_supplier_blocks(ws):
    blocks = []
    for mc in ws.merged_cells.ranges:
        if mc.min_row != 1 or mc.max_row != 1:
            continue
        if mc.min_col == 1 and mc.max_col == 3:
            continue
        if mc.max_col - mc.min_col + 1 == BLOCK_SIZE:
            cell = ws.cell(row=1, column=mc.min_col)
            name = str(cell.value).strip() if cell.value else ""
            blocks.append({"start": mc.min_col, "end": mc.max_col, "name": name})
    blocks.sort(key=lambda b: b["start"])
    return blocks


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


def _copy_block_formatting(ws, dst_start, src_start, max_row):
    for row in range(1, max_row + 1):
        for i in range(BLOCK_SIZE):
            _copy_style(ws.cell(row=row, column=src_start + i),
                        ws.cell(row=row, column=dst_start + i))


def _auto_fit_block_columns(ws, block_start, end_row):
    for offset in range(1, BLOCK_SIZE):
        col = block_start + offset
        cl = get_column_letter(col)
        rows_to_check = [2] + list(range(3, end_row + 1))
        if offset == 5:
            rows_to_check.append(end_row + 1)
        max_len = 0
        for r in rows_to_check:
            val = ws.cell(row=r, column=col).value
            if val is not None:
                max_len = max(max_len, len(str(val)))
        ws.column_dimensions[cl].width = min(max_len + 2, 40)


def _find_or_create_block(ws, existing_blocks, first_meta_row, total_row, ref_block_start):
    for b in existing_blocks:
        if not b["name"]:
            b["name"] = "PLACEHOLDER"
            return b

    if existing_blocks:
        last = max(b["end"] for b in existing_blocks)
        start = last + 1
    else:
        start = 4
    end = start + BLOCK_SIZE - 1

    ws.merge_cells(start_row=1, start_column=start, end_row=1, end_column=end)

    sub = ["предложено", "кол-во", "ед.изм", "ц/ед, с НДС", "сумма, без НДС", "сумма, с НДС"]
    for i, h in enumerate(sub):
        ws.cell(row=2, column=start + i).value = h

    col_letter = get_column_letter(start + 4)
    ws.column_dimensions[col_letter].hidden = True

    prop_col = get_column_letter(start)
    ws.column_dimensions[prop_col].width = 32

    block = {"start": start, "end": end, "name": "PLACEHOLDER"}
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


def _fill_data_row(ws, row_idx, block_start, row_data, bez_nds):
    ws.cell(row=row_idx, column=block_start).value = row_data.get("Товар")
    ws.cell(row=row_idx, column=block_start + 1).value = _to_num(row_data.get("Кол-во"))
    ws.cell(row=row_idx, column=block_start + 2).value = row_data.get("Ед. изм")

    sum_col = get_column_letter(block_start + 5)
    qty_col = get_column_letter(block_start + 1)
    ws.cell(row=row_idx, column=block_start + 3).value = (
        f'=IFERROR({sum_col}{row_idx}/{qty_col}{row_idx},"")'
    )

    ws.cell(row=row_idx, column=block_start + 4).value = _to_num(bez_nds)
    ws.cell(row=row_idx, column=block_start + 5).value = _to_num(row_data.get("Сумма"))


def fill_template(pdf_data_list, target_dir, script_dir, output_path=None):
    template_src = os.path.join(script_dir, "template.xlsx")

    if output_path is None:
        folder_basename = os.path.basename(target_dir)
        parts = folder_basename.split()
        first_two = " ".join(parts[:2]) if len(parts) >= 2 else (parts[0] if parts else "unknown")
        output_name = f"конкурент {first_two}.xlsx"
        output_path = os.path.join(target_dir, output_name)
    else:
        output_name = os.path.basename(output_path)

    shutil.copy2(template_src, output_path)

    wb = load_workbook(output_path)
    ws = wb.active

    first_meta_row = _find_first_meta_row(ws)
    data_end = first_meta_row - 1
    total_row = _find_total_row(ws)

    existing_blocks = _parse_supplier_blocks(ws)
    ref_block_start = existing_blocks[0]["start"] if existing_blocks else None
    original_block_count = len(existing_blocks)

    for df, orig_headers, bez_nds in pdf_data_list:
        if df.shape[0] == 0:
            continue

        filename = df.columns.get_level_values(0)[0]

        already_exists = any(
            b["name"] and filename in b["name"]
            for b in existing_blocks
        )
        if already_exists:
            continue

        block = _find_or_create_block(ws, existing_blocks, first_meta_row,
                                      total_row, ref_block_start)
        block["name"] = filename

        cell = ws.cell(row=1, column=block["start"])
        cell.value = filename

        max_data_rows = data_end - 3 + 1 if data_end >= 3 else 1
        for i in range(min(len(df), max_data_rows)):
            row_idx = 3 + i
            row_data = {col: df.iloc[i][(filename, col)] for col in STANDARD_COLUMNS}
            bv = bez_nds[i] if i < len(bez_nds) else None
            _fill_data_row(ws, row_idx, block["start"], row_data, bv)

        if len(df) > max_data_rows:
            extra = len(df) - max_data_rows
            ws.insert_rows(data_end + 1, extra)

            for i in range(max_data_rows, len(df)):
                row_idx = 3 + i
                row_data = {col: df.iloc[i][(filename, col)] for col in STANDARD_COLUMNS}
                bv = bez_nds[i] if i < len(bez_nds) else None
                _fill_data_row(ws, row_idx, block["start"], row_data, bv)

            first_meta_row += extra
            total_row += extra
            data_end += extra

            for r in range(data_end - extra + 1, data_end + 1):
                for b in existing_blocks:
                    for col_offset in range(BLOCK_SIZE):
                        _copy_style(
                            ws.cell(row=3, column=b["start"] + col_offset),
                            ws.cell(row=r, column=b["start"] + col_offset),
                        )
                for col in range(1, 4):
                    _copy_style(ws.cell(row=3, column=col),
                                ws.cell(row=r, column=col))

    for b in existing_blocks:
        ws.merge_cells(start_row=total_row, start_column=b["start"],
                       end_row=total_row, end_column=b["start"] + 3)

        col_letter = get_column_letter(b["start"] + 4)
        ws.column_dimensions[col_letter].hidden = True

        ws.cell(row=total_row, column=b["start"] + 5).value = "Сумма"

        total_col_letter = get_column_letter(b["start"] + 5)
        ws.cell(row=total_row + 1, column=b["start"] + 5).value = (
            f"=SUM({total_col_letter}3:{total_col_letter}{data_end})"
        )

    ws.merge_cells(start_row=total_row, start_column=1,
                   end_row=total_row, end_column=3)

    new_blocks = existing_blocks[original_block_count:] if ref_block_start else []
    for b in new_blocks:
        _copy_block_formatting(ws, b["start"], ref_block_start, total_row + 1)

    stale_ranges = list(ws.merged_cells.ranges)
    for mc in stale_ranges:
        if 3 <= mc.min_row <= data_end:
            ws.merged_cells.remove(mc)

    meta_start, meta_end = first_meta_row, total_row - 1
    for mr in range(meta_start, meta_end + 1):
        ws.merge_cells(start_row=mr, start_column=1, end_row=mr, end_column=3)
        for b in existing_blocks:
            ws.merge_cells(start_row=mr, start_column=b["start"],
                           end_row=mr, end_column=b["end"])

    for b in existing_blocks:
        _auto_fit_block_columns(ws, b["start"], data_end)

    for r in range(3, data_end + 1):
        ws.row_dimensions[r].height = None

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
