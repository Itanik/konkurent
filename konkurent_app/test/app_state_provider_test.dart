import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:konkurent_app/models/app_state.dart';
import 'package:konkurent_app/providers/app_state_provider.dart';

SupplierBlock block(String id, String name, List<double?> sums) {
  return SupplierBlock(
    id: id,
    displayName: name,
    offers: [
      for (var i = 0; i < sums.length; i++)
        Offer(id: '$id-o$i', itemName: 'item $i', sumWithVat: sums[i]),
    ],
  );
}

void main() {
  late ProviderContainer container;
  AppStateNotifier notifier() => container.read(appStateProvider.notifier);
  AppState state() => container.read(appStateProvider);

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
  });

  test('addSupplier / removeSupplier', () {
    notifier().addSupplier(block('s1', 'A', [100]));
    expect(state().suppliers, hasLength(1));
    notifier().removeSupplier('s1');
    expect(state().suppliers, isEmpty);
  });

  test('reorderSuppliers двигает блок на новую позицию', () {
    notifier().addSupplier(block('s1', 'A', [100]));
    notifier().addSupplier(block('s2', 'B', [200]));
    notifier().addSupplier(block('s3', 'C', [300]));
    notifier().reorderSuppliers(2, 0);
    expect(state().suppliers.map((s) => s.id).toList(), ['s3', 's1', 's2']);
  });

  test('sortSuppliersByTotal: слева самый выгодный, без сумм — в конце', () {
    notifier().addSupplier(block('s1', 'A', [300]));
    notifier().addSupplier(block('s2', 'B', [100]));
    notifier().addSupplier(block('s3', 'C', [null]));
    notifier().addSupplier(block('s4', 'D', [200]));
    notifier().sortSuppliersByTotal();
    expect(state().suppliers.map((s) => s.id).toList(),
        ['s2', 's4', 's1', 's3']);
  });

  test('reorderOffers внутри блока', () {
    notifier().addSupplier(block('s1', 'A', [100, 200, 300]));
    notifier().reorderOffers('s1', 2, 0);
    final ids = state().suppliers.first.offers.map((o) => o.id).toList();
    expect(ids, ['s1-o2', 's1-o0', 's1-o1']);
  });

  test('reorderOffers не трогает другие блоки', () {
    notifier().addSupplier(block('s1', 'A', [100, 200]));
    notifier().addSupplier(block('s2', 'B', [300, 400]));
    notifier().reorderOffers('s1', 1, 0);
    expect(state().suppliers[1].offers.map((o) => o.id).toList(),
        ['s2-o0', 's2-o1']);
  });

  test('updateOffer сохраняет изменения по id', () {
    notifier().addSupplier(block('s1', 'A', [100]));
    final offer = state().suppliers.first.offers.first;
    notifier().updateOffer('s1', offer.copyWith(itemName: 'new'));
    expect(state().suppliers.first.offers.first.itemName, 'new');
  });

  test('updateRequestItem расширяет список при пропуске', () {
    notifier().updateRequestItem(2, name: 'Поз', qty: '5');
    expect(state().requestItems, hasLength(3));
    expect(state().requestItems[2].name, 'Поз');
    expect(state().requestItems[2].qty, '5');
  });

  test('removeOffer оставляет минимум одну строку', () {
    notifier().addSupplier(block('s1', 'A', [100]));
    final id = state().suppliers.first.offers.first.id;
    notifier().removeOffer('s1', id);
    expect(state().suppliers.first.offers, hasLength(1));
    expect(state().suppliers.first.offers.first.itemName, '');
  });

  test('maxRows растёт при добавлении предложений', () {
    notifier().addSupplier(block('s1', 'A', [100, 200]));
    notifier().addOffer('s1');
    expect(state().maxRows, 3);
  });
}