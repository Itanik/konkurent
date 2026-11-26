import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_state_provider.dart';
import '../../providers/best_variant_provider.dart';
import '../../services/app_config_service.dart';
import '../../services/best_offer.dart';
import '../../utils/format.dart';

/// Панель под таблицей: лучшие варианты закупки по числу поставщиков
/// («Поставщик1: сумма», «П1+П2: сумма», …). Клик по строке временно
/// подсвечивает выигравшие суммы и колонки поставщиков.
class BestVariantPanel extends ConsumerWidget {
  const BestVariantPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appStateProvider);
    final config = ref.watch(appConfigProvider).value;
    final vat = config?.vatRate ?? 0.22;
    final maxSuppliers = config?.maxSuppliers ?? 3;
    final highlight = ref.watch(variantHighlightProvider);
    final notifier = ref.read(variantHighlightProvider.notifier);

    final variants = bestProcurementVariants(state,
        vat: vat, maxSuppliers: maxSuppliers);
    if (variants.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: EdgeInsets.fromLTRB(
          12, 8, 12, 12),
      padding: EdgeInsets.symmetric(vertical: 6, horizontal: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Лучшие варианты закупки',
              style: Theme.of(context).textTheme.labelLarge),
          for (final v in variants)
            InkWell(
              key: ValueKey('variant.${v.label}'),
              onTap: () {
                if (highlight.supplierIds.toSet().containsAll(v.supplierIds) &&
                    highlight.supplierIds.length == v.supplierIds.length) {
                  notifier.clear();
                  return;
                }
                // Выигравшие предложения: из каждого поставщика комбинации —
                // предложения, привязанные к покрытым позициям.
                final offerIds = <String>{};
                for (final sid in v.supplierIds) {
                  final s =
                      state.suppliers.firstWhere((s) => s.id == sid);
                  for (final o in s.offers) {
                    final item = state.requestItems
                        .where((it) => it.id == o.linkedRequestItemId)
                        .firstOrNull;
                    if (item == null) continue;
                    // позиция покрыта этим поставщиком, если у него есть
                    // хоть одно связанное предложение
                    final has = s.offers.any(
                        (x) => x.linkedRequestItemId == o.linkedRequestItemId);
                    if (has) offerIds.add(o.id);
                  }
                }
                notifier.set(VariantHighlight(
                  offerIds: offerIds,
                  supplierIds: {...v.supplierIds},
                ));
              },
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${v.label}${v.coverageSuffix}:',
                        style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(width: 8),
                    Text(formatNumber(v.total),
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 2),
          Text(
            'Клик по варианту подсвечивает его суммы. Позиция назначается '
            'поставщику целиком; критерий — минимальная сумма.',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: Theme.of(context).hintColor),
          ),
        ],
      ),
    );
  }
}
