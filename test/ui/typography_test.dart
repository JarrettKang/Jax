import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/app.dart';

void main() {
  test(
    'Windows theme uses one CJK-capable family without flattening weights',
    () {
      final theme = buildJaxTheme(TargetPlatform.windows);

      expect(theme.textTheme.bodyMedium?.fontFamily, 'Microsoft YaHei UI');
      expect(theme.textTheme.titleMedium?.fontFamily, 'Microsoft YaHei UI');
      expect(theme.textTheme.headlineSmall?.fontFamily, 'Microsoft YaHei UI');
      expect(theme.textTheme.bodyMedium?.fontWeight, isNull);
      expect(theme.textTheme.titleMedium?.fontWeight, isNull);
      expect(theme.navigationBarTheme.labelTextStyle, isNull);
    },
  );

  test('Android theme keeps the platform default font family', () {
    final theme = buildJaxTheme(TargetPlatform.android);

    expect(theme.textTheme.bodyMedium?.fontFamily, isNot('Microsoft YaHei UI'));
  });
}
