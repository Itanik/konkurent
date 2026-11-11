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
class OfferRow extends ConsumerWidget {
  const OfferRow({
    super.key,
    required this.supplierId,
    required this.offer,
    required this.index,
    required this.rowHeight,
    required this.withoutVat,
    required this.onReorder,
  });

  final String supplierId;

  /// null — пустая (запасная) строка.
  final Offer? offer;
  final int index;

  /// Высота строки (автовысота из rowHeightsProvider).
  final double rowHeight;

  /// Режим поставщика «без НДС».
  final bool withoutVat;

  final void Function(int fromIndex, int toIndex) onReorder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = offer;
    final notifier = ref.read(appStateProvider.notifier);
    final m = ref.watch(tableMetricsProvider);
    final vat = ref.watch(appConfigProvider).value?.vatRate ?? 0.22;
    final showSumWithoutVat = ref.watch(showSumWithoutVatProvider);
    final hasContent = current != null && !current.isEmpty;
    final keyBase = current != null
        ? 'offer.${current.id}'
        : 'offer.empty.$supplierId.$index';

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
        GridBox(
          width: m.priceWidth,
          height: rowHeight,
          child: EditableCell(
            testId: '$keyBase.price',
            value: formatEditable(current?.displayPrice(withoutVat)),
            numeric: true,
            textAlign: TextAlign.right,
            hint: 'цена',
            onChanged: (v) {
              final n = parseNumber(v);
              notifier.setOfferAt(
                supplierId,
                index,
                (o) => o.withPriceInput(n, withoutVat: withoutVat),
              );
            },
          ),
        ),
        if (showSumWithoutVat)
          GridBox(
            width: m.sumWithoutVatWidth,
            height: rowHeight,
            child: EditableCell(
              testId: '$keyBase.sumWithoutVat',
              value: formatEditable(current?.displaySumWithoutVat(
                  withoutVat, vat)),
              numeric: true,
              textAlign: TextAlign.right,
              onChanged: (v) {
                final n = parseNumber(v);
                notifier.setOfferAt(
                  supplierId,
                  index,
                  (o) => withoutVat
                      ? o.withSumInput(n, withoutVat: true, vat: vat)
                      : o.withSumWithoutVatInput(n, vat: vat),
                );
              },
            ),
          ),
        GridBox(
          width: m.sumWidth,
          height: rowHeight,
          child: EditableCell(
            testId: '$keyBase.sum',
            value: formatEditable(current?.displaySum(withoutVat)),
            numeric: true,
            textAlign: TextAlign.right,
            onChanged: (v) {
              final n = parseNumber(v);
              notifier.setOfferAt(
                supplierId,
                index,
                (o) => o.withSumInput(n, withoutVat: withoutVat, vat: vat),
              );
            },
          ),
        ),
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
