import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_state_provider.dart';
import '../../providers/zoom_provider.dart';
import '../../utils/request_items_parse.dart';
import '../constants.dart';
import 'editable_cell.dart';
import 'grid_box.dart';
import 'row_heights.dart';

/// Левая фиксированная панель: № / Название позиции / Кол-во, мета-строки
/// и строка «Итого:». Не скроллится горизонтально. В режиме сумм строки
/// данных прячутся (остаются шапка, мета и «Итого»).
class FixedPanel extends ConsumerWidget {
  const FixedPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appStateProvider);
    final notifier = ref.read(appStateProvider.notifier);
    final m = ref.watch(tableMetricsProvider);
    final heights = ref.watch(rowHeightsProvider);
    final maxRows = heights.data.length; // + запасная пустая строка внутри
    final headerStyle = Theme.of(context).textTheme.titleSmall;
    final horizontal = EdgeInsets.symmetric(horizontal: 8 * m.scale);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GridBox(
          width: m.fixedWidth,
          height: m.headerRowHeight,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text('Позиции заявки', style: headerStyle),
                ),
                IconButton(
                  key: const ValueKey('fixed.pasteRequestItems'),
                  tooltip: 'Вставить список из буфера',
                  icon: const Icon(Icons.content_paste),
                  onPressed: () => _pasteFromClipboard(notifier),
                ),
              ],
            ),
          ),
        ),
        Row(
          children: [
            _header(context, m, '№', m.fixedNumberWidth, TextAlign.center),
            _header(context, m, 'Название позиции', m.fixedNameWidth),
            _header(context, m, 'Кол-во', m.fixedQtyWidth, TextAlign.center),
          ],
        ),
        // Позиции заявки видны всегда, в т.ч. в режиме сумм — иначе не видно,
        // к какой позиции относится сумма поставщика.
        for (var i = 0; i < maxRows; i++)
          Row(
            children: [
              GridBox(
                width: m.fixedNumberWidth,
                height: heights.data[i],
                alignment: Alignment.center,
                child: Text('${i + 1}'),
              ),
              GridBox(
                width: m.fixedNameWidth,
                height: heights.data[i],
                child: Row(
                  children: [
                    Expanded(
                      child: EditableCell(
                        testId: 'fixed.item.$i.name',
                        hint: 'Позиция ${i + 1}',
                        value: i < state.requestItems.length
                            ? state.requestItems[i].name
                            : '',
                        onChanged: (v) =>
                            notifier.updateRequestItem(i, name: v),
                        onPaste: (text) {
                          final items = parseRequestItems(text);
                          if (items.length < 2 &&
                              !text.contains('\t') &&
                              !text.contains('\n')) {
                            return false;
                          }
                          if (items.isEmpty) return false;
                          notifier.pasteRequestItems(i, items);
                          return true;
                        },
                      ),
                    ),
                    if (i < state.requestItems.length)
                      IconButton(
                        key: ValueKey('fixed.item.$i.delete'),
                        iconSize: m.actionIconSize,
                        padding: EdgeInsets.zero,
                        constraints: BoxConstraints(
                          minWidth: m.tapTarget,
                          minHeight: m.tapTarget,
                        ),
                        tooltip: 'Удалить позицию',
                        icon: const Icon(Icons.close),
                        onPressed: () => notifier.removeRequestItem(i),
                      )
                    else
                      SizedBox(width: m.tapTarget),
                  ],
                ),
              ),
              GridBox(
                width: m.fixedQtyWidth,
                height: heights.data[i],
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
        for (var j = 0; j < kMetaRows.length; j++)
          GridBox(
            width: m.fixedWidth,
            height: heights.meta[j],
            child: Padding(
              padding: horizontal,
              child: Align(
                alignment: Alignment.centerLeft,
                child:
                    Text(kMetaRows[j].label, style: Theme.of(context).textTheme.bodySmall),
              ),
            ),
          ),
        GridBox(
          width: m.fixedWidth,
          height: m.totalRowHeight,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: horizontal,
            child: Text('Итого:', style: headerStyle),
          ),
        ),
      ],
    );
  }

  Future<void> _pasteFromClipboard(AppStateNotifier notifier) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final items = parseRequestItems(data?.text ?? '');
    if (items.isEmpty) return;
    notifier.pasteRequestItems(0, items);
  }

  Widget _header(
    BuildContext context,
    TableMetrics m,
    String text,
    double width, [
    TextAlign align = TextAlign.left,
  ]) {
    return GridBox(
      width: width,
      height: m.subHeaderHeight,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      alignment:
          align == TextAlign.center ? Alignment.center : Alignment.centerLeft,
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
