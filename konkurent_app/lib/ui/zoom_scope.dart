import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/zoom_provider.dart';

/// Пропорционально масштабирует текст и иконки всего приложения через
/// `MediaQuery.textScaler` и `IconTheme`. Размеры ячеек таблицы масштабируются
/// отдельно метриками (`tableMetricsProvider`) — это даёт реальный обзор
/// (в окно влезает больше колонок/строк), без `Transform` и зазоров.
class ZoomScope extends ConsumerWidget {
  const ZoomScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zoom = ref.watch(zoomProvider);
    final notifier = ref.read(zoomProvider.notifier);
    final media = MediaQuery.of(context);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.equal, control: true):
            notifier.zoomIn,
        const SingleActivator(LogicalKeyboardKey.equal,
            control: true, shift: true): notifier.zoomIn,
        const SingleActivator(LogicalKeyboardKey.numpadAdd, control: true):
            notifier.zoomIn,
        const SingleActivator(LogicalKeyboardKey.minus, control: true):
            notifier.zoomOut,
        const SingleActivator(LogicalKeyboardKey.numpadSubtract, control: true):
            notifier.zoomOut,
        const SingleActivator(LogicalKeyboardKey.digit0, control: true):
            notifier.reset,
        const SingleActivator(LogicalKeyboardKey.numpad0, control: true):
            notifier.reset,
      },
      child: Listener(
        onPointerSignal: (event) {
          if (event is! PointerScrollEvent) return;
          final keyboard = HardwareKeyboard.instance;
          if (!keyboard.isControlPressed && !keyboard.isMetaPressed) return;
          // Ctrl+колесо работает только вне поля ввода, чтобы не мешать правке.
          if (_editableTextFocused()) return;
          if (event.scrollDelta.dy < 0) {
            notifier.zoomIn();
          } else if (event.scrollDelta.dy > 0) {
            notifier.zoomOut();
          }
        },
        child: MediaQuery(
          data: media.copyWith(textScaler: TextScaler.linear(zoom)),
          child: IconTheme(
            data: IconThemeData(size: 24 * zoom),
            child: child,
          ),
        ),
      ),
    );
  }

  bool _editableTextFocused() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return false;
    return context.findAncestorWidgetOfExactType<EditableText>() != null;
  }
}