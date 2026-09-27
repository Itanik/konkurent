/// Типизированные полезные нагрузки drag&drop.
///
/// Вложенные [DragTarget] должны иметь разные типы: иначе внешний
/// (перестановка поставщиков) перехватывает перетаскивание предложения внутри
/// колонки. Раньше оба были `String` и конфликтовали.
class SupplierDrag {
  const SupplierDrag(this.supplierId);

  final String supplierId;
}

class OfferDrag {
  const OfferDrag(this.supplierId, this.fromIndex);

  final String supplierId;
  final int fromIndex;
}