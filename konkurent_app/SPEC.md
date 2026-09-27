# SPEC — KonkurentApp

Flutter Desktop приложение (Windows + Linux) для создания и редактирования
конкурентных таблиц сравнения поставщиков. Заменяет существующий Python/tkinter
инструмент (`gui.py`) и переиспользует его движок распознавания через
Python-sidecar.

## Ключевые сценарии

- Создание таблицы с нуля вручную
- Автозаполнение через drag&drop PDF / xlsx / docx счетов
- Редактирование ячеек, перестановка строк предложений и блоков поставщиков
- Сохранение в xlsx, открытие ранее сохранённого файла
- Сортировка поставщиков по итоговой сумме (слева самый выгодный)

## Технологический стек

| Компонент | Технология |
|---|---|
| UI | Flutter Desktop + Material 3 |
| State management | Riverpod 3.x |
| Локальное хранилище | JSON-файл в app-support dir (path_provider) |
| Распознавание файлов | Python sidecar (subprocess + JSON) |
| Экспорт / импорт xlsx | Python sidecar |
| Drag&drop файлов | desktop_drop |
| Тестирование | flutter_test + integration_test |

## Модель данных

```dart
class AppState {
  final String requestName;
  final List<RequestItem> requestItems;  // может быть пустым
  final List<SupplierBlock> suppliers;   // порядок = порядок колонок
}

class RequestItem {
  final String id;
  final String name;
  final String qty;
}

class SupplierBlock {
  final String id;                   // uuid
  final String displayName;          // заголовок блока
  final String? sourceFileName;      // оригинальное имя файла (для экспорта)
  final SupplierMeta meta;
  final List<Offer> offers;          // порядок = порядок строк
}

class SupplierMeta {
  final String contract;       // Договор
  final String deliveryTime;   // Сроки поставки
  final String delivery;       // Доставка
  final String paymentTerms;   // Условия оплаты
  final String comment;        // Комментарий
}

class Offer {
  final String id;             // uuid
  final String itemName;       // Предложено
  final double? qty;           // Кол-во
  final String? unit;          // Ед.изм
  final double? sumWithVat;    // Сумма, с НДС
  final double? sumWithoutVat; // Сумма, без НДС (скрытая колонка)
  // pricePerUnit = sumWithVat / qty — вычисляется, не хранится
}
```

**Высота таблицы** — производная от данных:
`maxRows = max(suppliers.map((s) => s.offers.length))`.
Поставщики с меньшим числом предложений отображают пустые ячейки до `maxRows`.
Строки предложений можно перетаскивать только внутри блока своего поставщика.

**Вычисляемые значения никогда не записываются константами** — они считаются
на лету (`pricePerUnit = sumWithVat / qty`, `total = Σ sumWithVat`) и в xlsx
экспортируются формулами (`=IFERROR(...)`, `=SUM(...)`).

## Структура UI

```
Scaffold
├── AppBar
│   ├── RequestNameField
│   ├── [+ Поставщик]
│   ├── [Сортировать по сумме ↑]    — меняет порядок suppliers
│   ├── [Открыть…]                  — импорт / открытие сессии
│   └── [Сохранить xlsx]            — экспорт
│
└── Body — DragDropWrapper          — drag файла на окно
    └── ComparisonTable
        ├── TableHeader             — строка 1: имена поставщиков + drag handle
        └── StickyHorizontalScroll
            ├── FixedPanel (не скроллится горизонтально)
            │   ├── FixedHeaderRow: ["№", "Название позиции", "Кол-во"]
            │   ├── FixedDataRows[0..maxRows-1]: EditableCell × 3
            │   └── FixedMetaFooter: 5 меток + строка "Итого:"
            │
            └── ScrollableArea (горизонтальный скролл)
                └── Row<SupplierColumn> (горизонтальный reorder)
                    └── SupplierColumn
                        ├── SupplierHeader: DragHandle + EditableText + [×]
                        ├── ColumnSubheader: ["Предложено","Кол-во","Ед.","Ц/ед","Сумма"]
                        ├── OfferRows[0..maxRows-1] (вертикальный reorder)
                        │   └── OfferRow: itemName, qty, unit, price (readonly), sumWithVat
                        ├── MetaRows × 5: EditableCell
                        └── TotalRow: computed SUM(sumWithVat), read-only
```

**Inline-редактирование**: клик по ячейке → `TextField` на месте. Подтверждение
по Enter / Tab / потере фокуса.

**Drag блоков**: горизонтальный drag за handle в `SupplierHeader`.

**Drag строк**: вертикальный drag за handle в `OfferRow`, только внутри блока.

## Обработка drag&drop файлов

```
Файл брошен на окно
│
├── .xlsx со "своей" структурой (лист "Заявка", A1 начинается с "Заявка:")
│   └── Диалог: "Открыть как новую сессию? Текущая [сохранится / будет потеряна]"
│       ├── [Сохранить текущую и открыть] → export текущей → import нового
│       └── [Открыть без сохранения]      → import нового
│
└── Всё остальное (PDF, произвольный xlsx, docx)
    └── sidecar --action=recognize → SupplierBlock
        ├── Успех (score ≥ 3) → добавить блок справа
        └── Ошибка             → SnackBar "Не удалось распознать файл"
```

