import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:konkurent_app/models/app_state.dart';
import 'package:konkurent_app/providers/app_state_provider.dart';
import 'package:konkurent_app/providers/session_provider.dart';

void main() {
  test('пустое состояние всегда «чистое»', () {
    expect(isStateDirty(const AppState(), null), isFalse);
    expect(isStateDirty(const AppState(), 'whatever'), isFalse);
  });

  test('заполненное состояние без базовой сигнатуры «грязное»', () {
    final state = AppState(
      suppliers: [SupplierBlock(id: 's1', displayName: 'A')],
    );
    expect(isStateDirty(state, null), isTrue);
    expect(isStateDirty(state, stateSignature(state)), isFalse);
    expect(
      isStateDirty(state.copyWith(requestName: 'X'), stateSignature(state)),
      isTrue,
    );
  });

  test('провайдер isDirty реагирует на изменения и markClean', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(isDirtyProvider), isFalse);
    container.read(appStateProvider.notifier).addSupplier(
          const SupplierBlock(id: 's1', displayName: 'A'),
        );
    expect(container.read(isDirtyProvider), isTrue);

    container.read(cleanSignatureProvider.notifier).markClean(
          stateSignature(container.read(appStateProvider)),
        );
    expect(container.read(isDirtyProvider), isFalse);

    container.read(appStateProvider.notifier).setRequestName('Y');
    expect(container.read(isDirtyProvider), isTrue);
  });

  test('пустой поставщик не делает состояние содержательным', () {
    final state = AppState(
      suppliers: [SupplierBlock.empty()],
    );
    expect(state.hasContent, isFalse);
    expect(isStateDirty(state, null), isFalse);
  });
}