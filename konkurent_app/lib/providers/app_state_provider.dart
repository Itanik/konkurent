import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_state.dart';
import '../services/app_config_service.dart';
import '../utils/fuzzy_match.dart';

class AppStateNotifier extends Notifier<AppState> {
  @override
  AppState build() => const AppState();

  double get _vat =>
      ref.read(appConfigProvider).value?.vatRate ?? 0.22;

  void setRequestName(String name) {
    state = state.copyWith(requestName: name);
  }

  void replaceState(AppState next) {
    state = next;
  }

  void reset() {
    state = const AppState();
  }

  // --- поставщики -----------------------------------------------------------

  void addSupplier(SupplierBlock block) {
    state = state.copyWith(suppliers: [...state.suppliers, block]);
  }

  void insertSupplierAt(int index, SupplierBlock block) {
    final list = [...state.suppliers];
    final i = index.clamp(0, list.length);
    list.insert(i, block);
    state = state.copyWith(suppliers: list);
  }

  void removeSupplier(String id) {
    state = state.copyWith(
      suppliers: state.suppliers.where((s) => s.id != id).toList(),
    );
  }

  void renameSupplier(String id, String name) {
    _updateSupplier(id, (s) => s.copyWith(displayName: name));
  }

  void setSupplierInn(String id, String inn) {
    _updateSupplier(
      id,
      (s) => s.copyWith(inn: inn.trim().isEmpty ? null : inn.trim()),
    );
  }

  /// Флажок «без НДС»: переключает базис блока и перекидывает введённые
  /// значения в колонки нового базиса (колонки старого скрываются).
  /// Состояние кнопки «позиции без НДС» сбрасывается.
  void setSupplierWithoutVat(String id, bool value) {
    _updateSupplier(id, (s) {
      final offers =
          s.offers.map((o) => o.vatMoveValues(toNet: value)).toList();
      return s.copyWith(
        withoutVat: value,
        vatMovedToNet: false,
        offers: offers,
      );
    });
  }

  /// Кнопка «позиции в счёте без НДС» — тумблер: первое нажатие переносит
  /// значения на базис «без НДС» и пересчитывает колонку с НДС
  /// (= без НДС × (1 + ставка)); повторное возвращает как было
  /// (= без НДС / (1 + ставка)). Колонки с НДС остаются видимыми.
  void recomputeVatFromNet(String id) {
    final vat = _vat;
    _updateSupplier(id, (s) {
      final toNet = !s.vatMovedToNet;
      final offers = s.offers
          .map((o) => toNet ? o.vatMoveGrossToNet(vat) : o.vatMoveNetToGross(vat))
          .toList();
      return s.copyWith(offers: offers, vatMovedToNet: toNet);
    });
  }

  /// [newIndex] — итоговый индекс, куда встаёт перемещаемый блок (drop на
  /// колонку с этим индексом).
  void reorderSuppliers(int oldIndex, int newIndex) {
    final list = [...state.suppliers];
    if (oldIndex < 0 || oldIndex >= list.length) return;
    final item = list.removeAt(oldIndex);
    list.insert(newIndex.clamp(0, list.length), item);
    state = state.copyWith(suppliers: list);
  }

  /// Сортировка по итоговой сумме: слева самый выгодный. Поставщики без
  /// заполненных сумм уходят в конец.
  void sortSuppliersByTotal() {
    final vat = _vat;
    final list = [...state.suppliers];
    final indexed = list.asMap().entries.toList();
    indexed.sort((a, b) {
      final ka = a.value.hasAnySum(vat) ? a.value.total(vat) : double.infinity;
      final kb = b.value.hasAnySum(vat) ? b.value.total(vat) : double.infinity;
      final cmp = ka.compareTo(kb);
      return cmp != 0 ? cmp : a.key.compareTo(b.key);
    });
    state = state.copyWith(suppliers: indexed.map((e) => e.value).toList());
  }

  // --- предложения ----------------------------------------------------------

