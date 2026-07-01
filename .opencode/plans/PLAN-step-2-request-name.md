# Шаг 2 — Поле имени заявки в GUI

## Цель

Добавить в GUI текстовое поле для ввода имени заявки. Значение подставляется
в A1: `"Заявка: {request_name}"`.

## Базовые предположения

- Шаг 1 выполнен: `fill_template()` принимает параметр `request_name`
- `config.row.request_name` указывает на строку, куда писать имя заявки

## Файлы

### Изменить
- `gui.py`

## Реализация по подшагам

### ▶ Подшаг 2.1 — Добавить поле в `_build_ui()` (делает opencode)

После создания `tabview`, до кнопок, разместить `CTkEntry`:

```python
top_frame = ctk.CTkFrame(self)
top_frame.pack(fill="x", padx=10, pady=(10, 0))

ctk.CTkLabel(top_frame, text="Имя заявки:").pack(side="left", padx=(0, 5))
self.request_name_var = ctk.StringVar(value="Заявка")
self.request_name_entry = ctk.CTkEntry(
    top_frame, textvariable=self.request_name_var
)
self.request_name_entry.pack(side="left", fill="x", expand=True)
```

**Что делает opencode:** изменяет `gui.py`.

⏸ **Контроль:** opencode останавливается и ждёт «Продолжай».

---

### ▶ Подшаг 2.2 — Пробросить в `_start_processing()` и `_run_processing()` (делает opencode)

- В `_start_processing()`: `request_name = self.request_name_var.get().strip() or "Заявка"`
- В `_run_processing()`: `out = fill_template(..., request_name=request_name)`

**Что делает opencode:** дописывает передачу параметра.

⏸ **Контроль:** opencode останавливается и ждёт «Продолжай».

---

### ▶ Подшаг 2.3 — Синтаксическая проверка (делает opencode)

```bash
.venv\Scripts\python -c "import ast; ast.parse(open('gui.py', encoding='utf-8').read())"
.venv\Scripts\python -c "from gui import App; print('OK')"
```

⏸ **Контроль:** opencode показывает результат, ждёт вашей команды.

---

### ▶ Подшаг 2.4 — Тестирование GUI (делаете ВЫ)

```bash
python gui.py
```

1. Поле «Имя заявки» отображается над вкладками
2. Значение по умолчанию — «Заявка»
3. Запустить обработку → в A1 результат: `"Заявка: {введённое}"`

✅ **Если ок:** «Продолжай».
❌ **Если ошибка:** «Отмена, шаг 2 сломан».

---

### ▶ Подшаг 2.5 — Портативная сборка (делает opencode)

```bash
Remove-Item -Recurse -Force "dist\kongkurent" -ErrorAction SilentlyContinue
cmd /c build_portable.bat
```

⏸ **Контроль:** opencode ждёт вашей команды.

---

### ▶ Подшаг 2.6 — Коммит и мёрж (делает opencode, утверждаете ВЫ)

```bash
git checkout -b feat/request-name
git add gui.py
git commit -m "feat: add request name field in GUI"
git checkout main
git merge feat/request-name
git branch -d feat/request-name
```

⏸ **Контроль:** opencode ждёт вашего «Утверждаю» перед `git push`.

## Точка отката

Если на любом подшаге вы сказали «Отмена»:
```bash
git checkout main && git branch -D feat/request-name
```
