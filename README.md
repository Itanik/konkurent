# Конкурентная таблица

Инструмент для отдела закупок: собирает коммерческие предложения поставщиков и
формирует единую конкурентную таблицу для сравнения. Основное приложение —
интерактивный редактор **KonkurentApp** (Flutter Desktop), работающий поверх
общего с Python движком распознавания.

**Русский** | [English](README.en.md)

---

## Два приложения

Проект содержит два фронтенда на одном движке:

| | **KonkurentApp** (рекомендуется) | Python-GUI (устаревший) |
|---|---|---|
| Интерфейс | Flutter Desktop, Material 3 | Tkinter + ttk |
| Платформы | Windows, Linux | Windows, Linux |
| Назначение | Интерактивный редактор таблицы | Генератор xlsx одним прогоном |
| Редактирование ячеек | да | нет |
| Перестановка строк/блоков | да (drag&drop) | нет |
| Сортировка по сумме | да | нет |
| Статус | развивается | поддержка без развития |

Движок распознавания (`recog.py`, `normalizer.py`, `config.json`) общий для обоих.

---

## Возможности KonkurentApp

- Таблица как в Excel: фиксированные колонки заявки слева, блоки поставщиков
  прокручиваются вправо.
- Редактирование любой ячейки прямо в таблице.
- Перетаскивание отдельных предложений внутри блока (строки у поставщиков
  независимы) и целых блоков поставщиков влево/вправо.
- Сортировка поставщиков по итоговой сумме — слева самый выгодный.
- Заполнение вручную и автоматически: перетащите счёт (pdf / xlsx / xls / docx) —
  позиции распознаются и появляются новым блоком.
- Сохранение результата в xlsx и открытие ранее сохранённого файла.
- Автосохранение сессии между запусками.
- Вычисляемые значения (цена за единицу, итоги) не хранятся константами, а
  считаются на лету и экспортируются формулами Excel.

## Скриншоты

_Место для скриншотов приложения._

---

## Требования

