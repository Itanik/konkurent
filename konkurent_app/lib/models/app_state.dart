import 'package:uuid/uuid.dart';

const _uuid = Uuid();

String newId() => _uuid.v4();

/// Что является источником истины для строки: введённая сумма (`sum`) или
/// введённая цена (`price`). «Последняя правка выигрывает»: правка суммы
/// переключает водителя на сумму, правка цены — на цену. Вторая величина
/// всегда вычисляется на лету и не хранится.
enum PriceDriver { sum, price }

class Offer {
  const Offer({
    required this.id,
    this.itemName = '',
    this.qty,
    this.unit = '',
    this.sumWithVat,
    this.sumWithoutVat,
    this.priceWithVat,
    this.priceWithoutVat,
    this.priceDriver = PriceDriver.sum,
  });

  final String id;
  final String itemName;
  final double? qty;
  final String unit;
  final double? sumWithVat;
  final double? sumWithoutVat;

  /// Хранится только при [PriceDriver.price] — сумма тогда вычисляется.
  final double? priceWithVat;
  final double? priceWithoutVat;
  final PriceDriver priceDriver;

  factory Offer.empty() => Offer(id: newId());

  /// Полностью пустая строка (нет ни одного заполненного поля).
  bool get isEmpty =>
      itemName.isEmpty &&
      qty == null &&
      unit.isEmpty &&
      sumWithVat == null &&
      sumWithoutVat == null &&
      priceWithVat == null &&
      priceWithoutVat == null;

  /// Цена с НДС с учётом производных: хранимая цена дорабатывается
  /// противоположной через ставку [vat].
  double? _priceGross(double vat) => priceWithVat ??
      (priceWithoutVat != null ? priceWithoutVat! * (1 + vat) : null);

  /// Цена без НДС с учётом производных.
  double? _priceNet(double vat) => priceWithoutVat ??
      (priceWithVat != null ? priceWithVat! / (1 + vat) : null);

  /// Сумма строки на заданном базисе. Всё, что не введено/не распознано,
  /// выводится через ставку НДС — обе стороны всегда согласованны.
  double? displaySum({required bool withoutVat, required double vat}) {
    final q = qty;
    if (priceDriver == PriceDriver.price) {
      final pr = withoutVat ? _priceNet(vat) : _priceGross(vat);
      if (pr == null || q == null || q == 0) return null;
      return pr * q;
    }
    if (withoutVat) {
      if (sumWithoutVat != null) return sumWithoutVat;
      return sumWithVat == null ? null : sumWithVat! / (1 + vat);
    }
    if (sumWithVat != null) return sumWithVat;
    return sumWithoutVat == null ? null : sumWithoutVat! * (1 + vat);
  }

  /// Цена за единицу на заданном базисе (производная от суммы или ввода).
  double? displayPrice({required bool withoutVat, required double vat}) {
    final s = displaySum(withoutVat: withoutVat, vat: vat);
    final q = qty;
    if (s == null || q == null || q == 0) return null;
    return s / q;
  }

  /// Правка суммы на заданном базисе: переключает водителя на сумму, вторая
  /// сторона выводится производной.
  Offer withSumInput(double? value,
      {required bool withoutVat, required double vat}) {
    if (value == null) {
      return copyWith(
        clearSumWithVat: true,
        clearSumWithoutVat: true,
        clearPriceWithVat: true,
        clearPriceWithoutVat: true,
        priceDriver: PriceDriver.sum,
      );
    }
    if (withoutVat) {
      return copyWith(
        sumWithoutVat: value,
        clearSumWithVat: true,
        clearPriceWithVat: true,
        clearPriceWithoutVat: true,
        priceDriver: PriceDriver.sum,
      );
    }
    return copyWith(
      sumWithVat: value,
      clearSumWithoutVat: true,
      clearPriceWithVat: true,
      clearPriceWithoutVat: true,
      priceDriver: PriceDriver.sum,
    );
  }

