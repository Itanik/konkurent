import 'package:flutter/material.dart';

// Высоты строк — общие для фиксированной панели и колонок поставщиков,
// иначе нарушается горизонтальное выравнивание.
const double kHeaderRowHeight = 56;
const double kSubHeaderHeight = 36;
const double kDataRowHeight = 44;
const double kMetaRowHeight = 40;
const double kTotalRowHeight = 48;

// Ширины фиксированных колонок.
const double kFixedNumberWidth = 52;
const double kFixedNameWidth = 240;
const double kFixedQtyWidth = 88;
const double kFixedWidth =
    kFixedNumberWidth + kFixedNameWidth + kFixedQtyWidth;

// Ширины колонок блока поставщика.
const double kItemWidth = 200;
const double kQtyWidth = 80;
const double kUnitWidth = 72;
const double kPriceWidth = 110;
const double kSumWidth = 120;
const double kSupplierWidth =
    kItemWidth + kQtyWidth + kUnitWidth + kPriceWidth + kSumWidth;

const EdgeInsets kCellPadding = EdgeInsets.symmetric(horizontal: 8, vertical: 4);
const BorderSide kGridSide = BorderSide(color: Color(0xFFD0D0D0));

// Мета-строки: ключ модели → подпись для UI и xlsx.
const List<({String key, String label})> kMetaRows = [
  (key: 'contract', label: 'Договор:'),
  (key: 'deliveryTime', label: 'Сроки поставки:'),
  (key: 'delivery', label: 'Доставка:'),
  (key: 'paymentTerms', label: 'Условия оплаты:'),
  (key: 'comment', label: 'Комментарий:'),
];