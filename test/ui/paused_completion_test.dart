import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/entities/routine.dart';
import 'package:jax/core/preferences/routine_category_collapse_store.dart';
import 'package:jax/ui/controllers/event_controller.dart';
import 'package:jax/ui/pages/events_page.dart';
import 'package:jax/ui/pages/routine_page.dart';
import 'package:jax/ui/pages/home_page.dart';
import 'package:jax/ui/controllers/planning_controller.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/repositories/sqlite_event_repository.dart';
import 'package:jax/data/repositories/sqlite_planning_repository.dart';
import 'package:jax/data/repositories/sqlite_world_node_repository.dart';

import '../support/world_map_fixture.dart';
import '../support/memory_repository.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    for (final type in RoutineType.values) {
      for (final detail in [false, true]) {
        testWidgets(
          '$platform $type paused completes from ${detail ? 'Routine menu' : 'Today'} after expiry',
          (tester) async {
            await tester.binding.setSurfaceSize(
              Size(platform == TargetPlatform.android ? 390 : 1200, 1000),
            );
            addTearDown(() => tester.binding.setSurfaceSize(null));
            var now = DateTime(2026, 9, 15, 10), seq = 0;
            final repo = MemoryRepository([], false);
            final r = Routine(
              id: 'r',
              name: 'Routine',
              type: type,
              recurrence: RoutineRecurrence.daily,
              weekdayMask: 0,
              isActive: true,
              sortOrder: 0,
              createdAt: now,
              updatedAt: now,
              timeRecommendation: type == RoutineType.scheduled
                  ? const RoutineTimeRecommendation(
                      startMinute: 600,
                      endMinute: 630,
                      latestEndMinute: 640,
                    )
                  : null,
            );
            repo.routines.add(r);
            final c = EventController(
              repository: repo,
              now: () => now,
              newId: () => 's-${seq++}',
            );
            await c.load();
            await c.startRoutine(r);
            now = DateTime(2026, 9, 15, 10, 30);
            await c.pauseRoutine(r);
            final execution = c.pausedRoutineExecutions.single;
            now = DateTime(2026, 9, 16, 11);
            await c.load();
            expect(
              c.homeRecommendations.where(
                (x) => x.candidate.routine?.id == r.id,
              ),
              isEmpty,
            );
            Widget wrap(Widget page) => MaterialApp(
              theme: ThemeData(platform: platform),
              home: Scaffold(body: page),
            );
            await tester.pumpWidget(wrap(EventsPage(controller: c)));
            await tester.pumpAndSettle();
            expect(find.text('Routine'), findsOneWidget);
            expect(find.text('继续'), findsOneWidget);
            expect(find.text('完成'), findsOneWidget);
            expect(find.text('开始'), findsNothing);
            if (detail) {
              await tester.pumpWidget(
                wrap(
                  RoutinePage(
                    controller: c,
                    collapseStore: InMemoryRoutineCategoryCollapseStore(),
                  ),
                ),
              );
              await tester.pumpAndSettle();
              await tester.tap(find.byKey(const ValueKey('routine-more-r')));
              await tester.pumpAndSettle();
            }
            await tester.tap(find.text('完成'));
            await tester.pumpAndSettle();
            expect(repo.routineExecutions.single.id, execution.id);
            expect(
              repo.routineExecutions.single.status,
              RoutineExecutionStatus.completed,
            );
            expect(repo.routineExecutions.single.completedAt, now.toUtc());
            expect(repo.routineSegments, hasLength(1));
            expect(
              repo.routineSegments.single.durationAt(now),
              const Duration(minutes: 30),
            );
            expect(c.pausedRoutineExecutions, isEmpty);
            await tester.pumpWidget(const SizedBox.shrink());
            c.dispose();
          },
        );
      }
    }
    for (final planned in [false, true]) {
      testWidgets(
        '$platform planned=$planned Today paused Event has resume and complete',
        (tester) async {
          var now = DateTime(2026, 9, 15, 10), seq = 0;
          final repo = MemoryRepository([
            JaxEvent(
              id: 'e',
              name: 'Event',
              status: EventStatus.pending,
              sourcePlanItemId: planned ? 'p' : null,
              createdAt: now,
              updatedAt: now,
            ),
          ], false);
          final c = EventController(
            repository: repo,
            now: () => now,
            newId: () => 's-${seq++}',
          );
          await c.load();
          await c.start('e');
          now = DateTime(2026, 9, 15, 10, 30);
          await c.pause('e');
          now = DateTime(2026, 9, 15, 11);
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(platform: platform),
              home: Scaffold(body: EventsPage(controller: c)),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('继续'), findsOneWidget);
          expect(find.text('完成'), findsOneWidget);
          await tester.tap(find.text('完成'));
          await tester.pumpAndSettle();
          expect(find.text('Event'), findsNothing);
          expect(repo.events.single.status, EventStatus.completed);
          expect(repo.segments, hasLength(1));
          expect(
            repo.segments.single.durationAt(now),
            const Duration(minutes: 30),
          );
          await tester.pumpWidget(const SizedBox.shrink());
          c.dispose();
        },
      );
    }
    testWidgets(
      '$platform Home Work paused directly completes and removes original step',
      (tester) async {
        await tester.runAsync(() async {
          final db = await AppDatabase.inMemory();
          addTearDown(db.close);
          await seedWorldMapFixture(db);
          final repo = SqliteEventRepository(db),
              planning = SqlitePlanningRepository(db);
          var now = DateTime(2026, 9, 15, 10), seq = 0;
          final c = EventController(
            repository: repo,
            now: () => now,
            newId: () => 's-${seq++}',
          );
          final pc = PlanningController(
            planningRepository: planning,
            worldNodeRepository: SqliteWorldNodeRepository(db),
            eventRepository: repo,
            now: () => now,
            newId: () => 'p-${seq++}',
          );
          addTearDown(c.dispose);
          addTearDown(pc.dispose);
          await planning.dispatchPlanItems(
            eventIdsByPlanItemId: {'fixture-step-0': 'e'},
            dayKey: '2026-09-15',
            now: now,
          );
          await c.load();
          await c.start('e');
          now = DateTime(2026, 9, 15, 10, 30);
          await c.pause('e');
          await pc.load();
          now = DateTime(2026, 9, 15, 11);
          Future<void> settle() async {
            await Future<void>.delayed(const Duration(milliseconds: 120));
            await tester.pumpAndSettle();
          }

          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(platform: platform),
              home: Scaffold(
                body: HomePage(
                  controller: c,
                  planningController: pc,
                  now: () => now,
                  onOpenEvents: () {},
                ),
              ),
            ),
          );
          await settle();
          await tester.tap(
            find.byKey(const ValueKey('home-category-entry-research')),
          );
          await settle();
          expect(
            find.byKey(const ValueKey('home-category-start-fixture-step-0')),
            findsOneWidget,
          );
          await tester.tap(
            find.byKey(const ValueKey('home-category-complete-fixture-step-0')),
          );
          await settle();
          expect(
            find.byKey(const ValueKey('home-category-plan-fixture-step-0')),
            findsNothing,
          );
          expect((await repo.getEvent('e'))!.status, EventStatus.completed);
          expect(
            (await repo.getRunSegments('e')).single.durationAt(now),
            const Duration(minutes: 30),
          );
          await tester.pumpWidget(const SizedBox.shrink());
        });
      },
    );
  }
}