- **Flutter SDK 3.32+** — [flutter.dev](https://docs.flutter.dev/get-started/install)
- **Python 3.13+**
- **Ghostscript** (`gs` на Linux, `gswin64c` на Windows) — [ghostscript.com](https://ghostscript.com).
  Нужен для распознавания PDF (lattice-режим camelot).
- Python-зависимости движка (`requirements.txt`).

Linux-сборка Flutter дополнительно требует `clang`, `cmake`, `ninja-build`,
`pkg-config`, `libgtk-3-dev`, `liblzma-dev`.

---

## Установка и запуск (из исходников)

```bash
git clone https://github.com/Itanik/konkurent.git
cd konkurent

# Python-движок и мост sidecar
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt      # Windows: .venv\Scripts\pip install -r requirements.txt

# Flutter-приложение
cd konkurent_app
flutter pub get
flutter run -d linux                            # или: flutter run -d windows
```

> **Важно:** запускайте приложение из корня репозитория (или соберите sidecar —
> см. ниже). `PythonBridge` ищет `sidecar.py` вверх по дереву и использует
> `../.venv/bin/python3`; из другой директории распознавание и экспорт не найдут
> движок.

### Сборка релиза

```bash
cd konkurent_app
flutter build linux --release      # → build/linux/x64/release/bundle/
flutter build windows --release    # → build/windows/x64/runner/Release/
```

Для автономной поставки соберите sidecar и положите его рядом с исполняемым файлом:

```bash
# из корня репозитория
.venv/bin/pip install pyinstaller
.venv/bin/pyinstaller --onefile sidecar.py --add-data "config.json:."
# Linux: dist/sidecar → рядом с bundle/konkurent_app
# Windows: dist\sidecar.exe → рядом с Release\konkurent_app.exe
```

После этого приложение находит sidecar рядом с собой и может запускаться из любой
директории.

---

## Как пользоваться

1. **Заполнить из счёта** — перетащите файл (pdf/xlsx/docx) в окно. При успешном
   распознавании справа появляется новый блок поставщика.
2. **Вручную** — добавьте поставщика кнопкой или заполните строки заявки слева.
3. **Редактирование** — клик по ячейке превращает её в поле ввода; Enter или клик
   вне ячейки сохраняет значение.
4. **Перестановка** — тяните за хендл (⠿) в заголовке блока, чтобы поменять
   поставщиков местами, или за хендл строки, чтобы изменить порядок предложений
   внутри блока.
5. **Сортировка** — кнопка «Сортировать по сумме» ставит слева самого выгодного
   поставщика.
6. **Сохранение** — «Сохранить xlsx» экспортирует таблицу, «Открыть…» загружает
   ранее сохранённый файл.

---

## Мост `sidecar.py`

Flutter-приложение не вызывает Python напрямую — оно запускает `sidecar.py` как
дочерний процесс и обменивается JSON (одна строка результата на stdout, логи — в
stderr).

```bash
# Распознать файл
python sidecar.py --action=recognize --file=/abs/path/invoice.pdf

# Экспортировать состояние (AppState JSON на stdin)
python sidecar.py --action=export --output=/abs/path/out.xlsx < state.json

# Открыть «свой» xlsx
python sidecar.py --action=import --file=/abs/path/saved.xlsx
```

«Своим» считается xlsx с листом `Заявка`, где ячейка A1 начинается с `Заявка:`;
иначе `import` возвращает `{"status": "foreign"}` и файл распознаётся как
прайс-лист.

---

## Тесты

```bash
cd konkurent_app
flutter analyze                            # статический анализ
flutter test                               # unit-тесты (sidecar-тесты требуют ../.venv)
flutter test integration_test -d linux     # UI-тесты (открывают окно)
```

---

## Устаревшее Python-приложение

Старый GUI сохранён для совместимости и не развивается.

```bash
.venv/bin/python3 gui.py                     # графический интерфейс
.venv/bin/python3 recog.py /путь/к/папке     # CLI: обработать папку с PDF
```

Портативные сборки (требуют `.venv` и Ghostscript на целевой машине):

```bash
./build_portable.sh          # Linux → dist/конкурент/конкурент
cmd /c build_portable.bat    # Windows → dist\kongkurent\kongkurent.exe
```

---

## Архитектура

| Модуль | Назначение |
|---|---|
| `recog.py` | Ядро: извлечение таблиц, заполнение книги Excel |
| `normalizer.py` | Нормализация колонок (товар, кол-во, сумма, без НДС) |
| `config.json` | Единый источник структуры выходной таблицы |
| `sidecar.py` | Мост Flutter ↔ Python (recognize / export / import) |
| `konkurent_app/` | Flutter-приложение (Riverpod + Material 3) |
| `gui.py` | Устаревший Tkinter-интерфейс |

Поток данных:

```
счёт (pdf/xlsx/docx) → camelot / pandas → нормализация колонок
→ pandas DataFrame → openpyxl → конкурент <имя заявки>.xlsx
```

- Полный контракт модели, UI и моста: [`konkurent_app/SPEC.md`](konkurent_app/SPEC.md)
- Заметки для разработки: [`AGENTS.md`](AGENTS.md)

---

## CI и релизы

- Пуш в `main` собирает портативные сборки и Flutter-приложение как артефакты
  GitHub Actions (**без** публикации релиза).
- Тег `v*` публикует GitHub Release с архивами:
  `konkurent-linux.zip`, `konkurent-windows.zip` (legacy) и
  `konkurent-app-linux.zip`, `konkurent-app-windows.zip` (Flutter).

```bash
git tag v1.1.0 && git push origin v1.1.0
```

Сборки **KonkurentApp** из исходников включают sidecar; на целевой машине
по-прежнему нужен Ghostscript для распознавания PDF.

---

## Лицензия

[MIT](LICENSE)