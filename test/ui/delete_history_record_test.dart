import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/app.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';

import '../support/memory_repository.dart';

void main() {
  testWidgets('World deletes completed history only after confirmation', (
    tester,
  ) async {
    final time = DateTime.utc(2026);
    final repository = MemoryRepository([
      JaxEvent(
        id: 'done',
        name: '历史',
        status: EventStatus.completed,
        createdAt: time,
        updatedAt: time,
        firstStartedAt: time,
        completedAt: time,
      ),
    ]);
    await tester.pumpWidget(JaxApp(repository: repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('世界'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('world-more-done')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('world-delete-history-done')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('历史'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('world-more-done')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('world-delete-history-done')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    expect(find.text('历史'), findsNothing);
  });
}
