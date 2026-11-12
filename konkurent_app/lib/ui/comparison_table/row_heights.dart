import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_state_provider.dart';
import '../../providers/view_preferences_provider.dart';
import '../../providers/zoom_provider.dart';
import '../constants.dart';

/// Высоты строк таблицы: строка данных = максимум по всем ячейкам этой строки
/// (панель заявки + все поставщики) с переносом по словам, но не меньше
/// базовой. Пересчитывается от состояния и масштаба.
///
/// Ширины текста берутся из TableMetrics (fixedNameTextWidth и т.п.) — те же
/// числа, по которым раскладываются сами ячейки, иначе измеренный перенос
/// разойдётся с реальным и последняя строка текста обрежется.
class TableHeights {
  const TableHeights(this.data, this.meta);

  /// Высоты строк данных (maxRows = state.maxRows + 1 запасная).
  final List<double> data;

  /// Высоты мета-строк (kMetaRows).
  final List<double> meta;
}

final rowHeightsProvider = Provider<TableHeights>((ref) {
  final state = ref.watch(appStateProvider);
  final m = ref.watch(tableMetricsProvider);
  final sumsOnly = ref.watch(sumsOnlyProvider);
  final showSecondary = ref.watch(showSumWithoutVatProvider);
  final scale = m.scale;

  final maxRows = state.maxRows + 1; // + запасная пустая строка
  final data = List.filled(maxRows, m.dataRowHeight);
  final meta = List.filled(kMetaRows.length, m.metaRowHeight);

  // Ширина мета-ячейки зависит от режима отображения блока.
  final metaWidth = (sumsOnly
          ? m.sumWidth
          : m.supplierWidth(withSumWithoutVat: showSecondary))
      .roundToDouble();

  void growData(int row, String text, double available) {
    if (row >= data.length) return;
    final h = _measuredHeight(text, available, scale, m.dataRowHeight);
    if (h > data[row]) data[row] = h;
  }

  for (var i = 0; i < state.requestItems.length; i++) {
    final item = state.requestItems[i];
    growData(i, item.name, m.fixedNameTextWidth);
    growData(i, item.qty, m.fixedQtyTextWidth);
  }
  for (final s in state.suppliers) {
    for (var i = 0; i < s.offers.length; i++) {
      final o = s.offers[i];
      growData(i, o.itemName, m.itemTextWidth);
      growData(i, o.unit, m.unitTextWidth);
    }
    for (var j = 0; j < kMetaRows.length; j++) {
      final h = _measuredHeight(
          s.meta.value(kMetaRows[j].key), metaWidth - 18, scale, m.metaRowHeight);
      if (h > meta[j]) meta[j] = h;
    }
  }
  return TableHeights(data, meta);
});

double _measuredHeight(
    String text, double availableWidth, double scale, double base) {
  if (text.trim().isEmpty) return base;
  final painter = TextPainter(
    // Дисплейный текст ячейки — bodyMedium (14) с масштабом ZoomScope;
    // измеряем тем же эффективным размером шрифта.
    text: TextSpan(text: text, style: TextStyle(fontSize: 14 * scale)),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: math.max(availableWidth, 20));
  final height = painter.height + 8 + 2; // запас на паддинги/рамки
  painter.dispose();
  return math.max(base, height);
}
