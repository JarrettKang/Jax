import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> openEventsPage(WidgetTester tester) async {
  if (find.byKey(const ValueKey('world-tree')).evaluate().isNotEmpty) return;
  await tester.tap(find.text('世界'));
  await tester.pumpAndSettle();
}

Future<void> openEventMenu(WidgetTester tester, String eventId) async {
  final menu = find.byKey(ValueKey('world-more-$eventId'));
  await tester.scrollUntilVisible(menu, 100);
  await tester.tap(menu);
  await tester.pumpAndSettle();
}
