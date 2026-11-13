import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:konkurent_app/models/app_state.dart';
import 'package:konkurent_app/providers/app_state_provider.dart';
import 'package:konkurent_app/providers/table_layout_provider.dart';

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

  test('updateOffer меняет предложение по id', () {
    notifier().addSupplier(block('s1', 'A', [100]));
    notifier().updateOffer('s1', 's1-o0', (o) => o.copyWith(itemName: 'new'));
    expect(state().suppliers.first.offers.first.itemName, 'new');
  });

  test('updateOffer: очистка последней строки схлопывает хвост', () {
    notifier().addSupplier(block('s1', 'A', [100]));
    notifier().updateOffer('s1', 's1-o0', (o) => Offer(id: o.id));
    expect(state().suppliers.first.offers, isEmpty);
  });

  test('removeOfferById удаляет строку', () {
    notifier().addSupplier(block('s1', 'A', [100, 200]));
    notifier().removeOfferById('s1', 's1-o0');
    expect(state().suppliers.first.offers.map((o) => o.itemName).toList(),
        ['item 1']);
  });

  test('createOfferAt создаёт привязанное предложение в конце группы', () {
    notifier().addSupplier(block('s1', 'A', []));
    notifier().updateRequestItem(0, name: 'Болт');
    final rid = state().requestItems.first.id;
    notifier().createOfferAt('s1', rid, (o) => o.copyWith(itemName: 'X'));
    final offers = state().suppliers.first.offers;
    expect(offers, hasLength(1));
    expect(offers.first.itemName, 'X');
    expect(offers.first.linkedRequestItemId, rid);
  });

  test('createOfferAt: зона без привязки — предложение без связи', () {
    notifier().addSupplier(block('s1', 'A', [100]));
    notifier().createOfferAt('s1', null, (o) => o.copyWith(itemName: 'Y'));
    expect(state().suppliers.first.offers.last.linkedRequestItemId, isNull);
  });

  // --- привязка ---------------------------------------------------------------

  test('linkOffer привязывает и отвязывает', () {
    notifier().addSupplier(block('s1', 'A', [100]));
    notifier().updateRequestItem(0, name: 'Болт');
    final rid = state().requestItems.first.id;

    notifier().linkOffer('s1', 's1-o0', rid);
    expect(state().suppliers.first.offers.first.linkedRequestItemId, rid);
    notifier().linkOffer('s1', 's1-o0', null);
    expect(state().suppliers.first.offers.first.linkedRequestItemId, isNull);
  });

  test('moveOfferWithinSupplier меняет привязку и порядок', () {
    notifier().addSupplier(SupplierBlock(id: 's1', displayName: 'A', offers: [
      const Offer(id: 'a', itemName: 'первое'),
      const Offer(id: 'b', itemName: 'второе'),
    ]));
    notifier().updateRequestItem(0, name: 'Болт');
    notifier().updateRequestItem(1, name: 'Гайка');
    final r0 = state().requestItems[0].id;

    // «второе» → в группу «Болт», перед «первое».
    notifier().moveOfferWithinSupplier(
        supplierId: 's1', offerId: 'b', requestItemId: r0, beforeOfferId: 'a');
    final offers = state().suppliers.first.offers;
    expect(offers.map((o) => o.id).toList(), ['b', 'a']);
    expect(offers[0].linkedRequestItemId, r0);
    expect(offers[1].linkedRequestItemId, isNull);
  });

  test('moveOfferToSupplier переносит предложение между поставщиками', () {
    notifier().addSupplier(SupplierBlock(id: 's1', displayName: 'A', offers: [
      const Offer(id: 'a', itemName: 'Болт'),
    ]));
    notifier().addSupplier(SupplierBlock(id: 's2', displayName: 'B', offers: [
      const Offer(id: 'b', itemName: 'Гайка'),
    ]));
    notifier().updateRequestItem(0, name: 'Болт');
    final r0 = state().requestItems.first.id;

    notifier().moveOfferToSupplier(
      fromSupplierId: 's1',
      offerId: 'a',
      toSupplierId: 's2',
      requestItemId: r0,
    );
    expect(state().suppliers[0].offers, isEmpty);
    // Без beforeOfferId — дописывается в конец блока получателя.
    expect(state().suppliers[1].offers.last.id, 'a');
    expect(state().suppliers[1].offers.last.linkedRequestItemId, r0);
  });

  test('autoLinkOffers сопоставляет по названию, порог отсекает слабые', () {
    notifier().updateRequestItem(0, name: 'Шпилька резьбовая М12 DIN 975');
    notifier().updateRequestItem(1, name: 'Совершенно другая вещь');
    final r0 = state().requestItems[0].id;
    notifier().addSupplier(SupplierBlock(id: 's1', displayName: 'A', offers: [
      const Offer(id: 'a', itemName: 'Шпилька резьбовая М12 DIN 975 цинк'),
      const Offer(id: 'b', itemName: 'Что-то нераспознаваемое 12345'),
    ]));
    final n = notifier().autoLinkOffers();
    expect(n, 1);
    final offers = state().suppliers.first.offers;
    expect(offers[0].linkedRequestItemId, r0);
    expect(offers[1].linkedRequestItemId, isNull);
  });

  test('requestFullyFilled: все три поля заполнены', () {
    expect(notifier().requestFullyFilled, isFalse);
    notifier().updateRequestItem(0, name: 'A', qty: '1', unit: 'шт');
    expect(notifier().requestFullyFilled, isTrue);
  });

  // --- позиции заявки ----------------------------------------------------------

  test('updateRequestItem расширяет список при пропуске и хранит ед.изм', () {
    notifier().updateRequestItem(2, name: 'Поз', qty: '5', unit: 'м');
    expect(state().requestItems, hasLength(3));
    expect(state().requestItems[2].name, 'Поз');
    expect(state().requestItems[2].unit, 'м');
  });

  test('очистка позиции схлопывает хвост', () {
    notifier().updateRequestItem(0, name: 'A');
    notifier().updateRequestItem(0, name: '');
    expect(state().requestItems, isEmpty);
  });

  test('supplierCoverage: n/z по количествам', () {
    notifier().updateRequestItem(0, name: 'A', qty: '10');
    notifier().updateRequestItem(1, name: 'B', qty: '5');
    final items = state().requestItems;
    final supplier = SupplierBlock(id: 's1', offers: [
      Offer(id: 'o1', qty: 10, linkedRequestItemId: items[0].id),
      Offer(id: 'o2', qty: 4, linkedRequestItemId: items[1].id), // 4 < 5
    ]);
    final c = supplierCoverage(supplier, items);
    expect(c.covered, 1);
    expect(c.total, 2);
  });

  test('maxRows считается по предложениям и позициям', () {
    notifier().addSupplier(block('s1', 'A', [100, 200]));
    notifier().updateOffer('s1', 's1-o1', (o) => o.copyWith(itemName: 'X'));
    notifier().updateOffer('s1', 's1-o0', (o) => o.copyWith(itemName: 'X'));
    expect(state().maxRows, 2);
  });
}
