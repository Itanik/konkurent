import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_state_provider.dart';
import '../constants.dart';
import 'editable_cell.dart';
import 'grid_box.dart';

/// Левая фиксированная панель: № / Название позиции / Кол-во, мета-строки
/// и строка «Итого:». Не скроллится горизонтально.
class FixedPanel extends ConsumerWidget {
  const FixedPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appStateProvider);
    final notifier = ref.read(appStateProvider.notifier);
    final maxRows = state.maxRows;
    final headerStyle = Theme.of(context).textTheme.titleSmall;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GridBox(
          width: kFixedWidth,
          height: kHeaderRowHeight,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text('Позиции заявки', style: headerStyle),
                ),
                IconButton(
                  key: const ValueKey('fixed.addRequestItem'),
                  tooltip: 'Добавить позицию заявки',
                  icon: const Icon(Icons.add),
                  onPressed: notifier.addRequestItem,
                ),
              ],
            ),
          ),
        ),
        Row(
          children: [
            _header(context, '№', kFixedNumberWidth, TextAlign.center),
            _header(context, 'Название позиции', kFixedNameWidth),
            _header(context, 'Кол-во', kFixedQtyWidth, TextAlign.center),
          ],
        ),
        for (var i = 0; i < maxRows; i++)
          Row(
            children: [
              GridBox(
                width: kFixedNumberWidth,
                height: kDataRowHeight,
                alignment: Alignment.center,
                child: Text('${i + 1}'),
              ),
              GridBox(
                width: kFixedNameWidth,
                height: kDataRowHeight,
                child: EditableCell(
                  testId: 'fixed.item.$i.name',
                  hint: 'Позиция ${i + 1}',
                  value: i < state.requestItems.length
                      ? state.requestItems[i].name
                      : '',
                  onChanged: (v) => notifier.updateRequestItem(i, name: v),
                ),
              ),
              GridBox(
                width: kFixedQtyWidth,
                height: kDataRowHeight,
                child: EditableCell(
                  testId: 'fixed.item.$i.qty',
                  value: i < state.requestItems.length
                      ? state.requestItems[i].qty
                      : '',
                  numeric: true,
                  textAlign: TextAlign.center,
                  onChanged: (v) => notifier.updateRequestItem(i, qty: v),
                ),
              ),
            ],
          ),
        for (final meta in kMetaRows)
          GridBox(
            width: kFixedWidth,
            height: kMetaRowHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(meta.label, style: Theme.of(context).textTheme.bodySmall),
            ),
          ),
        GridBox(
          width: kFixedWidth,
          height: kTotalRowHeight,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text('Итого:', style: headerStyle),
          ),
        ),
      ],
    );
  }

  Widget _header(
    BuildContext context,
    String text,
    double width, [
    TextAlign align = TextAlign.left,
  ]) {
    return GridBox(
      width: width,
      height: kSubHeaderHeight,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      alignment: align == TextAlign.center ? Alignment.center : Alignment.centerLeft,
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