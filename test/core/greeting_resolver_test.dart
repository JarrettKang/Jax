import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/services/greeting_resolver.dart';

void main() {
  const resolver = GreetingResolver();

  group('GreetingResolver', () {
    final cases = <(int, int, String)>[
      (4, 59, '晚上好'),
      (5, 0, '早上好'),
      (8, 59, '早上好'),
      (9, 0, '上午好'),
      (10, 59, '上午好'),
      (11, 0, '中午好'),
      (13, 59, '中午好'),
      (14, 0, '下午好'),
      (16, 59, '下午好'),
      (17, 0, '晚上好'),
      (23, 59, '晚上好'),
      (0, 0, '晚上好'),
    ];

    for (final (hour, minute, expected) in cases) {
      test(
        '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')} -> $expected',
        () {
          expect(
            resolver.resolve(() => DateTime(2026, 8, 25, hour, minute)),
            expected,
          );
        },
      );
    }

    test('converts an injected instant to device local time', () {
      final instant = DateTime.utc(2026, 8, 25, 1);
      expect(
        resolver.resolve(() => instant),
        resolver.resolveLocal(instant.toLocal()),
      );
    });
  });
}
