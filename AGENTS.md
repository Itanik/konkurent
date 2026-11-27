# AGENTS.md

One Flutter frontend on top of one Python recognition engine:

- **KonkurentApp** — Flutter Desktop (Windows + Linux) in `konkurent_app/`, an
  Excel-like editor that extracts line items from supplier invoices and builds a
  side-by-side comparison `.xlsx`. Reads/writes xlsx and drives the Python
  engine through `sidecar.py` (subprocess + JSON). Full design doc:
  `konkurent_app/SPEC.md`.

The Python engine (`recog.py`, `normalizer.py`, `config.json`) has no package,
lint, or test suite of its own; the Flutter app has a real test suite and its
`sidecar_roundtrip_test` is the engine's regression harness. When in doubt about
the data model, read `konkurent_app/SPEC.md`.

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

### Python engine

No lint, no typecheck, no formatter, and no test runner of its own (the Dart
`sidecar_roundtrip_test` covers it end-to-end). Verification is manual.

```bash
# setup (the venv is also what the Flutter sidecar tests expect at ../.venv)
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt

# headless CLI over a folder of PDFs
.venv/bin/python3 recog.py <folder-with-pdfs>

# the only fast automated checks that exist
.venv/bin/python3 -c "import ast; ast.parse(open('recog.py', encoding='utf-8').read())"
.venv/bin/python3 -c "import recog; import sidecar; print('OK')"

# frozen sidecar for a standalone Flutter bundle (see README for details)
.venv/bin/pip install pyinstaller
.venv/bin/pyinstaller --onefile sidecar.py --add-data "config.json:." \
    --add-data "tessdata:tessdata"   # OCR models; see the OCR gotchas below
```

## sidecar.py — Flutter ↔ Python bridge

One JSON object per invocation: result on the **last stdout line**, all `recog.py`
prints are redirected to stderr (the bridge parses stdout, so never print JSON to
stdout elsewhere).

```bash
.venv/bin/python3 sidecar.py --action=recognize --file=/abs/invoice.pdf [--legal-forms=/abs/legal-forms.json]
.venv/bin/python3 sidecar.py --action=export --output=/abs/out.xlsx < state.json
.venv/bin/python3 sidecar.py --action=import --file=/abs/saved.xlsx
```

- `recognize` — PDF (camelot; scanned/image-only PDF → OCR via `ocr_recog.py`) /
  xlsx / xls / docx → `{status, supplierName, sourceFileName, inn, kpp, ogrn,
  ocr, offers[]}`. `supplierName`/`inn`/`kpp`/`ogrn` come from
  `supplier_extract.py` (legal form + checksums; failure to extract is
  non-fatal — name falls back to the file stem); `ocr: true` marks the scanned
  path (text for requisites comes from OCR, not the text layer).
  Errors: `{status: "error", message}`.
- `export` — takes full `AppState` JSON on stdin, calls `recog.fill_template`.
  Offers may carry `priceDriver: "price"` + `priceWithVat`/`priceWithoutVat`:
  then the engine writes the price as a value and the sum as `=цена*кол-во`.
- `import` — returns `{status:"foreign"}` if the xlsx is not ours (no `"Заявка"`
  sheet or A1 not starting with `"Заявка:"`); Flutter then falls back to `recognize`.
- `docx` needs `python-docx` (in requirements); without it the sidecar returns a
  clear error.
- Flutter locates the sidecar: built binary next to the executable, else
  `sidecar.py` searched upward from cwd (dev), using `../.venv/bin/python3`.
  `--legal-forms` points at `legal-forms.json` in app-support (created by
  `AppConfigService` on first launch).

## Feature workflow

The standard loop for any change — follow it without being told:

- **Small fix** (bug, tweak): branch `fix/*` → code + tests → verification →
  merge to `main`, delete branch.
- **Large feature**: start in plan mode — explore via subagents (they read
  code in their own windows and return summaries, keeping the main context
  lean), ask the user only at real decision forks, get the plan approved.
  Then one branch `feat/*`, conventional commits per meaningful unit
  (engine / Flutter / docs separately).
- **Verification before every merge** (the gate): `flutter analyze` (0
  issues) + `flutter test` + `flutter test integration_test -d linux` +
  Python `ast`/import checks; for recognition changes, run the sidecar over
  the krep fixtures. Tests are written together with the code, not after.
