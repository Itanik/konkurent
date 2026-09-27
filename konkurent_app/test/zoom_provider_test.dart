import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:konkurent_app/providers/zoom_provider.dart';

void main() {
  late ProviderContainer container;
  ZoomNotifier notifier() => container.read(zoomProvider.notifier);
  double value() => container.read(zoomProvider);

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
  });

  test('по умолчанию 100 %', () {
    expect(value(), 1.0);
  });

  test('шаг 5 %', () {
    notifier().zoomIn();
    expect(value(), closeTo(1.05, 1e-9));
    notifier().zoomOut();
    notifier().zoomOut();
    expect(value(), closeTo(0.95, 1e-9));
  });

  test('ограничение диапазоном 75–125 %', () {
    notifier().set(0.1);
    expect(value(), ZoomNotifier.min);
    notifier().set(5.0);
    expect(value(), ZoomNotifier.max);
  });

  test('метрики пропорциональны масштабу', () {
    container.read(zoomProvider.notifier).set(1.25);
    final m = container.read(tableMetricsProvider);
    expect(m.dataRowHeight, closeTo(44 * 1.25, 1e-9));
    expect(m.itemWidth, closeTo(200 * 1.25, 1e-9));
  });

  test('reset возвращает 100 %', () {
    notifier().set(1.25);
    notifier().reset();
    expect(value(), 1.0);
  });
}