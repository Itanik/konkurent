# Шаг 1 — JSON-конфиг и динамическое построение таблицы

## Цель

Заменить `template.xlsx` на `config.json`. Вместо копирования шаблона и вставки
данных — создавать книгу с нуля по JSON-описанию, затем заполнять данными.

## Файлы

### Создать
- `config.json` — структура таблицы (см. PLAN.md)

### Изменить
- `recog.py` — перенести логику `fill_template()` на новую архитектуру
- `build_portable.bat` — добавить `config.json` в `--add-data`

### Удалить
- `template.xlsx`

## Реализация по подшагам

### ▶ Подшаг 1.1 — Создать config.json (делает opencode)

Скопировать схему из PLAN.md, сохранить рядом с `recog.py`. Все значения
соответствуют текущему `template.xlsx`.

**Что делает opencode:** пишет `config.json` в корень проекта.

⏸ **Контроль:** после этого opencode останавливается и ждёт вашей команды
«Продолжай» (или «Отмена») для перехода к подшагу 1.2.

---

### ▶ Подшаг 1.2 — Рефакторинг recog.py (делает opencode)

#### 1.2.1 Функция `load_config(path)`
- Загружает JSON, возвращает словарь.
- Валидирует: `block_size == len(block_columns)`, обязательные ключи.
- Падает с понятным `ValueError`, если конфиг битый.

#### 1.2.2 Функция `build_workbook(config, n_suppliers)`
Создаёт `openpyxl.Workbook` с нуля по конфигу:
- Заголовки колонок (row 2)
- Пустые строки данных
- Мета-строки (label A–C + объединённые ячейки для каждого блока)
- Строка «Сумма» (A–C merged, SUM-формулы)

#### 1.2.3 Переписать `fill_template()`
- Загружает `config.json` из `script_dir`
- Строит книгу через `build_workbook()`
- Заполняет данные (та же логика, но с пересчётом индексов колонок из конфига)
- Сохраняет

#### 1.2.4 Пересчёт индексов колонок
- `n_fixed = len(config["fixed_columns"])`
- `block_size = config["_block_size"]`
- `block_start = n_fixed + block_n * block_size`
- Скрытые колонки, SUM-колонки — по атрибутам из конфига

**Что делает opencode:** перезаписывает `recog.py`.

⏸ **Контроль:** opencode останавливается и ждёт команды.

---

### ▶ Подшаг 1.3 — Правка build_portable.bat (делает opencode)

Заменить `--add-data "template.xlsx;."` на `--add-data "config.json;."`.

**Что делает opencode:** изменяет `build_portable.bat`.

⏸ **Контроль:** opencode останавливается и ждёт команды.

---

### ▶ Подшаг 1.4 — Синтаксическая проверка (делает opencode)

```bash
.venv\Scripts\python -c "import ast; ast.parse(open('recog.py', encoding='utf-8').read())"
.venv\Scripts\python -c "import recog; print('OK')"
```

**Что делает opencode:** прогоняет базовые тесты импорта.

⏸ **Контроль:** opencode показывает результат, ждёт вашей команды.

---

### ▶ Подшаг 1.5 — Тестирование CLI (делаете ВЫ)

```bash
# Временно убрать template.xlsx
Move-Item template.xlsx template.xlsx.bak

# Запустить CLI на папке с PDF
python recog.py <папка_с_pdf>
```

**Что делаете вы:** запускаете CLI, открываете .xlsx, проверяете структуру.

✅ **Если ок:** командуете «Продолжай».
❌ **Если ошибка:** командуете «Отмена, шаг 1 сломан» — opencode откатывает.

---

### ▶ Подшаг 1.6 — Тестирование GUI (делаете ВЫ)

```bash
python gui.py
```

Открыть оба таба, запустить обработку, проверить результат.

✅ **Если ок:** командуете «Продолжай».
❌ **Если ошибка:** «Отмена».

---

### ▶ Подшаг 1.7 — Портативная сборка (делает opencode)

```bash
Remove-Item -Recurse -Force "dist\kongkurent" -ErrorAction SilentlyContinue
cmd /c build_portable.bat
```

**Что делает opencode:** собирает портативную версию.

⏸ **Контроль:** opencode показывает результат, ждёт вашей команды.

---

### ▶ Подшаг 1.8 — Коммит и мёрж (делает opencode, но утверждаете ВЫ)

```bash
git checkout -b feat/json-config
git add config.json recog.py build_portable.bat
git rm template.xlsx
git commit -m "feat: replace template.xlsx with config.json, build workbook dynamically"
git checkout main
git merge feat/json-config
git branch -d feat/json-config
```

**Что делает opencode:** коммитит, мёржит, удаляет ветку.

⏸ **Контроль:** opencode ждёт вашего «Утверждаю» перед `git push`.

## Точка отката

Если на любом подшаге вы сказали «Отмена»:
```bash
git checkout main
git branch -D feat/json-config
git checkout main -- template.xlsx   # если удалён
```
