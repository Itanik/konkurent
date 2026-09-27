import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_state_provider.dart';
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
    final maxRows = state.maxRows + 1; // + запасная пустая строка
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
                        iconSize: 16,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                            minWidth: 24, minHeight: 24),
                        tooltip: 'Удалить позицию',
                        icon: const Icon(Icons.close),
                        onPressed: () => notifier.removeRequestItem(i),
                      )
                    else
                      const SizedBox(width: 24),
                  ],
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

  Future<void> _pasteFromClipboard(AppStateNotifier notifier) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final items = parseRequestItems(data?.text ?? '');
    if (items.isEmpty) return;
    notifier.pasteRequestItems(0, items);
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