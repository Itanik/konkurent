import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_state.dart';
import '../../providers/app_state_provider.dart';
import '../../providers/zoom_provider.dart';
import '../../providers/view_preferences_provider.dart';
import '../../services/app_config_service.dart';
import '../../utils/format.dart';
import '../constants.dart';
import 'drag_types.dart';
import 'editable_cell.dart';
import 'grid_box.dart';
import 'offer_row.dart';
import 'row_heights.dart';

/// Колонка одного поставщика: заголовок с drag-handle, флажком «без НДС» и
/// кнопкой «позиции без НДС», подзаголовки, предложения (вертикальный
/// reorder), мета и итог.
///
/// Основная пара колонок цен/сумм следует базису блока (флажок «без НДС»);
/// вторая пара показывается тумблером «Сумма без НДС» в тулбаре. В режиме
/// сумм блок схлопывается до колонки сумм — строки позиций остаются.
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
    final showSecondary = ref.watch(showSumWithoutVatProvider);
    final vat = ref.watch(appConfigProvider).value?.vatRate ?? 0.22;

    final supplier = state.suppliers.firstWhere((s) => s.id == supplierId);
    final maxRows = heights.data.length;
    final headerStyle = Theme.of(context).textTheme.titleSmall;
    final secondaryVisible = showSecondary && !supplier.withoutVat;
    final width = sumsOnly
        ? m.sumWidth
        : m.supplierWidth(withSumWithoutVat: secondaryVisible);

    if (sumsOnly) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _headerBox(context, m, width, supplier, headerStyle, notifier),
          _subHeader(context, m, 'Сумма', width, TextAlign.right),
          for (var i = 0; i < maxRows; i++)
            OfferRow(
              key: ValueKey('offerRow.$supplierId.$i'),
              supplierId: supplierId,
              index: i,
              rowHeight: heights.data[i],
              withoutVat: supplier.withoutVat,
              offer: i < supplier.offers.length ? supplier.offers[i] : null,
              sumsOnly: true,
              onReorder: (_, __) {},
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
          _totalBox(context, m, width, supplier, vat, headerStyle),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _headerBox(context, m, width, supplier, headerStyle, notifier),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _subHeader(context, m, 'Предложено', m.itemWidth, TextAlign.left),
            _subHeader(context, m, 'Кол-во', m.qtyWidth, TextAlign.center),
            _subHeader(context, m, 'Ед.', m.unitWidth, TextAlign.center),
            _subHeader(context, m, supplier.withoutVat ? 'Ц/ед б/НДС' : 'Ц/ед',
                m.priceWidth, TextAlign.center),
            if (secondaryVisible) ...[
              _subHeader(
                  context, m, 'Ц/ед б/НДС', m.priceWidth, TextAlign.center),
              _subHeader(context, m, 'Сумма б/НДС', m.sumWithoutVatWidth,
                  TextAlign.right),
            ],
            _subHeader(context, m, supplier.withoutVat ? 'Сумма б/НДС' : 'Сумма',
                m.sumWidth, TextAlign.right),
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
        _totalBox(context, m, width, supplier, vat, headerStyle),
      ],
    );
  }

  Widget _headerBox(BuildContext context, TableMetrics m, double width,
      SupplierBlock supplier, TextStyle? headerStyle, AppStateNotifier notifier) {
    return GridBox(
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
                    data: SupplierDrag(supplier.id),
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
                      key: ValueKey('supplier.${supplier.id}.handle'),
                      padding:
                          EdgeInsets.symmetric(horizontal: 4 * m.scale),
                      child:
                          Icon(Icons.drag_indicator, size: m.dragIconSize),
                    ),
                  ),
                  Expanded(
                    child: EditableCell(
                      testId: 'supplier.${supplier.id}.name',
                      hint: 'Имя поставщика',
                      value: supplier.displayName,
                      padding:
                          EdgeInsets.symmetric(horizontal: 2 * m.scale),
                      onChanged: (v) =>
                          notifier.renameSupplier(supplier.id, v),
                    ),
                  ),
                  IconButton(
                    key: ValueKey('supplier.${supplier.id}.delete'),
                    iconSize: m.actionIconSize,
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints(
                      minWidth: m.tapTargetLarge,
                      minHeight: m.tapTargetLarge,
                    ),
                    tooltip: 'Удалить поставщика',
                    icon: const Icon(Icons.close),
                    onPressed: () => notifier.removeSupplier(supplier.id),
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
                    key: ValueKey('supplier.${supplier.id}.withoutVat'),
                    value: supplier.withoutVat,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: (v) => notifier.setSupplierWithoutVat(
                        supplier.id, v ?? false),
                  ),
                ),
                SizedBox(width: 4 * m.scale),
                Flexible(
                  child: Text('без НДС',
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: Theme.of(context).textTheme.labelSmall),
                ),
                SizedBox(width: 8 * m.scale),
                GestureDetector(
                  key: ValueKey('supplier.${supplier.id}.vatMove'),
                  onTap: () => notifier.recomputeVatFromNet(supplier.id),
                  child: Tooltip(
                    message:
                        'Позиции в счёте указаны без НДС — перенести и пересчитать с НДС',
                    child: Icon(Icons.price_change_outlined,
                        size: 16 * m.scale,
                        color: Theme.of(context).colorScheme.primary),
                  ),
                ),
                SizedBox(width: 4 * m.scale),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _totalBox(
    BuildContext context,
    TableMetrics m,
    double width,
    SupplierBlock supplier,
    double vat,
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
          formatNumber(supplier.total(vat)),
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
