import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/app.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/entities/run_segment.dart';

import '../support/memory_repository.dart';
import '../support/ui_navigation.dart';

void main() {
  testWidgets('moves completed event from events to history', (tester) async {
    final start = DateTime.utc(2026);
    final end = start.add(const Duration(minutes: 5));
    final repository =
        MemoryRepository([
            JaxEvent(
              id: 'one',
              name: '完成任务',
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
    await tester.tap(find.byKey(const ValueKey('complete-one')));
    await tester.pumpAndSettle();
    expect(find.text('完成任务'), findsNothing);
    await tester.tap(find.text('记录'));
    await tester.pumpAndSettle();
    expect(find.text('完成任务'), findsOneWidget);
    expect(find.textContaining('持续：5 分钟'), findsOneWidget);
  });
}
