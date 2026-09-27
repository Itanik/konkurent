/// Форматирование чисел для отображения (не для хранения).
String formatNumber(double? value) {
  if (value == null) return '';
  final fixed = value.toStringAsFixed(2);
  final parts = fixed.split('.');
  final intPart = parts[0];
  final sign = intPart.startsWith('-') ? '-' : '';
  final digits = sign.isEmpty ? intPart : intPart.substring(1);
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
    buffer.write(digits[i]);
  }
  return '$sign$buffer.${parts[1]}';
}

/// Компактное представление для редактирования (без лишних нулей).
String formatEditable(double? value) {
  if (value == null) return '';
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toString();
}

double? parseNumber(String raw) {
  final s = raw.trim().replaceAll('\u00a0', '').replaceAll(' ', '').replaceAll(',', '.');
  if (s.isEmpty) return null;
  return double.tryParse(s);
}