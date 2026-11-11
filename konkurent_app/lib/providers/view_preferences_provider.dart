import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Отображение таблицы (текущие настройки сессии, не сохраняются).
class ViewPreferencesNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
}

/// Режим сумм: спрятать все колонки блоков, кроме «Сумма, с НДС».
final sumsOnlyProvider =
    NotifierProvider<ViewPreferencesNotifier, bool>(ViewPreferencesNotifier.new);

/// Показ скрытой колонки «Сумма, без НДС» (по умолчанию спрятана).
final showSumWithoutVatProvider = NotifierProvider<ViewPreferencesNotifier, bool>(
  ViewPreferencesNotifier.new,
);
