import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_state_provider.dart';
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

    final supplier = state.suppliers.firstWhere((s) => s.id == supplierId);
    final maxRows = state.maxRows + 1; // + запасная пустая строка
    final headerStyle = Theme.of(context).textTheme.titleSmall;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GridBox(
          width: kSupplierWidth,
          height: kHeaderRowHeight,
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
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: const Icon(Icons.drag_indicator, size: 18),
                ),
              ),
              Expanded(
                child: EditableCell(
                  testId: 'supplier.$supplierId.name',
                  hint: 'Имя поставщика',
                  value: supplier.displayName,
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  onChanged: (v) => notifier.renameSupplier(supplierId, v),
                ),
              ),
              IconButton(
                key: ValueKey('supplier.$supplierId.delete'),
                iconSize: 16,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
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
            _subHeader(context, 'Предложено', kItemWidth, TextAlign.left),
            _subHeader(context, 'Кол-во', kQtyWidth, TextAlign.center),
            _subHeader(context, 'Ед.', kUnitWidth, TextAlign.center),
            _subHeader(context, 'Ц/ед', kPriceWidth, TextAlign.center),
            _subHeader(context, 'Сумма', kSumWidth, TextAlign.right),
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
            width: kSupplierWidth,
            height: kMetaRowHeight,
            child: EditableCell(
              testId: 'supplier.$supplierId.meta.${meta.key}',
              value: supplier.meta.value(meta.key),
              textAlign: TextAlign.center,
              onChanged: (v) => notifier.setMeta(supplierId, meta.key, v),
            ),
          ),
        GridBox(
          width: kSupplierWidth,
          height: kTotalRowHeight,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
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
    String text,
    double width,
    TextAlign align,
  ) {
    return GridBox(
      width: width,
      height: kSubHeaderHeight,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      alignment: align == TextAlign.center
          ? Alignment.center
          : (align == TextAlign.right ? Alignment.centerRight : Alignment.centerLeft),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text(
          text,
          textAlign: align,
          style: Theme.of(context).textTheme.labelLarge,
        ),
      ),
    );
  }
}