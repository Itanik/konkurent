import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'selection_controller.dart';

/// Ячейка таблицы с inline-редактированием: показывает текст, по клику
/// превращается в [TextField]. Подтверждение по Enter / Tab / потере фокуса;
/// Enter и Tab после подтверждения двигают выделение (Excel-навигация).
/// С [address] ячейка участвует в выделении и правке с клавиатуры.
class EditableCell extends StatefulWidget {
  const EditableCell({
    super.key,
    required this.value,
    required this.onChanged,
    this.readOnly = false,
    this.numeric = false,
    this.textAlign = TextAlign.left,
    this.padding = const EdgeInsets.symmetric(horizontal: 8),
    this.testId,
    this.hint,
    this.highlight = false,
    this.suggestions,
    this.address,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final bool readOnly;
  final bool numeric;
  final TextAlign textAlign;
  final EdgeInsets padding;
  final String? testId;
  final String? hint;

  /// Цветная подсветка значения (единицы вне словаря).
  final bool highlight;

  /// Кандидаты автодополнения (словарь единиц): во время правки под полем
  /// появляется список по префиксу.
  final Set<String>? suggestions;

  /// Адрес ячейки для выделения/клавиатуры (null — вне навигации).
  final CellAddress? address;

  @override
  State<EditableCell> createState() => _EditableCellState();
}

class _EditableCellState extends State<EditableCell> {
  late final TextEditingController _controller;
  late final FocusNode _focus;
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlay;
  bool _editing = false;
  SelectionController? _selection;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    _focus = FocusNode();
    _focus.addListener(() {
      if (!_focus.hasFocus && _editing) _commit();
    });
    _controller.addListener(_onControllerChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final sel = SelectionScope.of(context);
    if (sel != _selection) {
      _unregister();
      _selection = sel;
    }
    _register();
  }

  @override
  void didUpdateWidget(covariant EditableCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.address != widget.address) {
      _unregister();
      _register();
    }
    if (!_editing && widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  void _register() {
    final a = widget.address;
    if (a != null && _selection != null) {
      _selection!.register(a, _startEdit);
    }
  }

  void _unregister() {
    final a = widget.address;
    if (a != null && _selection != null) {
      _selection!.unregister(a);
    }
  }

  @override
  void dispose() {
    _removeOverlay();
    _unregister();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  // --- автодополнение --------------------------------------------------------

  void _onControllerChanged() {
    if (_editing) _updateSuggestions();
  }

  List<String> get _currentSuggestions {
    final src = widget.suggestions;
    if (src == null) return const [];
    final prefix = _controller.text.trim().toLowerCase();
    final list = prefix.isEmpty
        ? src.take(6).toList()
        : src.where((s) => s.toLowerCase().startsWith(prefix)).take(6).toList();
    return list.where((s) => s != _controller.text.trim()).toList();
  }

  void _updateSuggestions() {
    if (!mounted) return;
    final items = _currentSuggestions;
    if (items.isEmpty) {
      _removeOverlay();
      return;
    }
    final entry = OverlayEntry(
      builder: (context) => Positioned(
        width: 140,
        child: CompositedTransformFollower(
          link: _layerLink,
          targetAnchor: Alignment.bottomLeft,
          followerAnchor: Alignment.topLeft,
          showWhenUnlinked: false,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final s in items)
                  InkWell(
                    key: widget.testId != null
                        ? ValueKey<String>('${widget.testId}.suggestion.$s')
                        : null,
                    onTap: () {
                      _controller.text = s;
                      _controller.selection = TextSelection.collapsed(
                          offset: s.length);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(s,
                            style: Theme.of(context).textTheme.bodySmall),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    _removeOverlay();
    _overlay = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
  }

  void _removeOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  // --- правка ------------------------------------------------------------------

  void _startEdit() {
    if (widget.readOnly) return;
    final a = widget.address;
    if (a != null) _selection?.set(a);
    setState(() => _editing = true);
    _controller.selection =
        TextSelection(baseOffset: 0, extentOffset: _controller.text.length);
    _focus.requestFocus();
    if (widget.suggestions != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _editing) _updateSuggestions();
      });
    }
  }

  void _commit({bool navigateDown = false}) {
    if (!_editing) return;
    _removeOverlay();
    setState(() => _editing = false);
    if (_controller.text != widget.value) {
      widget.onChanged(_controller.text);
    }
    // Фокус обратно в таблицу: иначе стрелки/копипаста не сработают после
    // удаления поля.
    _selection?.keyFocus?.requestFocus();
    if (navigateDown) {
      final a = widget.address;
      if (a != null) _selection?.move(1, 0);
    }
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    // Tab подтверждает и уводит выделение вправо (Excel-навигация).
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      _commit();
      final a = widget.address;
      if (a != null) {
        _selection?.move(0,
            HardwareKeyboard.instance.isShiftPressed ? -1 : 1);
      }
      return KeyEventResult.handled;
    }
    // Esc — выйти из правки, оставив выделение на ячейке: дальше клавиатуру
    // получает таблица (навигация/копирование/вставка).
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _commit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final address = widget.address;
    final selected =
        address != null && _selection?.isSelected(address) == true;
    final display = Padding(
      padding: widget.padding,
      child: Align(
        alignment: _alignment,
        child: Text(
          widget.value.isEmpty ? (widget.hint ?? '') : widget.value,
          // Перенос по словам без ограничения строк: высота строки
          // подгоняется провайдером tableLayoutProvider.
          softWrap: true,
          style: TextStyle(
            color: widget.value.isEmpty
                ? theme.hintColor
                : (widget.highlight
                    ? const Color(0xFFB26A00) // единица вне словаря
                    : theme.textTheme.bodyMedium?.color),
            fontStyle:
                widget.value.isEmpty ? FontStyle.italic : FontStyle.normal,
          ),
        ),
      ),
    );

    if (!_editing) {
      return GestureDetector(
        key: widget.testId != null ? ValueKey<String>(widget.testId!) : null,
        behavior: HitTestBehavior.opaque,
        onTap: _startEdit,
        child: selected
            ? Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  border: Border.all(
                    color: theme.colorScheme.primary,
                    width: address == _selection?.primary ? 2 : 1,
                  ),
                ),
                child: display,
              )
            : display,
      );
    }

    return CompositedTransformTarget(
      link: _layerLink,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Focus(
          onKeyEvent: _onKeyEvent,
          child: TextField(
            key: widget.testId != null
                ? ValueKey<String>('${widget.testId}.field')
                : null,
            controller: _controller,
            focusNode: _focus,
            autofocus: true,
            textAlign: widget.textAlign,
            textAlignVertical: TextAlignVertical.center,
            keyboardType: widget.numeric
                ? const TextInputType.numberWithOptions(decimal: true)
                : TextInputType.text,
            // Поле занимает всю ячейку и переносит текст: многострочные
            // названия редактируются целиком, а не в узкой однострочной строке.
            maxLines: null,
            expands: true,
            style: theme.textTheme.bodyMedium,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            ),
            onSubmitted: (_) => _commit(navigateDown: true),
            onTapOutside: (_) => _commit(),
          ),
        ),
      ),
    );
  }

  Alignment get _alignment {
    switch (widget.textAlign) {
      case TextAlign.center:
        return Alignment.center;
      case TextAlign.right:
        return Alignment.centerRight;
      default:
        return Alignment.centerLeft;
    }
  }
}
