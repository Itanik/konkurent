import 'package:flutter_test/flutter_test.dart';
import 'package:konkurent_app/services/app_config_service.dart';
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

    test('родственные названия выше порога', () {
      final sim = itemSimilarity(
          'Шпилька резьбовая М12х2000 DIN 975',
          'Шпилька резьбовая М12 DIN 975 цинк');
      expect(sim, greaterThan(kMatchThreshold));
    });

    test('разные названия ниже порога', () {
      expect(
          itemSimilarity('Болт М8', 'Кабель силовой ВВГнг 3х2.5'),
          lessThan(kMatchThreshold));
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
