import '../models/app_state.dart';

/// Разбирает вставленный из буфера список позиций заявки.
///
/// Правила (вариант «d»):
/// - строки разделяются переводом строки, пустые отбрасываются;
/// - если в строке есть табуляция (копия из Excel `Название<TAB>Кол-во`) —
///   делим по первому табу;
/// - иначе, если есть запятая и после последней запятой непустой текст —
///   до последней запятой это название, после — количество;
/// - иначе вся строка целиком идёт в название.
List<RequestItem> parseRequestItems(String text) {
  final items = <RequestItem>[];
  for (final raw in text.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    items.add(_parseLine(line));
  }
  return items;
}

RequestItem _parseLine(String line) {
  final tab = line.indexOf('\t');
  if (tab >= 0) {
    return RequestItem(
      id: newId(),
      name: line.substring(0, tab).trim(),
      qty: line.substring(tab + 1).trim(),
    );
  }

  final comma = line.lastIndexOf(',');
  if (comma >= 0) {
    final name = line.substring(0, comma).trim();
    final qty = line.substring(comma + 1).trim();
    if (name.isNotEmpty && qty.isNotEmpty) {
      return RequestItem(id: newId(), name: name, qty: qty);
    }
  }

  return RequestItem(id: newId(), name: line);
}