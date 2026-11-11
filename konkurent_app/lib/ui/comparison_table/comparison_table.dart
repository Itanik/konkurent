import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_state.dart';
import '../../providers/app_state_provider.dart';
import 'fixed_panel.dart';
import 'drag_types.dart';
import 'supplier_column.dart';

/// Склейка фиксированной левой панели и горизонтально скроллящихся колонок
/// поставщиков. Вертикальный скролл общий. Средняя кнопка мыши включает
/// Windows-автоскролл (якорь + скорость от отклонения курсора), Shift+колесо
/// прокручивает по горизонтали.
class ComparisonTable extends ConsumerStatefulWidget {
  const ComparisonTable({super.key});

  @override
  ConsumerState<ComparisonTable> createState() => _ComparisonTableState();
}

class _ComparisonTableState extends ConsumerState<ComparisonTable>
    with SingleTickerProviderStateMixin {
  final ScrollController _vertical = ScrollController();
  final ScrollController _horizontal = ScrollController();

  // Автоскролл средней кнопкой.
  Ticker? _ticker;
  bool _autoscroll = false;
  Duration _lastElapsed = Duration.zero;
  Offset _anchor = Offset.zero;
  Offset _pointer = Offset.zero;

  // Live-превью перестановки поставщиков: индекс перетаскиваемого блока
  // и индекс колонки под курсором.
  int? _dragFrom;
  int? _dragHover;

  @override
  void dispose() {
    _ticker?.dispose();
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
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

    const deadzone = 12.0; // мёртвая зона вокруг якоря, px
    const speedFactor = 14.0; // px/с на пиксель отклонения

    final dx = _pointer.dx - _anchor.dx;
    final dy = _pointer.dy - _anchor.dy;

    if (_vertical.hasClients && dy.abs() > deadzone) {
      final speed = (dy.abs() - deadzone) * speedFactor * (dy.isNegative ? -1.0 : 1.0);
      final next = (_vertical.offset + speed * dt)
          .clamp(0.0, _vertical.position.maxScrollExtent);
      _vertical.jumpTo(next);
    }
    if (_horizontal.hasClients && dx.abs() > deadzone) {
      final speed = (dx.abs() - deadzone) * speedFactor * (dx.isNegative ? -1.0 : 1.0);
      final next = (_horizontal.offset + speed * dt)
          .clamp(0.0, _horizontal.position.maxScrollExtent);
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
    // Shift+колесо — горизонтальная прокрутка (Ctrl+колесо = зум, обрабатывает
    // ZoomScope выше по дереву).
    if (!keyboard.isShiftPressed || keyboard.isControlPressed) return;
    if (!_horizontal.hasClients) return;
    final next = (_horizontal.offset + event.scrollDelta.dy)
        .clamp(0.0, _horizontal.position.maxScrollExtent);
    _horizontal.jumpTo(next);
  }

  // --- live-превью перестановки поставщиков ---------------------------------

  void _onDragMove(int targetIndex, SupplierDrag data) {
    final from =
        ref.read(appStateProvider).suppliers.indexWhere((s) => s.id == data.supplierId);
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
    final from =
        ref.read(appStateProvider).suppliers.indexWhere((s) => s.id == data.supplierId);
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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appStateProvider);
    final notifier = ref.read(appStateProvider.notifier);

    return Listener(
      onPointerDown: _onPointerDown,
      onPointerSignal: _onPointerSignal,
      child: MouseRegion(
        cursor: _autoscroll ? SystemMouseCursors.allScroll : MouseCursor.defer,
        onHover: (event) => _pointer = event.position,
        child: SingleChildScrollView(
          controller: _vertical,
          scrollDirection: Axis.vertical,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Панель заявки видна всегда: список позиций заявки можно
              // заполнять ещё до появления поставщиков.
              const FixedPanel(),
              Expanded(
                child: state.suppliers.isEmpty
                    ? _EmptyState(onAdd: () {
                        notifier.addSupplier(SupplierBlock.empty());
                      })
                    : SingleChildScrollView(
                        key: const ValueKey('suppliers.horizontalScroll'),
                        controller: _horizontal,
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (var i = 0; i < state.suppliers.length; i++)
                              DragTarget<SupplierDrag>(
                                onWillAcceptWithDetails: (details) =>
                                    details.data.supplierId !=
                                    state.suppliers[i].id,
                                onMove: (details) =>
                                    _onDragMove(i, details.data),
                                onLeave: (data) => _onDragLeave(i),
                                onAcceptWithDetails: (details) =>
                                    _onDragAccept(i, details.data),
                                builder: (context, candidates, rejected) {
                                  return _withInsertPreview(
                                    context,
                                    i,
                                    SupplierColumn(
                                      supplierId: state.suppliers[i].id,
                                      index: i,
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
        ),
      ),
    );
  }

  /// Полоса вставки и анимированный зазор на той стороне целевой колонки,
  /// куда встанет перетаскиваемый блок (как в Windows Explorer).
  Widget _withInsertPreview(BuildContext context, int i, Widget column) {
    final from = _dragFrom;
    if (_dragHover != i || from == null || from == i) return column;
    final insertAfter = from < i; // reorderSuppliers: from<i → после цели
    final color = Theme.of(context).colorScheme.primary;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      margin: insertAfter
          ? const EdgeInsets.only(left: 8)
          : const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(
        border: Border(
          left: insertAfter ? BorderSide(color: color, width: 3) : BorderSide.none,
          right:
              !insertAfter ? BorderSide(color: color, width: 3) : BorderSide.none,
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
          Icon(Icons.table_chart_outlined,
              size: 64, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 16),
          const Text('Таблица пуста'),
          const SizedBox(height: 8),
          const Text('Перетащите счёт или добавьте поставщика вручную',
              textAlign: TextAlign.center),
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
