# Шаг 4 — Скрытая строка с именем файла

## Цель

Если пользователь указал хотя бы одно кастомное имя поставщика (через `block_names`),
добавить скрытую строку между row 1 и row 2 с оригинальными именами файлов
в объединённых ячейках каждого блока. Для блоков без кастомного имени — пусто.

## Базовые предположения

- Шаг 1 выполнен: `config.json` определяет структуру таблицы
- `fill_template()` принимает `block_names: dict[str, str]` (basename → custom name)
- Строка вставляется над row 2 (между именем поставщика и заголовками колонок)
- Строка скрывается через `ws.row_dimensions[row].hidden = True`

## Визуально

```
Row 1:  [Заявка: X]     [Поставщик А]         [Поставщик Б]
  — — — скрытая строка — — — — — — — — — — — — — — — — — — — —
  [merged A-C: ""]  [merged D-I: "файл1.pdf"] [merged J-O: "файл2.pdf"]
  — — — — — — — — — — — — — — — — — — — — — — — — — — — — — —
Row 2:  [№ поз|Название|кол-во] [предложено|кол-во|...] [...]
```

## Файлы

### Изменить
- `recog.py`

## Реализация по подшагам

### ▶ Подшаг 4.1 — Функция `_maybe_add_hidden_filename_row()` (делает opencode)

Добавить в `recog.py`:

```python
def _maybe_add_hidden_filename_row(ws, config, block_names):
    if not block_names:
        return False
    ws.insert_rows(2)
    n_fixed = config["_fixed_len"]
    block_size = config["_block_size"]
    for block_idx, (filename, custom_name) in enumerate(block_names.items()):
        sc = n_fixed + block_idx * block_size + 1
        ec = sc + block_size - 1
        if custom_name:
            cell_value = filename
        else:
            cell_value = ""
        if block_size > 1:
            ws.merge_cells(start_row=2, start_column=sc, end_row=2, end_column=ec)
        ws.cell(row=2, column=sc).value = cell_value
    ws.row_dimensions[2].hidden = True
    return True
```

**Что делает opencode:** дописывает функцию в `recog.py`.

⏸ **Контроль:** opencode ждёт «Продолжай».

---

### ▶ Подшаг 4.2 — Интеграция в `fill_template()` (делает opencode)

В `fill_template()`, после `build_workbook()`, до записи данных:

```python
row_offset = 0
if _maybe_add_hidden_filename_row(ws, config, block_names):
    row_offset = 1

# Далее использовать (config["row"]["data_start"] + row_offset) и т.д.
```

Поправить все обращения к строкам: `header_row`, `data_start`, `data_end`,
`meta_start`, `total_row` — прибавлять `row_offset`.

**Что делает opencode:** изменяет `fill_template()`.

⏸ **Контроль:** opencode ждёт «Продолжай».

---

### ▶ Подшаг 4.3 — Синтаксическая проверка (делает opencode)

```bash
.venv\Scripts\python -c "import ast; ast.parse(open('recog.py', encoding='utf-8').read())"
.venv\Scripts\python -c "import recog; print('OK')"
```

⏸ **Контроль:** opencode показывает результат, ждёт вашей команды.

---

### ▶ Подшаг 4.4 — Тестирование GUI (делаете ВЫ)

```bash
python gui.py
```

**Тест 1 — без кастомных имён:**
- Запустить обработку без ввода имён поставщиков
- Открыть .xlsx → row 2 — это заголовки колонок, скрытой строки нет

**Тест 2 — с кастомными именами:**
- Ввести имя хотя бы одному поставщику
- Запустить обработку
- Открыть .xlsx → unhide row 2 → в ней имя файла в соответствующем блоке
- Скрыть обратно, проверить остальные строки (данные, мета, тотал)

✅ **Если ок:** «Продолжай».
❌ **Если ошибка:** «Отмена, шаг 4 сломан».

---

### ▶ Подшаг 4.5 — Портативная сборка (делает opencode)

```bash
Remove-Item -Recurse -Force "dist\kongkurent" -ErrorAction SilentlyContinue
cmd /c build_portable.bat
```

⏸ **Контроль:** opencode ждёт вашей команды.

---

### ▶ Подшаг 4.6 — Коммит и мёрж (делает opencode, утверждаете ВЫ)

```bash
git checkout -b feat/hidden-filename-row
git add recog.py
git commit -m "feat: add hidden row with original filename when block_names specified"
git checkout main
git merge feat/hidden-filename-row
git branch -d feat/hidden-filename-row
```

⏸ **Контроль:** opencode ждёт вашего «Утверждаю».

## Точка отката

```bash
git checkout main && git branch -D feat/hidden-filename-row
```
