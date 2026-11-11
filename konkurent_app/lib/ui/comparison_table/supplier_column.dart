import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_state.dart';
import '../../providers/app_state_provider.dart';
import '../../providers/zoom_provider.dart';
import '../../providers/view_preferences_provider.dart';
import '../../utils/format.dart';
import '../constants.dart';
import 'drag_types.dart';
import 'editable_cell.dart';
import 'grid_box.dart';
import 'offer_row.dart';
import 'row_heights.dart';

/// Колонка одного поставщика: заголовок с drag-handle и чекбоксом «без НДС»,
/// подзаголовки, предложения (вертикальный reorder), мета и итог.
/// В режиме сумм остаются только заголовок, мета и итог (ширина = колонка сумм).
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
    final heights = ref.watch(rowHeightsProvider);
    final sumsOnly = ref.watch(sumsOnlyProvider);
    final showSumWithoutVat = ref.watch(showSumWithoutVatProvider);

    final supplier = state.suppliers.firstWhere((s) => s.id == supplierId);
    final maxRows = heights.data.length;
    final headerStyle = Theme.of(context).textTheme.titleSmall;
    final width = sumsOnly
        ? m.sumWidth
        : m.supplierWidth(withSumWithoutVat: showSumWithoutVat);

    if (sumsOnly) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GridBox(
            width: width,
            height: m.headerRowHeight,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 6 * m.scale),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  supplier.displayName.isEmpty
                      ? 'Поставщик'
                      : supplier.displayName,
                  softWrap: true,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: headerStyle,
                ),
              ),
            ),
          ),
          for (var j = 0; j < kMetaRows.length; j++)
            GridBox(
              width: width,
              height: heights.meta[j],
              child: EditableCell(
                testId: 'supplier.$supplierId.meta.${kMetaRows[j].key}',
                value: supplier.meta.value(kMetaRows[j].key),
                textAlign: TextAlign.center,
                onChanged: (v) =>
                    notifier.setMeta(supplierId, kMetaRows[j].key, v),
              ),
            ),
          _totalBox(context, m, width, supplier, headerStyle),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GridBox(
          width: width,
          height: m.headerRowHeight,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 2 * m.scale),
            child: Column(
              children: [
                Expanded(
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
                          padding:
                              EdgeInsets.symmetric(horizontal: 4 * m.scale),
                          child:
                              Icon(Icons.drag_indicator, size: m.dragIconSize),
                        ),
                      ),
                      Expanded(
                        child: EditableCell(
                          testId: 'supplier.$supplierId.name',
                          hint: 'Имя поставщика',
                          value: supplier.displayName,
                          padding:
                              EdgeInsets.symmetric(horizontal: 2 * m.scale),
                          onChanged: (v) =>
                              notifier.renameSupplier(supplierId, v),
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
                  children: [
                    SizedBox(width: m.handleGap),
                    SizedBox(
                      width: 18 * m.scale,
                      height: 18 * m.scale,
                      child: Checkbox(
                        key: ValueKey('supplier.$supplierId.withoutVat'),
                        value: supplier.withoutVat,
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        onChanged: (v) =>
                            notifier.setSupplierWithoutVat(supplierId, v ?? false),
                      ),
                    ),
                    SizedBox(width: 4 * m.scale),
                    Text('без НДС',
                        style: Theme.of(context).textTheme.labelSmall),
                  ],
                ),
              ],
            ),
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _subHeader(context, m, 'Предложено', m.itemWidth, TextAlign.left),
            _subHeader(context, m, 'Кол-во', m.qtyWidth, TextAlign.center),
            _subHeader(context, m, 'Ед.', m.unitWidth, TextAlign.center),
            _subHeader(context, m, 'Ц/ед', m.priceWidth, TextAlign.center),
            if (showSumWithoutVat)
              _subHeader(context, m, 'Сумма б/НДС', m.sumWithoutVatWidth,
                  TextAlign.right),
            _subHeader(context, m, 'Сумма', m.sumWidth, TextAlign.right),
          ],
        ),
        for (var i = 0; i < maxRows; i++)
          OfferRow(
            key: ValueKey('offerRow.$supplierId.$i'),
            supplierId: supplierId,
            index: i,
            rowHeight: heights.data[i],
            withoutVat: supplier.withoutVat,
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
        for (var j = 0; j < kMetaRows.length; j++)
          GridBox(
            width: width,
            height: heights.meta[j],
            child: EditableCell(
              testId: 'supplier.$supplierId.meta.${kMetaRows[j].key}',
              value: supplier.meta.value(kMetaRows[j].key),
              textAlign: TextAlign.center,
              onChanged: (v) => notifier.setMeta(supplierId, kMetaRows[j].key, v),
            ),
          ),
        _totalBox(context, m, width, supplier, headerStyle),
      ],
    );
  }

  Widget _totalBox(
    BuildContext context,
    TableMetrics m,
    double width,
    SupplierBlock supplier,
    TextStyle? headerStyle,
  ) {
    return GridBox(
      width: width,
      height: m.totalRowHeight,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      alignment: Alignment.centerRight,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 12 * m.scale),
        child: Text(
          formatNumber(supplier.total),
          key: ValueKey('supplier.${supplier.id}.total'),
          style: headerStyle,
        ),
      ),
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
