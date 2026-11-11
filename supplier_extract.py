"""Извлечение реквизитов поставщика из текста счёта.

Находит название организации по организационно-правовой форме (ООО, ОАО, …)
и проверяет ИНН/КПП/ОГРН. Используется sidecar'ом при распознавании: название
позиций даёт camelot/pandas, а «шапка» счёта — этот модуль.
"""

import json
import os
import re

DEFAULT_LEGAL_FORMS = [
    "Общество с ограниченной ответственностью",
    "Публичное акционерное общество",
    "Непубличное акционерное общество",
    "Закрытое акционерное общество",
    "Открытое акционерное общество",
    "Индивидуальный предприниматель",
    "Акционерное общество",
    "Автономная некоммерческая организация",
    "Федеральное государственное унитарное предприятие",
    "Федеральное государственное бюджетное учреждение",
    "ООО",
    "ПАО",
    "НАО",
    "ЗАО",
    "ОАО",
    "АО",
    "АНО",
    "ФГУП",
    "ФГБУ",
    "ГУП",
    "МУП",
    "ИП",
    "ТСЖ",
    "КФХ",
]

# Развёрнутые формы → краткие для отображения в названии блока.
_SHORT_FORMS = {
    "общество с ограниченной ответственностью": "ООО",
    "публичное акционерное общество": "ПАО",
    "непубличное акционерное общество": "НАО",
    "закрытое акционерное общество": "ЗАО",
    "открытое акционерное общество": "ОАО",
    "индивидуальный предприниматель": "ИП",
    "акционерное общество": "АО",
    "автономная некоммерческая организация": "АНО",
    "федеральное государственное унитарное предприятие": "ФГУП",
    "федеральное государственное бюджетное учреждение": "ФГБУ",
    "государственное унитарное предприятие": "ГУП",
    "муниципальное унитарное предприятие": "МУП",
    "товарищество собственников жилья": "ТСЖ",
    "крестьянское (фермерское) хозяйство": "КФХ",
}

# Название в кавычках после формы: ООО «Ромашка», ООО "Ромашка", ООО „Ромашка“
_QUOTED = re.compile(r"[«\"„“]([^»\"””]{1,150})[»\"””]")

# Хвост после названия, который отрезаем: …ООО «Ромашка» ИНН 7701…
_TRAILING_JUNK = re.compile(
    r"\b(ИНН|КПП|ОГРН|ОГРНИП|юр\.?\s*адрес|юридический\s+адрес|адрес|р/с|бик)\b",
    re.IGNORECASE,
)


def load_legal_forms(path):
    """Список юрформ из JSON-файла (список строк); при ошибке — дефолт."""
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        if isinstance(data, list):
            forms = [str(s).strip() for s in data if str(s).strip()]
            if forms:
                return forms
    except (OSError, ValueError):
        pass
    return DEFAULT_LEGAL_FORMS


def _clean(s):
    return re.sub(r"\s+", " ", s).strip()


def extract_text(path, max_pages=5):
    """Весь доступный текст файла (PDF — первые [max_pages] страниц)."""
    ext = os.path.splitext(path)[1].lower()

    if ext == ".pdf":
        try:
            import playa
        except ImportError:
            return ""
        chunks = []
        try:
            with playa.open(path) as doc:
                for page in doc.pages[:max_pages]:
                    fn = getattr(page, "extract_text_untagged", None)
                    chunks.append(fn() if fn else page.extract_text())
        except Exception:
            return ""
        return "\n".join(chunks)

    if ext == ".docx":
        try:
            from docx import Document
        except ImportError:
            return ""
        doc = Document(path)
        parts = [p.text for p in doc.paragraphs]
        for t in doc.tables:
            for row in t.rows:
                for cell in row.cells:
                    parts.append(cell.text)
        return "\n".join(parts)

    if ext in (".xlsx", ".xls", ".xlsm"):
        import pandas as pd

        sheets = pd.read_excel(path, sheet_name=None, header=None, dtype=object)
        parts = []
        for df in sheets.values():
            for row in df.itertuples(index=False):
                parts.extend(str(v) for v in row if v is not None)
        return "\n".join(parts)

    return ""


