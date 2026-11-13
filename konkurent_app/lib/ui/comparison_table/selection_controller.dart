import 'package:flutter/widgets.dart';

/// Адрес ячейки в координатах таблицы: [b] — блок (-1 панель заявки,
/// 0..n индекс поставщика), [c] — колонка внутри блока, [r] — физическая
/// строка (группы + зона без привязки).
typedef CellAddress = ({int b, int c, int r});

CellAddress cell(int b, int c, int r) => (b: b, c: c, r: r);

/// Границы навигации: число строк и колонок по блокам.
class SelectionBounds {
  const SelectionBounds({
    required this.totalRows,
    required this.supplierCount,
    this.requestCols = 3,
    this.supplierCols = 5,
  });

  final int totalRows;
  final int supplierCount;
  final int requestCols;
  final int supplierCols;

  int get maxBlock => supplierCount - 1;
  int colsOf(int b) => b == -1 ? requestCols : supplierCols;

  bool valid(CellAddress a) =>
      a.b >= -1 &&
      a.b <= maxBlock &&
      a.c >= 0 &&
      a.c < colsOf(a.b) &&
      a.r >= 0 &&
      a.r < totalRows;
}

/// Выделение ячеек (якорь + фокус, прямоугольный диапазон), перемещение
/// курсора стрелками/Tab/Enter и реестр редакторов для запуска правки с
/// клавиатуры. UI-состояние, не Riverpod.
class SelectionController extends ChangeNotifier {
  CellAddress? anchor;
  CellAddress? focus;
  SelectionBounds bounds = const SelectionBounds(totalRows: 0, supplierCount: 0);

  /// Узел фокуса таблицы: ячейки возвращают ему фокус после правки, чтобы
  /// клавиатурная навигация продолжала работать.
  FocusNode? keyFocus;

  /// Свежие границы на момент навигации: раскладка могла измениться после
  /// последней сборки (правка дорастила сетку).
  SelectionBounds Function()? boundsProvider;

  void _refreshBounds() {
    final b = boundsProvider?.call();
    if (b != null) bounds = b;
  }

  bool get isActive => anchor != null && focus != null;

  CellAddress? get primary => focus;

  void setBounds(SelectionBounds b) {
    bounds = b;
    if (focus != null && !b.valid(focus!)) clear();
  }

  void set(CellAddress a) {
    if (!bounds.valid(a)) return;
    anchor = a;
    focus = a;
    notifyListeners();
  }

  void extend(CellAddress a) {
    if (!bounds.valid(a)) return;
    anchor ??= a;
    focus = a;
    notifyListeners();
  }

  void clear() {
    if (anchor == null && focus == null) return;
    anchor = null;
    focus = null;
    notifyListeners();
  }

  /// Сдвиг курсора (стрелки/Enter=вниз/Tab=вправо через блоки).
  void move(int dRow, int dCol, {bool extendSelection = false}) {
    _refreshBounds();
    final from = focus;
    if (from == null) return;
    var b = from.b;
    var c = from.c;
    var r = from.r;

    r = (r + dRow).clamp(0, bounds.totalRows - 1);
    if (dCol != 0) {
      c += dCol;
      while (c >= bounds.colsOf(b) && b < bounds.maxBlock) {
        b++;
        c = 0;
      }
      while (c < 0 && b > -1) {
        b--;
        c = bounds.colsOf(b) - 1;
      }
      c = c.clamp(0, bounds.colsOf(b) - 1);
    }
    final next = cell(b, c, r);
    if (extendSelection) {
      extend(next);
    } else {
      set(next);
    }
  }

  /// Выделить всё (Ctrl+A).
  void selectAll() {
    _refreshBounds();
    if (bounds.maxBlock < 0 || bounds.totalRows == 0) return;
    anchor = cell(-1, 0, 0);
    focus = cell(bounds.maxBlock, bounds.colsOf(bounds.maxBlock) - 1,
        bounds.totalRows - 1);
    notifyListeners();
  }

  bool isSelected(CellAddress a) {
    final an = anchor;
    final fo = focus;
    if (an == null || fo == null) return false;
    return _between(a.b, an.b, fo.b) &&
        _between(a.c, an.c, fo.c) &&
        _between(a.r, an.r, fo.r);
  }

  /// Редактируемые ячейки регистрируют колбэк запуска правки.
  void register(CellAddress a, VoidCallback startEdit) =>
      _editors[a] = startEdit;

  void unregister(CellAddress a) => _editors.remove(a);

  /// Запустить правку ячейки (клавиатурный ввод по выделению).
  bool tryEdit(CellAddress a) {
    final cb = _editors[a];
    if (cb == null) return false;
    cb();
    return true;
  }

  final Map<CellAddress, VoidCallback> _editors = {};

  static bool _between(int v, int a, int b) =>
      a <= b ? (v >= a && v <= b) : (v >= b && v <= a);
}

/// Доступ к контроллеру выделения из ячеек (перерисовка при изменениях —
/// через InheritedNotifier).
class SelectionScope extends InheritedNotifier<SelectionController> {
  const SelectionScope({
    super.key,
    required SelectionController super.notifier,
    required super.child,
  });

  static SelectionController? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SelectionScope>()?.notifier;
}
