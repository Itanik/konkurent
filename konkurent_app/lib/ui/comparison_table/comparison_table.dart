import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_state.dart';
import '../../providers/app_state_provider.dart';
import '../../services/app_config_service.dart';
import '../../services/clipboard_grid.dart';
import '../../utils/format.dart';
import '../../providers/table_layout_provider.dart';
import 'fixed_panel.dart';
import 'drag_types.dart';
import 'best_variant_panel.dart';
import 'selection_controller.dart';
import 'supplier_column.dart';

/// Склейка фиксированной левой панели и горизонтально скроллящихся колонок
/// поставщиков. Вертикальный скролл общий. Средняя кнопка мыши включает
/// Windows-автоскролл, Shift+колесо прокручивает по горизонтали.
///
/// Клавиатура как в Excel (когда ни одно поле не в правке): стрелки —
/// навигация (Shift — выделение диапазона), Enter — вниз, Tab — вправо через
/// блоки, Ctrl+A — выделить всё, Ctrl+C — скопировать диапазон в TSV,
/// Ctrl+V — вставить TSV в выделение, набор текста — начать правку, Esc —
/// сбросить выделение.
class ComparisonTable extends ConsumerStatefulWidget {
  const ComparisonTable({super.key});

  @override
  ConsumerState<ComparisonTable> createState() => _ComparisonTableState();
}

