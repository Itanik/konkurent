import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_state.dart';
import '../../providers/app_state_provider.dart';
import '../../providers/recently_linked_provider.dart';
import '../../providers/zoom_provider.dart';
import '../../services/app_config_service.dart';
import '../../utils/format.dart';
import '../../providers/view_preferences_provider.dart';
import 'drag_types.dart';
import 'editable_cell.dart';
import 'grid_box.dart';
import 'selection_controller.dart';

/// Строка предложения одного поставщика (или пустая редактируемая ячейка
/// группы, [offer] == null: ввод создаёт предложение, привязанное к группе).
/// Строка может занимать всю высоту группы (визуальный merge), если
/// поставщик один в этой группе.
///
/// Drag&drop: строка принимает предложения любого поставщика — дроп на строку
/// группы привязывает переносимое предложение к этой позиции заявки,
/// дроп в зоне без привязки снимает привязку.
class OfferRow extends ConsumerWidget {
  const OfferRow({
    super.key,
    required this.supplierId,
    required this.blockIndex,
    required this.rowIndex,
    required this.offer,
    required this.rowHeight,
    required this.withoutVat,
    required this.groupRequestId,
    required this.onOfferDrop,
    this.sumsOnly = false,
    this.zoneIndex,
  });

  final String supplierId;

  /// Индекс поставщика (адрес блока для клавиатурной навигации).
  final int blockIndex;

  /// Физическая строка (адрес для клавиатурной навигации).
  final int rowIndex;

  /// Индекс строки в зоне без привязки — для уникальных ключей пустых строк.
  final int? zoneIndex;

  /// null — пустая (запасная) строка; ввод создаёт предложение.
  final Offer? offer;

  /// Высота строки/группы (автовысота из tableLayoutProvider).
  final double rowHeight;

  /// Режим поставщика «без НДС»: основная пара колонок — без НДС.
  final bool withoutVat;

  /// Позиция заявки, в чьей группе стоит строка (null — зона без привязки).
  final String? groupRequestId;

  /// Обработка дропа другого предложения на эту строку.
  final void Function(OfferDrag drag, Offer? targetOffer) onOfferDrop;

  /// Режим сумм: только редактируемая ячейка суммы позиции.
  final bool sumsOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = offer;
    final notifier = ref.read(appStateProvider.notifier);
    final m = ref.watch(tableMetricsProvider);
    final config = ref.watch(appConfigProvider).value;
    final vat = config?.vatRate ?? 0.22;
    final units = config?.units ?? const UnitsDict({});
    final showSecondary = ref.watch(showSumWithoutVatProvider) && !withoutVat;
    final recentlyLinked =
        current != null && ref.watch(recentlyLinkedProvider).contains(current.id);
    final hasContent = current != null && !current.isEmpty;
    final keyBase = current != null
        ? 'offer.${current.id}'
        : (groupRequestId != null
            ? 'offer.empty.$supplierId.g.$groupRequestId'
            : 'offer.empty.$supplierId.zone.${zoneIndex ?? 0}');

    // Подсказка единицы: единица позиции заявки, если у предложения пусто.
    final requestItem = groupRequestId == null
        ? null
        : ref.watch(appStateProvider).requestItems
            .where((r) => r.id == groupRequestId)
            .firstOrNull;

    void edit(Offer Function(Offer o) transform) {
      if (current != null) {
        notifier.updateOffer(supplierId, current.id, transform);
      } else {
        notifier.createOfferAt(supplierId, groupRequestId, transform);
      }
    }

    Widget sumCell({required bool net, required double width}) => GridBox(
          width: width,
          height: rowHeight,
          child: EditableCell(
            testId: net ? '$keyBase.sumNet' : '$keyBase.sum',
            value: formatEditable(
                current?.displaySum(withoutVat: net, vat: vat)),
            numeric: true,
            textAlign: TextAlign.right,
            address: net ? null : cell(blockIndex, 4, rowIndex),
            onChanged: (v) => edit(
                (o) => o.withSumInput(parseNumber(v), withoutVat: net, vat: vat)),
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
            address: net ? null : cell(blockIndex, 3, rowIndex),
            onChanged: (v) => edit(
                (o) => o.withPriceInput(parseNumber(v), withoutVat: net)),
          ),
        );

    if (sumsOnly) {
      return _wrapDrop(sumCell(net: withoutVat, width: m.sumWidth));
    }

    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GridBox(
          width: m.itemWidth,
          height: rowHeight,
          // Свежесопоставленное автолинком — мягкая зелёная подсказка.
          color: recentlyLinked
              ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.45)
              : null,
          child: Row(
            children: [
              if (hasContent)
                Draggable<OfferDrag>(
                  data: OfferDrag(supplierId, current.id),
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
                  address: cell(blockIndex, 0, rowIndex),
                  onChanged: (v) => edit((o) => o.copyWith(itemName: v)),
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
                  onPressed: () =>
                      notifier.removeOfferById(supplierId, current.id),
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
            address: cell(blockIndex, 1, rowIndex),
            onChanged: (v) => edit((o) {
              final n = parseNumber(v);
              return o.copyWith(qty: n, clearQty: n == null);
            }),
          ),
        ),
        GridBox(
          width: m.unitWidth,
          height: rowHeight,
          child: EditableCell(
            testId: '$keyBase.unit',
            value: current?.unit ?? '',
            hint: requestItem == null || requestItem.unit.isEmpty
                ? null
                : requestItem.unit,
            textAlign: TextAlign.center,
            address: cell(blockIndex, 2, rowIndex),
            // Единицы вне словаря подсвечиваем: вероятно, плохое распознавание.
            highlight: current != null &&
                current.unit.isNotEmpty &&
                !units.contains(current.unit),
            suggestions: units.canonical.isEmpty ? null : units.canonical,
            onChanged: (v) => edit((o) => o.copyWith(unit: v)),
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

    return _wrapDrop(row);
  }

  /// Строка принимает предложения любых поставщиков (кроме себя самого).
  Widget _wrapDrop(Widget row) {
    return DragTarget<OfferDrag>(
      onWillAcceptWithDetails: (details) =>
          details.data.offerId != offer?.id,
      onAcceptWithDetails: (details) => onOfferDrop(details.data, offer),
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
