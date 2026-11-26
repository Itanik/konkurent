import 'package:flutter_test/flutter_test.dart';
import 'package:konkurent_app/services/supplier_db.dart';

void main() {
  late SupplierDb? db;

  setUp(() {
    db = SupplierDb.openInMemory();
    // Нативная sqlite3 недоступна в окружении — тесты памяти пропускаются.
    if (db == null) {
      markTestSkipped('sqlite3 недоступна в этом окружении');
    }
  });

  test('upsert/get по ИНН; пустые поля не затирают', () {
    db!.upsertSupplier(inn: '7707083893', name: 'ООО «Ромашка»');
    db!.upsertSupplier(inn: '7707083893', name: '', kpp: '770701001');

    final rec = db!.getByInn('7707083893');
    expect(rec, isNotNull);
    expect(rec!.name, 'ООО «Ромашка»', reason: 'пустое имя не затирает');
    expect(rec.kpp, '770701001');
    expect(db!.getByInn('123'), isNull);
  });

  test('история мета-поля: последние 5, свежие в начале', () {
    db!.upsertSupplier(inn: '7707083893');
    const inn = '7707083893';
    for (final v in ['Д-1', 'Д-2', 'Д-3', 'Д-4', 'Д-5', 'Д-6']) {
      db!.recordMeta(inn, 'contract', v);
    }
    expect(db!.metaHistory(inn, 'contract'),
        ['Д-6', 'Д-5', 'Д-4', 'Д-3', 'Д-2']);
    expect(db!.metaHistory(inn, 'contract').length, 5);
    expect(db!.lastMeta(inn, 'contract'), 'Д-6');
    // По полям независимая история.
    db!.recordMeta(inn, 'delivery', '2 дня');
    expect(db!.lastMeta(inn, 'delivery'), '2 дня');
    expect(db!.metaHistory(inn, 'contract').first, 'Д-6');
  });

  test('пустые значения не пишутся', () {
    db!.recordMeta('7707083893', 'contract', '   ');
    expect(db!.metaHistory('7707083893', 'contract'), isEmpty);
    expect(db!.lastMeta('7707083893', 'contract'), isNull);
  });

  test('searchNames по подстроке', () {
    db!.upsertSupplier(inn: '1', name: 'ООО «Ромашка»');
    db!.upsertSupplier(inn: '2', name: 'ООО «Стройметиз»');
    db!.upsertSupplier(inn: '3', name: 'АО «Крепёж»');
    expect(db!.searchNames('строй'), ['ООО «Стройметиз»']);
    expect(db!.searchNames(''), hasLength(3));
    expect(db!.searchNames('НЕТ'), isEmpty);
  });
}
