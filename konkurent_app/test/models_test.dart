import 'package:flutter_test/flutter_test.dart';
import 'package:konkurent_app/models/app_state.dart';

void main() {
  const vat = 0.22;

  group('Offer', () {
    test('цена вычисляется из суммы, не хранится (driver=sum)', () {
      const offer = Offer(id: 'o1', qty: 4, sumWithVat: 100);
      expect(offer.displayPrice(withoutVat: false, vat: vat), 25);
    });

    test('цена null при нулевом количестве или отсутствии суммы', () {
      expect(
          const Offer(id: 'o1', qty: 0, sumWithVat: 100)
              .displayPrice(withoutVat: false, vat: vat),
          isNull);
      expect(
          const Offer(id: 'o1', qty: 4)
              .displayPrice(withoutVat: false, vat: vat),
          isNull);
      expect(
          const Offer(id: 'o1', sumWithVat: 100)
              .displayPrice(withoutVat: false, vat: vat),
          isNull);
    });

    test('copyWith clearQty обнуляет значение', () {
      const offer = Offer(id: 'o1', qty: 4);
      expect(offer.copyWith(clearQty: true).qty, isNull);
    });

    test('правка суммы сбрасывает цену; обратная сторона выводится через НДС',
        () {
      const offer = Offer(id: 'o1', qty: 4, priceWithVat: 25);
      final edited = offer.withSumInput(122, withoutVat: false, vat: vat);
      expect(edited.priceDriver, PriceDriver.sum);
      expect(edited.sumWithVat, 122);
      expect(edited.sumWithoutVat, isNull); // выводится на лету
      expect(edited.priceWithVat, isNull);
      expect(edited.displayPrice(withoutVat: false, vat: vat), closeTo(30.5, 1e-9));
      expect(edited.displaySum(withoutVat: true, vat: vat), closeTo(100, 1e-9));
    });

    test('правка цены переключает водителя, сумма вычисляется', () {
      const offer = Offer(id: 'o1', qty: 4, sumWithVat: 100);
      final edited = offer.withPriceInput(30, withoutVat: false);
      expect(edited.priceDriver, PriceDriver.price);
      expect(edited.priceWithVat, 30);
      expect(edited.sumWithVat, isNull);
      expect(edited.displaySum(withoutVat: false, vat: vat), closeTo(120, 1e-9));
      expect(edited.displayPrice(withoutVat: false, vat: vat), 30);
    });

    test('обе стороны всегда согласованы через ставку НДС', () {
      // Введена цена без НДС — с НДС выводится производной.
      final net = Offer(id: 'o1', qty: 10)
          .withPriceInput(50, withoutVat: true);
      expect(net.displaySum(withoutVat: true, vat: vat), 500);
      expect(net.displaySum(withoutVat: false, vat: vat), closeTo(610, 1e-9));

      // Введена сумма с НДС — без НДС выводится производной.
      const gross = Offer(id: 'o2', qty: 10, sumWithVat: 1220);
      expect(gross.displaySum(withoutVat: true, vat: vat), closeTo(1000, 1e-9));
      expect(
          gross.displayPrice(withoutVat: true, vat: vat), closeTo(100, 1e-9));
    });

    test('смена количества пересчитывает производную величину', () {
      final offer = Offer(id: 'o1', qty: 4, sumWithVat: 100)
          .withPriceInput(30, withoutVat: false);
      final grown = offer.copyWith(qty: 10);
      expect(grown.displaySum(withoutVat: false, vat: vat), closeTo(300, 1e-9));

      const sumOffer = Offer(id: 'o2', qty: 4, sumWithVat: 100);
      expect(
          sumOffer.copyWith(qty: 10).displayPrice(withoutVat: false, vat: vat),
          10);
    });

    test('базис «без НДС»: правка суммы пишет в сумму без НДС', () {
      const offer = Offer(id: 'o1', qty: 4);
      final edited = offer.withSumInput(100, withoutVat: true, vat: vat);
      expect(edited.sumWithoutVat, 100);
      expect(edited.sumWithVat, isNull);
      expect(edited.displaySum(withoutVat: true, vat: vat), 100);
    });

    test('vatMoveGrossToNet: значения переезжают на «без НДС», с НДС пересчитывается', () {
      const offer = Offer(id: 'o1', qty: 4, sumWithVat: 122);
      final moved = offer.vatMoveGrossToNet(vat);
      expect(moved.sumWithoutVat, 122);        // «перекинутое» значение
      expect(moved.sumWithVat, closeTo(148.84, 1e-9)); // 122 × 1.22
      expect(moved.displaySum(withoutVat: false, vat: vat), closeTo(148.84, 1e-9));

      final priced = Offer(id: 'o2', qty: 4)
          .withPriceInput(100, withoutVat: false)
          .vatMoveGrossToNet(vat);
      expect(priced.priceWithoutVat, 100);
      expect(priced.priceWithVat, closeTo(122, 1e-9));
    });

    test('vatMoveValues: перенос значений при смене флажка (в обе стороны)', () {
      const offer = Offer(id: 'o1', qty: 4, sumWithVat: 100);
      final toNet = offer.vatMoveValues(toNet: true);
      expect(toNet.sumWithoutVat, 100);
      expect(toNet.sumWithVat, isNull);
      expect(toNet.displaySum(withoutVat: true, vat: vat), 100);
      // Обратно — значение возвращается без искажения.
      final back = toNet.vatMoveValues(toNet: false);
      expect(back.sumWithVat, 100);
      expect(back.displaySum(withoutVat: false, vat: vat), 100);
    });

    test('пустая строка учитывает цены', () {
      expect(const Offer(id: 'o1').isEmpty, isTrue);
      expect(const Offer(id: 'o1', priceWithVat: 5).isEmpty, isFalse);
    });
  });

  group('SupplierMeta', () {
    test('value и copyWithValue по ключу', () {
      const meta = SupplierMeta();
      final updated = meta.copyWithValue('contract', 'Д-1');
      expect(updated.value('contract'), 'Д-1');
      expect(updated.value('delivery'), '');
    });
  });

  group('SupplierBlock', () {
    test('total — сумма сумм с НДС', () {
      final block = SupplierBlock(
        id: 's1',
        offers: const [
          Offer(id: 'o1', sumWithVat: 100),
          Offer(id: 'o2', sumWithVat: 250),
          Offer(id: 'o3'),
        ],
      );
      expect(block.total(vat), 350);
      expect(block.hasAnySum(vat), isTrue);
    });

    test('hasAnySum false без сумм', () {
      final block = SupplierBlock(id: 's1', offers: const [Offer(id: 'o1')]);
      expect(block.hasAnySum(vat), isFalse);
    });

    test('без НДС: total складывает суммы без НДС и вычисленные из цены', () {
      final block = SupplierBlock(
        id: 's1',
        withoutVat: true,
        offers: [
          const Offer(id: 'o1', qty: 2, sumWithoutVat: 100),
          Offer(id: 'o2', qty: 3)
              .withPriceInput(10, withoutVat: true), // 10 * 3 = 30
        ],
      );
      expect(block.total(vat), closeTo(130, 1e-9));
      expect(block.hasAnySum(vat), isTrue);
    });

    test('ИНН сохраняется и чистится через copyWith', () {
      final block = SupplierBlock(id: 's1', inn: '7707083893');
      expect(block.inn, '7707083893');
      expect(block.copyWith(clearInn: true).inn, isNull);
    });

    test('JSON round-trip ИНН и без НДС', () {
      final block = SupplierBlock(id: 's1', inn: '1234567890', withoutVat: true);
      final restored = SupplierBlock.fromJson(block.toJson());
      expect(restored.inn, '1234567890');
      expect(restored.withoutVat, isTrue);
    });
  });

  group('AppState.maxRows', () {
    test('равен максимуму предложений или позиций заявки', () {
      final state = AppState(
        requestItems: [
          const RequestItem(id: 'r1', name: 'A'),
          const RequestItem(id: 'r2', name: 'B'),
        ],
        suppliers: [
          SupplierBlock(id: 's1', offers: const [
            Offer(id: 'o1'),
            Offer(id: 'o2'),
            Offer(id: 'o3'),
          ]),
          SupplierBlock(id: 's2', offers: const [Offer(id: 'o4')]),
        ],
      );
      expect(state.maxRows, 3);
    });

    test('минимум одна строка даже на пустой таблице', () {
      expect(const AppState().maxRows, 1);
    });
  });

  group('JSON round-trip', () {
    test('полное состояние сохраняется и восстанавливается', () {
      final state = AppState(
        requestName: 'Заявка №1',
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
                sumWithoutVat: 1000,
              ),
            ],
          ),
        ],
      );

      final restored = AppState.fromJson(state.toJson());
      expect(restored.requestName, 'Заявка №1');
      expect(restored.requestItems.first.name, 'Болт');
      expect(restored.suppliers.first.displayName, 'Поставщик А');
      expect(restored.suppliers.first.meta.contract, 'Д-1');
      expect(restored.suppliers.first.offers.first.sumWithVat, 1200);
      expect(restored.suppliers.first.offers.first.sumWithoutVat, 1000);
    });
  });
}