import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ui/constants.dart';

/// Масштаб таблицы и шапки (1.0 = 100 %). Меняет реальные размеры ячеек,
/// колонок и шрифта — при уменьшении в окно влезает больше предложений.
class ZoomNotifier extends Notifier<double> {
  static const double min = 0.75;
  static const double max = 1.25;
  static const double step = 0.05;

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

/// Размеры таблицы, вычисляемые от текущего масштаба.
final tableMetricsProvider =
    Provider<TableMetrics>((ref) => TableMetrics(ref.watch(zoomProvider)));