- **Docs are part of the change**: SPEC.md always, an AGENTS.md gotcha for
  anything non-obvious, READMEs for user-visible changes — same branch.
- **Merge to `main`, then stop.** Never push or tag unprompted: the user
  manually tests on real invoices first; their feedback becomes fix rounds
  (same loop), and the release (tag `v1.0.x` + pubspec bump to match) happens
  only when the user asks to fix/release the version.

## Verification workflow

- `example_data/` is gitignored — it is your local fixture folder (PDFs to feed
  `recog.py`), never committed. The engine end-to-end check is
  `.venv/bin/python3 recog.py example_data` plus opening the produced
  `конкурент <folder>.xlsx`. The Flutter side is covered by `flutter test`
  (incl. `sidecar_roundtrip_test`) and `integration_test` (opens a window).
- `example_data/krep/` holds the maintainer's private real-world invoices used
  to tune recognition (do not commit, do not mention file names anywhere).
  Quick loop while debugging extraction/parsing: run
  `sidecar.py --action=recognize --file=...` over each PDF and compare the
  supplier name against the file-name prefix. One fixture is a scanned PDF with
  no text layer — it must now be recognized via OCR (correct supplier name and
  items; `ocr: true` in the JSON).
- **Scanned PDFs are recognized via OCR** (`ocr_recog.py`, system tesseract).
  `example_data/scanned_docs/` holds the scanned fixtures: 2 invoices per
  supplier («мсм», «перфорация»), each supplier having one transcribed invoice
  (a `.txt` pipe-table / `.xlsx` ground truth next to the PDF) and one blind.
  The tuning loop is `.venv/bin/python3 ocr_eval.py` (module mode for the fast
  inner cycle, `--mode sidecar` for the honest contract); exit code 1 means the
  transcribed «перфорация» invoice failed acceptance (19/19 items, exact
  qty/unit/sum, INN/KPP). «мсм» scans are best-effort (palette-quantized
  ~96 DPI + a specific font: digits/items read, some latin-in-cyrillic name
  noise remains) — a partial result there does not block the merge.
- `tessdata/` at the repo root is gitignored — download the four tesseract
  models into it for local OCR work (rus/eng fast + rus_best/eng_best, see
  `.github/workflows/build.yml` for the URLs); without them OCR falls back to
  the system tessdata (`ocr_recog._resolve_lang`).
- The old `.opencode/plans/` refactor plans (tkinter era) were removed — they
  described the deleted frontend. The step-by-step branch/substep/control-point
  convention they documented lives on in the «Feature workflow» section.
- Releases: `git tag v1.0.0 && git push origin v1.0.0` → `.github/workflows/build.yml`
  builds the Flutter app for Linux+Windows (sidecar bundled), zips it, and publishes
  a GitHub Release with auto notes. Pushing to `main` alone only produces artifacts,
  no release.
- Commits follow conventional commits (`feat:`, `fix:`, `docs:`), branches `feat/*`,
  `fix/*`, merged back into `main` and deleted.

## Architecture

```
recog.py   process_pdf_file()  camelot lattice -> stream fallback -> tuple (df, orig_headers, bez_nds)
           fill_template()     config.json -> openpyxl workbook + all row/merge bookkeeping
normalizer.py  picks the best camelot table, scores/finds the header row, maps
           columns onto STANDARD_COLUMNS, computes price-per-unit
supplier_extract.py  supplier identity from invoice text: legal-form name,
           INN (checksum-validated 10/12), KPP, OGRN. PDF via playa (already a
           camelot dep), docx via python-docx, xlsx via pandas.
           extract_supplier_from_text(text) is the OCR seam (no file access).
ocr_recog.py  OCR of image-only PDFs: pypdfium2 render -> cv2 line masks ->
           multi-pass tesseract (full page / header band / per-column strips /
           per-cell units+names) -> DataFrame via the sidecar._Table contract;
           also produces the page text for supplier_extract.
config.json    single source of truth for the output table layout
sidecar.py  argparse CLI wrapping the above for Flutter (recognize/export/import).
           `import camelot` is lazy so export/import work without the PDF stack.
           Locates config.json via SCRIPT_DIR (its own directory).
konkurent_app/  Flutter Desktop editor (Riverpod + Material 3).
           lib/services/python_bridge.dart runs sidecar.py and parses JSON.
           lib/services/storage_service.dart persists the session as JSON.
           lib/services/app_config_service.dart loads global settings
           (app-config.json: vatRate, maxSuppliers; legal-forms.json).
           lib/services/supplier_db.dart — SQLite supplier memory by INN
           (meta history last-5, name autocomplete); opened in main(),
           provider is null on failure = features off.
           lib/services/best_offer.dart — best procurement variants per k.
           Full model/UI contract: konkurent_app/SPEC.md
```

