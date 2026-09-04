import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/app.dart';
import 'package:jax/core/entities/event_day_plan.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';

import '../support/memory_repository.dart';

void main() {
  testWidgets('open app crosses 23:00 and shows carried Event in Today', (
    tester,
  ) async {
    var clock = DateTime(2026, 9, 3, 22, 59, 59);
    final repository = MemoryRepository([_event(clock)], false)
      ..eventDayPlans.add(_previousPlan(clock));

    await tester.pumpWidget(JaxApp(repository: repository, now: () => clock));
    await tester.pump();
    clock = DateTime(2026, 9, 3, 23, 0, 1);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    expect(
      repository.eventDayPlans.where((plan) => plan.dayKey == '2026-09-04'),
      hasLength(1),
    );
    await tester.tap(find.text('今日'));
    await tester.pump();
    expect(find.text('跨日事项'), findsOneWidget);
  });

  testWidgets('foreground resume initializes a JaxDay crossed in background', (
    tester,
  ) async {
    var clock = DateTime(2026, 9, 3, 22);
    final repository = MemoryRepository([_event(clock)], false)
      ..eventDayPlans.add(_previousPlan(clock));

    await tester.pumpWidget(JaxApp(repository: repository, now: () => clock));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    clock = DateTime(2026, 9, 3, 23, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(
      repository.eventDayPlans.where((plan) => plan.dayKey == '2026-09-04'),
      hasLength(1),
    );
  });
}

JaxEvent _event(DateTime now) => JaxEvent(
  id: 'carry',
  name: '跨日事项',
  status: EventStatus.paused,
  createdAt: now,
  updatedAt: now,
);

EventDayPlan _previousPlan(DateTime now) => EventDayPlan(
  eventId: 'carry',
  dayKey: '2026-09-03',
  order: 0,
  createdAt: now,
);
