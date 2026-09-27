import 'package:flutter_test/flutter_test.dart';
import 'package:konkurent_app/utils/format.dart';

void main() {
  test('formatNumber добавляет разделители разрядов', () {
    expect(formatNumber(1234.5), '1 234.50');
    expect(formatNumber(-1234567.0), '-1 234 567.00');
    expect(formatNumber(null), '');
  });

  test('formatEditable убирает лишние нули', () {
    expect(formatEditable(100.0), '100');
    expect(formatEditable(100.5), '100.5');
    expect(formatEditable(null), '');
  });

  test('parseNumber понимает запятую и пробелы', () {
    expect(parseNumber('1 234,5'), 1234.5);
    expect(parseNumber(''), isNull);
    expect(parseNumber('abc'), isNull);
  });
}