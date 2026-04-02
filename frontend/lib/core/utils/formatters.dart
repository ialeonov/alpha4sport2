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

String formatWeight(double value) {
  if (value == value.roundToDouble()) {
    return value.toStringAsFixed(0);
  }
  if ((value * 2) == (value * 2).roundToDouble()) {
    return value.toStringAsFixed(1);
  }
  return value.toStringAsFixed(2);
}

String capitalizeRu(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    return normalized;
  }
  return normalized[0].toUpperCase() + normalized.substring(1);
}