  /// Изменяет предложение по индексу, дополняя список пустыми строками до
  /// нужного индекса. Пустые «хвостовые» строки схлопываются.
  void setOfferAt(String supplierId, int index, Offer Function(Offer) transform) {
    _updateSupplier(supplierId, (s) {
      final offers = [...s.offers];
      while (offers.length <= index) {
        offers.add(Offer.empty());
      }
      offers[index] = transform(offers[index]);
      return s.copyWith(offers: _trimTrailingOffers(offers));
    });
  }

  List<Offer> _trimTrailingOffers(List<Offer> offers) {
    final list = [...offers];
    while (list.isNotEmpty && list.last.isEmpty) {
      list.removeLast();
    }
    return list;
  }

  // --- привязка предложений к позициям заявки --------------------------------

  /// Изменение предложения по id (сетка адресует строки идентификаторами:
  /// физический индекс нестабилен при перепривязках).
  void updateOffer(String supplierId, String offerId, Offer Function(Offer) transform) {
    _updateSupplier(supplierId, (s) {
      final offers = s.offers
          .map((o) => o.id == offerId ? transform(o) : o)
          .toList();
      return s.copyWith(offers: _trimTrailingOffers(offers));
    });
  }

  void removeOfferById(String supplierId, String offerId) {
    _updateSupplier(supplierId, (s) =>
        s.copyWith(offers: s.offers.where((o) => o.id != offerId).toList()));
  }

  /// Создание предложения в группе позиции заявки (null — зоне без привязки)
  /// со стартовыми значениями: ввод в пустую ячейку группы.
  void createOfferAt(String supplierId, String? requestItemId,
      Offer Function(Offer) init) {
    _updateSupplier(supplierId, (s) {
      final offer = init(Offer.empty()).copyWith(
        linkedRequestItemId: requestItemId,
        clearLink: requestItemId == null,
      );
      final offers = [...s.offers];
      final pos = requestItemId == null
          ? offers.lastIndexWhere((o) => o.linkedRequestItemId == null) + 1
          : offers.lastIndexWhere(
                  (o) => o.linkedRequestItemId == requestItemId) +
              1;
      offers.insert(pos, offer);
      return s.copyWith(offers: offers);
    });
  }

  /// Автосопоставление непривязанных предложений с позициями заявки
  /// (нечёткое сравнение названий). Возвращает число новых привязок.
  int autoLinkOffers() {
    final items = state.requestItems
        .where((r) => r.name.trim().isNotEmpty)
        .map((r) => (id: r.id, name: r.name))
        .toList();
    if (items.isEmpty) return 0;
    var linkedCount = 0;
    state = state.copyWith(suppliers: [
      for (final s in state.suppliers)
        s.copyWith(offers: [
          for (final o in s.offers)
            if (o.linkedRequestItemId == null &&
                o.itemName.trim().isNotEmpty)
              () {
                final match = bestMatch(o.itemName, items);
                if (match == null) return o;
                linkedCount++;
                return o.copyWith(linkedRequestItemId: match.$1);
              }()
            else
              o,
        ]),
    ]);
    return linkedCount;
  }

  /// Заявка «полностью заполнена» — у каждой позиции есть название, кол-во
  /// и ед.изм; условие автозапуска сопоставления после распознавания.
  bool get requestFullyFilled =>
      state.requestItems.isNotEmpty &&
      state.requestItems.every((r) =>
          r.name.trim().isNotEmpty &&
          r.qty.trim().isNotEmpty &&
          r.unit.trim().isNotEmpty);

  /// Привязать/отвязать предложение от позиции заявки (drag между строками).
  void linkOffer(String supplierId, String offerId, String? requestItemId) {
    _updateSupplier(supplierId, (s) {
      final offers = s.offers
          .map((o) => o.id == offerId
              ? (requestItemId == null
                  ? o.copyWith(clearLink: true)
                  : o.copyWith(linkedRequestItemId: requestItemId))
              : o)
          .toList();
      return s.copyWith(offers: offers);
    });
  }

