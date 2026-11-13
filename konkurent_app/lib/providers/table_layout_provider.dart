import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_state.dart';
import '../utils/format.dart';
import '../ui/constants.dart';
import 'app_state_provider.dart';
import 'view_preferences_provider.dart';
import 'zoom_provider.dart';

/// Группа строк таблицы: одна позиция заявки и строки предложений всех
/// поставщиков, привязанных к ней. Ячейки заявки и поставщики с одним
/// предложением растягиваются (merge) на всю высоту группы.
class RowGroup {
  const RowGroup({
    required this.item,
    required this.rows,
    required this.firstRow,
    required this.heights,
  });

  final RequestItem item;

  /// Высота группы в физических строках: max по поставщикам, минимум 1.
  final int rows;

  /// Индекс первой физической строки группы.
  final int firstRow;

  /// Высоты строк группы (последняя втянула в себя «растяжку» группы).
  final List<double> heights;

  int get lastRow => firstRow + rows - 1;

  double get height =>
      heights.fold(0.0, (sum, h) => sum + h);
}

/// Раскладка таблицы: группы + зона без привязки + высоты.
class TableLayout {
  const TableLayout({
    required this.groups,
    required this.unlinkedFirstRow,
    required this.unlinkedRows,
    required this.unlinkedHeights,
    required this.metaHeights,
  });

  final List<RowGroup> groups;

  /// Первая физическая строка зоны без привязки (после всех групп).
  final int unlinkedFirstRow;

  /// Число строк зоны без привязки (max непривязанных предложений по
  /// поставщикам + запасная редактируемая строка, минимум 1).
  final int unlinkedRows;
  final List<double> unlinkedHeights;
  final List<double> metaHeights;

  int get totalRows => unlinkedFirstRow + unlinkedRows;

  double get unlinkedHeight =>
      unlinkedHeights.fold(0.0, (sum, h) => sum + h);

  /// Группа, содержащая физическую строку [row] (null — зона без привязки).
  RowGroup? groupOfRow(int row) {
    for (final g in groups) {
      if (row >= g.firstRow && row <= g.lastRow) return g;
    }
    return null;
  }

  /// Высота физической строки.
  double rowHeight(int row) {
    final g = groupOfRow(row);
    if (g != null) return g.heights[row - g.firstRow];
    final j = row - unlinkedFirstRow;
    return j >= 0 && j < unlinkedHeights.length ? unlinkedHeights[j] : 44.0;
  }
}

/// Покрытие заявки поставщиком: (закрыто позиций, всего позиций).
/// Позиция закрыта, когда Σ кол-во привязанных предложений ≥ заявленного
/// (или есть хотя бы одно предложение, если в заявке не указано кол-во).
({int covered, int total}) supplierCoverage(
    SupplierBlock supplier, List<RequestItem> items) {
  var covered = 0;
  var total = 0;
  for (final item in items) {
    if (item.name.trim().isEmpty) continue;
    total++;
    final linked = supplier.offers
        .where((o) => o.linkedRequestItemId == item.id)
        .toList();
    if (linked.isEmpty) continue;
    final requiredQty = parseNumber(item.qty);
    if (requiredQty == null || requiredQty <= 0) {
      covered++;
      continue;
    }
    var qtySum = 0.0;
    for (final o in linked) {
      qtySum += o.qty ?? 0;
    }
    if (qtySum >= requiredQty) covered++;
  }
  return (covered: covered, total: total);
}

