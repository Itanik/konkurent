import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:konkurent_app/models/app_state.dart';
import 'package:konkurent_app/providers/app_state_provider.dart';
import 'package:konkurent_app/providers/services.dart';
import 'package:konkurent_app/providers/zoom_provider.dart';
import 'package:konkurent_app/services/python_bridge.dart';
import 'package:konkurent_app/services/storage_service.dart';
import 'package:konkurent_app/ui/app.dart';
import 'package:konkurent_app/ui/comparison_table/comparison_table.dart';

/// Движок-заглушка: не запускает Python, отдаёт заданные ответы.
class FakeFileEngine implements FileEngine {
  FakeFileEngine({this.recognizeResult, this.importResult, this.exportResult});

  RecognizeOutcome? recognizeResult;
  ImportOutcome? importResult;
  ExportOutcome? exportResult;

  @override
  Future<RecognizeOutcome> recognize(String filePath) async =>
      recognizeResult ?? const RecognizeOutcome(ok: false, error: 'нет');

  @override
  Future<ImportOutcome> importFile(String filePath) async =>
      importResult ?? const ImportOutcome(status: ImportStatus.foreign);

  @override
  Future<ExportOutcome> export(AppState state, String outputPath) async =>
      exportResult ?? ExportOutcome(ok: true, path: outputPath);
}

