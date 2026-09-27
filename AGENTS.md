# AGENTS.md

Two frontends share one recognition engine:

- **Legacy desktop app** — Python + tkinter (`gui.py`), Russian UI, extracts line
  items from supplier PDF invoices and builds a side-by-side comparison `.xlsx`.
- **KonkurentApp** — Flutter Desktop (Windows + Linux) in `konkurent_app/`, an
  Excel-like editor for the same tables. Reads/writes xlsx and drives the same
  Python engine through `sidecar.py` (subprocess + JSON). Full design doc:
  `konkurent_app/SPEC.md`.

The legacy app is three flat files with no package or test suite. The Flutter app
has a real test suite. When in doubt about the data model, read
`konkurent_app/SPEC.md`.

## Commands

### Flutter app (`konkurent_app/`)

```bash
cd konkurent_app
flutter run -d linux                 # dev
flutter analyze                      # only automated static check
flutter test                         # unit tests (sidecar tests need ../.venv)
flutter test integration_test -d linux   # UI tests, launches a window
flutter build linux --release
flutter build windows --release
```

`flutter` is not on the default PATH in this environment — use
`export PATH="$PATH:/home/nikita/flutter/bin"`. Only Linux desktop toolchain is
installed; Android/Chrome doctor failures are irrelevant (targets are
Windows + Linux).

### Legacy Python app

There is no lint, no typecheck, no formatter, and no test runner. Verification is manual.

```bash
# setup (venv must be created before the build scripts will work)
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt

# run
.venv/bin/python3 gui.py
.venv/bin/python3 recog.py <folder-with-pdfs>     # CLI, headless

# the only automated checks that exist
.venv/bin/python3 -c "import ast; ast.parse(open('recog.py', encoding='utf-8').read())"
.venv/bin/python3 -c "import recog; print('OK')"

# portable builds (both install pyinstaller themselves, both require .venv)
./build_portable.sh          # -> dist/конкурент/конкурент
cmd /c build_portable.bat    # -> dist\kongkurent\kongkurent.exe
```

Output paths differ per platform *and* per script: the `.sh` cleans/builds
`dist/конкурент` + `конкурент.spec`, the `.bat` builds `dist\kongkurent` +
`kongkurent.spec`. Don't assume one canonical dist name.

## sidecar.py — Flutter ↔ Python bridge

One JSON object per invocation: result on the **last stdout line**, all `recog.py`
prints are redirected to stderr (the bridge parses stdout, so never print JSON to
stdout elsewhere).

```bash
.venv/bin/python3 sidecar.py --action=recognize --file=/abs/invoice.pdf
.venv/bin/python3 sidecar.py --action=export --output=/abs/out.xlsx < state.json
.venv/bin/python3 sidecar.py --action=import --file=/abs/saved.xlsx
```

- `recognize` — PDF (camelot) / xlsx / xls / docx → `{status, supplierName,
  sourceFileName, offers[]}`. Errors: `{status: "error", message}`.
- `export` — takes full `AppState` JSON on stdin, calls `recog.fill_template`.
- `import` — returns `{status:"foreign"}` if the xlsx is not ours (no `"Заявка"`
  sheet or A1 not starting with `"Заявка:"`); Flutter then falls back to `recognize`.
- `docx` needs `python-docx` (in requirements); without it the sidecar returns a
  clear error.
- Flutter locates the sidecar: built binary next to the executable, else
  `sidecar.py` searched upward from cwd (dev), using `../.venv/bin/python3`.

## Verification workflow

- `example_data/` is gitignored — it is your local PDF fixture folder, never committed.
  The only end-to-end check is `.venv/bin/python3 recog.py example_data` and opening
  the produced `конкурент <folder>.xlsx`. Everything else is a human clicking
  through the GUI.
- `scripts`-style checks used by the past refactor plans live in `.opencode/plans/`
  (`PLAN*.md`) — those files document the step-by-step branch/substep/control-point
  convention the maintainer follows, including the exact verification commands.
- Releases: `git tag v1.0.0 && git push origin v1.0.0` → `.github/workflows/build.yml`
  builds Linux+Windows, zips them, and publishes a GitHub Release with auto notes.
  Pushing to `main` alone only produces artifacts, no release.
- Commits follow conventional commits (`feat:`, `fix:`, `docs:`), branches `feat/*`,
  `fix/*`, merged back into `main` and deleted.

## Architecture

