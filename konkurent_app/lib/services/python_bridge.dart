import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/app_state.dart';

enum ImportStatus { ok, foreign, error }

class RecognizeOutcome {
  const RecognizeOutcome({required this.ok, this.supplier, this.error});

  final bool ok;
  final SupplierBlock? supplier;
  final String? error;
}

class ImportOutcome {
  const ImportOutcome({required this.status, this.state, this.error});

  final ImportStatus status;
  final AppState? state;
  final String? error;
}

class ExportOutcome {
  const ExportOutcome({required this.ok, this.path, this.error});

  final bool ok;
  final String? path;
  final String? error;
}

/// Абстракция над движком распознавания/экспорта. Реализуется PythonBridge,
/// в тестах подменяется FakeFileEngine.
abstract class FileEngine {
  Future<RecognizeOutcome> recognize(String filePath);

  Future<ImportOutcome> importFile(String filePath);

  Future<ExportOutcome> export(AppState state, String outputPath);
}

class PythonBridge implements FileEngine {
  PythonBridge({
    required String executable,
    List<String> prefixArgs = const [],
    String? workingDirectory,
    String? resolutionError,
  })  : _executable = executable,
        _prefixArgs = prefixArgs,
        _workingDirectory = workingDirectory,
        _resolutionError = resolutionError;

  final String _executable;
  final List<String> _prefixArgs;
  final String? _workingDirectory;
  final String? _resolutionError;

  static const _timeout = Duration(minutes: 5);

  /// Ищет sidecar: сначала собранный бинарник рядом с исполняемым файлом,
  /// затем `sidecar.py` вверх по дереву от текущей директории (dev-режим).
  /// Никогда не бросает: при неудаче возвращает bridge, отдающий ошибку.
  factory PythonBridge.create() {
    try {
      return _resolve();
    } catch (e) {
      return PythonBridge(executable: '', resolutionError: '$e');
    }
  }

  static PythonBridge _resolve() {
    final exeDir = File(Platform.resolvedExecutable).parent;
    final binaryName = Platform.isWindows ? 'sidecar.exe' : 'sidecar';
    final binary = File(p.join(exeDir.path, binaryName));
    if (binary.existsSync()) {
      return PythonBridge(
        executable: binary.path,
        workingDirectory: binary.parent.path,
      );
    }

    var dir = Directory.current;
    for (var i = 0; i < 5; i++) {
      final script = File(p.join(dir.path, 'sidecar.py'));
      if (script.existsSync()) {
        return PythonBridge(
          executable: _resolvePython(dir.path),
          prefixArgs: [script.path],
          workingDirectory: dir.path,
        );
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    throw StateError(
      'sidecar.py не найден. Соберите его или запускайте из корня репозитория.',
    );
  }

  static String _resolvePython(String root) {
    if (Platform.isWindows) {
      final venv = p.join(root, '.venv', 'Scripts', 'python.exe');
      if (File(venv).existsSync()) return venv;
      return 'python';
    }
    final venv = p.join(root, '.venv', 'bin', 'python3');
    if (File(venv).existsSync()) return venv;
    return 'python3';
  }

  Future<ProcessResult> _run(List<String> args, {String? stdin}) async {
    if (_resolutionError != null) {
      throw StateError(_resolutionError);
    }
    final process = await Process.start(
      _executable,
      [..._prefixArgs, ...args],
      workingDirectory: _workingDirectory,
    );
    process.stdin.write(stdin ?? '');
    await process.stdin.close();
    final outFuture = process.stdout.transform(utf8.decoder).join();
    final errFuture = process.stderr.transform(utf8.decoder).join();
    final code = await process.exitCode.timeout(
      _timeout,
      onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
    return ProcessResult(process.pid, code, await outFuture, await errFuture);
  }

  Map<String, dynamic>? _parseJson(String stdout) {
    final lines = stdout
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.startsWith('{') && l.endsWith('}'))
        .toList();
    if (lines.isEmpty) return null;
    try {
      return jsonDecode(lines.last) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<RecognizeOutcome> recognize(String filePath) async {
    try {
      final result = await _run(['--action=recognize', '--file=$filePath']);
      final json = _parseJson(result.stdout as String);
      if (json == null) {
        return RecognizeOutcome(
          ok: false,
          error: _errorText(result, 'Нет ответа от sidecar'),
        );
      }
      if (json['status'] != 'ok') {
        return RecognizeOutcome(
          ok: false,
          error: json['message']?.toString() ?? 'Ошибка распознавания',
        );
      }
      final offers = ((json['offers'] as List?) ?? [])
          .map((e) => Offer.fromJson(e as Map<String, dynamic>))
          .toList();
      return RecognizeOutcome(
        ok: true,
        supplier: SupplierBlock(
          id: newId(),
          displayName: (json['supplierName'] as String?) ?? '',
          sourceFileName: json['sourceFileName'] as String?,
          offers: offers.isEmpty ? [Offer.empty()] : offers,
        ),
      );
    } catch (e) {
      return RecognizeOutcome(ok: false, error: '$e');
    }
  }

  @override
  Future<ImportOutcome> importFile(String filePath) async {
    try {
      final result = await _run(['--action=import', '--file=$filePath']);
      final json = _parseJson(result.stdout as String);
      if (json == null) {
        return ImportOutcome(
          status: ImportStatus.error,
          error: _errorText(result, 'Нет ответа от sidecar'),
        );
      }
      final status = json['status'];
      if (status == 'foreign') {
        return const ImportOutcome(status: ImportStatus.foreign);
      }
      if (status != 'ok') {
        return ImportOutcome(
          status: ImportStatus.error,
          error: json['message']?.toString() ?? 'Ошибка импорта',
        );
      }
      return ImportOutcome(
        status: ImportStatus.ok,
        state: AppState.fromJson(json),
      );
    } catch (e) {
      return ImportOutcome(status: ImportStatus.error, error: '$e');
    }
  }

  @override
  Future<ExportOutcome> export(AppState state, String outputPath) async {
    try {
      final result = await _run(
        ['--action=export', '--output=$outputPath'],
        stdin: jsonEncode(state.toJson()),
      );
      final json = _parseJson(result.stdout as String);
      if (json == null || json['status'] != 'ok') {
        return ExportOutcome(
          ok: false,
          error: json?['message']?.toString() ??
              _errorText(result, 'Ошибка экспорта'),
        );
      }
      return ExportOutcome(ok: true, path: json['path'] as String?);
    } catch (e) {
      return ExportOutcome(ok: false, error: '$e');
    }
  }

  String _errorText(ProcessResult result, String fallback) {
    final stderr = (result.stderr as String).trim();
    return stderr.isEmpty ? fallback : stderr;
  }
}