Future<void> pumpApp(WidgetTester tester, {FakeFileEngine? engine}) async {
  tester.view.physicalSize = const Size(1600, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        fileEngineProvider.overrideWithValue(engine ?? FakeFileEngine()),
        storageServiceProvider.overrideWithValue(InMemoryStorageService()),
      ],
      child: const KonkurentApp(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tapCell(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder, warnIfMissed: false);
  await tester.pumpAndSettle();
}

ProviderContainer containerOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(ComparisonTable)));

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('smoke: пустая таблица и панель инструментов', (tester) async {
    await pumpApp(tester);
    expect(find.text('Таблица пуста'), findsOneWidget);
    expect(find.byKey(const ValueKey('toolbar.addSupplier')), findsOneWidget);
    expect(find.byKey(const ValueKey('toolbar.sort')), findsOneWidget);
    expect(find.byKey(const ValueKey('toolbar.save')), findsOneWidget);
  });

  testWidgets('кнопки масштаба меняют zoom', (tester) async {
    await pumpApp(tester);
    final container = containerOf(tester);
    expect(container.read(zoomProvider), 1.0);

    await tester.tap(find.byKey(const ValueKey('toolbar.zoomIn')));
    await tester.pumpAndSettle();
    expect(container.read(zoomProvider), closeTo(1.1, 1e-9));
    expect(find.text('110 %'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('toolbar.zoomReset')));
    await tester.pumpAndSettle();
    expect(container.read(zoomProvider), 1.0);
  });

  testWidgets('редактирование предложения сохраняется в состоянии',
      (tester) async {
    await pumpApp(tester);
    final container = containerOf(tester);

    container.read(appStateProvider.notifier).addSupplier(
          SupplierBlock(
            id: 's1',
            displayName: 'А',
            offers: const [
              Offer(id: 'o1', itemName: 'Болт', qty: 10, unit: 'шт', sumWithVat: 1000),
            ],
          ),
        );
    await tester.pumpAndSettle();
    expect(find.text('Болт'), findsWidgets);

    await tapCell(tester, 'offer.o1.item');
    await tester.enterText(
        find.byKey(const ValueKey('offer.o1.item.field')), 'Гайка');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    final offer = container
        .read(appStateProvider)
        .suppliers
        .first
        .offers
        .first;
    expect(offer.itemName, 'Гайка');
  });

  testWidgets('цена за единицу пересчитывается автоматически', (tester) async {
    await pumpApp(tester);
    final container = containerOf(tester);

    container.read(appStateProvider.notifier).addSupplier(
          const SupplierBlock(
            id: 's1',
            displayName: 'А',
            offers: [
              Offer(id: 'o1', itemName: 'Болт', qty: 4, sumWithVat: 100),
            ],
          ),
        );
    await tester.pumpAndSettle();

    await tapCell(tester, 'offer.o1.qty');
    await tester.enterText(find.byKey(const ValueKey('offer.o1.qty.field')), '8');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text('12.50'), findsOneWidget);
  });

  testWidgets('сортировка по сумме переставляет блоки', (tester) async {
    await pumpApp(tester);
    final container = containerOf(tester);

    final notifier = container.read(appStateProvider.notifier);
    notifier.addSupplier(const SupplierBlock(
      id: 's1',
      displayName: 'Дорогой',
      offers: [Offer(id: 'o1', itemName: 'x', sumWithVat: 500)],
    ));
    notifier.addSupplier(const SupplierBlock(
      id: 's2',
      displayName: 'Дешёвый',
      offers: [Offer(id: 'o2', itemName: 'x', sumWithVat: 100)],
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('toolbar.sort')));
    await tester.pumpAndSettle();

    final order =
        container.read(appStateProvider).suppliers.map((s) => s.id).toList();
    expect(order, ['s2', 's1']);
  });

  testWidgets('добавление поставщика кнопкой создаёт колонку', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const ValueKey('toolbar.addSupplier')));
    await tester.pumpAndSettle();

    expect(containerOf(tester).read(appStateProvider).suppliers, hasLength(1));
    expect(find.text('Предложено'), findsOneWidget);
    expect(find.text('Сумма'), findsOneWidget);
  });

  testWidgets('распознанный файл создаёт блок поставщика', (tester) async {
    final engine = FakeFileEngine(
      recognizeResult: RecognizeOutcome(
        ok: true,
        supplier: SupplierBlock(
          id: 'recognized',
          displayName: 'Ромашка',
          sourceFileName: 'invoice.pdf',
          offers: const [
            Offer(id: 'r1', itemName: 'Болт', qty: 1, sumWithVat: 100),
          ],
        ),
      ),
    );
    await pumpApp(tester, engine: engine);

    // Эмулируем вызов обработки файла через провайдер движка.
    final container = containerOf(tester);
    final outcome = await container.read(fileEngineProvider).recognize('x.pdf');
    container.read(appStateProvider.notifier).addSupplier(outcome.supplier!);
    await tester.pumpAndSettle();

    expect(find.text('Ромашка'), findsWidgets);
    expect(find.text('Болт'), findsWidgets);
  });

  testWidgets('drag предложения меняет порядок внутри блока', (tester) async {
    await pumpApp(tester);
    final container = containerOf(tester);

    container.read(appStateProvider.notifier).addSupplier(
          const SupplierBlock(
            id: 's1',
            displayName: 'А',
            offers: [
              Offer(id: 'o1', itemName: 'Первый'),
              Offer(id: 'o2', itemName: 'Второй'),
              Offer(id: 'o3', itemName: 'Третий'),
            ],
          ),
        );
    await tester.pumpAndSettle();

    final from = find.byKey(const ValueKey('offer.o3.handle'));
    final to = find.byKey(const ValueKey('offer.o1.handle'));
    final gesture = await tester.startGesture(tester.getCenter(from));
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveTo(tester.getCenter(to));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      container
          .read(appStateProvider)
          .suppliers
          .first
          .offers
          .map((o) => o.id)
          .toList(),
      ['o3', 'o1', 'o2'],
    );
  });

  testWidgets('drag блока меняет порядок поставщиков', (tester) async {
    await pumpApp(tester);
    final container = containerOf(tester);

    final notifier = container.read(appStateProvider.notifier);
    notifier.addSupplier(const SupplierBlock(
      id: 's1',
      displayName: 'Первый',
      offers: [Offer(id: 'a1', itemName: 'x')],
    ));
    notifier.addSupplier(const SupplierBlock(
      id: 's2',
      displayName: 'Второй',
      offers: [Offer(id: 'b1', itemName: 'y')],
    ));
    await tester.pumpAndSettle();

    final from = find.byKey(const ValueKey('supplier.s2.handle'));
    final to = find.byKey(const ValueKey('supplier.s1.handle'));
    final gesture = await tester.startGesture(tester.getCenter(from));
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveTo(tester.getCenter(to));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      container.read(appStateProvider).suppliers.map((s) => s.id).toList(),
      ['s2', 's1'],
    );
  });

  testWidgets('Ctrl+V вставляет список позиций заявки', (tester) async {
    await pumpApp(tester);
    final container = containerOf(tester);

    await Clipboard.setData(const ClipboardData(
      text: 'Шпоночный материал 4х4, 5 м.п.\n'
          'Шпоночный материал 5х5, 5 м.п.\n'
          'Труба б/ш 27х4, 20 м.п.',
    ));

    await tapCell(tester, 'fixed.item.0.name');
    await sendPaste(tester);

    final items = container.read(appStateProvider).requestItems;
    expect(items, hasLength(3));
    expect(items[0].name, 'Шпоночный материал 4х4');
    expect(items[0].qty, '5 м.п.');
    expect(items[2].name, 'Труба б/ш 27х4');
    expect(items[2].qty, '20 м.п.');
  });

  testWidgets('кнопка «Вставить список» заполняет позиции заявки', (tester) async {
    await pumpApp(tester);
    final container = containerOf(tester);

    await Clipboard.setData(const ClipboardData(text: 'Позиция A\nПозиция B\nПозиция C'));
    await tester.tap(find.byKey(const ValueKey('fixed.pasteRequestItems')));
    await tester.pumpAndSettle();

    final items = container.read(appStateProvider).requestItems;
    expect(items.map((e) => e.name).toList(), ['Позиция A', 'Позиция B', 'Позиция C']);
  });

  testWidgets('Ctrl+V вставляет список в «Предложено» поставщика',
      (tester) async {
    await pumpApp(tester);
    final container = containerOf(tester);

    container.read(appStateProvider.notifier).addSupplier(
          const SupplierBlock(
            id: 's1',
            displayName: 'А',
            offers: [Offer(id: 'o1', itemName: '')],
          ),
        );
    await tester.pumpAndSettle();

    await Clipboard.setData(
        const ClipboardData(text: 'Болт\nГайка\nШайба'));
    await tapCell(tester, 'offer.o1.item');
    await sendPaste(tester);

    final offers = container.read(appStateProvider).suppliers.first.offers;
    expect(offers.map((o) => o.itemName).toList(), ['Болт', 'Гайка', 'Шайба']);
  });

  testWidgets('ввод в пустую строку создаёт предложение', (tester) async {
    await pumpApp(tester);
    final container = containerOf(tester);

    container
        .read(appStateProvider.notifier)
        .addSupplier(const SupplierBlock(id: 's1', displayName: 'А'));
    await tester.pumpAndSettle();

    await tapCell(tester, 'offer.empty.s1.0.item');
    await tester.enterText(
        find.byKey(const ValueKey('offer.empty.s1.0.item.field')), 'Новая');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    final offers = container.read(appStateProvider).suppliers.first.offers;
    expect(offers, hasLength(1));
    expect(offers.first.itemName, 'Новая');
  });

  testWidgets('drag предложения вниз меняет порядок', (tester) async {
    await pumpApp(tester);
    final container = containerOf(tester);

    container.read(appStateProvider.notifier).addSupplier(
          const SupplierBlock(
            id: 's1',
            displayName: 'А',
            offers: [
              Offer(id: 'o1', itemName: '1'),
              Offer(id: 'o2', itemName: '2'),
              Offer(id: 'o3', itemName: '3'),
            ],
          ),
        );
    await tester.pumpAndSettle();

    await dragTo(tester, 'offer.o1.handle', 'offer.o3.handle');
    expect(
      container.read(appStateProvider).suppliers.first.offers.map((o) => o.id),
      ['o2', 'o3', 'o1'],
    );
  });

  testWidgets('drag блока вниз меняет порядок поставщиков', (tester) async {
    await pumpApp(tester);
    final container = containerOf(tester);

    final notifier = container.read(appStateProvider.notifier);
    notifier.addSupplier(const SupplierBlock(
      id: 's1',
      displayName: 'Первый',
      offers: [Offer(id: 'a1', itemName: 'x')],
    ));
    notifier.addSupplier(const SupplierBlock(
      id: 's2',
      displayName: 'Второй',
      offers: [Offer(id: 'b1', itemName: 'y')],
    ));
    await tester.pumpAndSettle();

    await dragTo(tester, 'supplier.s1.handle', 'supplier.s2.handle');
    expect(
      container.read(appStateProvider).suppliers.map((s) => s.id).toList(),
      ['s2', 's1'],
    );
  });

  testWidgets('drag заполненной строки на пустую оставляет пробел',
      (tester) async {
    await pumpApp(tester);
    final container = containerOf(tester);

    container.read(appStateProvider.notifier).addSupplier(
          const SupplierBlock(
            id: 's1',
            displayName: 'А',
            offers: [
              Offer(id: 'o1', itemName: '1'),
              Offer(id: 'o2', itemName: '2'),
            ],
          ),
        );
    await tester.pumpAndSettle();

    // Запасная пустая строка — третья (index 2).
    await dragTo(tester, 'offer.o1.handle', 'offerRow.s1.2');

    final offers = container.read(appStateProvider).suppliers.first.offers;
    expect(offers, hasLength(3));
    expect(offers[0].isEmpty, isTrue);
    expect(offers[1].id, 'o2');
    expect(offers[2].id, 'o1');
  });
}

Future<void> dragTo(
    WidgetTester tester, String fromKey, String toKey) async {
  final from = find.byKey(ValueKey(fromKey));
  final to = find.byKey(ValueKey(toKey));
  final gesture = await tester.startGesture(tester.getCenter(from));
  await tester.pump(const Duration(milliseconds: 50));
  await gesture.moveTo(tester.getCenter(to));
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

Future<void> sendPaste(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}