  /// Правка цены за единицу на заданном базисе: переключает водителя на цену.
  Offer withPriceInput(double? value, {required bool withoutVat}) {
    if (value == null) {
      return copyWith(
        clearPriceWithVat: true,
        clearPriceWithoutVat: true,
        priceDriver: PriceDriver.sum,
      );
    }
    if (withoutVat) {
      return copyWith(
        priceWithoutVat: value,
        clearPriceWithVat: true,
        clearSumWithVat: true,
        clearSumWithoutVat: true,
        priceDriver: PriceDriver.price,
      );
    }
    return copyWith(
      priceWithVat: value,
      clearPriceWithoutVat: true,
      clearSumWithVat: true,
      clearSumWithoutVat: true,
      priceDriver: PriceDriver.price,
    );
  }

  /// Разовая миграция «значения позиций указаны без НДС»: введённые значения
  /// с НДС переезжают на базис «без НДС», а с НДС пересчитываются
  /// (= без НДС × (1 + [vat])). Обе колонки остаются видимыми.
  Offer vatMoveGrossToNet(double vat) {
    if (priceDriver == PriceDriver.price) {
      final gross = priceWithVat;
      if (gross == null) return this;
      return copyWith(
        priceWithoutVat: gross,
        priceWithVat: gross * (1 + vat),
      );
    }
    final gross = sumWithVat;
    if (gross == null) return this;
    return copyWith(
      sumWithoutVat: gross,
      sumWithVat: gross * (1 + vat),
    );
  }

  /// Перекидывание введённых значений между базисами при смене флажка
  /// «без НДС» (в обе стороны): [toNet] = перенос «с НДС → без НДС».
  Offer vatMoveValues({required bool toNet}) {
    if (priceDriver == PriceDriver.price) {
      if (toNet) {
        if (priceWithVat == null) return this;
        return copyWith(
          priceWithoutVat: priceWithVat,
          clearPriceWithVat: true,
        );
      }
      if (priceWithoutVat == null) return this;
      return copyWith(
        priceWithVat: priceWithoutVat,
        clearPriceWithoutVat: true,
      );
    }
    if (toNet) {
      if (sumWithVat == null) return this;
      return copyWith(
        sumWithoutVat: sumWithVat,
        clearSumWithVat: true,
      );
    }
    if (sumWithoutVat == null) return this;
    return copyWith(
      sumWithVat: sumWithoutVat,
      clearSumWithoutVat: true,
    );
  }

  Offer copyWith({
    String? itemName,
    double? qty,
    bool clearQty = false,
    String? unit,
    double? sumWithVat,
    bool clearSumWithVat = false,
    double? sumWithoutVat,
    bool clearSumWithoutVat = false,
    double? priceWithVat,
    bool clearPriceWithVat = false,
    double? priceWithoutVat,
    bool clearPriceWithoutVat = false,
    PriceDriver? priceDriver,
  }) {
    return Offer(
      id: id,
      itemName: itemName ?? this.itemName,
      qty: clearQty ? null : (qty ?? this.qty),
      unit: unit ?? this.unit,
      sumWithVat: clearSumWithVat ? null : (sumWithVat ?? this.sumWithVat),
      sumWithoutVat:
          clearSumWithoutVat ? null : (sumWithoutVat ?? this.sumWithoutVat),
      priceWithVat:
          clearPriceWithVat ? null : (priceWithVat ?? this.priceWithVat),
      priceWithoutVat: clearPriceWithoutVat
          ? null
          : (priceWithoutVat ?? this.priceWithoutVat),
      priceDriver: priceDriver ?? this.priceDriver,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'itemName': itemName,
        'qty': qty,
        'unit': unit,
        'sumWithVat': sumWithVat,
        'sumWithoutVat': sumWithoutVat,
        'priceWithVat': priceWithVat,
        'priceWithoutVat': priceWithoutVat,
        'priceDriver': priceDriver == PriceDriver.price ? 'price' : 'sum',
      };

  factory Offer.fromJson(Map<String, dynamic> json) => Offer(
        id: (json['id'] as String?) ?? newId(),
        itemName: (json['itemName'] as String?) ?? '',
        qty: _toDouble(json['qty']),
        unit: (json['unit'] as String?) ?? '',
        sumWithVat: _toDouble(json['sumWithVat']),
        sumWithoutVat: _toDouble(json['sumWithoutVat']),
        priceWithVat: _toDouble(json['priceWithVat']),
        priceWithoutVat: _toDouble(json['priceWithoutVat']),
        priceDriver: json['priceDriver'] == 'price'
            ? PriceDriver.price
            : PriceDriver.sum,
      );
}

class SupplierMeta {
  const SupplierMeta({
    this.contract = '',
    this.deliveryTime = '',
    this.delivery = '',
    this.paymentTerms = '',
    this.comment = '',
  });

