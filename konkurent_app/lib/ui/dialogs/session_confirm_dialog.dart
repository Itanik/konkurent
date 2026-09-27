import 'package:flutter/material.dart';

enum OpenSessionChoice { cancel, discard, saveThenOpen }

/// Пользователь перетащил файл со «своей» структурой: решаем, что делать
/// с текущей сессией.
Future<OpenSessionChoice> showOpenSessionDialog(BuildContext context) async {
  final result = await showDialog<OpenSessionChoice>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Открыть файл как новую сессию?'),
      content: const Text(
        'Текущая таблица будет заменена данными из файла.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, OpenSessionChoice.cancel),
          child: const Text('Отмена'),
        ),
        TextButton(
          key: const ValueKey('openSession.saveThenOpen'),
          onPressed: () =>
              Navigator.pop(context, OpenSessionChoice.saveThenOpen),
          child: const Text('Сохранить текущую и открыть'),
        ),
        FilledButton(
          key: const ValueKey('openSession.discard'),
          onPressed: () => Navigator.pop(context, OpenSessionChoice.discard),
          child: const Text('Открыть без сохранения'),
        ),
      ],
    ),
  );
  return result ?? OpenSessionChoice.cancel;
}