import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/app_state.dart';

abstract class StorageService {
  Future<AppState?> load();

  Future<void> save(AppState state);

  Future<void> clear();

  /// Масштаб интерфейса (UI-настройка, хранится отдельно от сессии).
  Future<double?> loadZoom();

  Future<void> saveZoom(double zoom);
}

class FileStorageService implements StorageService {
  FileStorageService({this.fileName = 'session.json', this.settingsName = 'settings.json'});

  final String fileName;
  final String settingsName;

  Future<Directory> _dir() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return dir;
  }

  Future<File> _file() async => File(p.join((await _dir()).path, fileName));

  Future<File> _settingsFile() async =>
      File(p.join((await _dir()).path, settingsName));

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

  @override
  Future<double?> loadZoom() async {
    final file = await _settingsFile();
    if (!file.existsSync()) return null;
    try {
      final raw = await file.readAsString();
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final zoom = json['zoom'];
      return zoom is num ? zoom.toDouble() : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveZoom(double zoom) async {
    final file = await _settingsFile();
    await file.writeAsString(jsonEncode({'zoom': zoom}));
  }
}

class InMemoryStorageService implements StorageService {
  AppState? _state;
  double? _zoom;

  @override
  Future<AppState?> load() async => _state;

  @override
  Future<void> save(AppState state) async => _state = state;

  @override
  Future<void> clear() async => _state = null;

  @override
  Future<double?> loadZoom() async => _zoom;

  @override
  Future<void> saveZoom(double zoom) async => _zoom = zoom;
}