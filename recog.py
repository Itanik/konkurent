import os
import sys
import argparse
import shutil
import pandas as pd
import camelot
from glob import glob

from openpyxl import load_workbook, Workbook
from openpyxl.utils import get_column_letter
from openpyxl.styles import Alignment

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


def write_merged_excel(output_path, file_data_list):
    cols_per_file = len(STANDARD_COLUMNS)
    wb = Workbook()
    ws = wb.active
    ws.title = "merged"

    max_data_rows = max((df.shape[0] for df, _, _ in file_data_list), default=0)

    col = 1
    for df, orig_headers, _ in file_data_list:
        filename = df.columns.get_level_values(0)[0]

        cell = ws.cell(row=1, column=col, value=filename)
        cell.alignment = Alignment(horizontal="center", wrap_text=True)
        if max_data_rows > 0:
            ws.merge_cells(
                start_row=1, start_column=col,
                end_row=1, end_column=col + cols_per_file - 1
            )

        for i, std_name in enumerate(STANDARD_COLUMNS):
            header_text = orig_headers.get(std_name, std_name)
            cell = ws.cell(row=2, column=col + i, value=header_text)
            cell.alignment = Alignment(horizontal="center", wrap_text=True)

        for row_idx in range(df.shape[0]):
            for i, std_name in enumerate(STANDARD_COLUMNS):
                val = df.iloc[row_idx][(filename, std_name)]
                if pd.isna(val):
                    continue
                ws.cell(row=row_idx + 3, column=col + i, value=val)

        col += cols_per_file

    ws.column_dimensions["A"].width = 14
    wb.save(output_path)


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


def _find_or_create_block(ws, existing_blocks, first_meta_row, total_row):
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

    if first_meta_row and total_row:
        for mr in range(first_meta_row, total_row):
            ws.merge_cells(start_row=mr, start_column=start, end_row=mr, end_column=end)

    block = {"start": start, "end": end, "name": "PLACEHOLDER"}
    existing_blocks.append(block)
    existing_blocks.sort(key=lambda b: b["start"])
    return block


def fill_template(pdf_data_list, target_dir, script_dir):
    template_src = os.path.join(script_dir, "конкурент.xlsx")
    template_dst = os.path.join(target_dir, "конкурент.xlsx")

    if os.path.exists(template_dst):
        os.remove(template_dst)
    shutil.copy2(template_src, template_dst)

    wb = load_workbook(template_dst)
    ws = wb.active

    first_meta_row = _find_first_meta_row(ws)
    data_end = first_meta_row - 1
    total_row = _find_total_row(ws)

    existing_blocks = _parse_supplier_blocks(ws)

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

        block = _find_or_create_block(ws, existing_blocks, first_meta_row, total_row)
        block["name"] = filename

        ws.cell(row=1, column=block["start"]).value = filename

        max_data_rows = data_end - 3 + 1 if data_end >= 3 else 1
        for i in range(min(len(df), max_data_rows)):
            row_idx = 3 + i
            ws.cell(row=row_idx, column=block["start"]).value = df.iloc[i][(filename, "Товар")]
            ws.cell(row=row_idx, column=block["start"] + 1).value = df.iloc[i][(filename, "Кол-во")]
            ws.cell(row=row_idx, column=block["start"] + 2).value = df.iloc[i][(filename, "Ед. изм")]
            ws.cell(row=row_idx, column=block["start"] + 3).value = df.iloc[i][(filename, "Цена за ед.")]
            bv = bez_nds[i] if i < len(bez_nds) and bez_nds[i] else None
            ws.cell(row=row_idx, column=block["start"] + 4).value = bv
            ws.cell(row=row_idx, column=block["start"] + 5).value = df.iloc[i][(filename, "Сумма")]

        if len(df) > max_data_rows:
            extra = len(df) - max_data_rows
            ws.insert_rows(data_end + 1, extra)

            for i in range(max_data_rows, len(df)):
                row_idx = 3 + i
                ws.cell(row=row_idx, column=block["start"]).value = df.iloc[i][(filename, "Товар")]
                ws.cell(row=row_idx, column=block["start"] + 1).value = df.iloc[i][(filename, "Кол-во")]
                ws.cell(row=row_idx, column=block["start"] + 2).value = df.iloc[i][(filename, "Ед. изм")]
                ws.cell(row=row_idx, column=block["start"] + 3).value = df.iloc[i][(filename, "Цена за ед.")]
                bv = bez_nds[i] if i < len(bez_nds) and bez_nds[i] else None
                ws.cell(row=row_idx, column=block["start"] + 4).value = bv
                ws.cell(row=row_idx, column=block["start"] + 5).value = df.iloc[i][(filename, "Сумма")]

            first_meta_row += extra
            total_row += extra
            data_end += extra

        if total_row:
            ws.cell(row=total_row, column=block["start"]).value = "Сумма"
            total_col_letter = get_column_letter(block["start"] + 5)
            ws.cell(row=total_row + 1, column=block["start"] + 5).value = (
                f"=SUM({total_col_letter}3:{total_col_letter}{data_end})"
            )

    folder_basename = os.path.basename(target_dir)
    parts = folder_basename.split()
    if len(parts) >= 2:
        first_two = " ".join(parts[:2])
    elif parts:
        first_two = parts[0]
    else:
        first_two = "unknown"
    output_name = f"конкурент {first_two}.xlsx"
    output_path = os.path.join(target_dir, output_name)

    wb.save(output_path)
    print(f"\nГотово! Конкурентная таблица сохранена как '{output_name}'")

    if os.path.exists(template_dst):
        os.remove(template_dst)


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


def get_output_path(folder_path, user_output):
    if user_output:
        return user_output
    return os.path.join(folder_path, "merged_tables.xlsx")


def main():
    parser = argparse.ArgumentParser(
        description="Извлечение таблиц из всех PDF-файлов в папке и объединение в один Excel."
    )
    parser.add_argument("folder_path", help="Путь к папке с PDF-файлами")
    parser.add_argument(
        "-o",
        "--output",
        help="Путь к выходному Excel-файлу (по умолчанию: режим конкурентной таблицы)",
    )
    args = parser.parse_args()

    if not os.path.isdir(args.folder_path):
        print(f"Ошибка: Папка '{args.folder_path}' не найдена.")
        return

    pdf_files = sorted(glob(os.path.join(args.folder_path, "*.pdf")))
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

    if args.output:
        output_path = get_output_path(args.folder_path, args.output)
        os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)
        write_merged_excel(output_path, file_data_list)
        total_rows = max((df.shape[0] for df, _, _ in file_data_list), default=0)
        print(f"\nГотово! Объединённый файл сохранён как '{output_path}'")
        print(f"Всего файлов: {len(file_data_list)}")
        print(f"Всего строк данных: {total_rows}")
    else:
        script_dir = os.path.dirname(os.path.abspath(__file__))
        fill_template(file_data_list, args.folder_path, script_dir)


if __name__ == "__main__":
    main()
