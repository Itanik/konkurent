import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_state.dart';
import '../../providers/app_state_provider.dart';
import '../../utils/format.dart';
import '../../utils/request_items_parse.dart';
import '../constants.dart';
import 'drag_types.dart';
import 'editable_cell.dart';
import 'grid_box.dart';

/// Строка предложения одного поставщика. Перетаскивается вертикально только
/// внутри своего блока (drag за handle).
class OfferRow extends ConsumerWidget {
  const OfferRow({
    super.key,
    required this.supplierId,
    required this.offer,
    required this.index,
    required this.onReorder,
  });

  final String supplierId;

  /// null — пустая ячейка-заполнитель до maxRows.
  final Offer? offer;
  final int index;
  final void Function(String offerId, int toIndex) onReorder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = offer;
    if (current == null) {
      return _EmptyOfferRow(supplierId: supplierId);
    }

    final notifier = ref.read(appStateProvider.notifier);
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GridBox(
          width: kItemWidth,
          height: kDataRowHeight,
          child: Row(
            children: [
              Draggable<OfferDrag>(
                data: OfferDrag(supplierId, current.id),
                feedback: Material(
                  elevation: 4,
                  child: Chip(label: Text(current.itemName.isEmpty ? 'Позиция' : current.itemName)),
                ),
                childWhenDragging: const Opacity(
                  opacity: 0.3,
                  child: Icon(Icons.drag_indicator),
                ),
                child: Padding(
                  key: ValueKey('offer.${current.id}.handle'),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: const Icon(Icons.drag_indicator, size: 18),
                ),
              ),
              Expanded(
                child: EditableCell(
                  testId: 'offer.${current.id}.item',
                  value: current.itemName,
                  onChanged: (v) =>
                      notifier.updateOffer(supplierId, current.copyWith(itemName: v)),
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
              IconButton(
                key: ValueKey('offer.${current.id}.delete'),
                iconSize: 16,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                tooltip: 'Удалить строку',
                icon: const Icon(Icons.close),
                onPressed: () => notifier.removeOffer(supplierId, current.id),
              ),
            ],
          ),
        ),
        GridBox(
          width: kQtyWidth,
          height: kDataRowHeight,
          child: EditableCell(
            testId: 'offer.${current.id}.qty',
            value: formatEditable(current.qty),
            numeric: true,
            textAlign: TextAlign.center,
            onChanged: (v) {
              final n = parseNumber(v);
              notifier.updateOffer(
                supplierId,
                current.copyWith(qty: n, clearQty: n == null),
              );
            },
          ),
        ),
        GridBox(
          width: kUnitWidth,
          height: kDataRowHeight,
          child: EditableCell(
            testId: 'offer.${current.id}.unit',
            value: current.unit,
            textAlign: TextAlign.center,
            onChanged: (v) =>
                notifier.updateOffer(supplierId, current.copyWith(unit: v)),
          ),
        ),
        GridBox(
          width: kPriceWidth,
          height: kDataRowHeight,
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              formatNumber(current.pricePerUnit),
              key: ValueKey('offer.${current.id}.price'),
            ),
          ),
        ),
        GridBox(
          width: kSumWidth,
          height: kDataRowHeight,
          child: EditableCell(
            testId: 'offer.${current.id}.sum',
            value: formatEditable(current.sumWithVat),
            numeric: true,
            textAlign: TextAlign.right,
            onChanged: (v) {
              final n = parseNumber(v);
              notifier.updateOffer(
                supplierId,
                current.copyWith(sumWithVat: n, clearSumWithVat: n == null),
              );
            },
          ),
        ),
      ],
    );

    return DragTarget<OfferDrag>(
      onWillAcceptWithDetails: (details) =>
          details.data.offerId != current.id,
      onAcceptWithDetails: (details) =>
          onReorder(details.data.offerId, index),
      builder: (context, candidates, rejected) {
        if (candidates.isEmpty) return row;
        return DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.primary, width: 2),
          ),
          child: row,
        );
      },
    );
  }
}

class _EmptyOfferRow extends ConsumerWidget {
  const _EmptyOfferRow({required this.supplierId});

  final String supplierId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(appStateProvider.notifier);
    return Opacity(
      opacity: 0.4,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GridBox(
            width: kItemWidth,
            height: kDataRowHeight,
            child: Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                key: ValueKey('offer.add.$supplierId'),
                iconSize: 18,
                tooltip: 'Добавить предложение',
                icon: const Icon(Icons.add),
                onPressed: () => notifier.addOffer(supplierId),
              ),
            ),
          ),
          const GridBox(width: kQtyWidth, height: kDataRowHeight),
          const GridBox(width: kUnitWidth, height: kDataRowHeight),
          const GridBox(width: kPriceWidth, height: kDataRowHeight),
          const GridBox(width: kSumWidth, height: kDataRowHeight),
        ],
      ),
    );
  }
}