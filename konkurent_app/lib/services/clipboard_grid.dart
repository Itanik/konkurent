/// TSV-обмен с Excel: разбор буфера в сетку значений и обратная сборка.
class ClipboardGrid {
  /// Разбирает текст буфера (из Excel или списка) в таблицу строк.
  /// Пустые строки и хвостовые пустые ячейки строки отбрасываются.
  static List<List<String>> parse(String text) {
    final rows = <List<String>>[];
    for (final line in text.split(RegExp(r'\r?\n'))) {
      if (line.isEmpty) continue;
      final cells = line.split('\t').map((c) => c.trim()).toList();
      while (cells.isNotEmpty && cells.last.isEmpty) {
        cells.removeLast();
      }
      if (cells.isEmpty) continue;
      rows.add(cells);
    }
    return rows;
  }

  /// Собирает TSV из сетки значений (ячейки с null/пусто → пустая ячейка).
  static String build(Iterable<Iterable<String?>> grid) {
    final buf = StringBuffer();
    var first = true;
    for (final row in grid) {
      if (!first) buf.write('\n');
      first = false;
      buf.write(row.map((c) => c ?? '').join('\t'));
    }
    return buf.toString();
  }
}
