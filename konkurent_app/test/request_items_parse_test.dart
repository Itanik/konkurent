import 'package:flutter_test/flutter_test.dart';
import 'package:konkurent_app/utils/request_items_parse.dart';

void main() {
  test('делит по последней запятой (пример из задачи)', () {
    final items = parseRequestItems('''
Шпоночный материал 4х4, 5 м.п.
Шпоночный материал 5х5, 5 м.п.
Шпоночный материал 6х6, 5 м.п.
Шпоночный материал 8х8, 5 м.п.
Шпоночный материал 10х10, 5 м.п.
Труба б/ш х/д 27х4 ГОСТ8734-75, 20 м.п.
Пруток шестигранный 13мм Ст.45, 20 м.п.
Пруток шестигранный 17мм Ст.45, 20 м.п.
Пруток шестигранный 19мм Ст.45, 20 м.п.
''');
    expect(items, hasLength(9));
    expect(items.first.name, 'Шпоночный материал 4х4');
    expect(items.first.qty, '5 м.п.');
    expect(items.last.name, 'Пруток шестигранный 19мм Ст.45');
    expect(items.last.qty, '20 м.п.');
  });

  test('табуляция имеет приоритет над запятой', () {
    final items = parseRequestItems('Болт, м8\t10\nГайка\t20');
    expect(items, hasLength(2));
    expect(items[0].name, 'Болт, м8');
    expect(items[0].qty, '10');
    expect(items[1].name, 'Гайка');
    expect(items[1].qty, '20');
  });

  test('строка без разделителя целиком в название', () {
    final items = parseRequestItems('Просто позиция без количества');
    expect(items, hasLength(1));
    expect(items.first.name, 'Просто позиция без количества');
    expect(items.first.qty, '');
  });

  test('запятая без количества — вся строка в название', () {
    final items = parseRequestItems('Название,');
    expect(items.single.name, 'Название,');
    expect(items.single.qty, '');
  });

  test('пустые строки и \\r\\n отбрасываются', () {
    final items = parseRequestItems('A, 1\r\n\r\n  \r\nB, 2\r\n');
    expect(items.map((e) => e.name).toList(), ['A', 'B']);
  });

  test('пустой ввод — пустой список', () {
    expect(parseRequestItems(''), isEmpty);
    expect(parseRequestItems('\n\n'), isEmpty);
  });
}