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
          sourceFileName: 'a.pdf',
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
          sourceFileName: 'b.pdf',
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
}