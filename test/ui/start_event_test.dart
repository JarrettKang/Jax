import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/app.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';

import '../support/memory_repository.dart';
import '../support/ui_navigation.dart';

void main() {
  testWidgets('starts pending event and hides edit/delete actions', (
    tester,
  ) async {
    final time = DateTime.utc(2026);
    final repository = MemoryRepository([
      JaxEvent(
        id: 'one',
        name: '计时任务',
        status: EventStatus.pending,
        createdAt: time,
        updatedAt: time,
      ),
    ]);
    await tester.pumpWidget(
      JaxApp(repository: repository, newId: () => 'segment', now: () => time),
    );
    await tester.pumpAndSettle();
    await openEventsPage(tester);
    await tester.tap(find.byKey(const ValueKey('start-one')));
    await tester.pump();
    expect(find.textContaining('正在进行'), findsOneWidget);
    expect(find.byKey(const ValueKey('edit-one')), findsNothing);
    expect(find.byKey(const ValueKey('delete-one')), findsNothing);
  });
}