def find_supplier_name(text, legal_forms=None):
    """Название организации по первому вхождению юрформы.

    Возвращает «КРАТКАЯФОРМА Название» (в кавычках, если найдено), либо None —
    тогда вызывающий код оставляет имя файла как название.
    """
    if not text:
        return None
    forms = legal_forms or DEFAULT_LEGAL_FORMS

    best_pos, best_form = None, None
    for form in forms:
        f = form.strip()
        if not f:
            continue
        m = re.search(rf"\b{re.escape(f.lower())}\b", text.lower())
        if m and (best_pos is None or m.start() < best_pos):
            best_pos, best_form = m.start(), f

    if best_form is None:
        return None

    line_end = text.find("\n", best_pos)
    line = text[best_pos: line_end if line_end != -1 else len(text)]
    short = _SHORT_FORMS.get(best_form.lower(), best_form.upper())

    quoted = _QUOTED.search(line)
    if quoted:
        name = _clean(quoted.group(1))
        if name:
            return f"{short} «{name}»"

    rest = line[len(best_form):].lstrip(" \t.,:;-—")
    rest = _TRAILING_JUNK.split(rest, maxsplit=1)[0]
    rest = _clean(rest).strip(".,;:—-")
    if 2 <= len(rest) <= 100:
        return f"{short} {rest}"
    return None


def _checksum(digits, weights):
    return sum(int(c) * w for c, w in zip(digits, weights)) % 11 % 10


def _inn_valid(s):
    if len(s) == 10:
        return _checksum(s, (2, 4, 10, 3, 5, 9, 4, 6, 8)) == int(s[9])
    if len(s) == 12:
        ok11 = _checksum(s, (7, 2, 4, 10, 3, 5, 9, 4, 6, 8)) == int(s[10])
        ok12 = _checksum(s, (3, 7, 2, 4, 10, 3, 5, 9, 4, 6, 8)) == int(s[11])
        return ok11 and ok12
    return False


def _ogrn_valid(s):
    return len(s) == 13 and int(s[:12]) % 11 % 10 == int(s[12])


def find_inn(text):
    """Первый подходящий по контрольной сумме ИНН (10 юрлицо / 12 ИП)."""
    if not text:
        return None
    for m in re.finditer(r"(?<!\d)(\d{10}|\d{12})(?!\d)", text):
        if _inn_valid(m.group(1)):
            return m.group(1)
    return None


def find_kpp(text):
    """КПП: 9 цифр в строке с меткой «КПП»."""
    if not text:
        return None
    for line in text.splitlines():
        if re.search(r"КПП", line, re.IGNORECASE):
            m = re.search(r"(?<!\d)(\d{9})(?!\d)", line)
            if m:
                return m.group(1)
    return None


def find_ogrn(text):
    """ОГРН: 13 цифр с контрольной цифрой (предпочтительно с меткой)."""
    if not text:
        return None
    labeled = None
    plain = None
    for line in text.splitlines():
        for m in re.finditer(r"(?<!\d)(\d{13})(?!\d)", line):
            if not _ogrn_valid(m.group(1)):
                continue
            if re.search(r"ОГРН", line, re.IGNORECASE) and labeled is None:
                labeled = m.group(1)
            if plain is None:
                plain = m.group(1)
    return labeled or plain


def extract_supplier(path, legal_forms=None):
    """Реквизиты поставщика из файла: {name, inn, kpp, ogrn} (None если нет)."""
    text = extract_text(path)
    return {
        "name": find_supplier_name(text, legal_forms),
        "inn": find_inn(text),
        "kpp": find_kpp(text),
        "ogrn": find_ogrn(text),
    }
