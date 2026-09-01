import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/app.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/entities/run_segment.dart';

import '../support/memory_repository.dart';
import '../support/ui_navigation.dart';

void main() {
  testWidgets('pauses a running flat Event and exposes resume', (tester) async {
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
    await openEventMenu(tester, 'one');
    await tester.tap(find.byKey(const ValueKey('pause-one')));
    await tester.pumpAndSettle();
    expect(find.textContaining('已暂停'), findsOneWidget);
    expect(repository.events.single.status, EventStatus.paused);
    expect(repository.segments.single.endedAt, end);
    expect(find.byKey(const ValueKey('resume-one')), findsOneWidget);
  });
}
