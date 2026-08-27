import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/app.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';

import '../support/memory_repository.dart';
import '../support/ui_navigation.dart';

void main() {
  testWidgets('deletes a pending event only after confirmation', (
    tester,
  ) async {
    final time = DateTime.utc(2026);
    final repository = MemoryRepository([
      JaxEvent(
        id: 'one',
        name: '待删除',
        status: EventStatus.pending,
        createdAt: time,
        updatedAt: time,
      ),
    ]);
    await tester.pumpWidget(JaxApp(repository: repository));
    await tester.pumpAndSettle();
    await openEventsPage(tester);
    await openEventMenu(tester, 'one');
    await tester.tap(find.byKey(const ValueKey('delete-one')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(repository.events, hasLength(1));
    await openEventMenu(tester, 'one');
    await tester.tap(find.byKey(const ValueKey('delete-one')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    expect(repository.events, isEmpty);
    expect(find.byKey(const ValueKey('world-node-one')), findsNothing);
  });
}
