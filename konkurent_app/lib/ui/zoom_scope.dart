import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/zoom_provider.dart';

/// Равномерно масштабирует всё приложение: логический размер окна уменьшается
/// в [zoom] раз, а отрисованное содержимое растягивается обратно (`Transform`).
/// Подмена `MediaQuery.size` держит диалоги по центру, а Flutter сам инвертирует
/// transform при обработке указателя.
class ZoomScope extends ConsumerWidget {
  const ZoomScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zoom = ref.watch(zoomProvider);
    final notifier = ref.read(zoomProvider.notifier);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.equal, control: true):
            notifier.zoomIn,
        const SingleActivator(LogicalKeyboardKey.equal, control: true, shift: true):
            notifier.zoomIn,
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth / zoom;
            final height = constraints.maxHeight / zoom;
            return ClipRect(
              child: Transform.scale(
                scale: zoom,
                alignment: Alignment.topLeft,
                child: MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    size: Size(width, height),
                  ),
                  // Align даёт дочернему `SizedBox` свободные констрейнты,
                  // иначе tight-констрейнты окна заставляют контент занять
                  // полную ширину и при zoom>1 шапка уезжает за экран.
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: width,
                      height: height,
                      child: child,
                    ),
                  ),
                ),
              ),
            );
          },
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