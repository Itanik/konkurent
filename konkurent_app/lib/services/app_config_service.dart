import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Глобальные настройки приложения, живущие между сессиями
/// (app-support каталог).
class AppConfig {
  const AppConfig({
    this.vatRate = 0.22,
    this.maxSuppliers = 3,
    this.legalForms = defaultLegalForms,
  });

  /// Ставка НДС для пересчёта цена ↔ сумма (0.22 = 22 %).
  final double vatRate;

  /// Максимум поставщиков в комбинированной закупке (используется
  /// расчётом лучших вариантов, волна 3).
  final int maxSuppliers;

  /// Юрформы для распознавания названия поставщика из текста счёта
  /// (передаётся в sidecar флагом --legal-forms).
  final List<String> legalForms;

  static const defaultLegalForms = [
    'Общество с ограниченной ответственностью',
    'Публичное акционерное общество',
    'Непубличное акционерное общество',
    'Закрытое акционерное общество',
    'Открытое акционерное общество',
    'Индивидуальный предприниматель',
    'Акционерное общество',
    'Автономная некоммерческая организация',
    'Федеральное государственное унитарное предприятие',
    'Федеральное государственное бюджетное учреждение',
    'ООО',
    'ПАО',
    'НАО',
    'ЗАО',
    'ОАО',
    'АО',
    'АНО',
    'ФГУП',
    'ФГБУ',
    'ГУП',
    'МУП',
    'ИП',
    'ТСЖ',
    'КФХ',
  ];

  Map<String, dynamic> toJson() =>
      {'vatRate': vatRate, 'maxSuppliers': maxSuppliers};

  factory AppConfig.fromJson(Map<String, dynamic> json) => AppConfig(
        vatRate: (json['vatRate'] as num?)?.toDouble() ?? 0.22,
        maxSuppliers: (json['maxSuppliers'] as num?)?.toInt() ?? 3,
      );
}

class AppConfigService {
  AppConfigService({Directory? directory}) : _overrideDir = directory;

  final Directory? _overrideDir;

  Future<Directory> _dir() async {
    final dir = _overrideDir ?? await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return dir;
  }

  Future<File> _configFile() async =>
      File(p.join((await _dir()).path, 'app-config.json'));

  Future<File> _legalFormsFile() async =>
      File(p.join((await _dir()).path, 'legal-forms.json'));

  /// Читает настройки, создавая дефолтные файлы при первом запуске.
  /// Повреждённый файл молча заменяется дефолтами.
  Future<AppConfig> load() async {
    final defaults = const AppConfig();
    final file = await _configFile();
    var config = defaults;
    if (file.existsSync()) {
      try {
        config = AppConfig.fromJson(
          jsonDecode(await file.readAsString()) as Map<String, dynamic>,
        );
      } catch (_) {
        // перезапишем дефолтом ниже
      }
    } else {
      await file.writeAsString(jsonEncode(defaults.toJson()));
    }

    final formsFile = await _legalFormsFile();
    if (formsFile.existsSync()) {
      try {
        final raw = jsonDecode(await formsFile.readAsString());
        if (raw is List && raw.isNotEmpty) {
          final forms = raw.whereType<String>().toList();
          if (forms.isNotEmpty) {
            return AppConfig(
              vatRate: config.vatRate,
              maxSuppliers: config.maxSuppliers,
              legalForms: forms,
            );
          }
        }
      } catch (_) {
        // повреждённый список — используем дефолт
      }
    } else {
      await formsFile.writeAsString(
          const JsonEncoder.withIndent('  ').convert(AppConfig.defaultLegalForms));
    }
    return config;
  }

  /// Путь к legal-forms.json для передачи в sidecar (null, если файла нет).
  Future<String?> legalFormsPath() async {
    final file = await _legalFormsFile();
    return file.existsSync() ? file.path : null;
  }
}

final appConfigServiceProvider =
    Provider<AppConfigService>((ref) => AppConfigService());

/// Загружается асинхронно при первом обращении; до загрузки — дефолты.
final appConfigProvider =
    AsyncNotifierProvider<AppConfigNotifier, AppConfig>(AppConfigNotifier.new);

class AppConfigNotifier extends AsyncNotifier<AppConfig> {
  @override
  Future<AppConfig> build() => ref.read(appConfigServiceProvider).load();
}
