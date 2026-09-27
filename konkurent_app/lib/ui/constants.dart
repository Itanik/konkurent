import 'package:flutter/material.dart';

/// Размеры таблицы, пропорциональные масштабу интерфейса (`scale`).
/// Значения — логические пиксели при `scale == 1.0`.
///
/// Фиксированная панель и колонки поставщиков должны брать размеры из одного
/// и того же экземпляра, иначе нарушится горизонтальное выравнивание.
class TableMetrics {
  const TableMetrics(this.scale);

  final double scale;

  double get headerRowHeight => 56 * scale;
  double get subHeaderHeight => 36 * scale;
  double get dataRowHeight => 44 * scale;
  double get metaRowHeight => 40 * scale;
  double get totalRowHeight => 48 * scale;

  double get fixedNumberWidth => 52 * scale;
  double get fixedNameWidth => 240 * scale;
  double get fixedQtyWidth => 88 * scale;
  double get fixedWidth => fixedNumberWidth + fixedNameWidth + fixedQtyWidth;

  double get itemWidth => 200 * scale;
  double get qtyWidth => 80 * scale;
  double get unitWidth => 72 * scale;
  double get priceWidth => 110 * scale;
  double get sumWidth => 120 * scale;
  double get supplierWidth =>
      itemWidth + qtyWidth + unitWidth + priceWidth + sumWidth;

  EdgeInsets get cellPadding =>
      EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 4 * scale);

  double get dragIconSize => 18 * scale;
  double get actionIconSize => 16 * scale;
  double get tapTarget => 24 * scale;
  double get tapTargetLarge => 28 * scale;
  double get handleGap => 26 * scale;

  /// Высота шапки приложения (масштабируется пропорционально).
  double get toolbarHeight => kToolbarHeight * scale;

  double get toolbarIconSize => 24 * scale;
}

const BorderSide kGridSide = BorderSide(color: Color(0xFFD0D0D0));

// Мета-строки: ключ модели → подпись для UI и xlsx.
const List<({String key, String label})> kMetaRows = [
  (key: 'contract', label: 'Договор:'),
  (key: 'deliveryTime', label: 'Сроки поставки:'),
  (key: 'delivery', label: 'Доставка:'),
  (key: 'paymentTerms', label: 'Условия оплаты:'),
  (key: 'comment', label: 'Комментарий:'),
];