```
gui.py     tkinter + ttk (theme "clam") + tkinterdnd2. Two entry paths:
             "Выбор папки" tab -> output next to the input folder
             "Drag && Drop" tab -> user-specified output path
           Runs the whole pipeline in a worker thread.
recog.py   process_pdf_file()  camelot lattice -> stream fallback -> tuple (df, orig_headers, bez_nds)
           fill_template()     config.json -> openpyxl workbook + all row/merge bookkeeping
normalizer.py  picks the best camelot table, scores/finds the header row, maps
           columns onto STANDARD_COLUMNS, computes price-per-unit
config.json    single source of truth for the output table layout
sidecar.py  argparse CLI wrapping the above for Flutter (recognize/export/import).
           `import camelot` is lazy so export/import work without the PDF stack.
konkurent_app/  Flutter Desktop editor (Riverpod + Material 3).
           lib/services/python_bridge.dart runs sidecar.py and parses JSON.
           lib/services/storage_service.dart persists the session as JSON.
           Full model/UI contract: konkurent_app/SPEC.md
```

`gui.py` imports `sys._MEIPASS` for `script_dir` so `config.json` is found inside a
PyInstaller bundle. Anything new that reads a data file at runtime must do the same.
`config.json` is baked in via `--add-data` — changing it requires a rebuild for portable builds.

## Gotchas in `recog.py` (the file you'll break if you don't read this)

- **`config.json` drives all geometry.** `load_config` derives `_block_size` from
  `len(block_columns)` and `_fixed_len` from `len(fixed_columns)`; there is no
  `block_size` key. Supplier blocks are laid out at a hardcoded stride of
  `block_size` starting after the fixed columns. Adding/reordering/inserting a block
  column (e.g. unhiding `Сумма, без НДС`) shifts every column index in the file.
- **openpyxl's `ws.insert_rows()` does NOT move merged ranges.** Verified: inserting a
  row at 2 moves values from row 3 to row 4 while leaving the merge at `A3:C3`.
  `fill_template` compensates by deleting stale ranges and re-merging
  (recog.py:487-498). Any new row insertion must follow that pattern.
- **Row bookkeeping is manual.** `data_start` / `data_end` / `meta_start` / `total_row`
  are ints shifted by hand at every insert site (hidden filename row, request items,
  overflow rows). Missing one shift silently corrupts the meta/total sections.
- **Borders/alignment must be assigned to the whole range *before* merging** (see
  commit `7444984`). Writing `.value` to a non-anchor cell of a merged range raises
  `AttributeError: 'MergedCell' object attribute 'value' is read-only`.
- **The SUM total lives one row *below* the `Сумма` label** (recog.py:470-476):
  the label and the first-4-columns merge are at `total_row`, the
  `=SUM(...)` formula is at `total_row + 1`. Not a bug to "fix".
- **Price per unit is an Excel formula, not a value**: `block_start+3` is
  `=IFERROR(<block_start+5 sum>/<block_start+1 qty>,"")`. `normalizer.py` computes
  `Цена за ед.` into the DataFrame but that column is never written to the sheet.
- **In `normalizer.py`**, `COLUMN_PATTERNS` has no entry for `Цена за ед.`, so
  `map_columns` skips it by design, and a PDF table is only accepted at all if its
  best-scoring header row reaches 3 (`normalizer.py:191`).
- **Supplier blocks are deduped by substring**: `filename in b["name"]`. This is how
  re-runs append new suppliers to the right instead of duplicating.
- **`fill_template(..., meta_values=None)`** — optional `{filename: {label: value}}`
  written into each block's meta rows; used by `sidecar.py` export. Blocks now also
  carry `block["filename"]` so meta values can be matched. `gui.py` doesn't pass it.

## Gotchas in `gui.py`

- **Tab dispatch is done by comparing the Russian tab label** (`self._current_tab`
  against `"Выбор папки"` / `"Позиции заявки"`) in `_update_run_button`,
  `_start_processing`, and `_run_processing` — and the `else` branch silently means
  the DnD tab. Renaming a tab label silently changes behaviour. The "Позиции заявки"
  tab is a special hybrid: it prefers folder files, falls back to DnD files.
- **stdout is the log transport.** The worker thread swaps in `QueueHandler`, so every
  `print` in `recog.py` lands in the GUI log box. Completion is signalled with the
  `__DONE__` / `__DONE__Ошибка: ` sentinel strings — do not emit user-visible text
  beginning with `__DONE__`.
