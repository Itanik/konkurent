import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:konkurent_app/models/app_state.dart';
import 'package:konkurent_app/providers/app_state_provider.dart';
import 'package:konkurent_app/providers/zoom_provider.dart';
import 'package:konkurent_app/ui/comparison_table/row_heights.dart';

void main() {
  // TextPainter в тестовом окружении доступен после TestWidgetsFlutterBinding.
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
  });

  void seed(String itemName) {
    container.read(appStateProvider.notifier).addSupplier(SupplierBlock(
          id: 's1',
          offers: [Offer(id: 'o1', itemName: itemName, qty: 9)],
        ));
  }

  test('длинная позиция поднимает высоту строки', () {
    seed('Шпилька резьбовая М 12х2000 DIN 975 цинк');
    final heights = container.read(rowHeightsProvider);
    // Базовая высота 44; перенос на ~3 строки должен дать существенно больше.
    expect(heights.data[0], greaterThan(60));
  });

  test('короткая позиция остаётся базовой', () {
    seed('Болт');
    final heights = container.read(rowHeightsProvider);
    expect(heights.data[0], 44.0);
  });

  test('высота учитывает масштаб: при 80% не больше, чем при 100%', () {
    seed('Анкер химический HVU шпилька HAS-E М16х125, либо аналог, л');
    final h100 = container.read(rowHeightsProvider).data[0];
    container.read(zoomProvider.notifier).set(0.8);
    final h80 = container.read(rowHeightsProvider).data[0];
    expect(h80, lessThanOrEqualTo(h100));
    expect(h80, greaterThan(44 * 0.8), reason: 'перенос сохраняется при зуме');
  });
}
