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

  /// Основная сумма строки с учётом режима поставщика «без НДС».
  /// При [PriceDriver.price] вычисляется из цены.
  double? displaySum(bool withoutVat) {
    if (priceDriver == PriceDriver.price) {
      final q = qty;
      final pr = withoutVat ? priceWithoutVat : priceWithVat;
      if (pr == null || q == null || q == 0) return null;
      return pr * q;
    }
    return withoutVat ? sumWithoutVat : sumWithVat;
  }

  /// Значение скрытой колонки «Сумма, без НДС».
  double? displaySumWithoutVat(bool withoutVat, double vat) {
    if (withoutVat) return displaySum(true);
    if (priceDriver == PriceDriver.price) {
      final q = qty;
      final pr = priceWithoutVat ??
          (priceWithVat != null ? priceWithVat! / (1 + vat) : null);
      if (pr == null || q == null) return null;
      return pr * q;
    }
    if (sumWithoutVat != null) return sumWithoutVat;
    final s = sumWithVat;
    return s == null ? null : s / (1 + vat);
  }

  /// Цена за единицу — вычисляемая, никогда не хранится при [PriceDriver.sum].
  double? displayPrice(bool withoutVat) {
    if (priceDriver == PriceDriver.price) {
      return withoutVat ? priceWithoutVat : priceWithVat;
    }
    final s = displaySum(withoutVat);
    final q = qty;
    if (s == null || q == null || q == 0) return null;
    return s / q;
  }

  /// Правка основной суммы. Переключает водителя на сумму, цена сбрасывается
  /// (вычисляется на лету). Для поставщика с НДС сумма без НДС выводится
  /// через [vat].
  Offer withSumInput(double? value, {required bool withoutVat, required double vat}) {
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
      sumWithoutVat: value / (1 + vat),
      clearPriceWithVat: true,
      clearPriceWithoutVat: true,
      priceDriver: PriceDriver.sum,
    );
  }

  /// Правка скрытой колонки «Сумма, без НДС» (только у поставщика с НДС):
  /// сумма с НДС становится первичной и пересчитывается из введённой.
  Offer withSumWithoutVatInput(double? value, {required double vat}) {
    if (value == null) {
      return copyWith(clearSumWithoutVat: true);
    }
    return copyWith(
      sumWithoutVat: value,
      sumWithVat: value * (1 + vat),
      clearPriceWithVat: true,
      clearPriceWithoutVat: true,
      priceDriver: PriceDriver.sum,
    );
  }

  /// Правка цены за единицу. Переключает водителя на цену, суммы сбрасываются
  /// (вычисляются на лету).
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

  /// Итог по поставщику — вычисляется, не хранится. Для «без НДС» складываются
  /// суммы без НДС (в т.ч. вычисленные из цены).
  double get total {
    var sum = 0.0;
    for (final o in offers) {
      sum += o.displaySum(withoutVat) ?? 0;
    }
    return sum;
  }

  bool get hasAnySum =>
      offers.any((o) => o.displaySum(withoutVat) != null);

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