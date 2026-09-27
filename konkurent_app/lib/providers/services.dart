import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/python_bridge.dart';
import '../services/storage_service.dart';

/// Движок распознавания/экспорта. В тестах переопределяется FakeFileEngine.
final fileEngineProvider = Provider<FileEngine>((ref) => PythonBridge.create());

/// Хранилище текущей сессии. В тестах переопределяется InMemoryStorageService.
final storageServiceProvider =
    Provider<StorageService>((ref) => FileStorageService());