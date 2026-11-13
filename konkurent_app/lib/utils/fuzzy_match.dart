/// Нечёткое сопоставление названий позиций из счёта с позициями заявки.
///
/// Названия в счетах пишутся по-разному («Шпилька резьбовая М16х2000
/// DIN 975 кл.пр.8.8» против «Шпилька резьбовая М16х2000»), поэтому
/// сравниваем нормализованные строки и множества токенов.
library;

const double kMatchThreshold = 0.7;

/// Нормализация: нижний регистр, ё→е, без пунктуации, схлопнутые пробелы.
String normalizeItemName(String raw) {
  var s = raw.toLowerCase().replaceAll('ё', 'е');
  s = s.replaceAll(RegExp(r'[^\wа-яй\s]+'), ' ');
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return s;
}

int _levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  var curr = List<int>.filled(b.length + 1, 0);
  for (var i = 0; i < a.length; i++) {
    curr[0] = i + 1;
    for (var j = 0; j < b.length; j++) {
      final cost = a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1;
      curr[j + 1] = [
        prev[j + 1] + 1, // удаление
        curr[j] + 1, // вставка
        prev[j] + cost, // замена
      ].reduce((x, y) => x < y ? x : y);
    }
    final tmp = prev;
    prev = curr;
    curr = tmp;
  }
  return prev[b.length];
}

double _levenshteinRatio(String a, String b) {
  final dist = _levenshtein(a, b);
  final maxLen = a.length > b.length ? a.length : b.length;
  if (maxLen == 0) return 1;
  return 1 - dist / maxLen;
}

/// Сходство двух названий в диапазоне 0..1: смесь расстояния Левенштейна
/// по нормализованным строкам и токен-мер. Контейнмент (доля меньшего
/// множества токенов внутри большего) — ключевой сигнал: названия счетов
/// часто длиннее заявочных («… DIN 975 цинк»), это то же самое положение.
double itemSimilarity(String a, String b) {
  final na = normalizeItemName(a);
  final nb = normalizeItemName(b);
  if (na.isEmpty || nb.isEmpty) return 0;
  if (na == nb) return 1;

  final tokensA = na.split(' ').toSet();
  final tokensB = nb.split(' ').toSet();
  final intersection = tokensA.intersection(tokensB).length;
  final union = tokensA.union(tokensB).length;
  final jaccard = union == 0 ? 0.0 : intersection / union;
  final minSize = tokensA.length < tokensB.length
      ? tokensA.length
      : tokensB.length;
  final containment = minSize == 0 ? 0.0 : intersection / minSize;

  final lev = _levenshteinRatio(na, nb);
  return 0.3 * lev + 0.5 * containment + 0.2 * jaccard;
}

/// Лучший кандидат для [name] среди [candidates] (id + название).
/// Возвращает (id, сходство), если сходство ≥ [threshold], иначе null.
(String, double)? bestMatch(
  String name,
  Iterable<({String id, String name})> candidates, {
  double threshold = kMatchThreshold,
}) {
  (String, double)? best;
  for (final c in candidates) {
    final sim = itemSimilarity(name, c.name);
    if (best == null || sim > best.$2) {
      best = (c.id, sim);
    }
  }
  if (best == null || best.$2 < threshold) return null;
  return best;
}
