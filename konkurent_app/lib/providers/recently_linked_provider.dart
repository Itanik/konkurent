import 'package:flutter_riverpod/flutter_riverpod.dart';

/// id предложений, привязанных последним запускoм автосопоставления:
/// подсвечиваются в сетке мягкой заливкой, пока пользователь не запустит
/// сопоставление снова или не начнёт новую сессию. UI-состояние, не
/// персистится.
class RecentlyLinkedNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void set(Iterable<String> ids) => state = {...ids};

  void clear() => state = const {};
}

final recentlyLinkedProvider =
    NotifierProvider<RecentlyLinkedNotifier, Set<String>>(
        RecentlyLinkedNotifier.new);
