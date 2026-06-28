import os
import argparse
import pandas as pd
import camelot
from glob import glob

from openpyxl import Workbook
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


COLS_PER_FILE = len(STANDARD_COLUMNS)


def write_merged_excel(output_path, file_data_list):
    wb = Workbook()
    ws = wb.active
    ws.title = "merged"

    max_data_rows = max((df.shape[0] for df, _ in file_data_list), default=0)

    col = 1
    for file_idx, (df, orig_headers) in enumerate(file_data_list):
        filename = df.columns.get_level_values(0)[0]

        cell = ws.cell(row=1, column=col, value=filename)
        cell.alignment = Alignment(horizontal="center", wrap_text=True)
        if max_data_rows > 0:
            ws.merge_cells(
                start_row=1, start_column=col,
                end_row=1, end_column=col + COLS_PER_FILE - 1
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

        col += COLS_PER_FILE

    ws.column_dimensions["A"].width = 14
    wb.save(output_path)


def process_pdf_file(pdf_path, file_data_list):
    print(f"\nОбработка: {os.path.basename(pdf_path)}")
    tables = extract_with_camelot(pdf_path)

    filename = os.path.basename(pdf_path)
    if tables:
        df, orig = process_pdf_tables(tables, filename)
        n_rows = len(df)
        if n_rows > 0:
            print(f"    Извлечено строк: {n_rows}")
        else:
            print(f"    Таблица не найдена (пустой результат)")
        file_data_list.append((df, orig))
    else:
        print(f"    Не удалось извлечь таблицы")
        empty = pd.DataFrame(columns=pd.MultiIndex.from_product([[filename], STANDARD_COLUMNS]))
        orig = {col: col for col in STANDARD_COLUMNS}
        file_data_list.append((empty, orig))


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
        help="Путь к выходному Excel-файлу (по умолчанию: [папка]/merged_tables.xlsx)",
    )
    args = parser.parse_args()

    if not os.path.isdir(args.folder_path):
        print(f"Ошибка: Папка '{args.folder_path}' не найдена.")
        return

    pdf_files = glob(os.path.join(args.folder_path, "*.pdf"))
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

    output_path = get_output_path(args.folder_path, args.output)
    os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)

    write_merged_excel(output_path, file_data_list)

    total_rows = max((df.shape[0] for df, _ in file_data_list), default=0)
    print(f"\nГотово! Объединённый файл сохранён как '{output_path}'")
    print(f"Всего файлов: {len(file_data_list)}")
    print(f"Всего строк данных: {total_rows}")


if __name__ == "__main__":
    main()
