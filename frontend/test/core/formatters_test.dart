import 'package:alpha4sport_app/core/utils/formatters.dart';
import 'package:alpha4sport_app/features/workouts/domain/workout_metrics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('weights use a comma and no trailing zeros', () {
    expect(formatWeight(80), '80');
    expect(formatWeight(82.5), '82,5');
    expect(formatWeight(82.75), '82,75');
  });

  test('decimals trim zeros and use a comma', () {
    expect(formatDecimal(8.17), '8,2');
    expect(formatDecimal(12), '12');
    expect(formatDecimal(1.5), '1,5');
  });

  test('input accepts both comma and dot', () {
    expect(parseDecimal('82,5'), 82.5);
    expect(parseDecimal(' 82.5 '), 82.5);
    expect(parseDecimal(''), isNull);
  });

  test('tonnage reads the same everywhere', () {
    expect(formatTonnage(825), '825 кг');
    expect(formatTonnage(8170), '8,2 т');
    expect(formatTonnage(12000), '12 т');
    expect(formatTonnage(0), '0 кг');
  });
}