`sidecar.py` finds `config.json` next to itself (`SCRIPT_DIR`); in a frozen
(PyInstaller) build `--add-data "config.json:."` puts it at the bundle root where
`SCRIPT_DIR` resolves. Anything new that reads a data file at runtime must work
through the same mechanism — and must be added to the `--add-data` flags in CI.

## Gotchas in `recog.py` (the file you'll break if you don't read this)

- **`config.json` drives all geometry.** `load_config` derives `_block_size` from
  `len(block_columns)` and `_fixed_len` from `len(fixed_columns)`; there is no
  `block_size` key. Supplier blocks are laid out at a hardcoded stride of
  `block_size` starting after the fixed columns (fixed part is now 4 columns:
  №, Название, Кол-во, Ед.изм → block 1 starts at column 5). Adding/reordering
  a block column shifts every column index in the file.
- **Wave-2 export path is `build_comparison_xlsx`** (bottom of recog.py), called
  by sidecar export with the cleaned AppState. The whole layout (rows 1 request
  name / 2 INN / 3 hidden files / 4 headers, request-item groups with vertical
  merges, unlinked zone, meta, total+SUM, variants) is computed BEFORE any
  cell is written — no `insert_rows`, no merge compensation. The old
  `fill_template` path remains only for the headless CLI (`recog.py <folder>`).
  Sheet «Суммы» is `wb.copy_worksheet` with all block columns hidden except
  the per-block sum column.
- **openpyxl's `ws.insert_rows()` does NOT move merged ranges.** Verified: inserting a
  row at 2 moves values from row 3 to row 4 while leaving the merge at `A3:C3`.
  `fill_template` compensates by deleting stale ranges and re-merging
  (recog.py:487-498). Any new row insertion must follow that pattern.
- **Row bookkeeping is manual.** `data_start` / `data_end` / `meta_start` / `total_row`
  are ints shifted by hand at every insert site (hidden filename row, request items,
  overflow rows). Missing one shift silently corrupts the meta/total sections — e.g.
  the request-items overflow branch must also do `meta_start += 1`, otherwise the
  final meta re-merge lands on top of data rows (this was a real bug for >3 request
  items). The `sidecar_roundtrip_test` "9 позиций заявки" test guards it.
- **Borders/alignment must be assigned to the whole range *before* merging** (see
  commit `7444984`). Writing `.value` to a non-anchor cell of a merged range raises
  `AttributeError: 'MergedCell' object attribute 'value' is read-only`.
- **The SUM total lives one row *below* the `Сумма` label** (recog.py:470-476):
  the label and the first-4-columns merge are at `total_row`, the
  `=SUM(...)` formula is at `total_row + 1`. Not a bug to "fix".
- **Price per unit has two modes** (`_fill_data_row`): by default `block_start+3`
  is the formula `=IFERROR(<block_start+5 sum>/<block_start+1 qty>,"")`, but when
  the user typed a price (sidecar passes a 4th element in the pdf_data_list tuple)
  the price cell becomes a value and the SUM cell becomes
  `=IFERROR(<price cell>*<qty cell>,"")`. `normalizer.py` computes `Цена за ед.`
  into the DataFrame but that column is never written to the sheet.
