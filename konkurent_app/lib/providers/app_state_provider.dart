import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_state.dart';
import '../providers/recently_linked_provider.dart';
import '../services/app_config_service.dart';
import '../services/supplier_db.dart';
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
    ref.read(recentlyLinkedProvider.notifier).clear();
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
    final clean = inn.trim();
    _updateSupplier(
      id,
      (s) => s.copyWith(inn: clean.isEmpty ? null : clean),
    );
    // Ручной ввод ИНН связывает блок с БД поставщиков.
    if (clean.isNotEmpty) {
      final db = ref.read(supplierDbProvider);
      final name =
          state.suppliers.where((s) => s.id == id).firstOrNull?.displayName;
      Future(() => db?.upsertSupplier(inn: clean, name: name ?? ''));
    }
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

  /// Позиционное сопоставление — стратегия по умолчанию: k-е предложение
  /// поставщика привязывается к k-й позиции заявки (счета обычно повторяют
  /// порядок заявки, нужна лишь небольшая правка drag'ом). Поставщики, у
  /// которых уже есть привязки, не трогаются — сохраняем ручную работу;
  /// излишки (предложений больше, чем позиций) остаются непривязанными.
  /// Возвращает число новых привязок; свежепривязанные подсвечиваются.
  int linkOffersPositionally() {
    if (state.requestItems.isEmpty) return 0;
    var count = 0;
    final linkedIds = <String>[];
    state = state.copyWith(suppliers: [
      for (final s in state.suppliers)
        if (s.offers.isNotEmpty &&
            s.offers.every((o) => o.linkedRequestItemId == null))
          () {
            var i = 0;
            final offers = <Offer>[];
            for (final o in s.offers) {
              if (o.isEmpty || i >= state.requestItems.length) {
                offers.add(o);
                continue;
              }
              offers.add(o.copyWith(
                  linkedRequestItemId: state.requestItems[i].id));
              linkedIds.add(o.id);
              count++;
              i++;
            }
            return s.copyWith(offers: offers);
          }()
        else
          s,
    ]);
    if (count > 0) {
      ref.read(recentlyLinkedProvider.notifier).set(linkedIds);
    }
    return count;
  }

  /// Автосопоставление непривязанных предложений с позициями заявки
  /// (нечёткое сравнение названий). Возвращает число новых привязок;
  /// свежепривязанные подсвечиваются (`recentlyLinkedProvider`).
  int autoLinkOffers() {
    final items = state.requestItems
        .where((r) => r.name.trim().isNotEmpty)
        .map((r) => (id: r.id, name: r.name))
        .toList();
    if (items.isEmpty) return 0;
    var linkedCount = 0;
    final linkedIds = <String>[];
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
                linkedIds.add(o.id);
                return o.copyWith(linkedRequestItemId: match.$1);
              }()
            else
              o,
        ]),
    ]);
    ref.read(recentlyLinkedProvider.notifier).set(linkedIds);
    return linkedCount;
  }

  /// Кнопка «Сопоставить»: улучшающая правка привязок **всех** предложений
  /// всех поставщиков по названиям позиций заявки. Позиционное
  /// сопоставление могло привязать по порядку неверно (счёт не в порядке
  /// заявки) — уверенное совпадение перекидывает предложение на свою
  /// позицию. Предложение **без** совпадения остаётся там, где стояло
  /// (в группе или зоне): «брак» не перемещает строки и не создает работу
  /// по возврату позиций на место. Совпадений может не быть у части
  /// позиций — они остаются пустыми в группах (предложений бывает меньше,
  /// чем позиций). Перемещённые подсвечиваются (`recentlyLinkedProvider`).
  int relinkAllOffersByName() {
    final items = state.requestItems
        .where((r) => r.name.trim().isNotEmpty)
        .map((r) => (id: r.id, name: r.name))
        .toList();
    var changedCount = 0;
    final changedIds = <String>[];
    state = state.copyWith(suppliers: [
      for (final s in state.suppliers)
        s.copyWith(offers: [
          for (final o in s.offers)
            if (o.itemName.trim().isNotEmpty)
              () {
                final match = bestMatch(o.itemName, items);
                if (match == null || o.linkedRequestItemId == match.$1) {
                  // Нет уверенного совпадения или уже на месте — не трогаем.
                  return o;
                }
                changedCount++;
                changedIds.add(o.id);
                return o.copyWith(linkedRequestItemId: match.$1);
              }()
            else
              o,
        ]),
    ]);
    if (changedCount > 0) {
      ref.read(recentlyLinkedProvider.notifier).set(changedIds);
    }
    return changedCount;
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
    // История мета-полей в БД (последние 5, комментарий не запоминаем).
    final inn = state.suppliers
        .where((s) => s.id == supplierId)
        .firstOrNull
        ?.inn;
    if (inn != null && inn.isNotEmpty) {
      final db = ref.read(supplierDbProvider);
      Future(() => db?.recordMeta(inn, key, value));
    }
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

  // --- счета одного поставщика ------------------------------------------------

  /// Есть ли пересечение позиций между имеющимся блоком и входящим счётом
  /// (нечёткое совпадение названий хотя бы одной пары).
  bool offersIntersect(SupplierBlock existing, SupplierBlock incoming) {
    final candidates = existing.offers
        .where((o) => o.itemName.trim().isNotEmpty)
        .map((o) => (id: o.id, name: o.itemName))
        .toList();
    return incoming.offers.any(
        (o) => o.itemName.trim().isNotEmpty && bestMatch(o.itemName, candidates) != null);
  }

  /// Точный дубль счёта: каждое входящее предложение находит по названию
  /// имеющееся с той же суммой (± округление) — второй раз платить не нужно.
  bool isDuplicateInvoice(SupplierBlock existing, SupplierBlock incoming) {
    final incomingReal =
        incoming.offers.where((o) => !o.isEmpty).toList();
    if (incomingReal.isEmpty) return false;
    final candidates = existing.offers
        .where((o) => !o.isEmpty)
        .map((o) => (id: o.id, name: o.itemName))
        .toList();
    for (final io in incomingReal) {
      final m = bestMatch(io.itemName, candidates);
      if (m == null) return false;
      final twin =
          existing.offers.firstWhere((o) => o.id == m.$1);
      final a = io.displaySum(withoutVat: false, vat: 0.0) ?? 0;
      final b = twin.displaySum(withoutVat: false, vat: 0.0) ?? 0;
      if ((a - b).abs() > 0.01) return false;
    }
    return true;
  }

  /// Тихое слияние счёта без пересечений: непривязанные предложения
  /// входящего добавляются в конец блока, файлы-источники пополняются,
  /// мета не трогается. Новые предложения привязываются по названиям.
  void mergeIntoSupplier({
    required String targetId,
    required SupplierBlock incoming,
  }) {
    _updateSupplier(targetId, (s) {
      final fresh = incoming.offers
          .where((o) => !o.isEmpty)
          .map((o) => o.copyWith(clearLink: true))
          .toList();
      final files = {...s.sourceFileNames, ...incoming.sourceFileNames};
      return s.copyWith(
        offers: [...s.offers, ...fresh],
        sourceFileNames: files.toList(growable: false),
        ocrUsed: s.ocrUsed || incoming.ocrUsed,
      );
    });
    autoLinkOffers();
  }

  /// «Обновить блок»: совпавшие по названиям предложения перезаписываются
  /// значениями входящего счёта (привязка строки сохраняется), отсутствующие
  /// во входящем — удаляются, новые — добавляются в конец. Файлы-источники
  /// пополняются.
  void updateSupplierInvoice({
    required String targetId,
    required SupplierBlock incoming,
  }) {
    _updateSupplier(targetId, (s) {
      final offers = [...s.offers];
      final matched = <String>{};
      for (final io in incoming.offers) {
        if (io.isEmpty) continue;
        final candidates = offers
            .where((o) => !o.isEmpty)
            .map((o) => (id: o.id, name: o.itemName))
            .toList();
        final m = bestMatch(io.itemName, candidates);
        if (m != null) {
          final idx = offers.indexWhere((o) => o.id == m.$1);
          final old = offers[idx];
          offers[idx] = io.copyWith(
            itemName: io.itemName,
            qty: io.qty,
            clearQty: io.qty == null,
            unit: io.unit,
            sumWithVat: io.sumWithVat,
            clearSumWithVat: io.sumWithVat == null,
            sumWithoutVat: io.sumWithoutVat,
            clearSumWithoutVat: io.sumWithoutVat == null,
            priceWithVat: io.priceWithVat,
            clearPriceWithVat: io.priceWithVat == null,
            priceWithoutVat: io.priceWithoutVat,
            clearPriceWithoutVat: io.priceWithoutVat == null,
            priceDriver: io.priceDriver,
            linkedRequestItemId: old.linkedRequestItemId,
            clearLink: old.linkedRequestItemId == null,
          );
          matched.add(m.$1);
        } else {
          offers.add(io);
        }
      }
      offers.removeWhere(
          (o) => !o.isEmpty && !matched.contains(o.id));
      final files = {...s.sourceFileNames, ...incoming.sourceFileNames};
      return s.copyWith(
        offers: _trimTrailingOffers(offers),
        sourceFileNames: files.toList(growable: false),
        ocrUsed: s.ocrUsed || incoming.ocrUsed,
      );
    });
  }
}

final appStateProvider =
    NotifierProvider<AppStateNotifier, AppState>(AppStateNotifier.new);