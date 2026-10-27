String formatShortDate(DateTime value) {
  final day = value.day.toString().padLeft(2, '0');
  final month = value.month.toString().padLeft(2, '0');
  return '$day.$month.${value.year}';
}

String formatShortDateTime(DateTime value) {
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '${formatShortDate(value)} $hour:$minute';
}

/// Вес для показа: «80», «82,5», «82,75».
String formatWeight(double value) {
  if (value == value.roundToDouble()) {
    return value.toStringAsFixed(0);
  }
  if ((value * 2) == (value * 2).roundToDouble()) {
    return _withComma(value.toStringAsFixed(1));
  }
  return _withComma(value.toStringAsFixed(2));
}

/// Число с запятой и без лишних нулей: «8,2», «1,5», «12».
String formatDecimal(double value, {int fractionDigits = 1}) {
  final fixed = value
      .toStringAsFixed(fractionDigits)
      .replaceFirst(RegExp(r'\.?0+$'), '');
  return _withComma(fixed);
}

/// Число из поля ввода: принимает и запятую, и точку.
double? parseDecimal(String text) {
  final normalized = text.trim().replaceAll(',', '.');
  if (normalized.isEmpty) return null;
  return double.tryParse(normalized);
}

String _withComma(String value) => value.replaceAll('.', ',');

String capitalizeRu(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    return normalized;
  }
  return normalized[0].toUpperCase() + normalized.substring(1);
}
