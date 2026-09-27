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

  test('reorderSuppliers двигает блок вниз (на соседний/через один)', () {
    notifier().addSupplier(block('s1', 'A', [100]));
    notifier().addSupplier(block('s2', 'B', [200]));
    notifier().addSupplier(block('s3', 'C', [300]));
    notifier().reorderSuppliers(0, 1);
    expect(state().suppliers.map((s) => s.id).toList(), ['s2', 's1', 's3']);
    notifier().reorderSuppliers(0, 2);
    expect(state().suppliers.map((s) => s.id).toList(), ['s1', 's3', 's2']);
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

  test('reorderOffers двигает строку вниз', () {
    notifier().addSupplier(block('s1', 'A', [100, 200, 300]));
    notifier().reorderOffers('s1', 0, 1);
    expect(state().suppliers.first.offers.map((o) => o.id).toList(),
        ['s1-o1', 's1-o0', 's1-o2']);
    notifier().reorderOffers('s1', 0, 2);
    expect(state().suppliers.first.offers.map((o) => o.id).toList(),
        ['s1-o0', 's1-o2', 's1-o1']);
  });

  test('reorderOffers не трогает другие блоки', () {
    notifier().addSupplier(block('s1', 'A', [100, 200]));
    notifier().addSupplier(block('s2', 'B', [300, 400]));
    notifier().reorderOffers('s1', 1, 0);
    expect(state().suppliers[1].offers.map((o) => o.id).toList(),
        ['s2-o0', 's2-o1']);
  });

  test('moveOfferToEmpty меняет заполненную строку с пустой, оставляя пробел',
      () {
    notifier().addSupplier(block('s1', 'A', [100, 200]));
    notifier().moveOfferToEmpty('s1', 0, 2);
    final offers = state().suppliers.first.offers;
    expect(offers, hasLength(3));
    expect(offers[0].isEmpty, isTrue);
    expect(offers[1].itemName, 'item 1');
    expect(offers[2].itemName, 'item 0');
  });

  test('moveOfferToEmpty в существующий пробел', () {
    notifier().addSupplier(block('s1', 'A', [100, 200, 300]));
    notifier().moveOfferToEmpty('s1', 0, 3); // [пусто, item1, item2, item0]
    expect(state().suppliers.first.offers[0].isEmpty, isTrue);
    expect(state().suppliers.first.offers[3].itemName, 'item 0');

    notifier().moveOfferToEmpty('s1', 2, 0); // item2 на пробел сверху
    expect(state().suppliers.first.offers.map((o) => o.itemName).toList(),
        ['item 2', 'item 1', '', 'item 0']);
  });

  test('setOfferAt изменяет предложение по индексу', () {
    notifier().addSupplier(block('s1', 'A', [100]));
    notifier().setOfferAt('s1', 0, (o) => o.copyWith(itemName: 'new'));
    expect(state().suppliers.first.offers.first.itemName, 'new');
  });

  test('setOfferAt создаёт предложение в пустой строке', () {
    notifier().addSupplier(SupplierBlock(id: 's1', displayName: 'A'));
    notifier().setOfferAt('s1', 0, (o) => o.copyWith(itemName: 'X'));
    expect(state().suppliers.first.offers, hasLength(1));
    expect(state().suppliers.first.offers.first.itemName, 'X');
  });

  test('updateRequestItem расширяет список при пропуске', () {
    notifier().updateRequestItem(2, name: 'Поз', qty: '5');
    expect(state().requestItems, hasLength(3));
    expect(state().requestItems[2].name, 'Поз');
    expect(state().requestItems[2].qty, '5');
  });

  test('removeOfferAt удаляет строку по индексу', () {
    notifier().addSupplier(block('s1', 'A', [100, 200]));
    notifier().removeOfferAt('s1', 0);
    expect(state().suppliers.first.offers.map((o) => o.itemName).toList(),
        ['item 1']);
  });

  test('очистка последней строки схлопывает «хвост»', () {
    notifier().addSupplier(block('s1', 'A', [100]));
    notifier().setOfferAt('s1', 0, (o) => Offer(id: o.id));
    expect(state().suppliers.first.offers, isEmpty);

    notifier().updateRequestItem(0, name: 'A');
    notifier().updateRequestItem(0, name: '');
    expect(state().requestItems, isEmpty);
  });

  test('maxRows растёт при добавлении предложений', () {
    notifier().addSupplier(block('s1', 'A', [100, 200]));
    notifier().setOfferAt('s1', 2, (o) => o.copyWith(itemName: 'X'));
    expect(state().maxRows, 3);
  });

  test('pasteRequestItems перезаписывает и доращивает, хвост не трогает', () {
    notifier().updateRequestItem(0, name: 'Старое', qty: '1');
    notifier().updateRequestItem(1, name: 'Второе', qty: '2');
    notifier().updateRequestItem(2, name: 'Хвост', qty: '3');

    notifier().pasteRequestItems(0, const [
      RequestItem(id: 'p1', name: 'A', qty: '10'),
      RequestItem(id: 'p2', name: 'B', qty: '20'),
      RequestItem(id: 'p3', name: 'C', qty: '30'),
      RequestItem(id: 'p4', name: 'D', qty: '40'),
    ]);

    final items = state().requestItems;
    expect(items, hasLength(4));
    expect(items.map((e) => e.name).toList(), ['A', 'B', 'C', 'D']);
    expect(items[0].qty, '10');
  });

  test('pasteRequestItems с непустого индекса заполняет пропуски', () {
    notifier().pasteRequestItems(2, const [
      RequestItem(id: 'p1', name: 'X', qty: ''),
    ]);
    final items = state().requestItems;
    expect(items, hasLength(3));
    expect(items[0].name, '');
    expect(items[2].name, 'X');
  });

  test('pasteOffers заполняет только названия и доращивает список', () {
    notifier().addSupplier(block('s1', 'A', [100]));
    notifier().pasteOffers('s1', 0, const [
      RequestItem(id: 'p1', name: 'X', qty: '1'),
      RequestItem(id: 'p2', name: 'Y', qty: '2'),
      RequestItem(id: 'p3', name: 'Z', qty: '3'),
    ]);
    final offers = state().suppliers.first.offers;
    expect(offers, hasLength(3));
    expect(offers.map((o) => o.itemName).toList(), ['X', 'Y', 'Z']);
    expect(offers.first.qty, isNull);
  });
}