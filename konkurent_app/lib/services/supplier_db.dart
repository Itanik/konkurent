import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

/// Запись о поставщике в локальной БД.
class SupplierRecord {
  const SupplierRecord({
    required this.inn,
    this.name = '',
    this.kpp = '',
    this.ogrn = '',
  });

  final String inn;
  final String name;
  final String kpp;
  final String ogrn;
}

/// Локальная SQLite-БД поставщиков: опознание по ИНН, история мета-полей
/// (последние 5 значений; комментарий не запоминается) и названия для
/// автодополнения. Файл в app-support — правится сторонними утилитами
/// (DB Browser и т.п.). Открывается в main() до runApp; открытие не должно
/// ронять приложение: при сбое возвращается null (фичи памяти молча гаснут).
class SupplierDb {
  SupplierDb._(this._db);

  final Database _db;

  static const _maxMetaHistory = 5;

  static const _schemaSql = '''
    CREATE TABLE IF NOT EXISTS suppliers (
      inn TEXT PRIMARY KEY,
      name TEXT NOT NULL DEFAULT '',
      kpp TEXT NOT NULL DEFAULT '',
      ogrn TEXT NOT NULL DEFAULT '',
      updated_at TEXT NOT NULL DEFAULT ''
    );
    CREATE TABLE IF NOT EXISTS meta_history (
      inn TEXT NOT NULL,
      field TEXT NOT NULL,
      value TEXT NOT NULL,
      used_at TEXT NOT NULL DEFAULT ''
    );
    CREATE INDEX IF NOT EXISTS idx_meta_history ON meta_history(inn, field);
  ''';

  /// Открывает БД по файлу; null при любой ошибке (нет нативной библиотеки,
  /// недоступен файл, битая схема).
  static SupplierDb? tryOpen(String path) {
    try {
      final db = sqlite3.open(path);
      db.execute(_schemaSql);
      return SupplierDb._(db);
    } catch (_) {
      return null;
    }
  }

  /// In-memory для тестов; null, если нативная библиотека недоступна.
  static SupplierDb? openInMemory() {
    try {
      final db = sqlite3.openInMemory();
      db.execute(_schemaSql);
      return SupplierDb._(db);
    } catch (_) {
      return null;
    }
  }

  static Future<SupplierDb?> openDefault() async {
    try {
      final dir = await getApplicationSupportDirectory();
      await dir.create(recursive: true);
      return tryOpen(p.join(dir.path, 'suppliers.db'));
    } catch (_) {
      return null;
    }
  }

  /// Вставить/обновить поставщика. Пустые поля не затирают существующие.
  void upsertSupplier({
    required String inn,
    String name = '',
    String kpp = '',
    String ogrn = '',
  }) {
    if (inn.trim().isEmpty) return;
    final stmt = _db.prepare(
      'INSERT INTO suppliers(inn, name, kpp, ogrn, updated_at) '
      "VALUES(?, ?, ?, ?, datetime('now')) "
      'ON CONFLICT(inn) DO UPDATE SET '
      "name = CASE WHEN excluded.name != '' THEN excluded.name ELSE name END, "
      "kpp = CASE WHEN excluded.kpp != '' THEN excluded.kpp ELSE kpp END, "
      "ogrn = CASE WHEN excluded.ogrn != '' THEN excluded.ogrn ELSE ogrn END, "
      'updated_at = excluded.updated_at');
    stmt.execute([inn.trim(), name.trim(), kpp.trim(), ogrn.trim()]);
    stmt.dispose();
  }

  SupplierRecord? getByInn(String inn) {
    if (inn.trim().isEmpty) return null;
    final rows = _db.select(
      'SELECT inn, name, kpp, ogrn FROM suppliers WHERE inn = ?',
      [inn.trim()],
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    return SupplierRecord(
      inn: r['inn'] as String,
      name: r['name'] as String,
      kpp: r['kpp'] as String,
      ogrn: r['ogrn'] as String,
    );
  }

  /// Названия для автодополнения при ручном вводе поставщика. Фильтр по
  /// подстроке в Dart: SQLite LIKE регистрозависим только для ASCII и не
  /// берёт кириллицу («строй» не найдёт «Стройметиз»).
  List<String> searchNames(String prefix, {int limit = 30}) {
    final rows = _db.select(
      "SELECT DISTINCT name FROM suppliers WHERE name != '' ORDER BY name",
    );
    final needle = prefix.trim().toLowerCase();
    return rows
        .map((r) => r['name'] as String)
        .where((name) => needle.isEmpty || name.toLowerCase().contains(needle))
        .take(limit)
        .toList();
  }

  /// Запомнить значение мета-поля (свежее в начало истории, максимум 5).
  void recordMeta(String inn, String field, String value) {
    if (inn.trim().isEmpty || value.trim().isEmpty) return;
    final stmt = _db.prepare(
      'INSERT INTO meta_history(inn, field, value, used_at) '
      "VALUES(?, ?, ?, datetime('now'))");
    stmt.execute([inn.trim(), field, value.trim()]);
    stmt.dispose();
    // Оставить только последние N значений ЭТОГО поля (свежие — с
    // большим rowid). DELETE обязан быть ограничен полем, иначе сотрёт
    // историю всех остальных полей поставщика.
    final prune = _db.prepare(
      'DELETE FROM meta_history WHERE inn = ? AND field = ? '
      'AND rowid NOT IN '
      '(SELECT rowid FROM meta_history WHERE inn = ? AND field = ? '
      'ORDER BY rowid DESC LIMIT ?)');
    final innClean = inn.trim();
    final fieldClean = field.trim();
    prune.execute([innClean, fieldClean, innClean, fieldClean, _maxMetaHistory]);
    prune.dispose();
  }

  /// История мета-поля: свежие в начале, максимум 5.
  List<String> metaHistory(String inn, String field) {
    if (inn.trim().isEmpty) return const [];
    final rows = _db.select(
      'SELECT value FROM meta_history WHERE inn = ? AND field = ? '
      'ORDER BY rowid DESC LIMIT ?',
      [inn.trim(), field, _maxMetaHistory],
    );
    return rows.map((r) => r['value'] as String).toList();
  }

  /// Последнее использованное значение поля (для автозаполнения пустых мета).
  String? lastMeta(String inn, String field) {
    final h = metaHistory(inn, field);
    return h.isEmpty ? null : h.first;
  }

  void close() => _db.dispose();
}

/// Открывается в main() до runApp (overrideWithValue); в тестах —
/// in-memory или null.
final supplierDbProvider = Provider<SupplierDb?>((ref) => null);