  final String contract;
  final String deliveryTime;
  final String delivery;
  final String paymentTerms;
  final String comment;

  String value(String key) {
    switch (key) {
      case 'contract':
        return contract;
      case 'deliveryTime':
        return deliveryTime;
      case 'delivery':
        return delivery;
      case 'paymentTerms':
        return paymentTerms;
      case 'comment':
        return comment;
      default:
        return '';
    }
  }

  SupplierMeta copyWithValue(String key, String value) {
    return SupplierMeta(
      contract: key == 'contract' ? value : contract,
      deliveryTime: key == 'deliveryTime' ? value : deliveryTime,
      delivery: key == 'delivery' ? value : delivery,
      paymentTerms: key == 'paymentTerms' ? value : paymentTerms,
      comment: key == 'comment' ? value : comment,
    );
  }

  Map<String, dynamic> toJson() => {
        'contract': contract,
        'deliveryTime': deliveryTime,
        'delivery': delivery,
        'paymentTerms': paymentTerms,
        'comment': comment,
      };

  factory SupplierMeta.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const SupplierMeta();
    return SupplierMeta(
      contract: (json['contract'] as String?) ?? '',
      deliveryTime: (json['deliveryTime'] as String?) ?? '',
      delivery: (json['delivery'] as String?) ?? '',
      paymentTerms: (json['paymentTerms'] as String?) ?? '',
      comment: (json['comment'] as String?) ?? '',
    );
  }
}

class SupplierBlock {
  const SupplierBlock({
    required this.id,
    this.displayName = '',
    this.sourceFileName,
    this.inn,
    this.withoutVat = false,
    this.meta = const SupplierMeta(),
    this.offers = const [],
  });

  final String id;
  final String displayName;
  final String? sourceFileName;

  /// ИНН поставщика (распознанный из счёта или введённый вручную).
  final String? inn;

  /// Счёт без НДС: суммы считаются как суммы без НДС.
  final bool withoutVat;
  final SupplierMeta meta;
  final List<Offer> offers;

  /// Итог по поставщику — вычисляется, не хранится. На базисе «без НДС»
  /// складываются суммы без НДС (в т.ч. выведенные через [vat]).
  double total(double vat) {
    var sum = 0.0;
    for (final o in offers) {
      sum += o.displaySum(withoutVat: withoutVat, vat: vat) ?? 0;
    }
    return sum;
  }

  bool hasAnySum(double vat) =>
      offers.any((o) => o.displaySum(withoutVat: withoutVat, vat: vat) != null);

  factory SupplierBlock.empty({String displayName = ''}) => SupplierBlock(
        id: newId(),
        displayName: displayName,
        offers: [Offer.empty()],
      );