**Признак "своего" xlsx**: лист с именем `"Заявка"` (из `config.json: sheet_name`)
и ячейка A1, начинающаяся с `"Заявка:"`. Если оба условия выполнены — файл
открывается как сессия, иначе распознаётся как прайс-лист.

## Python sidecar

**Файл**: `sidecar.py` в корне репозитория (обёртка над `recog.py` / `normalizer.py`).

```bash
# Распознавание файла
python sidecar.py --action=recognize --file=/abs/path/to/file.pdf
# stdout:
{
  "status": "ok",
  "supplierName": "file.pdf",
  "offers": [
    {"itemName": "Болт М8×40", "qty": 100, "unit": "шт",
     "sumWithVat": 1200.0, "sumWithoutVat": 1000.0}
  ]
}

# Экспорт (AppState передаётся через stdin)
python sidecar.py --action=export --output=/abs/path/to/out.xlsx < state.json
# stdout: {"status": "ok", "path": "/abs/path/to/out.xlsx"}

# Импорт своего xlsx
python sidecar.py --action=import --file=/abs/path/to/saved.xlsx
# stdout: {"status": "ok", "requestName": "…", "suppliers": [...]}
```

Поддерживаемые форматы при recognize: `.pdf`, `.xlsx`, `.xls`, `.docx`.

Ошибки: всегда `{"status": "error", "message": "…"}` в stdout, код выхода 1.
Импорт не своего xlsx: `{"status": "foreign"}`.

## Автосохранение и сессии

- Состояние сессии хранится в JSON-файле `session.json` в app-support каталоге
  (`getApplicationSupportDirectory()`): `~/.local/share/konkurent_app/` (Linux),
  `%APPDATA%\konkurent_app\` (Windows)
- При старте загружается последний сохранённый `AppState`
- При каждом изменении — debounced write (500 мс)
- `StorageService` — абстракция: `FileStorageService` (прод) и
  `InMemoryStorageService` (тесты)
- «Открыть свой xlsx» → новая сессия, старая перезаписывается (с подтверждением)

## Тестирование (для агентной разработки без человека)

Unit-тесты (`test/`):
- `models_test.dart` — сериализация, вычисляемые поля (`pricePerUnit`, `total`, `maxRows`)
- `app_state_provider_test.dart` — add/remove/reorder/sort поставщиков и предложений
- `format_test.dart` — формат и парсинг чисел
- `sidecar_roundtrip_test.dart` — реальный `sidecar.py`: export → import, recognize
  xlsx-прайса, определение чужого xlsx (пропускается, если нет `.venv`/`sidecar.py`)

Integration-тесты (`integration_test/app_test.dart`), запуск `-d linux`:
- smoke — таблица рендерится, панель инструментов на месте
- редактирование ячейки предложения и позиции заявки
- автоматический пересчёт `Ц/ед`
- сортировка блоков по сумме
- добавление поставщика кнопкой
- создание блока из распознанного файла
- drag-перестановка предложений внутри блока и блоков по горизонтали

Тесты используют `FakeFileEngine` и `InMemoryStorageService` (без Python и ФС).

Ключевой нюанс drag&drop: вложенные `DragTarget` имеют **разные типы**
(`SupplierDrag` / `OfferDrag`, см. `drag_types.dart`). Если оба будут `String`,
внешний target перехватит перетаскивание предложения и перестановка строк
молча не сработает.

## Структура репозитория

```
/                            ← корень (Python-приложение остаётся)
├── recog.py
├── normalizer.py
├── config.json
├── sidecar.py               ← Python-мост для Flutter
├── requirements.txt
├── AGENTS.md
│
└── konkurent_app/           ← Flutter-проект
    ├── pubspec.yaml
    ├── SPEC.md
    ├── lib/
    │   ├── main.dart
    │   ├── models/
    │   ├── providers/
    │   ├── services/
    │   └── ui/
    ├── integration_test/
    │   └── app_test.dart
    └── test/
```

## Сборка и CI

```bash
# Dev
cd konkurent_app && flutter run -d linux

# Тесты
flutter test
flutter test integration_test/ -d linux

# Release build
flutter build linux --release
flutter build windows --release

# Python sidecar (из корня репо)
.venv/bin/pyinstaller --onefile sidecar.py --add-data "config.json:."
# → dist/sidecar  (Linux) / dist/sidecar.exe (Windows)
```

## Ограничения

- **Ghostscript** нужен для PDF (lattice-режим camelot). Пользователь
  устанавливает вручную; sidecar проверяет наличие `gs` / `gswin64c` и возвращает
  ошибку, если его нет. В CI ставится через `apt-get` / `choco` (см. `build.yml`).
- **DOCX**: в текущем `normalizer.py` поддержки нет — нужен `python-docx` и логика
  в `sidecar.py`.
- **Версионирование формата** экспортируемого xlsx не реализовано: при изменении
  `config.json` старые файлы могут не открыться.