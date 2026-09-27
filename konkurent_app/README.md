# KonkurentApp

Flutter Desktop (Windows + Linux) редактор конкурентной таблицы. Работает поверх
общего Python-движка (`recog.py` / `normalizer.py` / `config.json`) через мост
`sidecar.py`.

**Русский** | [English](README.en.md)

> Обзор всего проекта и инструкция для пользователя — в [корневом README](../README.md).
> Полный контракт модели, UI и моста — в [SPEC.md](SPEC.md).

---

## Стек

| Слой | Технология |
|---|---|
| UI | Flutter 3.32, Material 3 |
| Состояние | Riverpod 3 (`Notifier`) |
| Файлы drag&drop | `desktop_drop` |
| Диалоги файлов | `file_selector` |
| Локальное хранилище | JSON-файл через `path_provider` |
| Распознавание/экспорт | Python `sidecar.py` (subprocess + JSON) |

---

## Структура `lib/`

```
lib/
├── main.dart                     ProviderScope + KonkurentApp
├── models/app_state.dart         AppState, SupplierBlock, Offer, RequestItem, SupplierMeta
├── providers/
│   ├── app_state_provider.dart   Notifier со всеми мутациями таблицы
│   └── services.dart             fileEngineProvider, storageServiceProvider
├── services/
│   ├── python_bridge.dart        FileEngine + PythonBridge (запуск sidecar)
│   └── storage_service.dart      StorageService / FileStorageService / InMemoryStorageService
└── ui/
    ├── app.dart                  AppShell: автосохранение, drag&drop, open/export
    ├── app_toolbar.dart          AppBar: имя заявки + действия
    ├── constants.dart            размеры сетки, мета-строки
    ├── utils/format.dart         форматирование и парсинг чисел
    ├── comparison_table/         таблица (fixed_panel, supplier_column, offer_row…)
    └── dialogs/                  диалог открытия «своей» сессии
```

---

## Модель данных (кратко)

- `AppState { requestName, requestItems[], suppliers[] }`.
- `SupplierBlock { id, displayName, sourceFileName, meta, offers[] }`.
- `Offer { id, itemName, qty, unit, sumWithVat, sumWithoutVat }`.
- **Высота таблицы — производная:** `maxRows = max(число предложений, число
  позиций заявки)`. У поставщиков с меньшим числом строк отображаются пустые
  ячейки.
- **Вычисляемые поля не хранятся:** `Offer.pricePerUnit` считается как
  `sumWithVat / qty`, `SupplierBlock.total` — сумма `sumWithVat`; при экспорте
  становятся формулами Excel.

---

## Сервисы

**`PythonBridge`** — находит sidecar: сначала собранный бинарник рядом с
исполняемым файлом, иначе `sidecar.py` вверх по дереву от рабочей директории с
`../.venv/bin/python3`. Никогда не бросает при инициализации: при неудаче отдаёт
ошибку в исходе вызова. Абстракция `FileEngine` позволяет подменять движок в
тестах.

**`StorageService`** — сессия сериализуется в JSON в app-support каталоге
(`getApplicationSupportDirectory()`). Запись debounce 500 мс. В тестах
используется `InMemoryStorageService`.

---

## Команды

```bash
flutter pub get
flutter analyze                            # статический анализ
flutter test                               # unit-тесты
flutter test integration_test -d linux     # UI-тесты (открывают окно)
flutter build linux --release
flutter build windows --release
```

> `flutter` в этом окружении не в PATH по умолчанию:
> `export PATH="$PATH:/home/nikita/flutter/bin"`. Установлен только Linux
> toolchain; Android/Chrome в `flutter doctor` можно игнорировать.

---

## Тесты

- `test/models_test.dart` — сериализация и вычисляемые поля.
- `test/app_state_provider_test.dart` — мутации `AppState`.
- `test/format_test.dart` — формат/парсинг чисел.
- `test/sidecar_roundtrip_test.dart` — реальный `sidecar.py`: export → import,
  recognize xlsx-прайса, определение чужого файла. Пропускается, если нет
  `../.venv` или `sidecar.py`.
- `integration_test/app_test.dart` — UI: редактирование, пересчёт цены,
  сортировка, drag-перестановки. Движок и хранилище подменяются заглушками
  (`FakeFileEngine`, `InMemoryStorageService`).

---

## Ограничения

- Для распознавания PDF нужен **Ghostscript** в `PATH` (`gs` / `gswin64c`) —
  иначе падает lattice-режим camelot.
- DOCX-распознавание требует `python-docx` (в `requirements.txt`); без него
  sidecar возвращает понятную ошибку.
- Flutter-приложение пока **не в CI** как релиз; в `.github/workflows/build.yml`
  добавлена сборочная джоба (analyze + test + build, sidecar кладётся в бандл).

---

## Отладка запуска

Если при распознавании приходит `No module named camelot` — не установлен
PDF-стек:

```bash
# из корня репозитория
.venv/bin/pip install -r requirements.txt
.venv/bin/python -c "import camelot; print(camelot.__version__)"
```

Запускать приложение следует из корня репозитория, чтобы `PythonBridge` нашёл
`sidecar.py` и `.venv`.