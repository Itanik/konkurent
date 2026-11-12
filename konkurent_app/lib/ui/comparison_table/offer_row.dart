import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_state.dart';
import '../../providers/app_state_provider.dart';
import '../../providers/zoom_provider.dart';
import '../../services/app_config_service.dart';
import '../../utils/format.dart';
import '../../utils/request_items_parse.dart';
import '../../providers/view_preferences_provider.dart';
import 'drag_types.dart';
import 'editable_cell.dart';
import 'grid_box.dart';

/// Строка предложения одного поставщика. Пустая строка ([offer] == null) тоже
/// редактируема: ввод создаёт предложение. Перетаскивается вертикально только
/// внутри своего блока (drag за handle).
///
/// Колонки цен/сумм: основная пара — базис блока («без НДС» или с НДС);
/// вторая пара (цена и сумма другого базиса) показывается тумблером
/// «Сумма без НДС» в тулбаре и остаётся редактируемой. В режиме сумм
/// ([sumsOnly]) рендерится только ячейка суммы позиции.
class OfferRow extends ConsumerWidget {
  const OfferRow({
    super.key,
    required this.supplierId,
    required this.offer,
    required this.index,
    required this.rowHeight,
    required this.withoutVat,
    required this.onReorder,
    this.sumsOnly = false,
  });

  final String supplierId;

  /// null — пустая (запасная) строка.
  final Offer? offer;
  final int index;

  /// Высота строки (автовысота из rowHeightsProvider).
  final double rowHeight;

  /// Режим поставщика «без НДС»: основная пара колонок — без НДС.
  final bool withoutVat;

  final void Function(int fromIndex, int toIndex) onReorder;

  /// Режим сумм: только редактируемая ячейка суммы позиции.
  final bool sumsOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = offer;
    final notifier = ref.read(appStateProvider.notifier);
    final m = ref.watch(tableMetricsProvider);
    final vat = ref.watch(appConfigProvider).value?.vatRate ?? 0.22;
    final showSecondary = ref.watch(showSumWithoutVatProvider) && !withoutVat;
    final hasContent = current != null && !current.isEmpty;
    final keyBase = current != null
        ? 'offer.${current.id}'
        : 'offer.empty.$supplierId.$index';

    Widget sumCell({required bool net, required double width}) => GridBox(
          width: width,
          height: rowHeight,
          child: EditableCell(
            testId: net ? '$keyBase.sumNet' : '$keyBase.sum',
            value: formatEditable(
                current?.displaySum(withoutVat: net, vat: vat)),
            numeric: true,
            textAlign: TextAlign.right,
            onChanged: (v) {
              final n = parseNumber(v);
              notifier.setOfferAt(
                supplierId,
                index,
                (o) => o.withSumInput(n, withoutVat: net, vat: vat),
              );
            },
          ),
        );

    Widget priceCell({required bool net, required double width}) => GridBox(
          width: width,
          height: rowHeight,
          child: EditableCell(
            testId: net ? '$keyBase.priceNet' : '$keyBase.price',
            value: formatEditable(
                current?.displayPrice(withoutVat: net, vat: vat)),
            numeric: true,
            textAlign: TextAlign.right,
            hint: 'цена',
            onChanged: (v) {
              final n = parseNumber(v);
              notifier.setOfferAt(
                supplierId,
                index,
                (o) => o.withPriceInput(n, withoutVat: net),
              );
            },
          ),
        );

    if (sumsOnly) {
      return sumCell(net: withoutVat, width: m.sumWidth);
    }

    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GridBox(
          width: m.itemWidth,
          height: rowHeight,
          child: Row(
            children: [
              if (hasContent)
                Draggable<OfferDrag>(
                  data: OfferDrag(supplierId, index),
                  feedback: Material(
                    elevation: 4,
                    child: Chip(
                      label: Text(
                        current.itemName.isEmpty
                            ? 'Позиция'
                            : current.itemName,
                      ),
                    ),
                  ),
                  childWhenDragging: const Opacity(
                    opacity: 0.3,
                    child: Icon(Icons.drag_indicator),
                  ),
                  child: Padding(
                    key: ValueKey('$keyBase.handle'),
                    padding: EdgeInsets.symmetric(horizontal: 4 * m.scale),
                    child: Icon(Icons.drag_indicator, size: m.dragIconSize),
                  ),
                )
              else
                SizedBox(width: m.handleGap),
              Expanded(
                child: EditableCell(
                  testId: '$keyBase.item',
                  value: current?.itemName ?? '',
                  onChanged: (v) => notifier.setOfferAt(
                    supplierId,
                    index,
                    (o) => o.copyWith(itemName: v),
                  ),
                  onPaste: (text) {
                    if (!text.contains('\t') && !text.contains('\n')) {
                      return false;
                    }
                    final items = parseRequestItems(text);
                    if (items.isEmpty) return false;
                    notifier.pasteOffers(supplierId, index, items);
                    return true;
                  },
                ),
              ),
              if (current != null)
                IconButton(
                  key: ValueKey('$keyBase.delete'),
                  iconSize: m.actionIconSize,
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(
                    minWidth: m.tapTarget,
                    minHeight: m.tapTarget,
                  ),
                  tooltip: 'Удалить строку',
                  icon: const Icon(Icons.close),
                  onPressed: () => notifier.removeOfferAt(supplierId, index),
                )
              else
                SizedBox(width: m.tapTarget),
            ],
          ),
        ),
        GridBox(
          width: m.qtyWidth,
          height: rowHeight,
          child: EditableCell(
            testId: '$keyBase.qty',
            value: formatEditable(current?.qty),
            numeric: true,
            textAlign: TextAlign.center,
            onChanged: (v) {
              final n = parseNumber(v);
              notifier.setOfferAt(
                supplierId,
                index,
                (o) => o.copyWith(qty: n, clearQty: n == null),
              );
            },
          ),
        ),
        GridBox(
          width: m.unitWidth,
          height: rowHeight,
          child: EditableCell(
            testId: '$keyBase.unit',
            value: current?.unit ?? '',
            textAlign: TextAlign.center,
            onChanged: (v) => notifier.setOfferAt(
              supplierId,
              index,
              (o) => o.copyWith(unit: v),
            ),
          ),
        ),
        priceCell(net: withoutVat, width: m.priceWidth),
        if (showSecondary) ...[
          priceCell(net: true, width: m.priceWidth),
          sumCell(net: true, width: m.sumWithoutVatWidth),
        ],
        sumCell(net: withoutVat, width: m.sumWidth),
      ],
    );

    return DragTarget<OfferDrag>(
      onWillAcceptWithDetails: (details) =>
          details.data.supplierId == supplierId &&
          details.data.fromIndex != index,
      onAcceptWithDetails: (details) =>
          onReorder(details.data.fromIndex, index),
      builder: (context, candidates, rejected) {
        if (candidates.isEmpty) return row;
        return DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(
              color: Theme.of(context).colorScheme.primary,
              width: 2,
            ),
          ),
          child: row,
        );
      },
    );
  }
}
