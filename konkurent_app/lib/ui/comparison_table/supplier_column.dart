import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_state_provider.dart';
import '../../providers/zoom_provider.dart';
import '../../utils/format.dart';
import '../constants.dart';
import 'drag_types.dart';
import 'editable_cell.dart';
import 'grid_box.dart';
import 'offer_row.dart';

/// Колонка одного поставщика: заголовок с drag-handle, подзаголовки,
/// предложения (вертикальный reorder), мета и итог.
class SupplierColumn extends ConsumerWidget {
  const SupplierColumn({
    super.key,
    required this.supplierId,
    required this.index,
  });

  final String supplierId;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appStateProvider);
    final notifier = ref.read(appStateProvider.notifier);
    final m = ref.watch(tableMetricsProvider);

    final supplier = state.suppliers.firstWhere((s) => s.id == supplierId);
    final maxRows = state.maxRows + 1; // + запасная пустая строка
    final headerStyle = Theme.of(context).textTheme.titleSmall;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GridBox(
          width: m.supplierWidth,
          height: m.headerRowHeight,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Row(
            children: [
              Draggable<SupplierDrag>(
                data: SupplierDrag(supplierId),
                feedback: Material(
                  elevation: 4,
                  child: Chip(label: Text(supplier.displayName.isEmpty
                      ? 'Поставщик'
                      : supplier.displayName)),
                ),
                childWhenDragging: const Opacity(
                  opacity: 0.3,
                  child: Icon(Icons.drag_indicator),
                ),
                child: Padding(
                  key: ValueKey('supplier.$supplierId.handle'),
                  padding: EdgeInsets.symmetric(horizontal: 4 * m.scale),
                  child: Icon(Icons.drag_indicator, size: m.dragIconSize),
                ),
              ),
              Expanded(
                child: EditableCell(
                  testId: 'supplier.$supplierId.name',
                  hint: 'Имя поставщика',
                  value: supplier.displayName,
                  padding: EdgeInsets.symmetric(horizontal: 2 * m.scale),
                  onChanged: (v) => notifier.renameSupplier(supplierId, v),
                ),
              ),
              IconButton(
                key: ValueKey('supplier.$supplierId.delete'),
                iconSize: m.actionIconSize,
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(
                  minWidth: m.tapTargetLarge,
                  minHeight: m.tapTargetLarge,
                ),
                tooltip: 'Удалить поставщика',
                icon: const Icon(Icons.close),
                onPressed: () => notifier.removeSupplier(supplierId),
              ),
            ],
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _subHeader(context, m, 'Предложено', m.itemWidth, TextAlign.left),
            _subHeader(context, m, 'Кол-во', m.qtyWidth, TextAlign.center),
            _subHeader(context, m, 'Ед.', m.unitWidth, TextAlign.center),
            _subHeader(context, m, 'Ц/ед', m.priceWidth, TextAlign.center),
            _subHeader(context, m, 'Сумма', m.sumWidth, TextAlign.right),
          ],
        ),
        for (var i = 0; i < maxRows; i++)
          OfferRow(
            key: ValueKey('offerRow.$supplierId.$i'),
            supplierId: supplierId,
            index: i,
            offer: i < supplier.offers.length ? supplier.offers[i] : null,
            onReorder: (fromIndex, toIndex) {
              final target = toIndex < supplier.offers.length
                  ? supplier.offers[toIndex]
                  : null;
              if (target == null || target.isEmpty) {
                // Сброс на пустую строку — оставляем пробел на прежнем месте.
                notifier.moveOfferToEmpty(supplierId, fromIndex, toIndex);
              } else {
                notifier.reorderOffers(supplierId, fromIndex, toIndex);
              }
            },
          ),
        for (final meta in kMetaRows)
          GridBox(
            width: m.supplierWidth,
            height: m.metaRowHeight,
            child: EditableCell(
              testId: 'supplier.$supplierId.meta.${meta.key}',
              value: supplier.meta.value(meta.key),
              textAlign: TextAlign.center,
              onChanged: (v) => notifier.setMeta(supplierId, meta.key, v),
            ),
          ),
        GridBox(
          width: m.supplierWidth,
          height: m.totalRowHeight,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          alignment: Alignment.centerRight,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 12 * m.scale),
            child: Text(
              formatNumber(supplier.total),
              key: ValueKey('supplier.$supplierId.total'),
              style: headerStyle,
            ),
          ),
        ),
      ],
    );
  }

  Widget _subHeader(
    BuildContext context,
    TableMetrics m,
    String text,
    double width,
    TextAlign align,
  ) {
    return GridBox(
      width: width,
      height: m.subHeaderHeight,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      alignment: align == TextAlign.center
          ? Alignment.center
          : (align == TextAlign.right
              ? Alignment.centerRight
              : Alignment.centerLeft),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 8 * m.scale),
        child: Text(
          text,
          textAlign: align,
          style: Theme.of(context).textTheme.labelLarge,
        ),
      ),
    );
  }
}