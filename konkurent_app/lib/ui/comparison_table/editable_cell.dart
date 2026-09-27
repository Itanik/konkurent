import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Ячейка таблицы с inline-редактированием: показывает текст, по клику
/// превращается в [TextField]. Подтверждение по Enter / Tab / потере фокуса.
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
    this.onPaste,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final bool readOnly;
  final bool numeric;
  final TextAlign textAlign;
  final EdgeInsets padding;
  final String? testId;
  final String? hint;

  /// Если задан, Ctrl+V в поле отдаётся сюда. Верните `true`, если вставку
  /// обработали сами (ячейка выйдет из режима редактирования), иначе текст
  /// вставится в поле как обычно.
  final bool Function(String text)? onPaste;

  @override
  State<EditableCell> createState() => _EditableCellState();
}

class _EditableCellState extends State<EditableCell> {
  late final TextEditingController _controller;
  late final FocusNode _focus;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    _focus = FocusNode();
    _focus.addListener(() {
      if (!_focus.hasFocus && _editing) _commit();
    });
  }

  @override
  void didUpdateWidget(covariant EditableCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_editing && widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _startEdit() {
    if (widget.readOnly) return;
    setState(() => _editing = true);
    _controller.selection =
        TextSelection(baseOffset: 0, extentOffset: _controller.text.length);
    _focus.requestFocus();
  }

  void _commit() {
    if (!_editing) return;
    setState(() => _editing = false);
    if (_controller.text != widget.value) {
      widget.onChanged(_controller.text);
    }
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (widget.onPaste == null || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    final isPaste = (event.logicalKey == LogicalKeyboardKey.keyV &&
            (keyboard.isControlPressed || keyboard.isMetaPressed)) ||
        (event.logicalKey == LogicalKeyboardKey.insert &&
            keyboard.isShiftPressed);
    if (!isPaste) return KeyEventResult.ignored;
    _handlePaste();
    return KeyEventResult.handled;
  }

  Future<void> _handlePaste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    if (!mounted) return;
    final consumed = widget.onPaste?.call(text) ?? false;
    if (consumed) {
      setState(() => _editing = false);
      return;
    }
    _insertText(text);
  }

  void _insertText(String text) {
    final value = _controller.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    final next = value.text.replaceRange(start, end, text);
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + text.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final display = Padding(
      padding: widget.padding,
      child: Align(
        alignment: _alignment,
        child: Text(
          widget.value.isEmpty ? (widget.hint ?? '') : widget.value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: widget.value.isEmpty
                ? Theme.of(context).hintColor
                : Theme.of(context).textTheme.bodyMedium?.color,
            fontStyle: widget.value.isEmpty ? FontStyle.italic : FontStyle.normal,
          ),
        ),
      ),
    );

    if (!_editing) {
      return GestureDetector(
        key: widget.testId != null ? ValueKey<String>(widget.testId!) : null,
        behavior: HitTestBehavior.opaque,
        onTap: _startEdit,
        child: display,
      );
    }

    return Padding(
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
          keyboardType: widget.numeric
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          style: Theme.of(context).textTheme.bodyMedium,
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          ),
          onSubmitted: (_) => _commit(),
          onTapOutside: (_) => _commit(),
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