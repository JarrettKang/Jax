import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/entities/routine.dart';
import 'package:jax/ui/controllers/event_controller.dart';
import 'package:jax/ui/pages/home_page.dart';
import 'package:jax/ui/pages/events_page.dart';

import '../support/memory_repository.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    for (final routine in [false, true]) {
      testWidgets(
        '$platform routine=$routine menu, cancel, invalid, correct and refresh',
        (tester) async {
          await tester.binding.setSurfaceSize(
            Size(platform == TargetPlatform.android ? 390 : 1200, 900),
          );
          addTearDown(() => tester.binding.setSurfaceSize(null));
          var now = DateTime(2026, 9, 15, 13);
          final repo = MemoryRepository([], false);
          var id = 0;
          final c = EventController(
            repository: repo,
            now: () => now,
            newId: () => 'id-${id++}',
          );
          if (routine) {
            repo.routines.add(
              Routine(
                id: 'r',
                name: '测试事项',
                recurrence: RoutineRecurrence.daily,
                weekdayMask: 0,
                isActive: true,
                sortOrder: 0,
                createdAt: now,
                updatedAt: now,
              ),
            );
            await c.load();
            expect(await c.startRoutine(repo.routines.single), isNull);
          } else {
            await repo.insertEvent(
              JaxEvent(
                id: 'e',
                name: '测试事项',
                status: EventStatus.pending,
                createdAt: now,
                updatedAt: now,
              ),
            );
            await c.load();
            expect(await c.start('e'), isNull);
          }
          now = DateTime(2026, 9, 15, 14, 20);
          Widget wrap(Widget child) => MaterialApp(
            theme: ThemeData(platform: platform),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(alwaysUse24HourFormat: true),
              child: child!,
            ),
            home: Scaffold(body: child),
          );
          await tester.pumpWidget(
            wrap(HomePage(controller: c, now: () => now, onOpenEvents: () {})),
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('home-running-pause')),
            findsOneWidget,
          );
          expect(find.text('暂停并修改暂停时间'), findsNothing);
          Future<void> open() async {
            await tester.tap(find.byKey(const ValueKey('home-running-more')));
            await tester.pumpAndSettle();
            expect(find.text('等待'), findsOneWidget);
            expect(find.text('完成'), findsOneWidget);
            await tester.tap(find.text('暂停并修改暂停时间'));
            await tester.pumpAndSettle();
            expect(find.text('实际暂停时间'), findsOneWidget);
          }

          bool getRunning() =>
              routine ? c.runningRoutine != null : c.runningEvent != null;
          DateTime? getEnd() => routine
              ? repo.routineSegments.single.endedAt
              : repo.segments.single.endedAt;
          await open();
          await tester.tap(find.text('取消'));
          await tester.pumpAndSettle();
          expect(getRunning(), isTrue);
          expect(getEnd(), isNull);
          await open();
          Future<void> pick(String hour, String minute) async {
            final dialog = find.byType(AlertDialog);
            await tester.tap(
              find
                  .descendant(of: dialog, matching: find.byType(OutlinedButton))
                  .last,
            );
            await tester.pumpAndSettle();
            await tester.tap(find.byIcon(Icons.keyboard_outlined));
            await tester.pumpAndSettle();
            final fields = find.descendant(
              of: find.byType(TimePickerDialog),
              matching: find.byType(TextField),
            );
            await tester.enterText(fields.at(0), hour);
            await tester.enterText(fields.at(1), minute);
            await tester.tap(find.text('OK'));
            await tester.pumpAndSettle();
          }

          Future<void> submit() async {
            await tester.tap(
              find.descendant(
                of: find.byType(AlertDialog),
                matching: find.byType(FilledButton),
              ),
            );
            await tester.pumpAndSettle();
          }

          await pick('12', '59');
          await submit();
          expect(find.text('结束时间必须晚于开始时间'), findsOneWidget);
          expect(getRunning(), isTrue);
          expect(getEnd(), isNull);
          await pick('14', '05');
          await submit();
          expect(find.byType(AlertDialog), findsNothing);
          expect(
            find.byKey(const ValueKey('home-running-pause')),
            findsNothing,
          );
          expect(getRunning(), isFalse);
          expect(getEnd(), DateTime(2026, 9, 15, 14, 5).toUtc());
          expect(
            routine
                ? repo.routineExecutions.single.status.name
                : repo.events.single.status.name,
            'paused',
          );
          expect(
            routine
                ? c.routineElapsed(repo.routines.single)
                : c.elapsedFor(repo.events.single),
            const Duration(minutes: 65),
          );
          await tester.pumpWidget(wrap(EventsPage(controller: c)));
          await tester.pumpAndSettle();
          expect(find.text('测试事项'), findsOneWidget);
          expect(find.text('继续'), findsOneWidget);
          now = DateTime(2026, 9, 15, 15);
          await tester.tap(find.text('继续'));
          await tester.pumpAndSettle();
          expect(getRunning(), isTrue);
          expect(
            routine ? repo.routineSegments.length : repo.segments.length,
            2,
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          c.dispose();
        },
      );
    }
  }
}
