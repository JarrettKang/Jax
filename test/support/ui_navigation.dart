import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> openEventsPage(WidgetTester tester) async {
  if (find.byKey(const ValueKey('add-standalone-event')).evaluate().isNotEmpty) {
    return;
  }
  await tester.tap(find.text('今日'));
  await tester.pumpAndSettle();
}

Future<void> openWorldOverview(WidgetTester tester) async {
  if (find.byKey(const ValueKey('world-node-overview')).evaluate().isNotEmpty) {
    return;
  }
  await tester.tap(find.text('世界'));
  await tester.pumpAndSettle();
}

Future<void> openWorldCategory(WidgetTester tester, String? categoryId) async {
  await openWorldOverview(tester);
  await tester.tap(
    find.byKey(ValueKey('world-category-${categoryId ?? 'unclassified'}')),
  );
  await tester.pumpAndSettle();
}

Future<void> openEventMenu(WidgetTester tester, String eventId) async {
  await openEventsPage(tester);
}
