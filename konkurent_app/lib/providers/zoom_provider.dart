import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Масштаб интерфейса (1.0 = 100 %). Равномерно масштабирует всё приложение.
class ZoomNotifier extends Notifier<double> {
  static const double min = 0.6;
  static const double max = 1.6;
  static const double step = 0.1;

  @override
  double build() => 1.0;

  void set(double value) {
    final rounded = (value * 100).round() / 100;
    state = rounded.clamp(min, max);
  }

  void zoomIn() => set(state + step);

  void zoomOut() => set(state - step);

  void reset() => set(1.0);
}

final zoomProvider = NotifierProvider<ZoomNotifier, double>(ZoomNotifier.new);