class _ComparisonTableState extends ConsumerState<ComparisonTable>
    with TickerProviderStateMixin {
  final ScrollController _vertical = ScrollController();
  final ScrollController _horizontal = ScrollController();
  final SelectionController _selection = SelectionController();
  final FocusNode _tableFocus = FocusNode();

  // Автоскролл средней кнопкой.
  Ticker? _ticker;
  bool _autoscroll = false;
  Duration _lastElapsed = Duration.zero;
  Offset _anchor = Offset.zero;
  Offset _pointer = Offset.zero;

  // Автоскролл у края экрана во время drag'а строки/колонки.
  Ticker? _dragTicker;
  bool _dragScrolling = false;
  Duration _dragElapsed = Duration.zero;
  double _dragVelocity = 0;

  static const double _edgeZone = 72.0;
  static const double _maxDragSpeed = 700.0; // px/с на краю зоны

  // Live-превью перестановки поставщиков.
  int? _dragFrom;
  int? _dragHover;

  @override
  void dispose() {
    _ticker?.dispose();
    _dragTicker?.dispose();
    _vertical.dispose();
    _horizontal.dispose();
    _tableFocus.dispose();
    _selection.dispose();
    super.dispose();
  }

  // --- автоскролл во время drag'а -------------------------------------------

  /// Вызывается из handle'ов строк/колонок на каждое перемещение drag'а:
  /// у верхнего/нижнего края вьюпорта запускает прокрутку, скорость растёт
  /// к краю. Держать курсор на месте — прокрутка продолжается (Windows-стиль).
  void _onTableDragUpdate(Offset global) {
    if (!_vertical.hasClients) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return;
    final local = box.globalToLocal(global);
    final fromTop = local.dy;
    final fromBottom = box.size.height - local.dy;

    // Курсор за границей вьюпорта (например у самого края окна) — считаем
    // что он на краю, с максимальной скоростью.
    double? velocity;
    if (fromTop <= 0) {
      velocity = -_maxDragSpeed;
    } else if (fromTop < _edgeZone) {
      velocity = -_maxDragSpeed * (1 - fromTop / _edgeZone);
    } else if (fromBottom <= 0) {
      velocity = _maxDragSpeed;
    } else if (fromBottom < _edgeZone) {
      velocity = _maxDragSpeed * (1 - fromBottom / _edgeZone);
    }
    if (velocity == null) {
      _stopDragScroll();
      return;
    }
    _dragVelocity = velocity;
    if (!_dragScrolling) {
      _dragScrolling = true;
      _dragElapsed = Duration.zero;
      _dragTicker?.dispose();
      _dragTicker = createTicker(_onDragTick)..start();
    }
  }

  void _stopDragScroll() {
    if (!_dragScrolling) return;
    _dragTicker?.stop();
    _dragScrolling = false;
  }

  /// Прокручивает оба вьюпорта так, чтобы сфокусированная ячейка была видна
  /// (стрелки/Enter/Tab/F2 у краёв экрана). Контекст ячейки знает свои
  /// Scrollable-предки — вертикальный и горизонтальный.
  void _ensureFocusedVisible() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _selection.cells[_selection.focus];
      if (ctx == null || !ctx.mounted) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
    });
  }

  void _onDragTick(Duration elapsed) {
    if (!_dragScrolling || !_vertical.hasClients) return;
    final dt = (elapsed - _dragElapsed).inMicroseconds / 1e6;
    _dragElapsed = elapsed;
    if (dt <= 0) return;
    final next = (_vertical.offset + _dragVelocity * dt).clamp(
      0.0,
      _vertical.position.maxScrollExtent,
    );
    _vertical.jumpTo(next);
  }

  // --- автоскролл -----------------------------------------------------------

  void _startAutoscroll(Offset position) {
    setState(() {
      _autoscroll = true;
      _anchor = position;
      _pointer = position;
      _lastElapsed = Duration.zero;
    });
    _ticker?.dispose();
    _ticker = createTicker(_onTick)..start();
  }

  void _stopAutoscroll() {
    if (!_autoscroll) return;
    _ticker?.stop();
    setState(() => _autoscroll = false);
  }

  void _onTick(Duration elapsed) {
    if (!_autoscroll) return;
    final dt = (elapsed - _lastElapsed).inMicroseconds / 1e6;
    _lastElapsed = elapsed;
    if (dt <= 0) return;

    const deadzone = 12.0;
    const speedFactor = 14.0;

    final dx = _pointer.dx - _anchor.dx;
    final dy = _pointer.dy - _anchor.dy;

    if (_vertical.hasClients && dy.abs() > deadzone) {
      final speed =
          (dy.abs() - deadzone) * speedFactor * (dy.isNegative ? -1.0 : 1.0);
      final next = (_vertical.offset + speed * dt).clamp(
        0.0,
        _vertical.position.maxScrollExtent,
      );
      _vertical.jumpTo(next);
    }
    if (_horizontal.hasClients && dx.abs() > deadzone) {
      final speed =
          (dx.abs() - deadzone) * speedFactor * (dx.isNegative ? -1.0 : 1.0);
      final next = (_horizontal.offset + speed * dt).clamp(
        0.0,
        _horizontal.position.maxScrollExtent,
      );
      _horizontal.jumpTo(next);
    }
  }

  void _onPointerDown(PointerDownEvent event) {
    if (_autoscroll) {
      _stopAutoscroll();
      return;
    }
    if (event.buttons == kMiddleMouseButton) {
      _startAutoscroll(event.position);
    }
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final keyboard = HardwareKeyboard.instance;
    if (!keyboard.isShiftPressed || keyboard.isControlPressed) return;
    if (!_horizontal.hasClients) return;
    final next = (_horizontal.offset + event.scrollDelta.dy).clamp(
      0.0,
      _horizontal.position.maxScrollExtent,
    );
    _horizontal.jumpTo(next);
  }

  // --- live-превью перестановки поставщиков ---------------------------------

  void _onDragMove(int targetIndex, SupplierDrag data) {
    final from = ref
        .read(appStateProvider)
        .suppliers
        .indexWhere((s) => s.id == data.supplierId);
    if (from == -1) return;
    if (_dragHover == targetIndex && _dragFrom == from) return;
    setState(() {
      _dragFrom = from;
      _dragHover = targetIndex;
    });
  }

  void _onDragLeave(int targetIndex) {
    if (_dragHover != targetIndex) return;
    setState(() => _dragHover = null);
  }

  void _onDragAccept(int targetIndex, SupplierDrag data) {
    _clearDragPreview();
    final from = ref
        .read(appStateProvider)
        .suppliers
        .indexWhere((s) => s.id == data.supplierId);
    if (from == -1) return;
    ref.read(appStateProvider.notifier).reorderSuppliers(from, targetIndex);
  }

  void _clearDragPreview() {
    if (_dragHover == null && _dragFrom == null) return;
    setState(() {
      _dragHover = null;
      _dragFrom = null;
    });
  }

  // --- клавиатура --------------------------------------------------------------

  bool _editableFocused() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return false;
    return context.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || _editableFocused()) {
      return KeyEventResult.ignored;
    }
    final kb = HardwareKeyboard.instance;

    if (kb.isControlPressed || kb.isMetaPressed) {
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.keyC) {
        _copySelection();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyA) {
        _selection.selectAll();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyV) {
        _pasteClipboard();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _selection.clear();
      return KeyEventResult.handled;
    }

    // F2 — начать правку выделенной ячейки (как в Excel).
    if (event.logicalKey == LogicalKeyboardKey.f2) {
      final f = _selection.focus;
      if (f != null) _selection.tryEdit(f);
      return KeyEventResult.handled;
    }

    final moves = <LogicalKeyboardKey, (int, int)>{
      LogicalKeyboardKey.arrowUp: (-1, 0),
      LogicalKeyboardKey.arrowDown: (1, 0),
      LogicalKeyboardKey.arrowLeft: (0, -1),
      LogicalKeyboardKey.arrowRight: (0, 1),
      LogicalKeyboardKey.enter: (1, 0),
      LogicalKeyboardKey.numpadEnter: (1, 0),
      LogicalKeyboardKey.tab: (0, 1),
    };
    final move = moves[event.logicalKey];
    if (move != null) {
      final (dr, dc) = move;
      final shift = kb.isShiftPressed;
      // Tab со Shift — влево, Enter/стрелки со Shift — протяжка выделения.
      _selection.move(
        dr,
        dc == 1 && shift && event.logicalKey == LogicalKeyboardKey.tab
            ? -1
            : dc,
        extendSelection: shift && event.logicalKey != LogicalKeyboardKey.tab,
      );
      return KeyEventResult.handled;
    }

    // Набор текста — начать правку выделенной ячейки.
    final ch = event.character;
    if (ch != null && ch.isNotEmpty && !kb.isAltPressed) {
      final f = _selection.focus;
      if (f != null && _selection.tryEdit(f)) {
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  // --- TSV copy/paste ----------------------------------------------------------

  /// Отображаемое значение ячейки для копирования.
  String? _cellValue(CellAddress a) {
    final state = ref.read(appStateProvider);
    final layout = ref.read(tableLayoutProvider);
    final vat = ref.read(appConfigProvider).value?.vatRate ?? 0.22;

    Offer? offerAt(int supplierIdx, int row) {
      final supplier = state.suppliers[supplierIdx];
      final g = layout.groupOfRow(row);
      if (g != null) {
        final linked = supplier.offers
            .where((o) => o.linkedRequestItemId == g.item.id)
            .toList();
        final j = row - g.firstRow;
        return j < linked.length ? linked[j] : null;
      }
      final unlinked = supplier.offers
          .where((o) => o.linkedRequestItemId == null)
          .toList();
      final j = row - layout.unlinkedFirstRow;
      return j >= 0 && j < unlinked.length ? unlinked[j] : null;
    }

    if (a.b == -1) {
      final g = layout.groupOfRow(a.r);
      if (g == null) return '';
      switch (a.c) {
        case 0:
          return g.item.name;
        case 1:
          return g.item.qty;
        case 2:
          return g.item.unit;
      }
      return '';
    }
    if (a.b >= state.suppliers.length) return '';
    final s = state.suppliers[a.b];
    final o = offerAt(a.b, a.r);
    final net = s.withoutVat;
    switch (a.c) {
      case 0:
        return o?.itemName ?? '';
      case 1:
        return formatEditable(o?.qty);
      case 2:
        return o?.unit ?? '';
      case 3:
        return formatEditable(o?.displayPrice(withoutVat: net, vat: vat));
      case 4:
        return formatEditable(o?.displaySum(withoutVat: net, vat: vat));
    }
    return '';
  }

  Future<void> _copySelection() async {
    final an = _selection.anchor;
    final fo = _selection.focus;
    if (an == null || fo == null) return;
    final b0 = an.b < fo.b ? an.b : fo.b, b1 = an.b > fo.b ? an.b : fo.b;
    final c0 = an.c < fo.c ? an.c : fo.c, c1 = an.c > fo.c ? an.c : fo.c;
    final r0 = an.r < fo.r ? an.r : fo.r, r1 = an.r > fo.r ? an.r : fo.r;
    final grid = [
      for (var r = r0; r <= r1; r++)
        [
          for (var b = b0; b <= b1; b++)
            for (var c = c0; c <= c1; c++) _cellValue(cell(b, c, r)) ?? '',
        ],
    ];
    await Clipboard.setData(ClipboardData(text: ClipboardGrid.build(grid)));
  }

  Future<void> _pasteClipboard() async {
    final at = _selection.focus;
    if (at == null) return;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    _pasteGridFrom(at, text);
  }

  /// Применяет TSV-сетку от ячейки [at] по-ячеечно; сетка дорастает.
  /// После вставки в панель заявки с полностью заполненными позициями
  /// запускает автосопоставление предложений.
  void _pasteGridFrom(CellAddress at, String text) {
    final grid = ClipboardGrid.parse(text);
    if (grid.isEmpty) return;
    final notifier = ref.read(appStateProvider.notifier);
    for (var i = 0; i < grid.length; i++) {
      final row = grid[i];
      for (var j = 0; j < row.length; j++) {
        _applyCell(
          cell(at.b, at.c + j, at.r + i),
          row[j],
          notifier,
          isLastSourceColumn: j == row.length - 1,
        );
      }
    }
    if (at.b == -1) {
      // Вставили заявку — свежие (полностью непривязанные) поставщики
      // сопоставляются позиционно: k-е предложение → k-я позиция.
      notifier.linkOffersPositionally();
    }
  }

  void _applyCell(
    CellAddress a,
    String value,
    AppStateNotifier notifier, {
    bool isLastSourceColumn = false,
  }) {
    final state = ref.read(appStateProvider);
    // Свежая раскладка: предыдущие ячейки вставки уже могли дорастить сетку.
    final layout = ref.read(tableLayoutProvider);
    final vat = ref.read(appConfigProvider).value?.vatRate ?? 0.22;
    if (a.r < 0 ||
        a.r >= layout.totalRows ||
        a.b < -1 ||
        a.b >= state.suppliers.length) {
      return;
    }

    if (a.b == -1) {
      final g = layout.groupOfRow(a.r);
      final idx = g != null
          ? state.requestItems.indexOf(g.item)
          : layout.groups.length + (a.r - layout.unlinkedFirstRow);
      if (idx < 0) return;
      switch (a.c) {
        case 0:
          notifier.updateRequestItem(idx, name: value);
        case 1:
          // Последняя колонка источника без отдельной ед.изм:
          // «9 шт» → кол-во 9 + ед.изм шт.
          final split = isLastSourceColumn
              ? ClipboardGrid.splitQtyUnit(value)
              : null;
          if (split != null && split.$2.isNotEmpty) {
            notifier.updateRequestItem(idx, qty: split.$1, unit: split.$2);
          } else {
            notifier.updateRequestItem(idx, qty: value);
          }
        case 2:
          notifier.updateRequestItem(idx, unit: value);
      }
      return;
    }

    if (a.b >= state.suppliers.length) return;
    final s = state.suppliers[a.b];
    final g = layout.groupOfRow(a.r);
    final Offer? offer;
    if (g != null) {
      final linked = s.offers
          .where((o) => o.linkedRequestItemId == g.item.id)
          .toList();
      offer = a.r - g.firstRow < linked.length
          ? linked[a.r - g.firstRow]
          : null;
    } else {
      final unlinked = s.offers
          .where((o) => o.linkedRequestItemId == null)
          .toList();
      final j = a.r - layout.unlinkedFirstRow;
      offer = j >= 0 && j < unlinked.length ? unlinked[j] : null;
    }

    Offer transform(Offer o) {
      switch (a.c) {
        case 0:
          return o.copyWith(itemName: value);
        case 1:
          final split = isLastSourceColumn
              ? ClipboardGrid.splitQtyUnit(value)
              : null;
          if (split != null && split.$2.isNotEmpty) {
            final n = parseNumber(split.$1);
            return o.copyWith(qty: n, clearQty: n == null, unit: split.$2);
          }
          final n = parseNumber(value);
          return o.copyWith(qty: n, clearQty: n == null);
        case 2:
          return o.copyWith(unit: value);
        case 3:
          return o.withPriceInput(parseNumber(value), withoutVat: s.withoutVat);
        default:
          return o.withSumInput(
            parseNumber(value),
            withoutVat: s.withoutVat,
            vat: vat,
          );
      }
    }

    if (offer != null) {
      notifier.updateOffer(s.id, offer.id, transform);
    } else {
      notifier.createOfferAt(s.id, g?.item.id, transform);
    }
  }

  // --- сборка ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appStateProvider);
    final layout = ref.watch(tableLayoutProvider);
    final notifier = ref.read(appStateProvider.notifier);

    _selection.setBounds(
      SelectionBounds(
        totalRows: layout.totalRows,
        supplierCount: state.suppliers.length,
      ),
    );
    _selection.keyFocus = _tableFocus;
    _selection.boundsProvider = () => SelectionBounds(
      totalRows: ref.read(tableLayoutProvider).totalRows,
      supplierCount: ref.read(appStateProvider).suppliers.length,
    );
    _selection.gridPaste = _pasteGridFrom;
    // Навигация перепрыгивает объединённые ячейки: группа заявки целиком
    // (фикс. колонки) или поставщик с одним предложением на группу.
    _selection.spanResolver = (a) {
      final layout = ref.read(tableLayoutProvider);
      final g = layout.groupOfRow(a.r);
      if (g == null) return null;
      if (a.b == -1) return (firstRow: g.firstRow, rows: g.rows);
      final suppliers = ref.read(appStateProvider).suppliers;
      if (a.b >= suppliers.length) return null;
      final linked = suppliers[a.b].offers
          .where((o) => o.linkedRequestItemId == g.item.id)
          .length;
      return linked <= 1 ? (firstRow: g.firstRow, rows: g.rows) : null;
    };
    _selection.onMoved = _ensureFocusedVisible;

    return SelectionScope(
      notifier: _selection,
      child: Focus(
        focusNode: _tableFocus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Listener(
          onPointerDown: _onPointerDown,
          onPointerSignal: _onPointerSignal,
          child: MouseRegion(
            cursor: _autoscroll
                ? SystemMouseCursors.allScroll
                : MouseCursor.defer,
            onHover: (event) => _pointer = event.position,
            child: SingleChildScrollView(
              controller: _vertical,
              scrollDirection: Axis.vertical,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const FixedPanel(),
                      Expanded(
                        child: state.suppliers.isEmpty
                            ? _EmptyState(
                                onAdd: () {
                                  notifier.addSupplier(SupplierBlock.empty());
                                },
                              )
                            : SingleChildScrollView(
                                key: const ValueKey(
                                  'suppliers.horizontalScroll',
                                ),
                                controller: _horizontal,
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    for (
                                      var i = 0;
                                      i < state.suppliers.length;
                                      i++
                                    )
                                      DragTarget<SupplierDrag>(
                                        onWillAcceptWithDetails: (details) =>
                                            details.data.supplierId !=
                                            state.suppliers[i].id,
                                        onMove: (details) =>
                                            _onDragMove(i, details.data),
                                        onLeave: (data) => _onDragLeave(i),
                                        onAcceptWithDetails: (details) =>
                                            _onDragAccept(i, details.data),
                                        builder:
                                            (context, candidates, rejected) {
                                              return _withInsertPreview(
                                                context,
                                                i,
                                                SupplierColumn(
                                                  supplierId:
                                                      state.suppliers[i].id,
                                                  index: i,
                                                  onDragUpdate:
                                                      _onTableDragUpdate,
                                                  onDragEnd: _stopDragScroll,
                                                ),
                                              );
                                            },
                                      ),
                                  ],
                                ),
                              ),
                      ),
                    ],
                  ),
                  const BestVariantPanel(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Полоса вставки и анимированный зазор на той стороне целевой колонки,
  /// куда встанет перетаскиваемый блок (как в Windows Explorer).
  Widget _withInsertPreview(BuildContext context, int i, Widget column) {
    final from = _dragFrom;
    if (_dragHover != i || from == null || from == i) return column;
    final insertAfter = from < i;
    final color = Theme.of(context).colorScheme.primary;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      margin: insertAfter
          ? const EdgeInsets.only(left: 8)
          : const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(
        border: Border(
          left: insertAfter
              ? BorderSide(color: color, width: 3)
              : BorderSide.none,
          right: !insertAfter
              ? BorderSide(color: color, width: 3)
              : BorderSide.none,
        ),
      ),
      child: column,
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.table_chart_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          const Text('Таблица пуста'),
          const SizedBox(height: 8),
          const Text(
            'Перетащите счёт или добавьте поставщика вручную',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const ValueKey('empty.addSupplier'),
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Добавить поставщика'),
          ),
        ],
      ),
    );
  }
}
