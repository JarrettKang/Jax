import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/routine.dart';
import 'package:jax/ui/controllers/event_controller.dart';
import 'package:jax/ui/pages/events_page.dart';
import 'package:jax/ui/pages/home_page.dart';

import '../support/memory_repository.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    for (final type in RoutineType.values) {
      testWidgets(
        '$platform $type wait from Home menu, deduplicate Today, resume and complete',
        (tester) async {
          await tester.binding.setSurfaceSize(
            Size(platform == TargetPlatform.android ? 360 : 1200, 1100),
          );
          addTearDown(() => tester.binding.setSurfaceSize(null));
          var now = DateTime(2026, 9, 14, 10);
          final repo = MemoryRepository();
          var id = 0;
          final r = Routine(
            id: 'laundry',
            name: '洗衣服',
            type: type,
            recurrence: RoutineRecurrence.daily,
            weekdayMask: 0,
            isActive: true,
            sortOrder: 0,
            createdAt: now,
            updatedAt: now,
            showInHomeQuickActions: type == RoutineType.onDemand,
            timeRecommendation: type == RoutineType.scheduled
                ? const RoutineTimeRecommendation(
                    startMinute: 540,
                    endMinute: 610,
                    latestEndMinute: 660,
                  )
                : null,
          );
          repo.routines.add(r);
          final c = EventController(
            repository: repo,
            newId: () => 'id-${id++}',
            now: () => now,
          );
          await c.load();
          await c.startRoutine(r);
          Widget page(Widget child) => MaterialApp(
            theme: ThemeData(platform: platform),
            home: Scaffold(body: child),
          );
          await tester.pumpWidget(
            page(HomePage(controller: c, now: () => now, onOpenEvents: () {})),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('home-running-more')));
          await tester.pumpAndSettle();
          expect(find.text('等待'), findsOneWidget);
          now = now.add(const Duration(minutes: 10));
          await tester.tap(find.text('等待'));
          await tester.pumpAndSettle();
          final execution = c.waitingRoutineExecutions.single;
          expect(c.runningRoutine, isNull);
          expect(find.text('等待中的事项 · 1'), findsOneWidget);
          expect(find.text('洗衣服'), findsNothing);
          await tester.tap(find.byKey(const ValueKey('home-waiting-open')));
          await tester.pumpAndSettle();
          expect(find.text('洗衣服'), findsOneWidget);
          expect(c.homeRecommendations, isEmpty);
          expect(find.text('继续'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pageBack();
          await tester.pumpAndSettle();
          now = DateTime(2026, 9, 17, 10);
          await c.load();
          await tester.pumpWidget(page(EventsPage(controller: c)));
          await tester.pumpAndSettle();
          expect(find.text('洗衣服'), findsOneWidget);
          expect(find.text('持续事项'), findsOneWidget);
          expect(find.text('现在需要处理'), findsNothing);
          expect(find.text('稍后'), findsNothing);
          expect(c.routineElapsed(r), const Duration(minutes: 10));
          await tester.tap(
            find.byKey(ValueKey('routine-waiting-resume-${execution.id}')),
          );
          await tester.pumpAndSettle();
          expect(c.runningRoutineExecution!.id, execution.id);
          expect(find.text('正在进行'), findsOneWidget);
          expect(find.text('洗衣服'), findsOneWidget);
          now = now.add(const Duration(minutes: 5));
          await tester.tap(
            find.byKey(const ValueKey('today-routine-wait-laundry')),
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(ValueKey('routine-waiting-complete-${execution.id}')),
          );
          await tester.pumpAndSettle();
          expect(c.waitingRoutineExecutions, isEmpty);
          expect(c.runningRoutine, isNull);
          expect(repo.routineSegments, hasLength(2));
          expect(
            repo.routineSegments.fold(
              Duration.zero,
              (a, s) => a + s.durationAt(now),
            ),
            const Duration(minutes: 15),
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          c.dispose();
        },
      );
    }
  }
}
