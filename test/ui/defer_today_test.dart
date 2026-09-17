import 'package:jax/core/entities/routine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/ui/controllers/event_controller.dart';
import 'package:jax/ui/pages/events_page.dart';

import '../support/memory_repository.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    testWidgets(
      'Routine types and execution states never offer Today removal $platform',
      (tester) async {
        final now = DateTime(2026, 9, 15, 14);
        for (final type in RoutineType.values) {
          for (final status in RoutineExecutionStatus.values) {
            final repo = MemoryRepository([], false);
            repo.routines.add(
              Routine(
                id: 'r',
                name: 'Routine',
                type: type,
                recurrence: RoutineRecurrence.daily,
                weekdayMask: 0,
                isActive: true,
                sortOrder: 0,
                createdAt: now,
                updatedAt: now,
              ),
            );
            repo.routineExecutions.add(
              RoutineExecution(
                id: 're',
                routineId: 'r',
                occurrenceDate: '2026-09-15',
                status: status,
                createdAt: now,
                updatedAt: now,
              ),
            );
            final c = EventController(
              repository: repo,
              newId: () => 'unused',
              now: () => now,
            );
            await c.load();
            await tester.pumpWidget(
              MaterialApp(
                theme: ThemeData(platform: platform),
                home: Scaffold(body: EventsPage(controller: c)),
              ),
            );
            await tester.pumpAndSettle();
            expect(find.byTooltip('移出今日'), findsNothing);
            expect(find.text('今天先不处理'), findsNothing);
            expect(
              find.byKey(const ValueKey('today-defer-more-r')),
              findsNothing,
            );
            expect(
              find.byKey(const ValueKey('today-defer-more-re')),
              findsNothing,
            );
            expect(await c.removeFromToday('re'), isNotNull);
            expect(repo.routineExecutions.single.status, status);
            await tester.pumpWidget(const SizedBox.shrink());
            c.dispose();
          }
        }
      },
    );
    testWidgets('Today defer eligibility and secondary action $platform', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(
        Size(platform == TargetPlatform.android ? 390 : 1200, 900),
      );
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final now = DateTime(2026, 9, 15, 14);
      for (final planned in [false, true]) {
        for (final status in EventStatus.values) {
          final repo = MemoryRepository([
            JaxEvent(
              id: 'e',
              name: 'Test Event',
              status: status,
              sourcePlanItemId: planned ? 'plan-item' : null,
              createdAt: now,
              updatedAt: now,
            ),
          ], false);
          final c = EventController(
            newId: () => 'unused',
            repository: repo,
            now: () => now,
          );
          await c.load();
          if (status != EventStatus.completed) await c.addToToday('e');
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(platform: platform),
              home: Scaffold(body: EventsPage(controller: c)),
            ),
          );
          await tester.pumpAndSettle();
          final eligible = !planned && status == EventStatus.pending;
          expect(
            find.byKey(const ValueKey('today-defer-more-e')),
            eligible ? findsOneWidget : findsNothing,
          );
          expect(find.byTooltip('移出今日'), findsNothing);
          expect(find.text('今天先不处理'), findsNothing);
          if (eligible) {
            await tester.tap(find.byKey(const ValueKey('today-defer-more-e')));
            await tester.pumpAndSettle();
            await tester.tap(find.text('今天先不处理'));
            await tester.pumpAndSettle();
            expect(c.todayEvents, isEmpty);
            expect(repo.events.single.status, EventStatus.pending);
            await c.load();
            expect(c.todayEvents, isEmpty);
          } else {
            expect(await c.removeFromToday('e'), isNotNull);
          }
          await tester.pumpWidget(const SizedBox.shrink());
          c.dispose();
        }
      }
    });
  }
}
