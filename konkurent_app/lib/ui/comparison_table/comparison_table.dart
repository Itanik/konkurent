import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_state.dart';
import '../../providers/app_state_provider.dart';
import 'fixed_panel.dart';
import 'drag_types.dart';
import 'supplier_column.dart';

/// Склейка фиксированной левой панели и горизонтально скроллящихся колонок
/// поставщиков. Вертикальный скролл — общий для обеих частей.
class ComparisonTable extends ConsumerWidget {
  const ComparisonTable({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appStateProvider);
    final notifier = ref.read(appStateProvider.notifier);

    if (state.suppliers.isEmpty) {
      return _EmptyState(onAdd: () {
        notifier.addSupplier(SupplierBlock.empty());
      });
    }

    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FixedPanel(),
          Expanded(
            child: SingleChildScrollView(
              key: const ValueKey('suppliers.horizontalScroll'),
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < state.suppliers.length; i++)
                    DragTarget<SupplierDrag>(
                      onWillAcceptWithDetails: (details) =>
                          details.data.supplierId != state.suppliers[i].id,
                      onAcceptWithDetails: (details) {
                        final from = state.suppliers.indexWhere(
                            (s) => s.id == details.data.supplierId);
                        if (from == -1) return;
                        notifier.reorderSuppliers(from, i);
                      },
                      builder: (context, candidates, rejected) {
                        final column = SupplierColumn(
                          supplierId: state.suppliers[i].id,
                          index: i,
                        );
                        if (candidates.isEmpty) return column;
                        return DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Theme.of(context).colorScheme.primary,
                              width: 2,
                            ),
                          ),
                          child: column,
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.table_chart_outlined,
              size: 64, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 16),
          const Text('Таблица пуста'),
          const SizedBox(height: 8),
          const Text('Перетащите счёт или добавьте поставщика вручную'),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const ValueKey('empty.addSupplier'),
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Добавить поставщика'),
          ),
        ],
      ),
    );
  }
}