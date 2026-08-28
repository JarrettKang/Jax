import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/app.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/entities/run_segment.dart';
import 'package:jax/core/entities/routine.dart';

import '../support/memory_repository.dart';
import '../support/ui_navigation.dart';

void main() {
  testWidgets(
    'paused Event opens shared closed segment editor without open segments',
    (tester) async {
      final now = DateTime(2026, 8, 28, 12);
      final repo =
          MemoryRepository([
              JaxEvent(
                id: 'e',
                name: '很长的执行时间纠错事件名称',
                status: EventStatus.paused,
                createdAt: now,
                updatedAt: now,
              ),
            ])
            ..segments.addAll([
              RunSegment(
                id: 'closed',
                eventId: 'e',
                startedAt: DateTime(2026, 8, 28, 9),
                endedAt: DateTime(2026, 8, 28, 9, 30),
                createdAt: now,
              ),
              RunSegment(
                id: 'open',
                eventId: 'e',
                startedAt: DateTime(2026, 8, 28, 10),
                createdAt: now,
              ),
            ]);
      await tester.pumpWidget(
        JaxApp(repository: repo, now: () => now, newId: () => 'new'),
      );
      await tester.pumpAndSettle();
      await openWorldCategory(tester, null);
      await tester.tap(find.byKey(const ValueKey('world-more-e')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('编辑执行时间'));
      await tester.pumpAndSettle();
      expect(find.text('8月28日 09:00 – 8月28日 09:30'), findsOneWidget);
      expect(find.byKey(const ValueKey('segment-edit-closed')), findsOneWidget);
      expect(find.byKey(const ValueKey('segment-edit-open')), findsNothing);
      expect(find.byKey(const ValueKey('segment-add')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Record lists completed Routine occurrence with zero segments', (
    tester,
  ) async {
    final now = DateTime(2026, 8, 28, 12);
    final repo = MemoryRepository()
      ..routines.add(
        Routine(
          id: 'r',
          name: '午饭',
          recurrence: RoutineRecurrence.daily,
          weekdayMask: 0,
          isActive: true,
          sortOrder: 0,
          createdAt: now,
          updatedAt: now,
        ),
      )
      ..routineExecutions.add(
        RoutineExecution(
          id: 'rx',
          routineId: 'r',
          occurrenceDate: '2026-08-27',
          status: RoutineExecutionStatus.completed,
          createdAt: now,
          updatedAt: now,
        ),
      );
    await tester.pumpWidget(
      JaxApp(repository: repo, now: () => now, newId: () => 'new'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('记录'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('execution-time-correction')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('execution-owner-routine-rx')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('execution-owner-routine-rx')));
    await tester.pumpAndSettle();
    expect(find.text('暂无执行时间记录'), findsOneWidget);
    expect(find.byKey(const ValueKey('segment-add')), findsOneWidget);
  });
}
