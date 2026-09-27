# KonkurentApp

Flutter Desktop (Windows + Linux) editor for the supplier comparison table. It
runs on the shared Python engine (`recog.py` / `normalizer.py` / `config.json`)
through the `sidecar.py` bridge.

[Русский](README.md) | **English**

> Project overview and end-user instructions live in the
> [root README](../README.en.md). The full model/UI/bridge contract is in
> [SPEC.md](SPEC.md).

---

## Stack

| Layer | Technology |
|---|---|
| UI | Flutter 3.32, Material 3 |
| State | Riverpod 3 (`Notifier`) |
| File drag&drop | `desktop_drop` |
| File dialogs | `file_selector` |
| Local storage | JSON file via `path_provider` |
| Recognition/export | Python `sidecar.py` (subprocess + JSON) |

---

## `lib/` layout

```
lib/
├── main.dart                     ProviderScope + KonkurentApp
├── models/app_state.dart         AppState, SupplierBlock, Offer, RequestItem, SupplierMeta
├── providers/
│   ├── app_state_provider.dart   Notifier with all table mutations
│   └── services.dart             fileEngineProvider, storageServiceProvider
├── services/
│   ├── python_bridge.dart        FileEngine + PythonBridge (runs the sidecar)
│   └── storage_service.dart      StorageService / FileStorageService / InMemoryStorageService
└── ui/
    ├── app.dart                  AppShell: autosave, drag&drop, open/export
    ├── app_toolbar.dart          AppBar: request name + actions
    ├── constants.dart            grid sizes, meta rows
    ├── utils/format.dart         number formatting and parsing
    ├── comparison_table/         the table (fixed_panel, supplier_column, offer_row…)
    └── dialogs/                  "our session" open dialog
```

---

## Data model (short)

- `AppState { requestName, requestItems[], suppliers[] }`.
- `SupplierBlock { id, displayName, sourceFileName, meta, offers[] }`.
- `Offer { id, itemName, qty, unit, sumWithVat, sumWithoutVat }`.
- **Table height is derived:** `maxRows = max(offer count, request item count)`.
  Suppliers with fewer rows render empty cells.
- **Computed values are not stored:** `Offer.pricePerUnit` is `sumWithVat / qty`,
  `SupplierBlock.total` is the sum of `sumWithVat`; on export they become Excel
  formulas.

---

## Services

**`PythonBridge`** locates the sidecar: first a built binary next to the
executable, otherwise `sidecar.py` searched upward from the working directory
using `../.venv/bin/python3`. It never throws during construction — failures are
returned in the call result. The `FileEngine` abstraction lets tests swap the
engine out.

**`StorageService`** serializes the session to JSON in the app-support directory
(`getApplicationSupportDirectory()`), debounced 500 ms. Tests use
`InMemoryStorageService`.

---

## Commands

```bash
flutter pub get
flutter analyze                            # static analysis
flutter test                               # unit tests
flutter test integration_test -d linux     # UI tests (open a window)
flutter build linux --release
flutter build windows --release
```

> In this environment `flutter` is not on the default PATH:
> `export PATH="$PATH:/home/nikita/flutter/bin"`. Only the Linux toolchain is
> installed; Android/Chrome `flutter doctor` failures are irrelevant.

---

## Tests

- `test/models_test.dart` — serialization and computed fields.
- `test/app_state_provider_test.dart` — `AppState` mutations.
- `test/format_test.dart` — number formatting/parsing.
- `test/sidecar_roundtrip_test.dart` — real `sidecar.py`: export → import,
  xlsx price-list recognition, foreign-file detection. Skipped when `../.venv`
  or `sidecar.py` is missing.
- `integration_test/app_test.dart` — UI: editing, price recalculation, sorting,
  drag reordering. Engine and storage are replaced with fakes
  (`FakeFileEngine`, `InMemoryStorageService`).

---

## Limitations

- PDF recognition requires **Ghostscript** in `PATH` (`gs` / `gswin64c`),
  otherwise camelot's lattice mode fails.
- DOCX recognition requires `python-docx` (in `requirements.txt`); without it the
  sidecar returns a clear error.
- The Flutter app is not yet a CI release; `.github/workflows/build.yml` has a
  build job (analyze + test + build, with the sidecar placed into the bundle).

---

## Launch troubleshooting

If recognition fails with `No module named camelot`, the PDF stack is not
installed:

```bash
# from the repository root
.venv/bin/pip install -r requirements.txt
.venv/bin/python -c "import camelot; print(camelot.__version__)"
```

Launch from the repository root so `PythonBridge` finds `sidecar.py` and `.venv`.