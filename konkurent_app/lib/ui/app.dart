import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../models/app_state.dart';
import '../providers/app_state_provider.dart';
import '../providers/services.dart';
import '../services/python_bridge.dart';
import 'app_toolbar.dart';
import 'comparison_table/comparison_table.dart';
import 'dialogs/session_confirm_dialog.dart';

const _typeGroups = [
  XTypeGroup(
    label: 'Счета и таблицы',
    extensions: ['pdf', 'xlsx', 'xls', 'docx'],
  ),
];

class KonkurentApp extends StatelessWidget {
  const KonkurentApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Конкурентная таблица',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
      ),
      home: const AppShell(),
    );
  }
}

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  final GlobalKey<ScaffoldMessengerState> _messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  bool _dragging = false;
  bool _busy = false;
  Timer? _saveDebounce;

  FileEngine get _engine => ref.read(fileEngineProvider);

  @override
  void initState() {
    super.initState();
    ref.listenManual(appStateProvider, (previous, next) => _scheduleSave());
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadInitial());
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    final saved = await ref.read(storageServiceProvider).load();
    if (saved != null && mounted) {
      ref.read(appStateProvider.notifier).replaceState(saved);
    }
  }

  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 500), () {
      ref.read(storageServiceProvider).save(ref.read(appStateProvider));
    });
  }

  void _snack(String message) {
    _messengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _handlePaths(List<String> paths) async {
    if (_busy || paths.isEmpty) return;
    setState(() => _busy = true);
    try {
      for (final path in paths) {
        await _processPath(path);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _processPath(String path) async {
    final ext = p.extension(path).toLowerCase();
    if (ext == '.xlsx' || ext == '.xls' || ext == '.xlsm') {
      final outcome = await _engine.importFile(path);
      if (!mounted) return;

      if (outcome.status == ImportStatus.ok && outcome.state != null) {
        final choice = await showOpenSessionDialog(context);
        if (!mounted || choice == OpenSessionChoice.cancel) return;
        if (choice == OpenSessionChoice.saveThenOpen) {
          final saved = await _save();
          if (!saved || !mounted) return;
        }
        ref.read(appStateProvider.notifier).replaceState(outcome.state!);
        _snack('Сессия открыта из ${p.basename(path)}');
        return;
      }
      if (outcome.status == ImportStatus.error) {
        _snack('Ошибка открытия: ${outcome.error}');
        return;
      }
      // foreign → распознаём как прайс-лист
    }

    final rec = await _engine.recognize(path);
    if (!mounted) return;
    if (rec.ok && rec.supplier != null) {
      ref.read(appStateProvider.notifier).addSupplier(rec.supplier!);
      _snack('Добавлен поставщик: '
          '${rec.supplier!.displayName.isEmpty ? p.basename(path) : rec.supplier!.displayName}');
    } else {
      _snack('Не удалось распознать ${p.basename(path)}: ${rec.error}');
    }
  }

  Future<void> _open() async {
    final file = await openFile(acceptedTypeGroups: _typeGroups);
    if (file == null) return;
    await _handlePaths([file.path]);
  }

  Future<bool> _save() async {
    final state = ref.read(appStateProvider);
    if (state.suppliers.isEmpty && state.requestItems.isEmpty) {
      _snack('Нечего сохранять');
      return false;
    }
    final location = await getSaveLocation(
      suggestedName: _suggestedName(state),
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Excel', extensions: ['xlsx']),
      ],
    );
    if (location == null) return false;

    final outcome = await _engine.export(state, location.path);
    if (outcome.ok) {
      _snack('Сохранено: ${outcome.path}');
      return true;
    }
    _snack('Ошибка сохранения: ${outcome.error}');
    return false;
  }

  String _suggestedName(AppState state) {
    final base = state.requestName.trim().isEmpty
        ? 'конкурент'
        : 'конкурент ${state.requestName.trim()}';
    return '$base.xlsx';
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: _messengerKey,
      child: Scaffold(
        appBar: AppToolbar(
          onOpen: _open,
          onSave: _save,
        ),
        body: Stack(
          children: [
            Positioned.fill(
              child: DropTarget(
                onDragEntered: (_) => setState(() => _dragging = true),
                onDragExited: (_) => setState(() => _dragging = false),
                onDragDone: (details) {
                  setState(() => _dragging = false);
                  _handlePaths(details.files.map((f) => f.path).toList());
                },
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _dragging
                          ? Theme.of(context).colorScheme.primary
                          : Colors.transparent,
                      width: 3,
                    ),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: const ComparisonTable(),
                ),
              ),
            ),
            if (_busy)
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(minHeight: 3),
              ),
          ],
        ),
      ),
    );
  }
}