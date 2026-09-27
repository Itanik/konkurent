import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/app_state.dart';

abstract class StorageService {
  Future<AppState?> load();

  Future<void> save(AppState state);

  Future<void> clear();
}

class FileStorageService implements StorageService {
  FileStorageService({this.fileName = 'session.json'});

  final String fileName;

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return File(p.join(dir.path, fileName));
  }

  @override
  Future<AppState?> load() async {
    final file = await _file();
    if (!file.existsSync()) return null;
    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return null;
      return AppState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(AppState state) async {
    final file = await _file();
    await file.writeAsString(jsonEncode(state.toJson()));
  }

  @override
  Future<void> clear() async {
    final file = await _file();
    if (file.existsSync()) await file.delete();
  }
}

class InMemoryStorageService implements StorageService {
  AppState? _state;

  @override
  Future<AppState?> load() async => _state;

  @override
  Future<void> save(AppState state) async => _state = state;

  @override
  Future<void> clear() async => _state = null;
}