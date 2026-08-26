import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> openEventsPage(WidgetTester tester) async {
  if (find.text('新建事件').evaluate().isNotEmpty) return;
  await tester.tap(find.text('事件'));
  await tester.pumpAndSettle();
}

Future<void> openEventMenu(WidgetTester tester, String eventId) async {
  final menu = find.byKey(ValueKey('more-$eventId'));
  await tester.scrollUntilVisible(menu, 100);
  await tester.tap(menu);
  await tester.pumpAndSettle();
}
