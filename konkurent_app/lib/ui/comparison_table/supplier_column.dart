import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_state.dart';
import '../../providers/app_state_provider.dart';
import '../../providers/table_layout_provider.dart';
import '../../providers/zoom_provider.dart';
import '../../providers/view_preferences_provider.dart';
import '../../services/app_config_service.dart';
import '../../utils/format.dart';
import '../constants.dart';
import 'drag_types.dart';
import 'editable_cell.dart';
import 'grid_box.dart';
import 'offer_row.dart';

/// Колонка одного поставщика: заголовок (drag-handle, флажок «без НДС»,
/// кнопка пересчёта, ИНН, покрытие n/z), группы позиций заявки со строками
/// предложений (одиночная строка группы растянута на её высоту), зона без
/// привязки, мета и итог.
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
    final layout = ref.watch(tableLayoutProvider);
    final sumsOnly = ref.watch(sumsOnlyProvider);
    final showSecondary = ref.watch(showSumWithoutVatProvider);
    final vat = ref.watch(appConfigProvider).value?.vatRate ?? 0.22;

    final supplier = state.suppliers.firstWhere((s) => s.id == supplierId);
    final headerStyle = Theme.of(context).textTheme.titleSmall;
    final secondaryVisible = showSecondary && !supplier.withoutVat;
    final width = sumsOnly
        ? m.sumWidth
        : m.supplierWidth(withSumWithoutVat: secondaryVisible);
    final coverage = supplierCoverage(supplier, state.requestItems);

    // Дроп предложения на строку: свой поставщик — перепривязка/порядок,
    // чужой — перенос с привязкой к группе строки.
    void handleDrop(OfferDrag drag, Offer? target, String? groupRequestId) {
      if (drag.supplierId == supplierId) {
        notifier.moveOfferWithinSupplier(
          supplierId: supplierId,
          offerId: drag.offerId,
          requestItemId: groupRequestId,
          beforeOfferId: target?.id,
        );
      } else {
        notifier.moveOfferToSupplier(
          fromSupplierId: drag.supplierId,
          offerId: drag.offerId,
          toSupplierId: supplierId,
          requestItemId: groupRequestId,
          beforeOfferId: target?.id,
        );
      }
    }

    final children = <Widget>[
      _headerBox(
          context, m, width, supplier, coverage, headerStyle, notifier),
      if (sumsOnly)
        _subHeader(context, m, 'Сумма', width, TextAlign.right)
      else ...[
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
      ],
    ];

    // Группы позиций заявки.
    for (final g in layout.groups) {
      final linked = supplier.offers
          .where((o) => o.linkedRequestItemId == g.item.id)
          .toList();
      if (linked.length <= 1) {
        children.add(OfferRow(
          key: ValueKey('offerRow.$supplierId.g.${g.item.id}'),
          supplierId: supplierId,
          blockIndex: index,
          rowIndex: g.firstRow,
          offer: linked.isEmpty ? null : linked.first,
          rowHeight: g.height,
          withoutVat: supplier.withoutVat,
          groupRequestId: g.item.id,
          sumsOnly: sumsOnly,
          onOfferDrop: (drag, target) => handleDrop(drag, target, g.item.id),
        ));
      } else {
        for (var j = 0; j < linked.length; j++) {
          final h = j < g.heights.length - 1
              ? g.heights[j]
              : g.heights.sublist(j).fold(0.0, (a, b) => a + b);
          children.add(OfferRow(
            key: ValueKey('offerRow.$supplierId.g.${g.item.id}.$j'),
            supplierId: supplierId,
            blockIndex: index,
            rowIndex: g.firstRow + j,
            offer: linked[j],
            rowHeight: h,
            withoutVat: supplier.withoutVat,
            groupRequestId: g.item.id,
            sumsOnly: sumsOnly,
            onOfferDrop: (drag, target) => handleDrop(drag, target, g.item.id),
          ));
        }
      }
    }

    // Зона без привязки (+ запасная пустая строка).
    final unlinked = supplier.offers
        .where((o) => o.linkedRequestItemId == null)
        .toList();
    for (var j = 0; j < layout.unlinkedRows; j++) {
      children.add(OfferRow(
        key: ValueKey('offerRow.$supplierId.zone.$j'),
        supplierId: supplierId,
        blockIndex: index,
        rowIndex: layout.unlinkedFirstRow + j,
        zoneIndex: j,
        offer: j < unlinked.length ? unlinked[j] : null,
        rowHeight: layout.unlinkedHeights[j],
        withoutVat: supplier.withoutVat,
        groupRequestId: null,
        sumsOnly: sumsOnly,
        onOfferDrop: (drag, target) => handleDrop(drag, target, null),
      ));
    }

    for (var j = 0; j < kMetaRows.length; j++) {
      children.add(GridBox(
        width: width,
        height: layout.metaHeights[j],
        child: EditableCell(
          testId: 'supplier.$supplierId.meta.${kMetaRows[j].key}',
          value: supplier.meta.value(kMetaRows[j].key),
          textAlign: TextAlign.center,
          onChanged: (v) => notifier.setMeta(supplierId, kMetaRows[j].key, v),
        ),
      ));
    }
    children.add(_totalBox(context, m, width, supplier, vat, headerStyle));

    return DragTarget<OfferDrag>(
      // Дроп «в колонку мимо строк» — в конец зоны без привязки.
      onWillAcceptWithDetails: (details) =>
          details.data.supplierId != supplierId,
      onAcceptWithDetails: (details) => notifier.moveOfferToSupplier(
        fromSupplierId: details.data.supplierId,
        offerId: details.data.offerId,
        toSupplierId: supplierId,
        requestItemId: null,
      ),
      builder: (context, candidates, rejected) => Column(
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }

  Widget _headerBox(BuildContext context, TableMetrics m, double width,
      SupplierBlock supplier,
      ({int covered, int total}) coverage,
      TextStyle? headerStyle,
      AppStateNotifier notifier) {
    final coverageText = coverage.total > 0
        ? ' (${coverage.covered}/${coverage.total})'
        : '';
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
                  child: Text('без НДС$coverageText',
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
                // ИНН: видимое копируемое поле.
                Expanded(
                  child: SizedBox(
                    height: 20 * m.scale,
                    child: EditableCell(
                      testId: 'supplier.${supplier.id}.inn',
                      value: supplier.inn ?? '',
                      hint: 'ИНН',
                      numeric: true,
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      onChanged: (v) =>
                          notifier.setSupplierInn(supplier.id, v),
                    ),
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