final tableLayoutProvider = Provider<TableLayout>((ref) {
  final state = ref.watch(appStateProvider);
  final m = ref.watch(tableMetricsProvider);
  final scale = m.scale;
  final sumsOnly = ref.watch(sumsOnlyProvider);

  // --- структура -------------------------------------------------------------
  final groups = <RowGroup>[];
  var row = 0;
  for (final item in state.requestItems) {
    var maxLinked = 1;
    for (final s in state.suppliers) {
      final count =
          s.offers.where((o) => o.linkedRequestItemId == item.id).length;
      if (count > maxLinked) maxLinked = count;
    }
    final heights =
        List.filled(maxLinked, m.dataRowHeight, growable: true);
    groups.add(RowGroup(
      item: item,
      rows: maxLinked,
      firstRow: row,
      heights: heights,
    ));
    row += maxLinked;
  }

  var unlinkedRows = 1; // + запасная редактируемая строка
  for (final s in state.suppliers) {
    final count =
        s.offers.where((o) => o.linkedRequestItemId == null).length;
    if (count + 1 > unlinkedRows) unlinkedRows = count + 1;
  }
  final unlinkedHeights =
      List.filled(unlinkedRows, m.dataRowHeight, growable: true);

  final metaHeights = List.filled(kMetaRows.length, m.metaRowHeight);

  // --- замер текста ----------------------------------------------------------
  void growRow(int r, String text, double available) {
    final h = _measure(text, available, scale);
    if (r < 0) return;
    for (final g in groups) {
      if (r >= g.firstRow && r <= g.lastRow) {
        if (h > g.heights[r - g.firstRow]) {
          g.heights[r - g.firstRow] = h;
        }
        return;
      }
    }
    final j = r - row;
    if (j >= 0 && j < unlinkedHeights.length && h > unlinkedHeights[j]) {
      unlinkedHeights[j] = h;
    }
  }

  if (!sumsOnly) {
    for (final s in state.suppliers) {
      for (final o in s.offers) {
        final g = groups
            .where((g) => g.item.id == o.linkedRequestItemId)
            .firstOrNull;
        if (g == null) {
          // непривязанное — позиция в зоне определяется порядком среди
          // непривязанных предложений этого поставщика
          final idx = s.offers
              .where((x) => x.linkedRequestItemId == null)
              .toList()
              .indexOf(o);
          growRow(row + idx, o.itemName, m.itemTextWidth);
          growRow(row + idx, o.unit, m.unitTextWidth);
        } else {
          final idx = s.offers
              .where((x) => x.linkedRequestItemId == o.linkedRequestItemId)
              .toList()
              .indexOf(o);
          growRow(g.firstRow + idx, o.itemName, m.itemTextWidth);
          growRow(g.firstRow + idx, o.unit, m.unitTextWidth);
        }
      }
    }
  }

  // Ячейки заявки тянут всю группу: если текст позиции выше суммы строк,
  // разница уходит в последнюю строку группы.
  final metaWidth = (sumsOnly
          ? m.sumWidth
          : m.supplierWidth(withSumWithoutVat: ref.watch(showSumWithoutVatProvider)))
      .roundToDouble();
  for (final g in groups) {
    final nameH = _measure(g.item.name, m.fixedNameTextWidth, scale);
    final qtyH = _measure(g.item.qty, m.fixedQtyTextWidth, scale);
    final unitH = _measure(g.item.unit, m.unitTextWidth, scale);
    final need = math.max(nameH, math.max(qtyH, unitH));
    final have = g.height;
    if (need > have) {
      g.heights[g.heights.length - 1] += need - have;
    }
  }

  for (final s in state.suppliers) {
    for (var j = 0; j < kMetaRows.length; j++) {
      final h = _measure(
          s.meta.value(kMetaRows[j].key), metaWidth - 18, scale);
      if (h > metaHeights[j]) metaHeights[j] = h;
    }
  }

  return TableLayout(
    groups: groups,
    unlinkedFirstRow: row,
    unlinkedRows: unlinkedRows,
    unlinkedHeights: unlinkedHeights,
    metaHeights: metaHeights,
  );
});

/// Высота текста ячейки с переносом (см. гочу про rowHeightsProvider
/// в AGENTS.md — измерение обязано совпадать с дисплейным рендером).
double _measure(String text, double availableWidth, double scale) {
  if (text.trim().isEmpty) return 0;
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(fontSize: 14 * scale, height: 20 / 14),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: math.max(availableWidth, 20));
  final height = painter.height + 8 + 2;
  painter.dispose();
  return height;
}
