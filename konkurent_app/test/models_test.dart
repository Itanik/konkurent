import 'package:flutter_test/flutter_test.dart';
import 'package:konkurent_app/models/app_state.dart';

void main() {
  group('Offer', () {
    test('pricePerUnit вычисляется, не хранится', () {
      const offer = Offer(id: 'o1', qty: 4, sumWithVat: 100);
      expect(offer.pricePerUnit, 25);
    });

    test('pricePerUnit null при нулевом количестве или отсутствии суммы', () {
      expect(const Offer(id: 'o1', qty: 0, sumWithVat: 100).pricePerUnit, isNull);
      expect(const Offer(id: 'o1', qty: 4).pricePerUnit, isNull);
      expect(const Offer(id: 'o1', sumWithVat: 100).pricePerUnit, isNull);
    });

    test('copyWith clearQty обнуляет значение', () {
      const offer = Offer(id: 'o1', qty: 4);
      expect(offer.copyWith(clearQty: true).qty, isNull);
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
      expect(block.total, 350);
      expect(block.hasAnySum, isTrue);
    });

    test('hasAnySum false без сумм', () {
      final block = SupplierBlock(id: 's1', offers: const [Offer(id: 'o1')]);
      expect(block.hasAnySum, isFalse);
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