import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_state_provider.dart';
import '../../providers/table_layout_provider.dart';
import '../../providers/zoom_provider.dart';
import '../constants.dart';
import 'editable_cell.dart';
import 'grid_box.dart';
import 'selection_controller.dart';

/// Левая фиксированная панель: № / Название позиции / Кол-во / Ед.изм.
/// Каждая позиция заявки — группа высотой в max строк поставщиков (ячейки
/// объединены по вертикали). Под группами — зона без привязки: пустые
/// редактируемые строки заявки (ввод создаёт новые позиции). Не скроллится
/// горизонтально; в режиме сумм видна так же.
class FixedPanel extends ConsumerWidget {
  const FixedPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appStateProvider);
    final notifier = ref.read(appStateProvider.notifier);
    final m = ref.watch(tableMetricsProvider);
    final layout = ref.watch(tableLayoutProvider);
    final headerStyle = Theme.of(context).textTheme.titleSmall;
    final horizontal = EdgeInsets.symmetric(horizontal: 8 * m.scale);

    final children = <Widget>[
      GridBox(
        width: m.fixedWidth,
        height: m.headerRowHeight,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('Позиции заявки', style: headerStyle),
          ),
        ),
      ),
      Row(
        children: [
          _header(context, m, '№', m.fixedNumberWidth, TextAlign.center),
          _header(context, m, 'Название позиции', m.fixedNameWidth),
          _header(context, m, 'Кол-во', m.fixedQtyWidth, TextAlign.center),
          _header(context, m, 'Ед.изм', m.unitWidth, TextAlign.center),
        ],
      ),
    ];

    // Группы позиций заявки: ячейки растянуты на высоту группы.
    for (final g in layout.groups) {
      final i = state.requestItems.indexOf(g.item);
      children.add(Row(
        children: [
          GridBox(
            width: m.fixedNumberWidth,
            height: g.height,
            alignment: Alignment.center,
            child: Text('${i + 1}'),
          ),
          GridBox(
            width: m.fixedNameWidth,
            height: g.height,
            child: Row(
              children: [
                Expanded(
                  child: EditableCell(
                    testId: 'fixed.item.$i.name',
                    hint: 'Позиция ${i + 1}',
                    value: g.item.name,
                    address: cell(-1, 0, g.firstRow),
                    onChanged: (v) => notifier.updateRequestItem(i, name: v),
                  ),
                ),
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
                ),
              ],
            ),
          ),
          GridBox(
            width: m.fixedQtyWidth,
            height: g.height,
            child: EditableCell(
              testId: 'fixed.item.$i.qty',
              value: g.item.qty,
              numeric: true,
              textAlign: TextAlign.center,
              address: cell(-1, 1, g.firstRow),
              onChanged: (v) => notifier.updateRequestItem(i, qty: v),
            ),
          ),
          GridBox(
            width: m.unitWidth,
            height: g.height,
            child: EditableCell(
              testId: 'fixed.item.$i.unit',
              value: g.item.unit,
              textAlign: TextAlign.center,
              address: cell(-1, 2, g.firstRow),
              onChanged: (v) => notifier.updateRequestItem(i, unit: v),
            ),
          ),
        ],
      ));
    }

    // Зона без привязки: пустые редактируемые строки заявки; ввод имени
    // создаёт новую позицию (следующей группой).
    for (var j = 0; j < layout.unlinkedRows; j++) {
      final i = layout.groups.length + j;
      children.add(Row(
        children: [
          GridBox(
            width: m.fixedNumberWidth,
            height: layout.unlinkedHeights[j],
            alignment: Alignment.center,
            child: const SizedBox.shrink(),
          ),
          GridBox(
            width: m.fixedNameWidth,
            height: layout.unlinkedHeights[j],
            child: Row(
              children: [
                Expanded(
                  child: EditableCell(
                    testId: 'fixed.item.$i.name',
                    hint: 'Позиция ${i + 1}',
                    value: '',
                    address: cell(-1, 0, layout.unlinkedFirstRow + j),
                    onChanged: (v) => notifier.updateRequestItem(i, name: v),
                  ),
                ),
                SizedBox(width: m.tapTarget),
              ],
            ),
          ),
          GridBox(
            width: m.fixedQtyWidth,
            height: layout.unlinkedHeights[j],
            child: EditableCell(
              testId: 'fixed.item.$i.qty',
              value: '',
              numeric: true,
              textAlign: TextAlign.center,
              address: cell(-1, 1, layout.unlinkedFirstRow + j),
              onChanged: (v) => notifier.updateRequestItem(i, qty: v),
            ),
          ),
          GridBox(
            width: m.unitWidth,
            height: layout.unlinkedHeights[j],
            child: EditableCell(
              testId: 'fixed.item.$i.unit',
              value: '',
              textAlign: TextAlign.center,
              address: cell(-1, 2, layout.unlinkedFirstRow + j),
              onChanged: (v) => notifier.updateRequestItem(i, unit: v),
            ),
          ),
        ],
      ));
    }

    for (var j = 0; j < kMetaRows.length; j++) {
      children.add(GridBox(
        width: m.fixedWidth,
        height: layout.metaHeights[j],
        child: Padding(
          padding: horizontal,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(kMetaRows[j].label,
                style: Theme.of(context).textTheme.bodySmall),
          ),
        ),
      ));
    }

    children.add(GridBox(
      width: m.fixedWidth,
      height: m.totalRowHeight,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: horizontal,
        child: Text('Итого:', style: headerStyle),
      ),
    ));

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
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
