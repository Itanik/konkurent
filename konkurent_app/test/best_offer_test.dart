import 'package:flutter_test/flutter_test.dart';
import 'package:konkurent_app/models/app_state.dart';
import 'package:konkurent_app/services/best_offer.dart';

void main() {
  const vat = 0.0; // для простоты подсчёта суммы

  AppState fixture() {
    return AppState(
      requestItems: [
        const RequestItem(id: 'item-1', name: 'Болт', qty: '10'),
        const RequestItem(id: 'item-2', name: 'Гайка', qty: '10'),
        const RequestItem(id: 'item-3', name: 'Шайба', qty: '10'),
      ],
      suppliers: [
        // Дешёвый на болты, дорогой на остальное.
        SupplierBlock(
          id: 's1',
          displayName: 'А',
          offers: [
            const Offer(id: 'o1', itemName: 'Болт', qty: 10, sumWithVat: 100,
                linkedRequestItemId: 'item-1'),
            const Offer(id: 'o2', itemName: 'Гайка', qty: 10, sumWithVat: 500,
                linkedRequestItemId: 'item-2'),
            const Offer(id: 'o3', itemName: 'Шайба', qty: 10, sumWithVat: 500,
                linkedRequestItemId: 'item-3'),
          ],
        ),
        // Дорогой на болты, дешёвый на гайки+шайбы.
        SupplierBlock(
          id: 's2',
          displayName: 'Б',
          offers: [
            const Offer(id: 'o4', itemName: 'Болт', qty: 10, sumWithVat: 300,
                linkedRequestItemId: 'item-1'),
            const Offer(id: 'o5', itemName: 'Гайка', qty: 10, sumWithVat: 150,
                linkedRequestItemId: 'item-2'),
            const Offer(id: 'o6', itemName: 'Шайба', qty: 10, sumWithVat: 150,
                linkedRequestItemId: 'item-3'),
          ],
        ),
      ],
    );
  }

  test('k=1: лучший одиночный поставщик по сумме', () {
    final variants = bestProcurementVariants(fixture(),
        vat: vat, maxSuppliers: 2);
    final k1 = variants.first;
    expect(k1.supplierIds, ['s2'], reason: 'Б = 600 < А = 1100');
    expect(k1.total, 600);
    expect(k1.coverageSuffix, '');
  });

  test('k=2: комбинированный вариант дешевле одиночных', () {
    final variants = bestProcurementVariants(fixture(),
        vat: vat, maxSuppliers: 2);
    final k2 = variants.last;
    expect(k2.supplierIds, ['s1', 's2']);
    // Болты у А (100) + гайки и шайбы у Б (150+150).
    expect(k2.total, 400);
    expect(k2.picks[0], 0);
    expect(k2.picks[1], 1);
    expect(k2.picks[2], 1);
  });

  test('позиция без предложений не блокирует покрытие', () {
    final state = AppState(
      requestItems: [
        const RequestItem(id: 'a', name: 'Есть'),
        const RequestItem(id: 'b', name: 'Нет в счетах'),
      ],
      suppliers: [
        SupplierBlock(
          id: 's1',
          offers: [
            const Offer(id: 'o1', itemName: 'Есть', qty: 1, sumWithVat: 50,
                linkedRequestItemId: 'a'),
          ],
        ),
      ],
    );
    final variants = bestProcurementVariants(state, vat: vat, maxSuppliers: 3);
    expect(variants, hasLength(1));
    expect(variants.first.covered, 1);
    expect(variants.first.totalItems, 2);
    expect(variants.first.coverageSuffix, contains('покрыто 1/2'));
  });

  test('maxSuppliers ограничивает размер комбинаций', () {
    final variants =
        bestProcurementVariants(fixture(), vat: vat, maxSuppliers: 1);
    expect(variants, hasLength(1));
  });

  test('нет привязанных предложений — пустой список', () {
    expect(
        bestProcurementVariants(const AppState(), vat: vat, maxSuppliers: 3),
        isEmpty);
  });
}
