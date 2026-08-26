import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/app.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/entities/run_segment.dart';

import '../support/memory_repository.dart';
import '../support/ui_navigation.dart';

void main() {
  testWidgets('pauses running event and restores edit/delete', (tester) async {
    final start = DateTime.utc(2026);
    final end = start.add(const Duration(minutes: 3));
    final repository =
        MemoryRepository([
            JaxEvent(
              id: 'one',
              name: '任务',
              status: EventStatus.running,
              createdAt: start,
              updatedAt: start,
              firstStartedAt: start,
            ),
          ])
          ..segments.add(
            RunSegment(
              id: 'segment',
              eventId: 'one',
              startedAt: start,
              createdAt: start,
            ),
          );
    await tester.pumpWidget(JaxApp(repository: repository, now: () => end));
    await tester.pumpAndSettle();
    await openEventsPage(tester);
    await tester.tap(find.byKey(const ValueKey('pause-one')));
    await tester.pumpAndSettle();
    expect(find.textContaining('已暂停'), findsOneWidget);
    expect(find.byKey(const ValueKey('edit-one')), findsNothing);
    expect(find.byKey(const ValueKey('delete-one')), findsNothing);
    await openEventMenu(tester, 'one');
    expect(find.byKey(const ValueKey('edit-one')), findsOneWidget);
    expect(find.byKey(const ValueKey('delete-one')), findsOneWidget);
  });
}