  SupplierBlock copyWith({
    String? displayName,
    String? sourceFileName,
    String? inn,
    bool clearInn = false,
    bool? withoutVat,
    SupplierMeta? meta,
    List<Offer>? offers,
  }) {
    return SupplierBlock(
      id: id,
      displayName: displayName ?? this.displayName,
      sourceFileName: sourceFileName ?? this.sourceFileName,
      inn: clearInn ? null : (inn ?? this.inn),
      withoutVat: withoutVat ?? this.withoutVat,
      meta: meta ?? this.meta,
      offers: offers ?? this.offers,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        'sourceFileName': sourceFileName,
        'inn': inn,
        'withoutVat': withoutVat,
        'meta': meta.toJson(),
        'offers': offers.map((o) => o.toJson()).toList(),
      };

  factory SupplierBlock.fromJson(Map<String, dynamic> json) => SupplierBlock(
        id: (json['id'] as String?) ?? newId(),
        displayName: (json['displayName'] as String?) ?? '',
        sourceFileName: json['sourceFileName'] as String?,
        inn: json['inn'] as String?,
        withoutVat: json['withoutVat'] as bool? ?? false,
        meta: SupplierMeta.fromJson(json['meta'] as Map<String, dynamic>?),
        offers: ((json['offers'] as List?) ?? [])
            .map((e) => Offer.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class RequestItem {
  const RequestItem({required this.id, this.name = '', this.qty = ''});

  final String id;
  final String name;
  final String qty;

  factory RequestItem.empty() => RequestItem(id: newId());

  bool get isEmpty => name.isEmpty && qty.isEmpty;

  RequestItem copyWith({String? name, String? qty}) =>
      RequestItem(id: id, name: name ?? this.name, qty: qty ?? this.qty);

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'qty': qty};

  factory RequestItem.fromJson(Map<String, dynamic> json) => RequestItem(
        id: (json['id'] as String?) ?? newId(),
        name: (json['name'] as String?) ?? '',
        qty: (json['qty'] as String?) ?? '',
      );
}

class AppState {
  const AppState({
    this.requestName = '',
    this.requestItems = const [],
    this.suppliers = const [],
  });

  final String requestName;
  final List<RequestItem> requestItems;
  final List<SupplierBlock> suppliers;

  /// Высота таблицы — производная: максимум строк среди предложений
  /// поставщиков и позиций заявки, но не меньше одной видимой строки.
  int get maxRows {
    var maxOffers = 0;
    for (final s in suppliers) {
      if (s.offers.length > maxOffers) maxOffers = s.offers.length;
    }
    final rows =
        maxOffers > requestItems.length ? maxOffers : requestItems.length;
    return rows < 1 ? 1 : rows;
  }

  /// Есть ли в таблице что-то содержательное (для решения о хранении сессии).
  bool get hasContent {
    if (requestName.trim().isNotEmpty) return true;
    if (requestItems.any((e) => !e.isEmpty)) return true;
    return suppliers.any((s) =>
        s.displayName.isNotEmpty ||
        !s.meta.toJson().values.every((v) => (v as String).isEmpty) ||
        s.offers.any((o) => !o.isEmpty));
  }

  AppState copyWith({
    String? requestName,
    List<RequestItem>? requestItems,
    List<SupplierBlock>? suppliers,
  }) {
    return AppState(
      requestName: requestName ?? this.requestName,
      requestItems: requestItems ?? this.requestItems,
      suppliers: suppliers ?? this.suppliers,
    );
  }

  Map<String, dynamic> toJson() => {
        'requestName': requestName,
        'requestItems': requestItems.map((e) => e.toJson()).toList(),
        'suppliers': suppliers.map((e) => e.toJson()).toList(),
      };

  factory AppState.fromJson(Map<String, dynamic> json) => AppState(
        requestName: (json['requestName'] as String?) ?? '',
        requestItems: ((json['requestItems'] as List?) ?? [])
            .map((e) => RequestItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        suppliers: ((json['suppliers'] as List?) ?? [])
            .map((e) => SupplierBlock.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

double? _toDouble(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  final s = value.toString().trim().replaceAll(',', '.');
  if (s.isEmpty) return null;
  return double.tryParse(s);
}