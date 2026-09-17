import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/routine.dart';
import 'package:jax/ui/controllers/event_controller.dart';
import 'package:jax/ui/pages/events_page.dart';

import '../support/memory_repository.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    testWidgets(
      'boundary timer moves Today sections without polling $platform',
      (tester) async {
        await tester.binding.setSurfaceSize(
          Size(platform == TargetPlatform.android ? 360 : 1200, 900),
        );
        addTearDown(() => tester.binding.setSurfaceSize(null));
        var now = DateTime(2026, 9, 14, 10, 59);
        final repo = MemoryRepository();
        repo.routines.add(
          Routine(
            id: 'lunch',
            name: '一个很长的午饭日常名称用于验证移动端布局',
            recurrence: RoutineRecurrence.daily,
            weekdayMask: 0,
            isActive: true,
            sortOrder: 0,
            createdAt: now,
            updatedAt: now,
            timeRecommendation: const RoutineTimeRecommendation(
              startMinute: 660,
              endMinute: 661,
              latestEndMinute: 662,
            ),
          ),
        );
        var seq = 0;
        final ec = EventController(
          repository: repo,
          newId: () => 'id-${seq++}',
          now: () => now,
        );
        await ec.load();
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: platform),
            home: Scaffold(body: EventsPage(controller: ec)),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('稍后'), findsOneWidget);
        expect(find.text('现在需要处理'), findsNothing);
        expect(find.text('持续事项'), findsNothing);
        expect(find.text('未开始'), findsNothing);
        now = DateTime(2026, 9, 14, 11);
        await tester.pump(const Duration(minutes: 1));
        await tester.pumpAndSettle();
        expect(find.text('现在需要处理'), findsOneWidget);
        expect(find.text('稍后'), findsNothing);
        expect(find.text('理想完成前 11:01'), findsOneWidget);
        now = DateTime(2026, 9, 14, 11, 1, 0, 1);
        await tester.pump(const Duration(minutes: 1, milliseconds: 1));
        await tester.pumpAndSettle();
        expect(find.text('已超过理想时间 · 最晚 11:02'), findsOneWidget);
        now = DateTime(2026, 9, 14, 11, 2, 0, 1);
        await tester.pump(const Duration(minutes: 1));
        await tester.pumpAndSettle();
        expect(find.text('现在需要处理'), findsNothing);
        expect(find.text('稍后'), findsNothing);
        expect(find.text('当前没有待处理事项'), findsOneWidget);
        expect(find.text('今日事项'), findsNothing);
        expect(find.text('今日日常'), findsNothing);
        expect(repo.routineExecutions, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        ec.dispose();
      },
    );
  }
  testWidgets(
    'cross-day occurrence completes original, later start targets next explicitly',
    (tester) async {
      var now = DateTime(2026, 9, 14, 23, 30);
      final repo = MemoryRepository();
      var seq = 0;
      repo.routines.add(
        Routine(
          id: 'night',
          name: '晚上洗漱',
          recurrence: RoutineRecurrence.daily,
          weekdayMask: 0,
          isActive: true,
          sortOrder: 0,
          createdAt: now,
          updatedAt: now,
          timeRecommendation: const RoutineTimeRecommendation(
            startMinute: 1350,
            endMinute: 30,
            latestEndMinute: 120,
          ),
        ),
      );
      final ec = EventController(
        repository: repo,
        newId: () => 'id-${seq++}',
        now: () => now,
      );
      await ec.load();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: EventsPage(controller: ec)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('晚上洗漱'), findsOneWidget);
      expect(find.text('稍后'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('today-routine-start-night')));
      await tester.pumpAndSettle();
      expect(repo.routineExecutions.single.occurrenceDate, '2026-09-14');
      expect(find.text('正在进行'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('today-routine-pause-night')));
      await tester.pumpAndSettle();
      now = DateTime(2026, 9, 15, 0, 45);
      await ec.load();
      await tester.pumpAndSettle();
      expect(find.text('2026-09-14'), findsOneWidget);
      await tester.tap(
        find.byKey(
          ValueKey(
            'routine-paused-complete-${repo.routineExecutions.single.id}',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        repo.routineExecutions.single.status,
        RoutineExecutionStatus.completed,
      );
      expect(find.text('现在需要处理'), findsNothing);
      expect(find.text('稍后'), findsOneWidget);
      expect(find.text('晚上洗漱'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('today-routine-start-night')));
      await tester.pumpAndSettle();
      expect(repo.routineExecutions.map((e) => e.occurrenceDate), [
        '2026-09-14',
        '2026-09-15',
      ]);
      expect(find.text('晚上洗漱'), findsOneWidget);
      expect(find.text('正在进行'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      ec.dispose();
    },
  );

  testWidgets('app resume recomputes lifecycle with no execution writes', (
    tester,
  ) async {
    var now = DateTime(2026, 9, 14, 10);
    final repo = MemoryRepository();
    repo.routines.add(
      Routine(
        id: 'lunch',
        name: 'Lunch',
        recurrence: RoutineRecurrence.daily,
        weekdayMask: 0,
        isActive: true,
        sortOrder: 0,
        createdAt: now,
        updatedAt: now,
        timeRecommendation: const RoutineTimeRecommendation(
          startMinute: 660,
          endMinute: 780,
          latestEndMinute: 1020,
        ),
      ),
    );
    final ec = EventController(
      repository: repo,
      newId: () => 'unused',
      now: () => now,
    );
    await ec.load();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: EventsPage(controller: ec)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('稍后'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    now = DateTime(2026, 9, 14, 14);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('现在需要处理'), findsOneWidget);
    expect(find.text('已超过理想时间 · 最晚 17:00'), findsOneWidget);
    expect(repo.routineExecutions, isEmpty);
    expect(repo.routineSegments, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    ec.dispose();
  });
}
