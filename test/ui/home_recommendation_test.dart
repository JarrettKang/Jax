import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/app.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/event_day_plan.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/entities/routine.dart';

import '../support/memory_repository.dart';

void main() {
  testWidgets(
    'Home shows only one temporal decision and keeps temporary action available without focused nodes',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final now = DateTime(2026, 9, 3, 12);
      JaxEvent event(String id) => JaxEvent(
        id: id,
        name: id,
        status: EventStatus.pending,
        createdAt: now,
        updatedAt: now,
      );
      final repo = MemoryRepository([event('Event A'), event('Event B')])
        ..eventDayPlans.addAll([
          for (var index = 0; index < 2; index++)
            EventDayPlan(
              eventId: index == 0 ? 'Event A' : 'Event B',
              dayKey: '2026-09-03',
              order: index,
              createdAt: now,
            ),
        ])
        ..routines.add(
          Routine(
            id: 'lunch',
            name: '吃午饭',
            recurrence: RoutineRecurrence.daily,
            weekdayMask: 0,
            isActive: true,
            sortOrder: 0,
            createdAt: now,
            updatedAt: now,
            timeRecommendation: const RoutineTimeRecommendation(
              startMinute: 660,
              endMinute: 780,
              reason: '该吃午饭了',
            ),
          ),
        );

      await tester.pumpWidget(JaxApp(repository: repo, now: () => now));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('home-primary-lunch')), findsOneWidget);
      expect(find.text('已经到了推荐时间 · 理想完成前 13:00'), findsOneWidget);
      expect(find.text('首选'), findsNothing);
      expect(find.text('其他可做'), findsNothing);
      expect(find.text('Event A'), findsNothing);
      expect(find.text('Event B'), findsNothing);
      expect(find.text('工作'), findsNothing);
      expect(find.byKey(const ValueKey('home-temporary')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