  /// Перенос предложения между поставщиками (drag на чужую колонку).
  /// [requestItemId] группы, куда переносим (null — зона без привязки);
  /// [beforeOfferId] — вставить перед этим предложением цели (null — в конец
  /// группы/зоны). Привязка сохраняется/обновляется.
  void moveOfferToSupplier({
    required String fromSupplierId,
    required String offerId,
    required String toSupplierId,
    String? requestItemId,
    String? beforeOfferId,
  }) {
    if (fromSupplierId == toSupplierId) return;
    Offer? moved;
    state = state.copyWith(
      suppliers: [
        for (final s in state.suppliers)
          if (s.id == fromSupplierId)
            s.copyWith(
                offers: s.offers.where((o) => o.id != offerId).toList())
          else if (s.id == toSupplierId)
            s.copyWith(offers: () {
              final offers = [...s.offers];
              final relinked = (moved ??= state.suppliers
                      .firstWhere((x) => x.id == fromSupplierId)
                      .offers
                      .firstWhere((o) => o.id == offerId))
                  .copyWith(
                linkedRequestItemId: requestItemId,
                clearLink: requestItemId == null,
              );
              final pos = beforeOfferId == null
                  ? offers.length
                  : offers.indexWhere((o) => o.id == beforeOfferId);
              offers.insert(
                  pos == -1 ? offers.length : pos, relinked);
              return offers;
            }())
          else
            s,
      ],
    );
  }

  /// Перестановка внутри поставщика: предложение встаёт перед [beforeOfferId]
  /// (null — в конец) со сменой привязки на [requestItemId] (null — отвязать).
  /// Используется drag'ом: дроп на строку группы = перепривязка.
  void moveOfferWithinSupplier({
    required String supplierId,
    required String offerId,
    required String? requestItemId,
    String? beforeOfferId,
  }) {
    _updateSupplier(supplierId, (s) {
      final idx = s.offers.indexWhere((o) => o.id == offerId);
      if (idx == -1) return s;
      final offers = [...s.offers];
      final relinked = offers.removeAt(idx).copyWith(
            linkedRequestItemId: requestItemId,
            clearLink: requestItemId == null,
          );
      final pos = beforeOfferId == null
          ? offers.length
          : offers.indexWhere((o) => o.id == beforeOfferId);
      offers.insert(pos == -1 ? offers.length : pos, relinked);
      return s.copyWith(offers: offers);
    });
  }

  // --- мета -----------------------------------------------------------------

  void setMeta(String supplierId, String key, String value) {
    _updateSupplier(
      supplierId,
      (s) => s.copyWith(meta: s.meta.copyWithValue(key, value)),
    );
  }

  // --- позиции заявки -------------------------------------------------------

  void updateRequestItem(int index, {String? name, String? qty, String? unit}) {
    final items = [...state.requestItems];
    while (items.length <= index) {
      items.add(RequestItem.empty());
    }
    items[index] = items[index].copyWith(name: name, qty: qty, unit: unit);
    state = state.copyWith(requestItems: _trimTrailingRequestItems(items));
  }

  void removeRequestItem(int index) {
    if (index < 0 || index >= state.requestItems.length) return;
    final items = [...state.requestItems]..removeAt(index);
    state = state.copyWith(requestItems: _trimTrailingRequestItems(items));
  }

  List<RequestItem> _trimTrailingRequestItems(List<RequestItem> items) {
    final list = [...items];
    while (list.isNotEmpty && list.last.isEmpty) {
      list.removeLast();
    }
    return list;
  }

  void _updateSupplier(
    String id,
    SupplierBlock Function(SupplierBlock) transform,
  ) {
    state = state.copyWith(
      suppliers: [
        for (final s in state.suppliers) if (s.id == id) transform(s) else s,
      ],
    );
  }
}

final appStateProvider =
    NotifierProvider<AppStateNotifier, AppState>(AppStateNotifier.new);