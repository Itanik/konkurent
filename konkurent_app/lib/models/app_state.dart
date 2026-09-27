import 'package:uuid/uuid.dart';

const _uuid = Uuid();

String newId() => _uuid.v4();

class Offer {
  const Offer({
    required this.id,
    this.itemName = '',
    this.qty,
    this.unit = '',
    this.sumWithVat,
    this.sumWithoutVat,
  });

  final String id;
  final String itemName;
  final double? qty;
  final String unit;
  final double? sumWithVat;
  final double? sumWithoutVat;

  factory Offer.empty() => Offer(id: newId());

  /// Вычисляемое значение — никогда не хранится и не экспортируется как число.
  double? get pricePerUnit {
    final q = qty;
    final s = sumWithVat;
    if (q == null || q == 0 || s == null) return null;
    return s / q;
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
  }) {
    return Offer(
      id: id,
      itemName: itemName ?? this.itemName,
      qty: clearQty ? null : (qty ?? this.qty),
      unit: unit ?? this.unit,
      sumWithVat: clearSumWithVat ? null : (sumWithVat ?? this.sumWithVat),
      sumWithoutVat:
          clearSumWithoutVat ? null : (sumWithoutVat ?? this.sumWithoutVat),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'itemName': itemName,
        'qty': qty,
        'unit': unit,
        'sumWithVat': sumWithVat,
        'sumWithoutVat': sumWithoutVat,
      };

  factory Offer.fromJson(Map<String, dynamic> json) => Offer(
        id: (json['id'] as String?) ?? newId(),
        itemName: (json['itemName'] as String?) ?? '',
        qty: _toDouble(json['qty']),
        unit: (json['unit'] as String?) ?? '',
        sumWithVat: _toDouble(json['sumWithVat']),
        sumWithoutVat: _toDouble(json['sumWithoutVat']),
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

  static const keys = [
    'contract',
    'deliveryTime',
    'delivery',
    'paymentTerms',
    'comment',
  ];

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
    this.meta = const SupplierMeta(),
    this.offers = const [],
  });

  final String id;
  final String displayName;
  final String? sourceFileName;
  final SupplierMeta meta;
  final List<Offer> offers;

  /// Итог по поставщику — вычисляется, не хранится.
  double get total {
    var sum = 0.0;
    for (final o in offers) {
      sum += o.sumWithVat ?? 0;
    }
    return sum;
  }

  bool get hasAnySum => offers.any((o) => o.sumWithVat != null);

  factory SupplierBlock.empty({String displayName = ''}) => SupplierBlock(
        id: newId(),
        displayName: displayName,
        offers: [Offer.empty()],
      );

  SupplierBlock copyWith({
    String? displayName,
    String? sourceFileName,
    SupplierMeta? meta,
    List<Offer>? offers,
  }) {
    return SupplierBlock(
      id: id,
      displayName: displayName ?? this.displayName,
      sourceFileName: sourceFileName ?? this.sourceFileName,
      meta: meta ?? this.meta,
      offers: offers ?? this.offers,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        'sourceFileName': sourceFileName,
        'meta': meta.toJson(),
        'offers': offers.map((o) => o.toJson()).toList(),
      };

  factory SupplierBlock.fromJson(Map<String, dynamic> json) => SupplierBlock(
        id: (json['id'] as String?) ?? newId(),
        displayName: (json['displayName'] as String?) ?? '',
        sourceFileName: json['sourceFileName'] as String?,
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
  /// поставщиков и позиций заявки.
  int get maxRows {
    var maxOffers = 0;
    for (final s in suppliers) {
      if (s.offers.length > maxOffers) maxOffers = s.offers.length;
    }
    return maxOffers > requestItems.length ? maxOffers : requestItems.length;
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