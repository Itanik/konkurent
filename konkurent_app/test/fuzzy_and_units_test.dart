import 'package:flutter_test/flutter_test.dart';
import 'package:konkurent_app/services/app_config_service.dart';
import 'package:konkurent_app/services/clipboard_grid.dart';
import 'package:konkurent_app/utils/fuzzy_match.dart';

void main() {
  group('fuzzy_match', () {
    test('нормализация убирает пунктуацию и регистр', () {
      expect(normalizeItemName('Шпилька, резьбовая М-12!'),
          'шпилька резьбовая м 12');
    });

    test('одинаковые строки = 1', () {
      expect(itemSimilarity('Болт М8', 'болт м8'), 1);
    });

    test('родственные названия выше порога (пары из реальных счетов)', () {
      // Пробел в размере + лишние слова в счёте.
      expect(
          itemSimilarity('Шпилька резьбовая М 16х2000 DIN 975 кл.пр.8.8 цинк',
              'Шпилька резьбовая М16 кл. пр. 8.8'),
          greaterThan(kMatchThreshold));
      expect(
          itemSimilarity('Гайка М 16 DIN 934 кл.пр.8 цинк (уп.1 кг)',
              'Гайка DIN934 М16 кл.пр. 8 цинк'),
          greaterThan(kMatchThreshold));
      expect(
          itemSimilarity('Шпилька резьбовая М 12х2000 DIN 975 цинк',
              'Шпилька резьбовая М12'),
          greaterThan(kMatchThreshold));
    });

    test('разные названия ниже порога', () {
      expect(
          itemSimilarity('Болт М8', 'Кабель силовой ВВГнг 3х2.5'),
          lessThan(kMatchThreshold));
    });

    test('диаметр-гард: разный размер — сильный штраф', () {
      // М10-гайка не должна матчиться к М16-позиции.
      final wrong = itemSimilarity(
          'Гайка М 10 DIN 934 кл.пр.8 цинк (уп.1 кг)',
          'Гайка DIN934 М16 кл.пр. 8 цинк');
      final right = itemSimilarity(
          'Гайка М 10 DIN 934 кл.пр.8 цинк (уп.1 кг)', 'Гайка DIN 934 оц');
      expect(wrong, lessThan(right));
      expect(wrong, lessThan(kMatchThreshold));
      expect(right, greaterThan(kMatchThreshold));
    });

    test('без явного «М» у одной стороны штраф не применяется', () {
      // «Шайба 16 (d17)» против «ув. М16 (д17)» — верная пара.
      expect(
          itemSimilarity('Шайба плоская увеличенная 16 (d17) DIN 9021 цинк',
              'Шайба плоская ув. М16 (д17) цинк'),
          greaterThan(0.4));
      expect(itemDiameter('Шайба плоская увеличенная 16 (d17)'), isNull);
      expect(itemDiameter('Шайба плоская ув. М16 (д17)'), '16');
    });

    test('itemDiameter достаёт м-диаметр', () {
      expect(itemDiameter('Шпилька М 16х2000'), '16');
      expect(itemDiameter('Болт М10х1,5'), '10');
      expect(itemDiameter('Анкер клиновой 16х110'), isNull);
    });

    test('bestMatch находит лучшего кандидата', () {
      final match = bestMatch('Гайка М12 оцинк.', [
        (id: 'a', name: 'Гайка М12'),
        (id: 'b', name: 'Шайба М12'),
      ]);
      expect(match, isNotNull);
      expect(match!.$1, 'a');
    });

    test('bestMatch возвращает null ниже порога', () {
      expect(
          bestMatch('Болт', [(id: 'a', name: 'Совершенно иное')]), isNull);
    });
  });

  group('splitQtyUnit', () {
    test('число + короткий хвост', () {
      expect(ClipboardGrid.splitQtyUnit('9 шт'), ('9', 'шт'));
      expect(ClipboardGrid.splitQtyUnit('5 м.п.'), ('5', 'м.п.'));
      expect(ClipboardGrid.splitQtyUnit('2,5 кг'), ('2.5', 'кг'));
      expect(ClipboardGrid.splitQtyUnit('10'), ('10', ''));
    });

    test('без числа — null', () {
      expect(ClipboardGrid.splitQtyUnit('шт'), isNull);
      expect(ClipboardGrid.splitQtyUnit(''), isNull);
    });
  });

  group('UnitsDict', () {
    test('алиасы нормализуют распознанные единицы', () {
      final dict = UnitsDict.fromJson(UnitsDict.defaultJson);
      expect(dict.normalize('тн'), 'т');
      expect(dict.normalize('теор. т'), 'т');
      expect(dict.normalize('м.п.'), anyOf('м.п.', 'м'));
      expect(dict.normalize('м2'), 'м²');
      expect(dict.normalize('ШТ'), 'шт');
      // каноническое значение проходит насквозь
      expect(dict.normalize('шт'), 'шт');
    });

    test('неизвестная единица не сопоставляется', () {
      final dict = UnitsDict.fromJson(UnitsDict.defaultJson);
      expect(dict.normalize('ведро'), isNull);
    });

    test('пользовательский JSON: алиас на неканоническое значение', () {
      final dict = UnitsDict.fromJson({
        'canonical': ['боб'],
        'aliases': {'бобина': 'рулон'},
      });
      expect(dict.normalize('бобина'), 'рулон');
      expect(dict.normalize('боб'), 'боб');
    });

    test('round-trip toJson/fromJson сохраняет словарь', () {
      final dict = UnitsDict.fromJson(UnitsDict.defaultJson);
      final restored = UnitsDict.fromJson(dict.toJson());
      expect(restored.normalize('тн'), 'т');
      expect(restored.normalize('м2'), 'м²');
    });

    test('suggestions по префиксу', () {
      final dict = UnitsDict.fromJson(UnitsDict.defaultJson);
      expect(dict.suggestions('м'), isNotEmpty);
      expect(dict.suggestions('', limit: 3), hasLength(3));
    });
  });
}
