import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_state.dart';
import '../../providers/app_state_provider.dart';
import '../../providers/zoom_provider.dart';

/// Верхняя панель: имя заявки и действия. Открытие/сохранение делегируются
/// в AppShell, т.к. требуют доступа к файловому движку и диалогам.
class AppToolbar extends ConsumerWidget implements PreferredSizeWidget {
  const AppToolbar({
    super.key,
    required this.onOpen,
    required this.onSave,
  });

  final Future<void> Function() onOpen;
  final Future<void> Function() onSave;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(appStateProvider.notifier);
    final zoom = ref.watch(zoomProvider);
    final zoomNotifier = ref.read(zoomProvider.notifier);

    return AppBar(
      titleSpacing: 12,
      title: SizedBox(
        width: 320,
        child: const _RequestNameField(),
      ),
      actions: [
        IconButton(
          key: const ValueKey('toolbar.addSupplier'),
          tooltip: 'Добавить поставщика',
          icon: const Icon(Icons.group_add_outlined),
          onPressed: () => notifier.addSupplier(SupplierBlock.empty()),
        ),
        IconButton(
          key: const ValueKey('toolbar.sort'),
          tooltip: 'Сортировать по сумме',
          icon: const Icon(Icons.sort),
          onPressed: notifier.sortSuppliersByTotal,
        ),
        IconButton(
          key: const ValueKey('toolbar.open'),
          tooltip: 'Открыть…',
          icon: const Icon(Icons.folder_open),
          onPressed: onOpen,
        ),
        IconButton(
          key: const ValueKey('toolbar.save'),
          tooltip: 'Сохранить xlsx',
          icon: const Icon(Icons.save_alt),
          onPressed: onSave,
        ),
        const SizedBox(width: 8),
        IconButton(
          key: const ValueKey('toolbar.zoomOut'),
          tooltip: 'Уменьшить масштаб (Ctrl+-)',
          icon: const Icon(Icons.remove),
          onPressed: zoomNotifier.zoomOut,
        ),
        TextButton(
          key: const ValueKey('toolbar.zoomReset'),
          onPressed: zoomNotifier.reset,
          child: Text('${(zoom * 100).round()} %'),
        ),
        IconButton(
          key: const ValueKey('toolbar.zoomIn'),
          tooltip: 'Увеличить масштаб (Ctrl++)',
          icon: const Icon(Icons.add),
          onPressed: zoomNotifier.zoomIn,
        ),
        const SizedBox(width: 8),
      ],
    );
  }
}

class _RequestNameField extends ConsumerStatefulWidget {
  const _RequestNameField();

  @override
  ConsumerState<_RequestNameField> createState() => _RequestNameFieldState();
}

class _RequestNameFieldState extends ConsumerState<_RequestNameField> {
  late final TextEditingController _controller;
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _controller =
        TextEditingController(text: ref.read(appStateProvider).requestName);
    _focus = FocusNode();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(appStateProvider, (previous, next) {
      if (!_focus.hasFocus && next.requestName != _controller.text) {
        _controller.text = next.requestName;
      }
    });

    return TextField(
      key: const ValueKey('toolbar.requestName'),
      controller: _controller,
      focusNode: _focus,
      style: Theme.of(context).textTheme.titleMedium,
      decoration: const InputDecoration(
        isDense: true,
        prefixText: 'Заявка: ',
        hintText: 'Название заявки',
        border: InputBorder.none,
      ),
      onChanged: ref.read(appStateProvider.notifier).setRequestName,
    );
  }
}