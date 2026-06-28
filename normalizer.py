import re
import pandas as pd

COLUMN_PATTERNS = {
    "№": ["№", "номер", "п/п"],
    "Товар": ["товар", "наименование", "название"],
    "Кол-во": ["кол-во", "количество", "кол"],
    "Ед. изм": ["ед", "единиц"],
    "Сумма": ["всего", "итого", "стоимость с", "сумма"],
}

STANDARD_COLUMNS = ["№", "Товар", "Кол-во", "Ед. изм", "Сумма"]

SUMMARY_KEYWORDS = ["итого", "всего", "ндс", "к оплате", "в том числе"]


def _clean_cell(val):
    s = str(val).strip()
    s = s.replace("\n", " ")
    s = re.sub(r"\s+", " ", s)
    return s


def _normalize_number(s):
    if not s or s in ("", "nan", "None"):
        return ""
    s = s.replace("\xa0", " ").replace(" ", "")
    s = s.replace(",", ".")
    try:
        return str(float(s))
    except ValueError:
        return s


def _row_is_summary(row_vals):
    text = " ".join(str(v).lower() for v in row_vals if str(v).strip())
    for kw in SUMMARY_KEYWORDS:
        if kw in text:
            return True
    return False


def _row_is_empty(row_vals):
    return all(str(v).strip() in ("", "nan", "None") for v in row_vals)


def _cell_matches_any(cell_lower):
    for patterns in COLUMN_PATTERNS.values():
        for pat in patterns:
            if pat in cell_lower:
                return True
    return False


def score_header_row(row):
    score = 0
    for cell in row:
        cell_lower = str(cell).lower().strip()
        if _cell_matches_any(cell_lower):
            score += 1
    return score


def find_header_row(df):
    best_row = 0
    best_score = 0
    for row_idx in range(len(df)):
        row = df.iloc[row_idx]
        score = score_header_row(row)
        if score > best_score:
            best_score = score
            best_row = row_idx
    return best_row, best_score


def map_columns(header_row):
    mapping = {}
    for col_idx, cell in enumerate(header_row):
        cell_lower = str(cell).lower().strip()
        best_match = None
        for std_name in STANDARD_COLUMNS:
            for pat in COLUMN_PATTERNS[std_name]:
                if pat in cell_lower:
                    best_match = std_name
                    break
            if best_match:
                break
        if best_match:
            if best_match not in mapping:
                mapping[best_match] = col_idx
            else:
                existing_idx = mapping[best_match]
                existing_cell = str(header_row[existing_idx]).lower().strip()
                new_score = sum(1 for p in COLUMN_PATTERNS[best_match] if p in cell_lower)
                old_score = sum(1 for p in COLUMN_PATTERNS[best_match] if p in existing_cell)
                if new_score > old_score or (new_score == old_score and col_idx > existing_idx):
                    mapping[best_match] = col_idx
    return mapping


def normalize_table(df, header_row_idx, col_mapping):
    data_rows = []
    for row_idx in range(header_row_idx + 1, len(df)):
        row = df.iloc[row_idx]
        row_vals = [_clean_cell(row[col_mapping.get(col)]) if col in col_mapping else ""
                    for col in STANDARD_COLUMNS]
        if _row_is_empty(row_vals) or _row_is_summary(row_vals):
            continue
        if not row_vals[1].strip():
            continue
        row_vals[2] = _normalize_number(row_vals[2])
        row_vals[4] = _normalize_number(row_vals[4])
        data_rows.append(row_vals)

    if not data_rows:
        return pd.DataFrame(columns=STANDARD_COLUMNS)

    result = pd.DataFrame(data_rows, columns=STANDARD_COLUMNS)

    has_any_number = result["№"].apply(lambda x: bool(re.match(r"^\d+$", str(x).strip()))).any()
    if not has_any_number:
        result["№"] = range(1, len(result) + 1)

    result = result.reset_index(drop=True)
    return result


def find_best_table(tables):
    best_idx = -1
    best_score = 0
    for i, table in enumerate(tables):
        _, score = find_header_row(table.df)
        if score > best_score:
            best_score = score
            best_idx = i
    return best_idx, best_score


def get_original_headers(header_row, col_mapping):
    orig = {}
    for std_name, col_idx in col_mapping.items():
        raw = str(header_row[col_idx]).strip()
        raw = raw.replace("\n", " ").replace("\xa0", " ")
        raw = re.sub(r"\s+", " ", raw)
        orig[std_name] = raw if raw else std_name
    for col in STANDARD_COLUMNS:
        if col not in orig:
            orig[col] = col
    return orig


def process_pdf_tables(tables, filename):
    best_idx, score = find_best_table(tables)
    if best_idx == -1 or score < 3:
        empty = pd.DataFrame(columns=STANDARD_COLUMNS)
        empty.columns = pd.MultiIndex.from_product([[filename], STANDARD_COLUMNS])
        orig = {col: col for col in STANDARD_COLUMNS}
        return empty, orig

    df = tables[best_idx].df
    header_row_idx, _ = find_header_row(df)
    header_row = df.iloc[header_row_idx]
    col_mapping = map_columns(header_row)

    normalized = normalize_table(df, header_row_idx, col_mapping)
    orig = get_original_headers(header_row, col_mapping)

    normalized.columns = pd.MultiIndex.from_product([[filename], STANDARD_COLUMNS])
    return normalized, orig
