import 'package:flutter_test/flutter_test.dart';

Future<void> openEventsPage(WidgetTester tester) async {
  if (find.text('新建事件').evaluate().isNotEmpty) return;
  await tester.tap(find.text('事件'));
  await tester.pumpAndSettle();
}
