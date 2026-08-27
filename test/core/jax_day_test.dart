import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/jax_day.dart';

void main() {
  test('Jax day changes exactly at local 23:00', () {
    expect(JaxDay.containing(DateTime(2026, 8, 27, 22, 59)).key, '2026-08-27');
    expect(JaxDay.containing(DateTime(2026, 8, 27, 23)).key, '2026-08-28');
    expect(JaxDay.containing(DateTime(2026, 8, 27, 23, 1)).key, '2026-08-28');
    final day = JaxDay.forDisplayDate(DateTime(2026, 8, 27));
    expect(day.start, DateTime(2026, 8, 26, 23));
    expect(day.end, DateTime(2026, 8, 27, 23));
  });
}
