import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_state.dart';
import 'app_state_provider.dart';

/// Каноническая JSON-сигнатура состояния — для сравнения «сохранённого»
/// и текущего.
String stateSignature(AppState state) => jsonEncode(state.toJson());

/// Есть ли несохранённые изменения. Пустое состояние всегда «чистое», чтобы
/// не хранить пустую сессию.
bool isStateDirty(AppState state, String? cleanSignature) {
  if (!state.hasContent) return false;
  if (cleanSignature == null) return true;
  return stateSignature(state) != cleanSignature;
}

/// Хранит сигнатуру состояния, которое считается сохранённым (`null` — базового
/// нет, например после восстановления несохранённой сессии).
class CleanSignatureNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void markClean(String? signature) => state = signature;
}

final cleanSignatureProvider =
    NotifierProvider<CleanSignatureNotifier, String?>(
        CleanSignatureNotifier.new);

final isDirtyProvider = Provider<bool>((ref) {
  final state = ref.watch(appStateProvider);
  final clean = ref.watch(cleanSignatureProvider);
  return isStateDirty(state, clean);
});