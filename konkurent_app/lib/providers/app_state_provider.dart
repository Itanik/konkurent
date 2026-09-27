import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_state.dart';

class AppStateNotifier extends Notifier<AppState> {
  @override
  AppState build() => const AppState();

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
    final list = [...state.suppliers];
    final indexed = list.asMap().entries.toList();
    indexed.sort((a, b) {
      final ka = a.value.hasAnySum ? a.value.total : double.infinity;
      final kb = b.value.hasAnySum ? b.value.total : double.infinity;
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

  void removeOfferAt(String supplierId, int index) {
    _updateSupplier(supplierId, (s) {
      final offers = [...s.offers];
      if (index < 0 || index >= offers.length) return s;
      offers.removeAt(index);
      return s.copyWith(offers: _trimTrailingOffers(offers));
    });
  }

  /// [newIndex] — итоговый индекс строки, на которую сбросили предложение.
  void reorderOffers(String supplierId, int oldIndex, int newIndex) {
    _updateSupplier(supplierId, (s) {
      final list = [...s.offers];
      if (oldIndex < 0 || oldIndex >= list.length) return s;
      final item = list.removeAt(oldIndex);
      list.insert(newIndex.clamp(0, list.length), item);
      return s.copyWith(offers: list);
    });
  }

  /// Меняет местами предложение с пустой строкой: предложение встаёт на место
  /// пустой, а на его прежнем месте остаётся пробел. Список дополняется
  /// пустыми строками до нужного индекса.
  void moveOfferToEmpty(String supplierId, int fromIndex, int toIndex) {
    if (fromIndex == toIndex) return;
    _updateSupplier(supplierId, (s) {
      final offers = [...s.offers];
      if (fromIndex < 0 || fromIndex >= offers.length) return s;
      final need = (fromIndex > toIndex ? fromIndex : toIndex) + 1;
      while (offers.length < need) {
        offers.add(Offer.empty());
      }
      final item = offers[fromIndex];
      offers[fromIndex] = offers[toIndex];
      offers[toIndex] = item;
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

  // --- мета -----------------------------------------------------------------

  void setMeta(String supplierId, String key, String value) {
    _updateSupplier(
      supplierId,
      (s) => s.copyWith(meta: s.meta.copyWithValue(key, value)),
    );
  }

  // --- позиции заявки -------------------------------------------------------

  void updateRequestItem(int index, {String? name, String? qty}) {
    final items = [...state.requestItems];
    while (items.length <= index) {
      items.add(RequestItem.empty());
    }
    items[index] = items[index].copyWith(name: name, qty: qty);
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

  /// Вставка списка позиций заявки: строки заменяются начиная с [startIndex],
  /// при нехватке — добавляются, «хвост» существующих строк не трогается.
  void pasteRequestItems(int startIndex, List<RequestItem> items) {
    if (items.isEmpty) return;
    final list = [...state.requestItems];
    while (list.length < startIndex) {
      list.add(RequestItem.empty());
    }
    for (var i = 0; i < items.length; i++) {
      final idx = startIndex + i;
      if (idx < list.length) {
        list[idx] = items[i];
      } else {
        list.add(items[i]);
      }
    }
    state = state.copyWith(requestItems: _trimTrailingRequestItems(list));
  }

  /// Вставка списка в колонку «Предложено» поставщика: заполняет только
  /// названия предложений (количество/единицу не трогаем).
  void pasteOffers(String supplierId, int startIndex, List<RequestItem> items) {
    if (items.isEmpty) return;
    _updateSupplier(supplierId, (s) {
      final offers = [...s.offers];
      while (offers.length < startIndex) {
        offers.add(Offer.empty());
      }
      for (var i = 0; i < items.length; i++) {
        final idx = startIndex + i;
        final offer = Offer(id: newId(), itemName: items[i].name);
        if (idx < offers.length) {
          offers[idx] = offer;
        } else {
          offers.add(offer);
        }
      }
      return s.copyWith(offers: offers);
    });
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