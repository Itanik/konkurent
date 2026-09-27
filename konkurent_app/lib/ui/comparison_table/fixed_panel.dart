import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_state_provider.dart';
import '../../providers/zoom_provider.dart';
import '../../utils/request_items_parse.dart';
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
    final m = ref.watch(tableMetricsProvider);
    final maxRows = state.maxRows + 1; // + запасная пустая строка
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
        for (var i = 0; i < maxRows; i++)
          Row(
            children: [
              GridBox(
                width: m.fixedNumberWidth,
                height: m.dataRowHeight,
                alignment: Alignment.center,
                child: Text('${i + 1}'),
              ),
              GridBox(
                width: m.fixedNameWidth,
                height: m.dataRowHeight,
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
                height: m.dataRowHeight,
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
            width: m.fixedWidth,
            height: m.metaRowHeight,
            child: Padding(
              padding: horizontal,
              child:
                  Text(meta.label, style: Theme.of(context).textTheme.bodySmall),
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