- **In `normalizer.py`**, `COLUMN_PATTERNS` has no entry for `Цена за ед.`, so
  `map_columns` skips it by design, and a PDF table is only accepted at all if its
  best-scoring header row reaches 3 (`normalizer.py:191`). Header-column ties
  resolve to the *earlier* column **unless** one candidate is an exact match of
  the standard name (+2 bonus, `map_columns`): the scanned «перфорация» invoice
  has «Кол-во упак.» (col C) before the real «Кол-во» (col E) — substring ties
  picked the packaging column; exact-match-wins fixes it and also the reference
  «Кол-во шт. (справочно)» case. `normalize_table` also re-joins camelot-stream
  name fragments around the numeric row and splits qty glued into the unit
  cell («9 шт»). `_normalize_number`/`sidecar._num_or_none` strip 1С thousand
  apostrophes (5'265.00).
- **`extract_with_camelot` runs BOTH flavors and merges tables.** Lattice alone
  missed whole item tables in text-based invoices (1C layout without rules);
  `find_best_table` picks the winner by header score, so merging is safe.
  Never go back to lattice-only fallback-on-empty.
- **Supplier blocks are deduped by substring**: `filename in b["name"]`. This is how
  re-runs append new suppliers to the right instead of duplicating.
- **`fill_template(..., meta_values=None)`** — optional `{filename: {label: value}}`
  written into each block's meta rows; used by `sidecar.py` export. Blocks also
  carry `block["filename"]` so meta values can be matched.

## Gotchas in `ocr_recog.py` (scanned-PDF OCR)

- **Tesseract child processes MUST NOT inherit stdout.** `action_recognize` runs
  under `contextlib.redirect_stdout(sys.stderr)`, but that only rewires the
  Python-level stream — **fd 1 is inherited by children** and a tesseract that
  prints to it would poison the JSON channel. `ocr_recog._ocr_words` therefore
  always uses `subprocess.run(..., capture_output=True)` + temp files for TSV.
  Keep it that way for any new subprocess call in the sidecar.
- **Frame lines poison OCR — erase them before reading.** The same digit cell
  reads perfectly with `psm 7` inside the (erased) cell and fails in *every*
  psm when the ruling lines are in the crop. `ocr_recog._erase_lines` dilates
  the cv2 line masks and whitens them; every read (full page, strips, cells)
  happens on the erased image only.
- **One tesseract call per context, tuned per role** — the pipeline re-reads the
  page several times because each context needs different settings: full page
  psm 4 fast (page text for requisites), header band psm 11 + ×2 upscale read
  twice (fast AND best) with a per-column pick (`_pick_header_cells` — the мсм
  font needs best for «Сумма» but fast for «Кол-во», read as «Kon-» by best),
  unit cells psm 7 + ×3 with a Cyrillic whitelist, name cells psm 6 + ×2 on
  `rus_best+eng_best` (fixes latin/cyrillic confusion like HIMTEX→НМТЕХ),
  numeric columns psm 6 strips with a digit whitelist. Changing one role's psm
  without re-running `ocr_eval.py` will silently regress another supplier.
- **Real scans are ~96 DPI natively** — rendering at 300 adds nothing (pure
  interpolation). `RENDER_SCALE = 4` (~380 DPI) is the tuned sweet spot; all
  pixel thresholds (line clustering, group gap = 12% of page height) assume it.
- **Table lines are found by crossings, not length.** A short invoice (header +
  1 item row) has table rules *shorter* than the bank block frames above them;
  `_detect_grid` keeps horizontals crossing ≥4 verticals and picks the main
  group by summed crossings. The blind «СМ13391450» fixture guards this.
- **Pages are glued by the OCR path itself**: a page whose rows contain no
  header (score < 3) is appended to the previous page's table — camelot never
  merges across pages and `find_best_table` keeps exactly one table. The tail
  of the last page («Итого», «Вес по счету»...) is cut by `TAIL_BAND_KEYWORDS`
  over the full band text — normalizer's summary filter only sees *mapped*
  columns and misses when «Итого» lands in an unmapped one.
- **Page text is homoglyph-folded for requisitions** (`_HOMOGLYPHS`): tesseract
  reads «ООО» as latin «OOO»/«000», and then `supplier_extract` finds no legal
  form and crowns the *buyer* the supplier. Folding goes into the page text
  only — item names keep their letters (latin DIN/HIMTEX stays).
- **tessdata resolution**: `ocr_recog` prefers `SCRIPT_DIR/tessdata` (repo root
  in dev, `_MEIPASS/tessdata` in a frozen build — the same mechanism as
  config.json) and falls back to the system tessdata, mapping `rus_best`→`rus`
  when bundled models are missing (`_resolve_lang`). The repo `tessdata/` is
  gitignored; CI downloads the four models and bundles them via
  `--add-data "tessdata:tessdata"` — anything adding a new model must update
  build.yml AND the manual pyinstaller line in this file.

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
- **`markTestSkipped()` does NOT stop the test body** — it only marks the test
  skipped while the code keeps running; if the body then fails, the test is
  reported as FAILED, not skipped. Always `return;` right after it. This cost a
  broken v1.0.10 Windows CI run: the OCR test marked itself skipped on the
  tesseract-less Windows runner, then still ran `bridge.recognize` and failed
  on the «Tesseract не найден» error.
- State lives in `appStateProvider` (Riverpod `Notifier`); persistence is a
  debounced JSON write via `storageServiceProvider`. Tests override both
  `storageServiceProvider` and `fileEngineProvider`. Never call Python from tests.
- CI (`.github/workflows/build.yml`) has a `flutter` job (`ubuntu-latest` +
  `windows-2022`): it builds the sidecar with PyInstaller, runs `flutter analyze`
  / `flutter test`, builds the app, copies the sidecar into the bundle and uploads
  `konkurent-app-*.zip`. Linux runners also apt-install `tesseract-ocr` +
  `tesseract-ocr-rus` so the OCR sidecar test runs there (Windows runners have
  no tesseract — the test self-skips). Offline UI tests (`integration_test`) are
  still not run in CI — they need Xvfb on Linux runners.
- **PyInstaller must bundle the mypyc runtime from `playa-pdf`.** `camelot` pulls
  in `playa-pdf`, which ships a hash-named extension at the *root* of
  site-packages (`<hash>__mypyc.cpython-*.so` / `.pyd`). PyInstaller does not
  discover it on its own, so a frozen sidecar fails PDF recognition with
  `ModuleNotFoundError: No module named '<hash>_mypyc'`. The CI sidecar step adds
  it explicitly with `--add-binary "$(ls site-packages/*__mypyc*.<so|pyd>):."`;
  a manual sidecar build needs the same flag. Keep it. The sidecar also bundles
  the four tesseract models via `--add-data "tessdata:tessdata"` (CI downloads
  them; see the OCR gotchas above) — without it a frozen sidecar falls back to
  the end user's system tessdata and loses the best-name reads.
- **The grid is address-driven, not index-driven.** `tableLayoutProvider`
  (`lib/providers/table_layout_provider.dart`) computes RowGroups per request
  item (height = max linked offers across suppliers), an unlinked zone and
  per-row heights; UI renders groups + zone. Offer linking has two strategies
  in `AppStateNotifier`: **positional** (`linkOffersPositionally`, the default
  on recognize/paste — k-th offer → k-th request item, skips suppliers that
  already have any links) and **fuzzy** (`autoLinkOffers`, the toolbar
  button — name matching only). Offer identity is `offer.id` —
  mutations are `updateOffer`/`removeOfferById`/`createOfferAt`/
  `moveOfferWithinSupplier`/`moveOfferToSupplier`/`linkOffer`; the old
  index-based `reorderOffers`/`moveOfferToEmpty`/`setOfferAt` and the list
  paste (`parseRequestItems`) are gone — clipboard is grid TSV
  (`clipboard_grid.dart` + Ctrl+C/V on `SelectionController`,
  `selection_controller.dart`).
- **Selection focus pitfall:** after an edit the cell returns focus to
  `_selection.keyFocus` (the table FocusNode) — without that, arrows/Ctrl+C/V
  are dead because no node in the table's path has focus. Navigation uses
  `boundsProvider` for fresh bounds — a stale bounds snapshot silently clips
  moves after the grid grows during a paste.
- **Ctrl+V has two paths.** When a cell is being edited, `EditableCell`
  intercepts the shortcut: a multi-line/multi-column buffer is delegated to
  the grid paste (`SelectionController.gridPaste` → ComparisonTable's
  `_pasteGridFrom`), a single-line buffer goes into the field. When nothing
  is edited, the table Focus handles Ctrl+V at the selection. Paste also
  splits a glued qty+unit last column («9 шт») via `ClipboardGrid.splitQtyUnit`
  and auto-links offers when the pasted request is fully filled.
- **Dart RegExp `\b` is ASCII-only** — it never fires next to Cyrillic
  letters (there is no `\w` boundary before «м16»). Spell the boundary out
  explicitly (`(?:^|[^а-яёa-z0-9])`) — this bit the diameter guard in
  `fuzzy_match.itemDiameter` after it had been tuned in Python (Python's `\b`
  is Unicode by default).
- **Spare-row keys need `zoneIndex`**: all empty unlinked rows share one
  keyBase, the loop index disambiguates (`offer.empty.<sid>.zone.<j>`).
  Group rows are keyed by request-item id (`offerRow.<sid>.g.<rid>`), which
  makes drag-relink tests stable.
- **Unit dictionary**: `units.json` in app-support (created by
  AppConfigService with `UnitsDict.defaultJson`); recognized units are
  normalized on invoice add; unmatched units render orange and get an
  autocomplete overlay in `EditableCell` (`suggestions` param).
- **Sidecar stdio is forced to UTF-8.** On Windows the default code page makes
  the Cyrillic in recog/camelot logs (stderr) invalid UTF-8, so a strict decoder
  in `PythonBridge` throws `FormatException: Missing extension byte` and masks a
  successful recognition. `sidecar.py` reconfigures stdout/stderr/stdin, and the
  bridge starts the child with `PYTHONUTF8=1` + `PYTHONIOENCODING=utf-8` and
  decodes with `Utf8Decoder(allowMalformed: true)`. Keep all three.
- **Offer stores exactly one side of the VAT pair (`PriceDriver`).** `displaySum`
  / `displayPrice` derive the other side through the VAT rate on the fly — the
  stored sibling stays null by design (tests assert `displaySum`, not the stored
  sibling). Editing goes through `withSumInput` / `withPriceInput`; the two
  bulk moves are `vatMoveValues` (checkbox basis switch, values migrate to the
  new basis) and `vatMoveGrossToNet` («позиции без НДС» button: values move to
  net, gross is recomputed, columns stay visible). The VAT rate lives in the
  global config (`appConfigProvider`), default 0.22.
- **Row heights are measured, not fixed** (`rowHeightsProvider`): it lays out
  every cell's text with a `TextPainter` using `TableMetrics` text widths
  (`itemTextWidth` etc. — borders and padding deducted, `-18`). When you add a
  new text column, register its text width in `TableMetrics` and use it in
  `row_heights.dart` with the same deduction, or the measured wrap diverges
  from the real wrap and the last line clips. Known debt: the last line still
  clips for *some* wrapped names (e.g. «Шпилька резьбовая М 12х2000 DIN 975
  цинк») — the measured wrap occasionally differs from the rendered one by a
  line. Suspects: ZoomScope `TextScaler` vs painter rounding, `Expanded`
  width rounding, emoji/letter-spacing nuances. Fix direction: measure with
  the exact merged display style (inherit bodyMedium via a real `Text`
  repaint boundary) or render-then-measure with a global key.
- **View toggles are separate Riverpod notifiers** (`sumsOnlyProvider`,
  `showSumWithoutVatProvider` in `view_preferences_provider.dart`) — session
  state (AppState) must never depend on them; they are not persisted. The
  secondary pair is only shown for suppliers on the gross basis (net-basis
  suppliers already show net as primary).
- **sqlite3 API quirks (SupplierDb).** `Database.execute` takes no bound
  parameters — use `prepare()` + `stmt.execute([...])` + `dispose()`
  (`select(sql, [params])` is positional). The meta-history prune DELETE must
  be scoped by `inn AND field` — an unscoped `rowid NOT IN (top-5)` silently
  wiped the history of the supplier's OTHER fields. And `LIKE` in SQLite is
  ASCII-case-insensitive only — cyrillic name search filters in Dart
  (`searchNames`), never in SQL.
- **Best-variant xlsx cells mirror config.json geometry** (`app.dart _save`):
  the excel sum cell of a pick = column `5 + 6*supplierIdx + 5`, row
  `5 + layoutRow` — the constants (4 fixed columns → block at 5, 6 block
  columns → sum last, data from row 5) are hardcoded in TWO places: here
  and in `build_comparison_xlsx`. Changing `config.json` columns means
  updating both (plus the engine's own block math).

## Docs

- Root `README.md` (Russian) and `README.en.md` (English) are current;
  `konkurent_app/README.md` / `README.en.md` are the developer docs.
  Keep them from drifting behind the code.
- Runtime prerequisite that is easy to miss: **Ghostscript** must be on `PATH`
  (`gs` on Linux/macOS, `gswin64c` on Windows) or camelot's lattice mode fails.
  `sidecar.py` does not fail early on this (stream mode works without it) —
  when PDF recognition fails and Ghostscript is missing, it appends an
  install hint to the error message (`_gs_hint`). Likewise **tesseract** must
  be on `PATH` for scanned-PDF OCR (`_tess_hint` mirrors the pattern; the
  Russian models are bundled with the sidecar, only the binary is needed).
