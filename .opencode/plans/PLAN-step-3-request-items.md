# Шаг 3 — Редактор позиций заявки

## Цель

Добавить третью вкладку «Позиции заявки» с динамической таблицей для ручного
ввода названий и количества. При обработке эти позиции записываются в колонки
B и C (fixed_columns[1] и fixed_columns[2]) и используются как эталонный список.
PDF-данные дополняют только блоки поставщиков; A–C не перезаписываются из PDF.

## Базовые предположения

- Шаг 1 выполнен: `fill_template()` умеет работать с `request_items`
- `request_items` — `list[tuple[str, str]]` (название, количество) или None
- Если `request_items` передан — колонки A–C заполняются из него, PDF-данные
  в A–C игнорируются (но блоки поставщиков из PDF всё равно пишутся).
- Если `request_items` не передан или пуст — поведение как сейчас (A–C из PDF)

## Файлы

### Изменить
- `gui.py` — новая вкладка, сбор данных
- `recog.py` — логика приоритета request_items над PDF

## Реализация по подшагам

### ▶ Подшаг 3.1 — Новая вкладка + методы управления строками (делает opencode)

Добавить в `gui.py`:

1. Метод `_build_request_items_tab(parent)`
2. Метод `_add_request_item_row(self, name="", qty="")`
3. Метод `_remove_request_item_row(self, frame)`
4. Метод `_clear_request_items(self)`
5. Вызов `self.tabview.add("Позиции заявки")` в `_build_ui()`

**Что делает opencode:** расширяет `gui.py`.

⏸ **Контроль:** opencode останавливается и ждёт «Продолжай».

---

### ▶ Подшаг 3.2 — Сбор данных в `_start_processing()` (делает opencode)

Добавить сбор `request_items` из вкладки «Позиции заявки».

```python
current_tab = self.tabview.get()
request_items = None
if current_tab == "Позиции заявки" and self.request_item_rows:
    items = [(r["name_var"].get().strip(), r["qty_var"].get().strip())
             for r in self.request_item_rows if r["name_var"].get().strip()]
    if items:
        request_items = items
```

Пробросить `request_items` в `_run_processing()`.

⏸ **Контроль:** opencode останавливается и ждёт «Продолжай».

---

### ▶ Подшаг 3.3 — Логика A–C в recog.py (делает opencode)

В `fill_template()` добавить:

```python
if request_items:
    for i, (name, qty) in enumerate(request_items):
        row_idx = data_start + i
        ws.cell(row=row_idx, column=1, value=i + 1)
        ws.cell(row=row_idx, column=2, value=name)
        ws.cell(row=row_idx, column=3, value=qty)
    # PDF пишет ТОЛЬКО в блоки поставщиков, НЕ перезаписывает A–C
```

При наличии `request_items` — пропускать запись A–C из PDF.

**Что делает opencode:** изменяет `recog.py`.

⏸ **Контроль:** opencode останавливается и ждёт «Продолжай».

---

### ▶ Подшаг 3.4 — Синтаксическая проверка (делает opencode)

```bash
.venv\Scripts\python -c "import ast; ast.parse(open('gui.py').read()); ast.parse(open('recog.py').read())"
.venv\Scripts\python -c "import recog; from gui import App; print('OK')"
```

⏸ **Контроль:** opencode показывает результат, ждёт вашей команды.

---

### ▶ Подшаг 3.5 — Автоматический CLI-тест на example_data (делает opencode)

```bash
.venv\Scripts\python recog.py example_data
if (Test-Path "example_data\\конкурент example_data.xlsx") { Write-Host "OK: файл создан" } else { throw "Файл не создан" }
```

**Что делает opencode:** прогоняет CLI на example_data (без request_items — старый путь, A–C из PDF).

⏸ **Контроль:** opencode показывает результат, ждёт вашей команды.

---

### ▶ Подшаг 3.6 — Тестирование GUI (делаете ВЫ)

```bash
python gui.py
```

1. Вкладка «Позиции заявки» отображается и работает
2. Добавить 2-3 позиции → выбрать `example_data` → запустить → A–C = введённые, блоки = PDF
3. Очистить вкладку → запустить → поведение как раньше (A–C из PDF)

✅ **Если ок:** «Продолжай».
❌ **Если ошибка:** «Отмена, шаг 3 сломан».

---

### ▶ Подшаг 3.7 — Портативная сборка (делает opencode)

```bash
Remove-Item -Recurse -Force "dist\kongkurent" -ErrorAction SilentlyContinue
cmd /c build_portable.bat
```

⏸ **Контроль:** opencode ждёт вашей команды.

---

### ▶ Подшаг 3.8 — Коммит и мёрж (делает opencode, утверждаете ВЫ)

```bash
git checkout -b feat/request-items
git add gui.py recog.py
git commit -m "feat: add request items editor tab, use as source for A-C columns"
git checkout main
git merge feat/request-items
git branch -d feat/request-items
```

⏸ **Контроль:** opencode ждёт вашего «Утверждаю».

## Точка отката

```bash
git checkout main && git branch -D feat/request-items
```
