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
    this.units = const UnitsDict({}),
  });

  /// Ставка НДС для пересчёта цена ↔ сумма (0.22 = 22 %).
  final double vatRate;

  /// Максимум поставщиков в комбинированной закупке (используется
  /// расчётом лучших вариантов, волна 3).
  final int maxSuppliers;

  /// Юрформы для распознавания названия поставщика из текста счёта
  /// (передаётся в sidecar флагом --legal-forms).
  final List<String> legalForms;

  /// Словарь единиц измерения (units.json).
  final UnitsDict units;

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

/// Словарь единиц измерения: канонические значения + алиасы. Алиасы
/// сопоставляют «сырые» распознанные единицы («тн», «теор. т», «м.п»)
/// каноническим («т», «м»). Файл units.json редактируется пользователем.
class UnitsDict {
  const UnitsDict(this.aliases);

  /// alias (нормализованный, нижний регистр без точек/пробелов) → канон.
  final Map<String, String> aliases;

  /// Все канонические единицы (для автодополнения).
  Set<String> get canonical => aliases.values.toSet();

  static String _key(String raw) =>
      raw.toLowerCase().replaceAll('.', '').replaceAll(' ', '').trim();

  /// Каноническое значение для сырой строки; null — не сопоставилось.
  String? normalize(String raw) {
    final k = _key(raw);
    if (k.isEmpty) return null;
    return aliases[k] ?? (canonical.contains(raw.trim()) ? raw.trim() : null);
  }

  /// Есть ли [raw] в словаре (каноническое или алиас).
  bool contains(String raw) => normalize(raw) != null;

  /// Подсказки автодополнения по префиксу (канонические значения).
  List<String> suggestions(String prefix, {int limit = 6}) {
    final p = prefix.trim().toLowerCase();
    if (p.isEmpty) return canonical.take(limit).toList(growable: false);
    final hits = canonical
        .where((c) => c.toLowerCase().startsWith(p))
        .take(limit)
        .toList(growable: false);
    return hits;
  }

  static const defaultJson = <String, dynamic>{
    'canonical': [
      'шт', 'компл', 'уп', 'пара',
      'м', 'м²', 'м³', 'км', 'см', 'мм',
      'кг', 'г', 'т',
      'л', 'мл',
      'рул', 'м.п.', 'ед',
    ],
    'aliases': {
      'штука': 'шт', 'штук': 'шт', 'щт': 'шт',
      'комплект': 'компл', 'комплектов': 'компл',
      'упак': 'уп', 'упаковка': 'уп',
      'метр': 'м', 'мп': 'м', 'мпог': 'м', 'пм': 'м', 'м/п': 'м',
      'квм': 'м²', 'м2': 'м²', 'кв м': 'м²', 'квм2': 'м²',
      'кубм': 'м³', 'м3': 'м³',
      'килограмм': 'кг', 'килогр': 'кг',
      'грамм': 'г', 'гр': 'г',
      'тонна': 'т', 'тн': 'т', 'теорт': 'т', 'т-теор': 'т', 'теор т': 'т',
      'литр': 'л', 'литров': 'л',
      'мл': 'мл', 'милилитр': 'мл',
      'рулон': 'рул',
      'метров погонных': 'м',
      'единица': 'ед', 'единиц': 'ед',
    },
  };

  static UnitsDict fromJson(Map<String, dynamic> json) {
    final aliases = <String, String>{};
    final canonical = (json['canonical'] as List?)
            ?.map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toSet() ??
        <String>{};
    for (final c in canonical) {
      aliases[_key(c)] = c;
    }
    final rawAliases = json['aliases'] as Map<String, dynamic>?;
    rawAliases?.forEach((k, v) {
      final value = v.toString().trim();
      if (value.isNotEmpty && canonical.contains(value)) {
        aliases[_key(k)] = value;
      } else if (value.isNotEmpty) {
        // алиас на неканоническое значение — считаем его каноническим тоже
        aliases[_key(k)] = value;
        aliases[_key(value)] = value;
      }
    });
    return UnitsDict(aliases);
  }

  Map<String, dynamic> toJson() {
    final canonical = this.canonical.toList()..sort();
    final aliasEntries = <MapEntry<String, String>>[
      for (final e in aliases.entries)
        if (e.key != _key(e.value)) e,
    ]..sort((a, b) => a.key.compareTo(b.key));
    return {
      'canonical': canonical,
      'aliases': Map.fromEntries(aliasEntries),
    };
  }
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

  Future<File> _unitsFile() async =>
      File(p.join((await _dir()).path, 'units.json'));

  /// Читает настройки, создавая дефолтные файлы при первом запуске.
  /// Повреждённые файлы молча дают дефолты.
  Future<AppConfig> load() async {
    var config = const AppConfig();

    final file = await _configFile();
    if (file.existsSync()) {
      try {
        config = AppConfig.fromJson(
          jsonDecode(await file.readAsString()) as Map<String, dynamic>,
        );
      } catch (_) {
        // повреждён — используем дефолты
      }
    } else {
      await file.writeAsString(jsonEncode(const AppConfig().toJson()));
    }

    final forms = await _readOrCreate(
      await _legalFormsFile(),
      encoder: () => const JsonEncoder.withIndent('  ')
          .convert(AppConfig.defaultLegalForms),
      parse: (raw) => raw is List && raw.isNotEmpty
          ? raw.whereType<String>().toList()
          : null,
    );

    final units = await _readOrCreate(
      await _unitsFile(),
      encoder: () => const JsonEncoder.withIndent('  ')
          .convert(UnitsDict.defaultJson),
      parse: (raw) => raw is Map<String, dynamic>
          ? UnitsDict.fromJson(raw)
          : null,
    );

    return AppConfig(
      vatRate: config.vatRate,
      maxSuppliers: config.maxSuppliers,
      legalForms: forms ?? AppConfig.defaultLegalForms,
      units: units ?? const UnitsDict({}),
    );
  }

  /// Читает файл [file]: если есть и валиден — [parse]; если нет — создаёт
  /// дефолтным содержимым [encoder]; повреждён — дефолт (null).
  Future<T?> _readOrCreate<T>(
    File file, {
    required T? Function(dynamic raw) parse,
    required String Function() encoder,
  }) async {
    if (file.existsSync()) {
      try {
        return parse(jsonDecode(await file.readAsString()));
      } catch (_) {
        return null;
      }
    }
    try {
      await file.writeAsString(encoder());
    } catch (_) {
      // без записи просто используем дефолты
    }
    return null;
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
