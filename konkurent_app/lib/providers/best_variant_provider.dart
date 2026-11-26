import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Временная подсветка кликнутого варианта закупки: заливка сумм выигравших
/// предложений и колонок поставщиков. Не персистится; сбрасывается новой
/// сессией и любым изменением таблицы не сбрасывается (пересчитывается
/// панелью при следующем клике).
class VariantHighlight {
  const VariantHighlight({this.offerIds = const {}, this.supplierIds = const {}});

  final Set<String> offerIds;
  final Set<String> supplierIds;

  bool get isEmpty => offerIds.isEmpty && supplierIds.isEmpty;
}

class VariantHighlightNotifier extends Notifier<VariantHighlight> {
  @override
  VariantHighlight build() => const VariantHighlight();

  void set(VariantHighlight next) => state = next;

  void clear() => state = const VariantHighlight();
}

final variantHighlightProvider =
    NotifierProvider<VariantHighlightNotifier, VariantHighlight>(
        VariantHighlightNotifier.new);
