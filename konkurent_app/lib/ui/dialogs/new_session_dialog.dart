import 'package:flutter/material.dart';

/// Подтверждение сброса текущей сессии, если есть несохранённые изменения.
Future<bool> confirmNewSession(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Новая сессия?'),
      content: const Text(
        'Текущая таблица будет очищена, несохранённые изменения будут потеряны.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Отмена'),
        ),
        FilledButton(
          key: const ValueKey('newSession.confirm'),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Очистить'),
        ),
      ],
    ),
  );
  return result ?? false;
}