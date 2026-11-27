import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:konkurent_app/models/app_state.dart';
import 'package:konkurent_app/services/python_bridge.dart';
import 'package:path/path.dart' as p;

/// Определяем корень репозитория (папка с sidecar.py и .venv).
String? _findRepoRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 5; i++) {
    if (File(p.join(dir.path, 'sidecar.py')).existsSync()) return dir.path;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return null;
}

String? _python(String root) {
  final unix = p.join(root, '.venv', 'bin', 'python3');
  if (File(unix).existsSync()) return unix;
  final win = p.join(root, '.venv', 'Scripts', 'python.exe');
  if (File(win).existsSync()) return win;
  return null;
}

void main() {
  final root = _findRepoRoot();
  final python = root == null ? null : _python(root);
  final available = root != null && python != null;
  final skipReason = available ? null : 'sidecar.py/.venv не найдены — пропуск';

  test('export → import сохраняет позиции, мета и заявку',
      skip: skipReason, () async {
    final bridge = PythonBridge.create();
    final state = AppState(
      requestName: 'Заявка X',
      requestItems: const [RequestItem(id: 'r1', name: 'Болт', qty: '10')],
      suppliers: [
        SupplierBlock(
          id: 's1',
          displayName: 'Поставщик А',
          sourceFileNames: ['a.pdf'],
          meta: const SupplierMeta(contract: 'Д-1', comment: 'ok'),
          offers: const [
            Offer(
                id: 'o1',
                itemName: 'Болт',
                qty: 10,
                unit: 'шт',
                sumWithVat: 1200,
                sumWithoutVat: 1000),
            Offer(id: 'o2', itemName: 'Гайка', qty: 5, unit: 'шт', sumWithVat: 300),
          ],
        ),
        SupplierBlock(
          id: 's2',
          displayName: 'Поставщик Б',
          sourceFileNames: ['b.pdf'],
          offers: const [
            Offer(id: 'o3', itemName: 'Болт', qty: 10, unit: 'шт', sumWithVat: 990),
            Offer(id: 'o4', itemName: 'Шайба', qty: 20, unit: 'шт', sumWithVat: 200),
            Offer(id: 'o5', itemName: 'Гайка', qty: 5, unit: 'шт', sumWithVat: 280),
          ],
        ),
      ],
    );

    final tmp = Directory.systemTemp.createTempSync('konkurent_test');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final out = p.join(tmp.path, 'out.xlsx');

    final export = await bridge.export(state, out);
    expect(export.ok, isTrue, reason: export.error);
    expect(File(out).existsSync(), isTrue);

    final import = await bridge.importFile(out);
    expect(import.status, ImportStatus.ok, reason: import.error);
    final restored = import.state!;
    expect(restored.requestName, 'Заявка X');
    expect(restored.requestItems.first.name, 'Болт');
    expect(restored.suppliers, hasLength(2));
    expect(restored.suppliers.first.displayName, 'Поставщик А');
    expect(restored.suppliers.first.meta.contract, 'Д-1');
    expect(restored.suppliers.first.offers.first.sumWithVat, 1200);
    expect(restored.suppliers.first.offers.first.sumWithoutVat, 1000);
    expect(restored.suppliers[1].offers, hasLength(3));
  });

  test('recognize читает прайс-лист xlsx', skip: skipReason, () async {
    final tmp = Directory.systemTemp.createTempSync('konkurent_rec');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final invoice = p.join(tmp.path, 'invoice.xlsx');

    final script = '''
import openpyxl
wb = openpyxl.Workbook(); ws = wb.active
ws.append(["№", "Товар", "Кол-во", "Ед.", "Цена", "Сумма"])
ws.append([1, "Болт М8", 10, "шт", 50, 500])
ws.append([2, "Гайка М8", 20, "шт", 10, 200])
ws.append(["", "Итого", None, None, None, 700])
wb.save(r"$invoice")
''';
    final gen = await Process.run(python!, ['-c', script]);
    expect(gen.exitCode, 0, reason: gen.stderr.toString());

    final bridge = PythonBridge.create();
    final outcome = await bridge.recognize(invoice);
    expect(outcome.ok, isTrue, reason: outcome.error);
    expect(outcome.supplier!.offers, hasLength(2));
    expect(outcome.supplier!.offers.first.itemName, 'Болт М8');
    expect(outcome.supplier!.offers.first.qty, 10);
  });

  test('import произвольного xlsx возвращает foreign',
      skip: skipReason, () async {
    final tmp = Directory.systemTemp.createTempSync('konkurent_foreign');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final other = p.join(tmp.path, 'other.xlsx');

    final script = '''
import openpyxl
wb = openpyxl.Workbook(); ws = wb.active
ws.append(["Произвольный файл"])
ws.append([1, 2, 3])
wb.save(r"$other")
''';
    final gen = await Process.run(python!, ['-c', script]);
    expect(gen.exitCode, 0, reason: gen.stderr.toString());

    final bridge = PythonBridge.create();
    final outcome = await bridge.importFile(other);
    expect(outcome.status, ImportStatus.foreign);
  });

  test('экспорт 9 позиций заявки не ломает геометрию книги',
      skip: skipReason, () async {
    final bridge = PythonBridge.create();

    AppState stateOf(int requested, List<int> offersPerSupplier) => AppState(
          requestName: 'Длинная заявка',
          requestItems: [
            for (var i = 0; i < requested; i++)
              RequestItem(id: 'r$i', name: 'Позиция $i', qty: '${i + 1}'),
          ],
          suppliers: [
            for (var s = 0; s < offersPerSupplier.length; s++)
              SupplierBlock(
                id: 's$s',
                displayName: 'Поставщик $s',
                sourceFileNames: ['s$s.pdf'],
                offers: [
                  for (var i = 0; i < offersPerSupplier[s]; i++)
                    Offer(
                      id: 's${s}o$i',
                      itemName: 'S$s-$i',
                      qty: 1,
                      unit: 'шт',
                      sumWithVat: 100.0 * (i + 1),
                      // Все предложения привязаны к первой позиции: группа
                      // получает max строк по поставщикам.
                      linkedRequestItemId: 'r0',
                    ),
                ],
              ),
          ],
        );

    final tmp = Directory.systemTemp.createTempSync('konkurent_geom');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final out = p.join(tmp.path, 'out.xlsx');

    final export = await bridge.export(stateOf(9, [3, 5]), out);
    expect(export.ok, isTrue, reason: export.error);

    // Round-trip: все позиции и предложения на месте.
    final import = await bridge.importFile(out);
    expect(import.status, ImportStatus.ok, reason: import.error);
    final restored = import.state!;
    expect(restored.requestItems.where((e) => e.name.isNotEmpty).length, 9);
    expect(
      restored.suppliers[0].offers.where((o) => o.itemName.isNotEmpty).length, 3);
    expect(
      restored.suppliers[1].offers.where((o) => o.itemName.isNotEmpty).length, 5);

    // Геометрия новой раскладки: строка 1 заявка, 2 ИНН, 3 файлы (скрыта),
    // 4 заголовки, 5+ группы, затем мета, «Сумма» и =SUM строкой ниже.
    // Группа r0 должна занять 5 строк (у «Поставщик 1» их 5).
    final geometry = '''
import json
import openpyxl
wb = openpyxl.load_workbook(r"$out")
ws = wb["Заявка"]
header = next(r for r in range(1, ws.max_row + 1)
              if str(ws.cell(r, 1).value or "").strip() == "№ поз")
data_start = header + 1
meta = next((r for r in range(data_start, ws.max_row + 1)
             if str(ws.cell(r, 1).value or "").strip() == "Договор:"), None)
total = next((r for r in range(data_start, ws.max_row + 1)
              if str(ws.cell(r, 1).value or "").strip() == "Сумма"), None)
sum_row = total + 1 if total else None
sum_formula = ws.cell(sum_row, 10).value if sum_row else None
sheets = wb.sheetnames
hidden_row3 = ws.row_dimensions[3].hidden
b_merge = [str(m) for m in ws.merged_cells.ranges if str(m).startswith("B5:")]
print(json.dumps({"header": header, "meta": meta, "total": total,
                  "sum_row": sum_row, "sum_formula": sum_formula,
                  "sheets": sheets, "hidden_row3": hidden_row3,
                  "b_merge": b_merge}))
''';
    final res = await Process.run(python!, ['-c', geometry]);
    expect(res.exitCode, 0, reason: res.stderr.toString());
    final geo = jsonDecode((res.stdout as String).trim()) as Map<String, dynamic>;

    expect(geo['header'], 4);
    expect(geo['hidden_row3'], isTrue);
    expect(geo['sheets'], contains('Суммы'));
    // Группа первой позиции: 5 строк (max предложений по поставщикам).
    expect(geo['b_merge'], ['B5:B9']);
    // r0 — 5 строк, r1..r8 — по 1, все предложения привязаны →
    // данные 5..17, зона без привязки 18 (1 запасная строка), мета 19.
    expect(geo['meta'], 19);
    expect(geo['total'], 24); // meta + 5 мета-строк
    expect(geo['sum_row'], 25);
    // Блок поставщика 1: колонки 5..10, сумма — 10-я.
    expect(geo['sum_formula'], '=SUM(J5:J18)');
  });

  test('экспорт введённой цены пишет сумму формулой «цена × кол-во»',
      skip: skipReason, () async {
    final bridge = PythonBridge.create();
    final state = AppState(
      requestName: 'Цены',
      requestItems: const [RequestItem(id: 'r1', name: 'Болт', qty: '4')],
      suppliers: [
        SupplierBlock(
          id: 's1',
          displayName: 'Поставщик А',
          sourceFileNames: ['a.pdf'],
          offers: [
            // Введённая сумма: цена остаётся формулой =сумма/кол-во.
            const Offer(id: 'o1', itemName: 'Болт', qty: 4, unit: 'шт',
                sumWithVat: 122),
            // Введённая цена: пишется значением, сумма — формулой =цена*кол-во.
            const Offer(id: 'o2', itemName: 'Гайка', qty: 10, unit: 'шт')
                .withPriceInput(25, withoutVat: false),
          ],
        ),
      ],
    );

    final tmp = Directory.systemTemp.createTempSync('konkurent_price');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final out = p.join(tmp.path, 'out.xlsx');

    final export = await bridge.export(state, out);
    expect(export.ok, isTrue, reason: export.error);

    // Новая раскладка: блок с 5-й колонки (4 фиксированные), цена = 5+3,
    // сумма с НДС = 5+5; оба предложения непривязаны → зона без привязки,
    // строки 6 и 7 (5 — группа r1).
    final script = '''
import json
import openpyxl
wb = openpyxl.load_workbook(r"$out")
ws = wb["Заявка"]
print(json.dumps({
  "price_sum_driver": ws.cell(6, 8).value,
  "sum_sum_driver": ws.cell(6, 10).value,
  "price_price_driver": ws.cell(7, 8).value,
  "sum_price_driver": ws.cell(7, 10).value,
}))
''';
    final res = await Process.run(python!, ['-c', script]);
    expect(res.exitCode, 0, reason: res.stderr.toString());
    final cells = jsonDecode((res.stdout as String).trim()) as Map<String, dynamic>;

    expect(cells['price_sum_driver'], '=IFERROR(J6/F6,"")');
    expect(cells['sum_sum_driver'], 122);
    expect(cells['price_price_driver'], 25);
    expect(cells['sum_price_driver'], '=IFERROR(H7*F7,"")');
  });

  test('recognize извлекает название по юрформе и ИНН из docx',
      skip: skipReason, () async {
    final tmp = Directory.systemTemp.createTempSync('konkurent_docx');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final invoice = p.join(tmp.path, 'invoice.docx');

    final script = '''
from docx import Document
doc = Document()
doc.add_paragraph("СЧЁТ № 5 от 01.11.2026")
doc.add_paragraph("Общество с ограниченной ответственностью \\u00abРомашка Плюс\\u00bb")
doc.add_paragraph("ИНН 7707083893 / КПП 770701001")
table = doc.add_table(rows=3, cols=6)
rows = [["\\u2116", "Товар", "Кол-во", "Ед.", "Цена", "Сумма"],
        ["1", "Болт М8", "10", "шт", "50", "500"],
        ["2", "Гайка М8", "20", "шт", "10", "200"]]
for r, vals in enumerate(rows):
    for c, v in enumerate(vals):
        table.rows[r].cells[c].text = v
doc.save(r"$invoice")
''';
    final gen = await Process.run(python!, ['-c', script]);
    expect(gen.exitCode, 0, reason: gen.stderr.toString());

    // Пользовательский список юрформ.
    final forms = p.join(tmp.path, 'legal-forms.json');
    File(forms).writeAsStringSync(
        '["Общество с ограниченной ответственностью", "ООО", "ОАО", "АО", "ИП"]');

    final bridge = PythonBridge.create();
    final outcome = await bridge.recognize(invoice, legalFormsPath: forms);
    expect(outcome.ok, isTrue, reason: outcome.error);
    expect(outcome.supplier!.displayName, 'ООО «Ромашка Плюс»');
    expect(outcome.supplier!.inn, '7707083893');
    expect(outcome.supplier!.offers, hasLength(2));
    expect(outcome.supplier!.offers.first.itemName, 'Болт М8');
  });

  test('recognize читает отсканированный PDF через OCR', skip: skipReason,
      () async {
    // OCR требует системный tesseract (как Ghostscript для lattice).
    var tessOk = false;
    try {
      final r = await Process.run('tesseract', ['--version']);
      tessOk = r.exitCode == 0;
    } catch (_) {}
    if (!tessOk) {
      // markTestSkipped НЕ останавливает тело теста — обязательно return,
      // иначе Windows CI (без tesseract) фейлит помеченный тест.
      markTestSkipped('tesseract не найден в PATH — пропуск');
      return;
    }

    final tmp = Directory.systemTemp.createTempSync('konkurent_ocr');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final pdf = p.join(tmp.path, 'scan.pdf');

    // Синтетический «скан»: PIL рисует счёт с линейками и сохраняет
    // image-only PDF (без текстового слоя). Код 3 = нет кириллического
    // шрифта — скипаем, а не падаем (зависит от ОС).
    final script = '''
import glob, sys
cands = []
for pat in ("/usr/share/fonts/**/DejaVuSans.ttf",
            "/usr/share/fonts/**/LiberationSans-Regular.ttf",
            "C:/Windows/Fonts/arial.ttf", "C:/Windows/Fonts/calibri.ttf"):
    cands += glob.glob(pat, recursive=True)
if not cands:
    sys.exit(3)
from PIL import Image, ImageDraw, ImageFont
img = Image.new("RGB", (1000, 800), "white")
d = ImageDraw.Draw(img)
f = ImageFont.truetype(cands[0], 22)
d.text((40, 30), "ООО «Ромашка Плюс»", font=f, fill="black")
d.text((40, 70), "ИНН 7707083893 КПП 770501001", font=f, fill="black")
xs = [40, 110, 560, 690, 800, 950]
ys = [200, 270, 340, 410, 480]
for y in ys:
    d.rectangle([xs[0], y, xs[-1], y + 2], fill="black")
for x in xs:
    d.rectangle([x, ys[0], x + 2, ys[-1]], fill="black")
data = [["№", "Товар", "Кол-во", "Ед.", "Сумма"],
        ["1", "Болт М8", "10", "шт", "500"],
        ["2", "Гайка М8", "20", "шт", "200"]]
for r, row in enumerate(data):
    for c, cell in enumerate(row):
        d.text((xs[c] + 12, ys[r] + 14), cell, font=f, fill="black")
img.save(r"$pdf", resolution=72.0)
''';
    final gen = await Process.run(python!, ['-c', script]);
    if (gen.exitCode == 3) {
      markTestSkipped('кириллический шрифт не найден — пропуск');
      return;
    }
    expect(gen.exitCode, 0, reason: gen.stderr.toString());

    final bridge = PythonBridge.create();
    final outcome = await bridge.recognize(pdf);
    expect(outcome.ok, isTrue, reason: outcome.error);
    final sup = outcome.supplier!;
    expect(sup.inn, '7707083893');
    // КПП сайдкар отдаёт, но блок не хранит — проверяем его на уровне
    // engine-харнесса (ocr_eval).
    expect(sup.displayName, contains('Ромашка'));
    expect(sup.ocrUsed, isTrue, reason: 'скан должен помечаться как OCR');
    expect(sup.offers, hasLength(2));
    expect(sup.offers.first.qty, 10);
    expect(sup.offers.first.unit.toLowerCase(), 'шт');
    expect(sup.offers.first.sumWithVat, 500);
    expect(sup.offers[1].sumWithVat, 200);
  });
}