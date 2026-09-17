import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/app.dart';
import 'package:jax/core/entities/routine.dart';

import '../support/memory_repository.dart';

void main() {
  for (final width in [390.0, 1400.0]) {
    testWidgets(
      'Home keeps quick actions out of root while Routine entry can resume at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final now = DateTime(2026, 9, 5, 12);
        Routine routine(
          String id,
          int order, {
          bool quick = true,
          bool active = true,
        }) => Routine(
          id: id,
          name: '$id 很长的按需日常名称用于验证窄屏布局',
          type: RoutineType.onDemand,
          recurrence: RoutineRecurrence.daily,
          weekdayMask: 0,
          isActive: active,
          sortOrder: order,
          showInHomeQuickActions: quick,
          createdAt: now,
          updatedAt: now,
        );
        final repo = MemoryRepository()
          ..routines.addAll([
            routine('unmarked', 0, quick: false),
            routine('inactive', 1, active: false),
            for (var i = 0; i < 5; i++) routine('quick$i', i + 2),
          ])
          ..routineExecutions.add(
            RoutineExecution(
              id: 'paused',
              routineId: 'quick0',
              occurrenceDate: '2026-09-05',
              status: RoutineExecutionStatus.paused,
              createdAt: now,
              updatedAt: now,
            ),
          );
        await tester.pumpWidget(JaxApp(repository: repo, now: () => now));
        await tester.pumpAndSettle();
        expect(find.text('快捷动作'), findsNothing);
        expect(find.byKey(const ValueKey('home-root-ask')), findsOneWidget);
        expect(repo.routineSegments, isEmpty);
        await tester.tap(find.text('日常').last);
        await tester.pumpAndSettle();
        final first = find.byKey(
          const ValueKey('routine-on-demand-start-quick0'),
        );
        await tester.ensureVisible(first);
        await tester.tap(first);
        await tester.pumpAndSettle();
        expect(repo.routineExecutions, hasLength(1));
        expect(repo.routineExecutions.single.id, 'paused');
        expect(
          repo.routineExecutions.single.status,
          RoutineExecutionStatus.running,
        );
        expect(
          find.byKey(const ValueKey('home-on-demand-quick0')),
          findsNothing,
        );
        expect(repo.eventDayPlans, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