- **The entry placeholder is real text.** `_setup_placeholder` inserts the filename
  into an entry bound to `name_var`, so `_collect_selected` reports a "custom supplier
  name" equal to the filename for every checked file unless the user overtypes it.
  Consequence: `block_names` is effectively never empty, so the hidden original-filename
  row is inserted on nearly every run, not only when names are customized.
- `output_dir` defaults to `<app_dir>/output` and is created via `makedirs` at run time.
- Clipboard support is hand-rolled per widget (`_add_clipboard_bindings` /
  `_create_entry`) plus a `bind_class` right-click menu, because `tkinterdnd2` and
  `CustomTkinter` historically broke clipboard behaviour. Use `_create_entry`, not a
  bare `tk.Entry`, or you silently lose copy/paste and the context menu.

## Gotchas in the Flutter app (`konkurent_app/`)

- **Widget keys must be `ValueKey<String>`.** `EditableCell` used to build
  `ValueKey(widget.testId)` where `testId` is `String?`, producing
  `ValueKey<String?>`; `find.byKey(ValueKey<String>(...))` then silently matched
  nothing (Flutter's `ValueKey.==` checks `runtimeType`). Always pin the type
  parameter.
- **Nested `DragTarget`s must use different payload types.** Offer rows and
  supplier columns both drag `String` at first, so the outer supplier target
  swallowed offer drags and row reordering did nothing. Use `SupplierDrag` /
  `OfferDrag` (`lib/ui/comparison_table/drag_types.dart`).
- **Drag handles use immediate `Draggable`, not `LongPressDraggable`** — desktop
  drag, and it is what the integration tests simulate.
- `flutter test` runs unit tests only; UI tests live in `integration_test/` and
  need `-d linux` (they open a window). Unit tests for `sidecar.py` shell out to
  `../.venv/bin/python3`; they skip themselves if `.venv` is absent.
- State lives in `appStateProvider` (Riverpod `Notifier`); persistence is a
  debounced JSON write via `storageServiceProvider`. Tests override both
  `storageServiceProvider` and `fileEngineProvider`. Never call Python from tests.
- CI (`.github/workflows/build.yml`) has a `flutter` job (`ubuntu-latest` +
  `windows-2022`): it builds the sidecar with PyInstaller, runs `flutter analyze`
  / `flutter test`, builds the app, copies the sidecar into the bundle and uploads
  `konkurent-app-*.zip`. Offline UI tests (`integration_test`) are still not run in
  CI — they need Xvfb on Linux runners.
- **PyInstaller must bundle the mypyc runtime from `playa-pdf`.** `camelot` pulls
  in `playa-pdf`, which ships a hash-named extension at the *root* of
  site-packages (`<hash>__mypyc.cpython-*.so` / `.pyd`). PyInstaller does not
  discover it on its own, so a frozen sidecar fails PDF recognition with
  `ModuleNotFoundError: No module named '<hash>_mypyc'`. Both `build_portable.*`
  and the CI sidecar step add it explicitly with
  `--add-binary "$(ls site-packages/*__mypyc*.<so|pyd>):."`. Keep that flag.
- **Sidecar stdio is forced to UTF-8.** On Windows the default code page makes
  the Cyrillic in recog/camelot logs (stderr) invalid UTF-8, so a strict decoder
  in `PythonBridge` throws `FormatException: Missing extension byte` and masks a
  successful recognition. `sidecar.py` reconfigures stdout/stderr/stdin, and the
  bridge starts the child with `PYTHONUTF8=1` + `PYTHONIOENCODING=utf-8` and
  decodes with `Utf8Decoder(allowMalformed: true)`. Keep all three.

## Docs

- Root `README.md` (Russian) and `README.en.md` (English) are current for both
  frontends; `konkurent_app/README.md` / `README.en.md` are the developer docs.
  The legacy "README is behind the code" drift has been fixed — keep it that way.
- `customtkinter` is still listed in `requirements.txt` but is imported nowhere;
  it is a dead dependency. The GUI is native `tkinter` + `ttk`.
- Runtime prerequisite that is easy to miss: **Ghostscript** must be on `PATH`
  (`gs` on Linux/macOS, `gswin64c` on Windows) or camelot's lattice mode fails.
  `gui.py` only logs a warning at startup via `_check_gs`; `sidecar.py` surfaces
  the failure as an error for the Flutter app.
