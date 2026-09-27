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
            ├── FixedPanel (не скроллится горизонтально, видна всегда)
            │   ├── FixedHeaderRow: ["№", "Название позиции", "Кол-во"] + [Вставить список]
            │   ├── FixedDataRows[0..displayRows-1]: EditableCell × 3 + [×]
            │   └── FixedMetaFooter: 5 меток + строка "Итого:"
            │
            └── ScrollableArea (горизонтальный скролл)
                └── Row<SupplierColumn> (горизонтальный reorder)
                    └── SupplierColumn
                        ├── SupplierHeader: DragHandle + EditableText + [×]
                        ├── ColumnSubheader: ["Предложено","Кол-во","Ед.","Ц/ед","Сумма"]
                        ├── OfferRows[0..displayRows-1] (вертикальный reorder)
                        │   └── OfferRow: itemName, qty, unit, price (readonly), sumWithVat
                        ├── MetaRows × 5: EditableCell
                        └── TotalRow: computed SUM(sumWithVat), read-only
```

**Пустые строки.** `displayRows = maxRows + 1`: внизу всегда есть одна запасная
пустая строка, а все пустые ячейки (и у заявки, и у поставщиков) — обычные
редактируемые `EditableCell`. Кнопок «+» нет: ввод в пустую строку создаёт
запись, и снизу автоматически появляется новая запасная. Кнопка «×» удаляет
заполненную строку. «Хвостовые» полностью пустые строки в модели схлопываются
автоматически (`_trimTrailingOffers` / `_trimTrailingRequestItems`); пустые
строки в середине сохраняются.

**Inline-редактирование**: клик по ячейке → `TextField` на месте. Подтверждение
по Enter / Tab / потере фокуса.

**Drag блоков**: горизонтальный drag за handle в `SupplierHeader`.

**Drag строк**: вертикальный drag за handle в `OfferRow`, только внутри блока.
Сброс на **заполненную** строку переставляет (уплотняет) список; сброс на
**пустую** строку меняет их местами — предложение встаёт на место пустой, а на
его прежнем месте остаётся пробел (`moveOfferToEmpty`). Так можно расставлять
пропуски между предложениями.

## Вставка списка позиций из буфера

Панель заявки видна всегда (даже без поставщиков) и содержит минимум одну
строку, поэтому её можно заполнить первой.

- **Ctrl+V в ячейке «Название позиции»** (или Shift+Insert): многострочный
  текст из буфера раскладывается по строкам заявки начиная с текущей.
- **Ctrl+V в ячейке «Предложено» поставщика**: так же заполняет названия
  предложений этого блока.
- **Кнопка «Вставить список»** в шапке панели заявки — запасной путь,
  заполняет с первой строки.
- Одиночная строка без таба и перевода строки вставляется как обычный текст.

Правила разбора (`lib/utils/request_items_parse.dart`):

1. строки делятся по переводу строки, пустые отбрасываются;
2. если есть табуляция (копия из Excel `Название<TAB>Кол-во`) — делим по табу;
3. иначе — по **последней** запятой: до неё название, после — количество;
4. если разделителя нет или после запятой пусто — вся строка в название.

Строки перезаписываются сверху вниз; при нехватке добавляются; «хвост»
существующих строк не трогается. Для предложений поставщика заполняется только
название (количество/единица не трогаются).

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
- `request_items_parse_test.dart` — разбор вставленного списка (запятая, таб, пустые строки)
- `sidecar_roundtrip_test.dart` — реальный `sidecar.py`: export → import, recognize
  xlsx-прайса, определение чужого xlsx, геометрия книги при 9 позициях заявки
  (пропускается, если нет `.venv`/`sidecar.py`)

Integration-тесты (`integration_test/app_test.dart`), запуск `-d linux`:
- smoke — таблица рендерится, панель инструментов на месте
- редактирование ячейки предложения и позиции заявки
- автоматический пересчёт `Ц/ед`
- сортировка блоков по сумме
- добавление поставщика кнопкой
- создание блока из распознанного файла
- drag-перестановка предложений внутри блока и блоков по горизонтали (вверх и вниз)
- сброс предложения на пустую строку оставляет пробел
- вставка списка позиций заявки через Ctrl+V и кнопкой, и в «Предложено»
- создание предложения вводом в пустую (запасную) строку

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