import 'package:flutter/material.dart';

/// Что делать со счётом, распознанным от уже известного поставщика, когда
/// его позиции пересекаются с имеющимися.
enum InvoiceMergeChoice { update, alternative, separate }

/// Диалог выбора: обновить блок значениями нового счёта, добавить как
/// альтернативное предложение (АП) или отдельным блоком.
Future<InvoiceMergeChoice?> showInvoiceMergeDialog(
  BuildContext context,
  String supplierName,
) {
  return showDialog<InvoiceMergeChoice>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Счёт от $supplierName уже есть в таблице'),
      content: const Text(
          'Позиции нового счёта пересекаются с имеющимися. Как поступить?'),
      actions: [
        TextButton(
          key: const ValueKey('invoiceMerge.update'),
          onPressed: () =>
              Navigator.of(context).pop(InvoiceMergeChoice.update),
          child: const Text('Обновить блок'),
        ),
        TextButton(
          key: const ValueKey('invoiceMerge.alternative'),
          onPressed: () =>
              Navigator.of(context).pop(InvoiceMergeChoice.alternative),
          child: const Text('Как альтернативу (АП)'),
        ),
        TextButton(
          key: const ValueKey('invoiceMerge.separate'),
          onPressed: () =>
              Navigator.of(context).pop(InvoiceMergeChoice.separate),
          child: const Text('Отдельным блоком'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
      ],
    ),
  );
}
