import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../models/app_state.dart';
import '../providers/app_state_provider.dart';
import '../providers/services.dart';
import '../providers/session_provider.dart';
import '../providers/table_layout_provider.dart';
import '../providers/zoom_provider.dart';
import '../services/app_config_service.dart';
import '../services/python_bridge.dart';
import '../services/best_offer.dart';
import '../services/supplier_db.dart';
import '../ui/constants.dart';
import 'app_toolbar.dart';
import 'comparison_table/comparison_table.dart';
import 'dialogs/invoice_merge_dialog.dart';
import 'dialogs/new_session_dialog.dart';
import 'dialogs/session_confirm_dialog.dart';
import 'zoom_scope.dart';

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
      builder: (context, child) =>
          ZoomScope(child: child ?? const SizedBox.shrink()),
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
  late final AppLifecycleListener _lifecycle;

  FileEngine get _engine => ref.read(fileEngineProvider);

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onExitRequested: _onExitRequested);
    ref.listenManual(appStateProvider, (previous, next) => _scheduleSave());
    ref.listenManual(zoomProvider,
        (previous, next) => ref.read(storageServiceProvider).saveZoom(next));
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadInitial());
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    final storage = ref.read(storageServiceProvider);
    final saved = await storage.load();
    if (saved != null && mounted) {
      // Восстановленная сессия = несохранённые изменения, поэтому базовую
      // сигнатуру не трогаем (clean = null) — она продолжит сохраняться.
      ref.read(appStateProvider.notifier).replaceState(saved);
    }
    final zoom = await storage.loadZoom();
    if (zoom != null && mounted) {
      ref.read(zoomProvider.notifier).set(zoom);
    }
  }

  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 500), _persist);
  }

  /// Сохраняет сессию только при несохранённых изменениях, иначе удаляет её.
  void _persist() {
    if (!mounted) return;
    final storage = ref.read(storageServiceProvider);
    if (ref.read(isDirtyProvider)) {
      storage.save(ref.read(appStateProvider));
    } else {
      storage.clear();
    }
  }

  void _markClean() {
    ref
        .read(cleanSignatureProvider.notifier)
        .markClean(stateSignature(ref.read(appStateProvider)));
  }

  Future<AppExitResponse> _onExitRequested() async {
    _saveDebounce?.cancel();
    final storage = ref.read(storageServiceProvider);
    if (ref.read(isDirtyProvider)) {
      await storage.save(ref.read(appStateProvider));
    } else {
      await storage.clear();
    }
    return AppExitResponse.exit;
  }

  Future<void> _onNewSession() async {
    if (ref.read(isDirtyProvider)) {
      final confirmed = await confirmNewSession(context);
      if (!confirmed || !mounted) return;
    }
    ref.read(appStateProvider.notifier).reset();
    _markClean();
    await ref.read(storageServiceProvider).clear();
    _snack('Новая сессия');
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
        _markClean();
        await ref.read(storageServiceProvider).clear();
        _snack('Сессия открыта из ${p.basename(path)}');
        return;
      }
      if (outcome.status == ImportStatus.error) {
        _snack('Ошибка открытия: ${outcome.error}');
        return;
      }
      // foreign → распознаём как прайс-лист
    }

    final rec = await _engine.recognize(
      path,
      legalFormsPath:
          await ref.read(appConfigServiceProvider).legalFormsPath(),
    );
    if (!mounted) return;
    final notifier = ref.read(appStateProvider.notifier);
    final db = ref.read(supplierDbProvider);
    if (rec.ok && rec.supplier != null) {
      // Нормализуем распознанные единицы по словарю (тн/м.п/… → т/м);
      // несопоставившиеся остаются как есть и подсвечиваются в сетке.
      final units =
          ref.read(appConfigProvider).value?.units ?? const UnitsDict({});
      var supplier = rec.supplier!.copyWith(
        offers: [
          for (final o in rec.supplier!.offers)
            o.unit.isEmpty ? o : (() {
                  final n = units.normalize(o.unit);
                  return n == null ? o : o.copyWith(unit: n);
                })(),
        ],
      );

      // Память поставщиков: знакомый ИНН — автозаполнение пустых мета
      // последними значениями и названием из БД.
      if (db != null && supplier.inn != null) {
        final record = db.getByInn(supplier.inn!);
        if (record != null) {
          if (supplier.displayName.isEmpty && record.name.isNotEmpty) {
            supplier = supplier.copyWith(displayName: record.name);
          }
          var meta = supplier.meta;
          for (final row in kMetaRows) {
            if (row.key == 'comment') continue;
            if (meta.value(row.key).isEmpty) {
              final last = db.lastMeta(supplier.inn!, row.key);
              if (last != null) meta = meta.copyWithValue(row.key, last);
            }
          }
          supplier = supplier.copyWith(meta: meta);
        }
      }

      // Счёт от уже известного поставщика (совпал ИНН)?
      final existing = supplier.inn == null
          ? null
          : ref
              .read(appStateProvider)
              .suppliers
              .where((s) => s.inn == supplier.inn)
              .firstOrNull;
      if (existing == null) {
        notifier.addSupplier(supplier);
        // Позиционное сопоставление по умолчанию: счета обычно повторяют
        // порядок заявки. Излишки остаются в зоне без привязки.
        final linked = notifier.linkOffersPositionally();
        db?.upsertSupplier(
            inn: supplier.inn ?? '', name: supplier.displayName);
        _snack('Добавлен поставщик: '
            '${supplier.displayName.isEmpty ? p.basename(path) : supplier.displayName}'
            '${linked > 0 ? ' (сопоставлено позиций: $linked)' : ''}');
        return;
      }

      if (notifier.isDuplicateInvoice(existing, supplier)) {
        _snack('Точный дубль счёта от ${existing.displayName} — пропущен');
        return;
      }

      if (!notifier.offersIntersect(existing, supplier)) {
        // Без пересечений — тихое слияние в тот же блок.
        notifier.mergeIntoSupplier(targetId: existing.id, incoming: supplier);
        db?.upsertSupplier(inn: supplier.inn!, name: existing.displayName);
        _snack('Счёт добавлен к поставщику ${existing.displayName}');
        return;
      }

      final choice = await showInvoiceMergeDialog(
          context,
          existing.displayName.isEmpty
              ? p.basename(path)
              : existing.displayName);
      if (!mounted || choice == null) return;
      switch (choice) {
        case InvoiceMergeChoice.update:
          notifier.updateSupplierInvoice(
              targetId: existing.id, incoming: supplier);
          _snack('Блок ${existing.displayName} обновлён из счёта');
        case InvoiceMergeChoice.alternative:
          final base = supplier.displayName.isEmpty
              ? existing.displayName
              : supplier.displayName;
          final apCount = ref
              .read(appStateProvider)
              .suppliers
              .where((s) => s.displayName.startsWith('$base (АП'))
              .length;
          final name =
              apCount == 0 ? '$base (АП)' : '$base (АП ${apCount + 1})';
          notifier.addSupplier(supplier.copyWith(displayName: name));
          notifier.linkOffersPositionally();
          _snack('Альтернативное предложение добавлено: $name');
        case InvoiceMergeChoice.separate:
          notifier.addSupplier(supplier);
          notifier.linkOffersPositionally();
          _snack('Добавлен отдельный блок: ${supplier.displayName}');
      }
      db?.upsertSupplier(inn: supplier.inn ?? '', name: supplier.displayName);
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

    // Лучшие варианты закупки: движок запишет их строками под итогом
    // (название варианта + =SUM по выигравшим ячейкам сумм).
    final config = ref.read(appConfigProvider).value;
    final variants = bestProcurementVariants(state,
        vat: config?.vatRate ?? 0.22,
        maxSuppliers: config?.maxSuppliers ?? 3);
    final layout = ref.read(tableLayoutProvider);
    const excelDataStart = 5; // строки 1-4: заявка/ИНН/файлы/заголовки
    const blockStart = 5; // первая колонка блока поставщика
    const blockSize = 6; // Предложено..Сумма с НДС
    final bestVariants = <Map<String, dynamic>>[];
    for (final v in variants) {
      final cells = <List<int>>[];
      v.picks.forEach((itemIdx, supplierIdx) {
        final g = layout.groups[itemIdx];
        final s = state.suppliers[supplierIdx];
        final linked = s.offers
            .where((o) => o.linkedRequestItemId == g.item.id)
            .toList();
        for (var j = 0; j < linked.length; j++) {
          final r = g.firstRow + (linked.length > 1 ? j : 0);
          final col = blockStart + blockSize * supplierIdx + blockSize - 1;
          cells.add([col, excelDataStart + r]);
        }
      });
      bestVariants.add({
        'label': '${v.label}${v.coverageSuffix}',
        'cells': cells,
      });
    }

    final outcome =
        await _engine.export(state, location.path, bestVariants: bestVariants);
    if (outcome.ok) {
      _markClean();
      await ref.read(storageServiceProvider).clear();
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
    final zoom = ref.watch(zoomProvider);
    return ScaffoldMessenger(
      key: _messengerKey,
      child: Scaffold(
        appBar: AppToolbar(
          scale: zoom,
          onOpen: _open,
          onSave: _save,
          onNewSession: _onNewSession,
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