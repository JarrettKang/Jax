import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> openEventsPage(WidgetTester tester) async {
  if (find.byKey(const ValueKey('world-tree')).evaluate().isNotEmpty) return;
  await openWorldOverview(tester);
  var entries = find.byWidgetPredicate(
    (widget) =>
        widget.key is ValueKey<String> &&
        (widget.key! as ValueKey<String>).value.startsWith(
          'world-category-open-',
        ),
  );
  if (entries.evaluate().isEmpty) {
    await tester.tap(find.byKey(const ValueKey('world-new-category')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '测试分类');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    entries = find.byWidgetPredicate(
      (widget) =>
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith(
            'world-category-open-',
          ),
    );
  }
  if (entries.evaluate().length != 1) {
    throw StateError('openEventsPage requires exactly one World Category');
  }
  await tester.tap(entries);
  await tester.pumpAndSettle();
}

Future<void> openWorldOverview(WidgetTester tester) async {
  if (find.byKey(const ValueKey('world-overview')).evaluate().isNotEmpty) {
    return;
  }
  if (find.byKey(const ValueKey('world-tree')).evaluate().isNotEmpty) {
    await tester.tap(find.byKey(const ValueKey('world-back-overview')));
  } else {
    await tester.tap(find.text('世界'));
  }
  await tester.pumpAndSettle();
}

Future<void> openWorldCategory(WidgetTester tester, String? categoryId) async {
  await openWorldOverview(tester);
  await tester.tap(find.byKey(ValueKey('world-category-open-$categoryId')));
  await tester.pumpAndSettle();
}

Future<void> openEventMenu(WidgetTester tester, String eventId) async {
  final menu = find.byKey(ValueKey('world-more-$eventId'));
  await tester.scrollUntilVisible(menu, 100);
  await tester.tap(menu);
  await tester.pumpAndSettle();
}
