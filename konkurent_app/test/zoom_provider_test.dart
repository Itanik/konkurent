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

  test('шаг 10 %', () {
    notifier().zoomIn();
    expect(value(), 1.1);
    notifier().zoomOut();
    notifier().zoomOut();
    expect(value(), closeTo(0.9, 1e-9));
  });

  test('ограничение диапазоном 60–160 %', () {
    notifier().set(0.1);
    expect(value(), ZoomNotifier.min);
    notifier().set(5.0);
    expect(value(), ZoomNotifier.max);
  });

  test('reset возвращает 100 %', () {
    notifier().set(1.5);
    notifier().reset();
    expect(value(), 1.0);
  });
}