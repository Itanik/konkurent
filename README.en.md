# Comparison Table

A procurement tool: it collects supplier quotes and builds a single comparison
table. The primary application is **KonkurentApp**, an interactive Flutter
Desktop editor backed by a shared Python recognition engine.

[Русский](README.md) | **English**

---

## Two applications

The project ships two frontends over one engine:

| | **KonkurentApp** (recommended) | Python GUI (legacy) |
|---|---|---|
| UI | Flutter Desktop, Material 3 | Tkinter + ttk |
| Platforms | Windows, Linux | Windows, Linux |
| Purpose | Interactive table editor | One-shot xlsx generator |
| Cell editing | yes | no |
| Reorder rows/blocks | yes (drag&drop) | no |
| Sort by total | yes | no |
| Status | actively developed | maintenance only |

The recognition engine (`recog.py`, `normalizer.py`, `config.json`) is shared.

---

## KonkurentApp features

- Excel-like table: fixed request columns on the left, supplier blocks scroll
  horizontally.
- Edit any cell in place.
- Drag individual offers within a block (each supplier's rows are independent)
  and drag whole supplier blocks left/right.
- Sort suppliers by total amount — cheapest on the left.
- Fill manually or automatically: drop an invoice (pdf / xlsx / xls / docx) and
  recognized items appear as a new block.
- Save the result to xlsx and reopen a previously saved file.
- Autosave the session between launches.
- Computed values (unit price, totals) are never stored as constants — they are
  derived live and exported as Excel formulas.

## Screenshots

_Screenshots placeholder._

---

## Requirements

- **Flutter SDK 3.32+** — [flutter.dev](https://docs.flutter.dev/get-started/install)
- **Python 3.13+**
- **Ghostscript** (`gs` on Linux, `gswin64c` on Windows) —
  [ghostscript.com](https://ghostscript.com). Required for PDF recognition
  (camelot lattice mode).
- Python engine dependencies (`requirements.txt`).

The Linux Flutter build additionally needs `clang`, `cmake`, `ninja-build`,
`pkg-config`, `libgtk-3-dev`, `liblzma-dev`.

---

## Install and run (from source)

```bash
git clone https://github.com/Itanik/konkurent.git
cd konkurent

# Python engine and sidecar bridge
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt      # Windows: .venv\Scripts\pip install -r requirements.txt

# Flutter app
cd konkurent_app
flutter pub get
flutter run -d linux                            # or: flutter run -d windows
```

> **Important:** run the app from the repository root (or bundle the sidecar —
> see below). `PythonBridge` searches upward for `sidecar.py` and uses
> `../.venv/bin/python3`; from any other directory recognition and export cannot
> find the engine.

### Release build

```bash
cd konkurent_app
flutter build linux --release      # → build/linux/x64/release/bundle/
flutter build windows --release    # → build/windows/x64/runner/Release/
```

For a standalone distribution, build the sidecar and place it next to the
executable:

```bash
# from the repository root
.venv/bin/pip install pyinstaller
.venv/bin/pyinstaller --onefile sidecar.py --add-data "config.json:."
# Linux: dist/sidecar → next to bundle/konkurent_app
# Windows: dist\sidecar.exe → next to Release\konkurent_app.exe
```

The app then finds the sidecar next to itself and can run from any directory.

---

## Usage

1. **From an invoice** — drop a file (pdf/xlsx/docx) onto the window. On success a
   new supplier block appears on the right.
2. **Manually** — fill the request rows on the left or add a supplier with the
   toolbar button. There is always an empty editable row at the bottom: start
   typing in it to create an entry, and a new empty row appears below. The "×"
   button deletes a row.
3. **Paste a list** — copy a list of items (one per line) and press Ctrl+V in the
   "Item name" cell: the request rows are filled and grown as needed. It also works
   in a supplier's "Offered" column and via the "Paste list" button in the request
   panel header. Name and quantity are split by tab (Excel copy) or by the last
   comma (`Шпоночный материал 4х4, 5 м.п.`).
4. **Editing** — clicking a cell turns it into an input field; Enter or clicking
   away commits the value.
5. **Reordering** — drag the handle (⠿) in a block header to swap suppliers, or a
   row handle to change the order of offers within a block.
6. **Sorting** — the "Sort by total" button puts the cheapest supplier on the left.
7. **Saving** — "Save xlsx" exports the table; "Open…" loads a previously saved
   file.

---

## `sidecar.py` bridge

The Flutter app never calls Python directly — it runs `sidecar.py` as a child
process and exchanges JSON (one result line on stdout, logs on stderr).

```bash
# Recognize a file
python sidecar.py --action=recognize --file=/abs/path/invoice.pdf

# Export state (AppState JSON on stdin)
python sidecar.py --action=export --output=/abs/path/out.xlsx < state.json

# Open an xlsx produced by this app
python sidecar.py --action=import --file=/abs/path/saved.xlsx
```

An xlsx is considered "ours" if it has a `Заявка` sheet whose A1 starts with
`Заявка:`; otherwise `import` returns `{"status": "foreign"}` and the file is
recognized as a price list.

---

## Tests

```bash
cd konkurent_app
flutter analyze                            # static analysis
flutter test                               # unit tests (sidecar tests need ../.venv)
flutter test integration_test -d linux     # UI tests (open a window)
```

---

## Legacy Python application

The old GUI is kept for compatibility and is no longer developed.

```bash
.venv/bin/python3 gui.py                     # graphical interface
.venv/bin/python3 recog.py /path/to/folder   # CLI: process a folder of PDFs
```

Portable builds (need `.venv` and Ghostscript on the target machine):

```bash
./build_portable.sh          # Linux → dist/конкурент/конкурент
cmd /c build_portable.bat    # Windows → dist\kongkurent\kongkurent.exe
```

---

## Architecture

| Module | Purpose |
|---|---|
| `recog.py` | Core: table extraction, filling the Excel workbook |
| `normalizer.py` | Column normalization (item, qty, total, without VAT) |
| `config.json` | Single source of truth for the output table layout |
| `sidecar.py` | Flutter ↔ Python bridge (recognize / export / import) |
| `konkurent_app/` | Flutter app (Riverpod + Material 3) |
| `gui.py` | Legacy Tkinter interface |

Data flow:

```
invoice (pdf/xlsx/docx) → camelot / pandas → column normalization
→ pandas DataFrame → openpyxl → конкурент <request name>.xlsx
```

- Full model/UI/bridge contract: [`konkurent_app/SPEC.md`](konkurent_app/SPEC.md)
- Development notes: [`AGENTS.md`](AGENTS.md)

---

## CI and releases

- Pushing to `main` builds the portable apps and the Flutter app as GitHub Actions
  artifacts (**no** release published).
- A `v*` tag publishes a GitHub Release with archives:
  `konkurent-linux.zip`, `konkurent-windows.zip` (legacy) and
  `konkurent-app-linux.zip`, `konkurent-app-windows.zip` (Flutter).

```bash
git tag v1.1.0 && git push origin v1.1.0
```

**KonkurentApp** builds from CI include the sidecar; Ghostscript is still required
on the target machine for PDF recognition.

---

## License

[MIT](LICENSE)