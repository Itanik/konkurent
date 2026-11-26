import 'dart:math' as math;

import '../models/app_state.dart';
import '../utils/format.dart';

/// Лучший вариант закупки: комбинация поставщиков и их предложений,
/// покрывающая позиции заявки, с минимальной суммой.
class BestVariant {
  const BestVariant({
    required this.label,
    required this.supplierIds,
    required this.total,
    required this.covered,
    required this.totalItems,
    required this.picks,
  });

  /// «Поставщик1+Поставщик2».
  final String label;
  final List<String> supplierIds;
  final double total;
  final int covered;
  final int totalItems;

  /// «Покрыто 3/5» для неполных вариантов (пусто для полных).
  String get coverageSuffix =>
      covered < totalItems ? ' — покрыто $covered/$totalItems' : '';

  /// Назначения позиций: индекс позиции заявки → индекс поставщика.
  /// По ним собираются ячейки сумм для формулы варианта в xlsx.
  final Map<int, int> picks;
}

/// Расчёт лучших вариантов закупки по связанным предложениям.
///
/// Позиция назначается поставщику целиком: суммой становятся Σ сумм его
/// предложений, привязанных к этой позиции (на базисе поставщика).
/// Позиция покрыта, если назначена; комбинированный вариант с k
/// поставщиками перебирает все подмножества размера k. При равных суммах
/// предпочтение — меньшему числу поставщиков (уже заложено порядком k).
List<BestVariant> bestProcurementVariants(
  AppState state, {
  required double vat,
  required int maxSuppliers,
}) {
  final suppliers = state.suppliers;
  final items = state.requestItems;
  if (suppliers.isEmpty || items.isEmpty) return const [];

  final totalItems = items.length;

  // Предрасчёт: стоимость позиции у каждого поставщика (null — не предлагает).
  final cost = List.generate(
      suppliers.length, (_) => List<double?>.filled(items.length, null));
  for (var b = 0; b < suppliers.length; b++) {
    final s = suppliers[b];
    for (var i = 0; i < items.length; i++) {
      final linked = s.offers
          .where((o) => o.linkedRequestItemId == items[i].id)
          .toList();
      if (linked.isEmpty) continue;
      var sum = 0.0;
      var hasAny = false;
      for (final o in linked) {
        final v = o.displaySum(withoutVat: s.withoutVat, vat: vat);
        if (v != null) {
          sum += v;
          hasAny = true;
        }
      }
      cost[b][i] = hasAny ? sum : null;
    }
  }

  // Подмножества поставщиков размера k (поставщиков немного, k ≤ 3).
  final result = <BestVariant>[];
  final kMax = math.min(math.max(maxSuppliers, 1), suppliers.length);
  final indices = List<int>.generate(suppliers.length, (i) => i);

  List<List<int>> combosOf(int k) {
    final out = <List<int>>[];
    void rec(int start, List<int> cur) {
      if (cur.length == k) {
        out.add(List.of(cur));
        return;
      }
      for (var i = start; i < indices.length; i++) {
        cur.add(indices[i]);
        rec(i + 1, cur);
        cur.removeLast();
      }
    }

    rec(0, []);
    return out;
  }

  for (var k = 1; k <= kMax; k++) {
    List<int>? bestCombo;
    var bestSum = double.infinity;
    var bestCovered = 0;
    for (final combo in combosOf(k)) {
      var sum = 0.0;
      var covered = 0;
      for (var i = 0; i < items.length; i++) {
        double? pick;
        for (final b in combo) {
          final v = cost[b][i];
          if (v != null && (pick == null || v < pick)) pick = v;
        }
        if (pick != null) {
          sum += pick;
          covered++;
        }
      }
      if (covered > bestCovered ||
          (covered == bestCovered && sum < bestSum)) {
        bestSum = sum;
        bestCovered = covered;
        bestCombo = combo;
      }
    }
    if (bestCombo == null || bestCovered == 0) continue;
    // Назначение позиции поставщику: минимум среди комбинации.
    final picks = <int, int>{};
    for (var i = 0; i < items.length; i++) {
      int? pickB;
      var pickV = double.infinity;
      for (final b in bestCombo) {
        final v = cost[b][i];
        if (v != null && v < pickV) {
          pickV = v;
          pickB = b;
        }
      }
      if (pickB != null) picks[i] = pickB;
    }
    result.add(BestVariant(
      label: bestCombo
          .map((b) =>
              suppliers[b].displayName.isEmpty
                  ? 'Поставщик ${b + 1}'
                  : suppliers[b].displayName)
          .join('+'),
      supplierIds: bestCombo.map((b) => suppliers[b].id).toList(),
      total: (bestSum * 100).roundToDouble() / 100,
      covered: bestCovered,
      totalItems: totalItems,
      picks: picks,
    ));
  }
  return result;
}

/// Форматированная сумма для панели.
String variantSumLabel(BestVariant v) => formatNumber(v.total);
