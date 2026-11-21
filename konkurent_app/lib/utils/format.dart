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

/// Компактное представление для редактирования: 2 знака после запятой
/// без лишних нулей (41.666… → «41.67», 30.50 → «30.5», 120 → «120»).
String formatEditable(double? value) {
  if (value == null) return '';
  final r = (value * 100).roundToDouble() / 100;
  if (r == r.roundToDouble()) return r.toStringAsFixed(0);
  var s = r.toStringAsFixed(2);
  while (s.endsWith('0')) {
    s = s.substring(0, s.length - 1);
  }
  return s;
}

double? parseNumber(String raw) {
  final s = raw.trim().replaceAll('\u00a0', '').replaceAll(' ', '').replaceAll(',', '.');
  if (s.isEmpty) return null;
  return double.tryParse(s);
}