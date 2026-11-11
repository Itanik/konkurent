import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_state_provider.dart';
import '../../providers/zoom_provider.dart';
import '../constants.dart';

/// Высоты строк таблицы: строка данных = максимум по всем ячейкам этой строки
/// (панель заявки + все поставщики) с переносом по словам, но не меньше
/// базовой. Пересчитывается от состояния и масштаба.
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
  final scale = m.scale;

  final maxRows = state.maxRows + 1; // + запасная пустая строка
  final data = List.filled(maxRows, m.dataRowHeight);
  final meta = List.filled(kMetaRows.length, m.metaRowHeight);

  // Ширины, доступные тексту в ячейках (минус padding, кнопки и хендл).
  final nameAvail = m.fixedNameWidth - m.tapTarget - 16 * scale;
  final fixedQtyAvail = m.fixedQtyWidth - 16 * scale;
  final itemAvail = m.itemWidth - m.handleGap - m.tapTarget - 16 * scale;
  final unitAvail = m.unitWidth - 16 * scale;
  final metaAvail = m.supplierWidth() - 16 * scale;

  void growData(int row, String text, double available) {
    if (row >= data.length) return;
    final h = _measuredHeight(text, available, scale, m.dataRowHeight);
    if (h > data[row]) data[row] = h;
  }

  for (var i = 0; i < state.requestItems.length; i++) {
    final item = state.requestItems[i];
    growData(i, item.name, nameAvail);
    growData(i, item.qty, fixedQtyAvail);
  }
  for (final s in state.suppliers) {
    for (var i = 0; i < s.offers.length; i++) {
      final o = s.offers[i];
      growData(i, o.itemName, itemAvail);
      growData(i, o.unit, unitAvail);
    }
    for (var j = 0; j < kMetaRows.length; j++) {
      final h = _measuredHeight(
          s.meta.value(kMetaRows[j].key), metaAvail, scale, m.metaRowHeight);
      if (h > meta[j]) meta[j] = h;
    }
  }
  return TableHeights(data, meta);
});

double _measuredHeight(
    String text, double availableWidth, double scale, double base) {
  if (text.trim().isEmpty) return base;
  final painter = TextPainter(
    // В таблице текст рендерится bodyMedium (14) со scaler'ом масштаба —
    // измеряем тем же размером, чтобы перенос совпал с реальным.
    text: TextSpan(text: text, style: TextStyle(fontSize: 14 * scale)),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: math.max(availableWidth, 20));
  final height = painter.height + 8 * scale + 2; // padding ячейки + рамки
  painter.dispose();
  return math.max(base, height);
}
