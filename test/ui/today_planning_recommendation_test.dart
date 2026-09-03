import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/app.dart';
import 'package:jax/core/entities/event_day_plan.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/entities/plan.dart';
import 'package:jax/core/entities/plan_item.dart';
import 'package:jax/core/entities/world_node.dart';
import 'package:jax/core/errors/domain_failure.dart';
import 'package:jax/core/repositories/planning_dispatch_repository.dart';
import 'package:jax/core/repositories/planning_repository.dart';
import 'package:jax/core/repositories/world_node_repository.dart';

import '../support/memory_repository.dart';

void main() {
  testWidgets(
    'Today selects and dispatches derived recommendations immediately',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final now = DateTime(2026, 9, 2, 10);
      final events = MemoryRepository(const [], false);
      final planning = _PlanningRepository(events, now);
      final worlds = _WorldRepository(now);
      var id = 0;

      await tester.pumpWidget(
        JaxApp(
          repository: events,
          planningRepository: planning,
          worldNodeRepository: worlds,
          newId: () => 'event-${id++}',
          now: () => now,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('今日'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('today-recommendations')),
        findsOneWidget,
      );
      expect(find.text('实现今日建议'), findsOneWidget);
      expect(find.text('仍是草稿'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('dispatch-recommendations')),
            )
            .onPressed,
        isNull,
      );

      await tester.tap(find.byKey(const ValueKey('recommendation-next')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('dispatch-recommendations')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('recommendation-next')), findsNothing);
      expect(find.text('实现今日建议'), findsOneWidget);
      expect(planning.items.first.status, PlanItemStatus.dispatched);
      expect(events.eventDayPlans, hasLength(1));
      expect(events.segments, isEmpty);

      final eventId = events.events.single.id;
      await events.removeEventDayPlan(eventId, '2026-09-02');
      await tester.tap(find.text('世界'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('今日'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('today-add-existing')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('today-add-existing')));
      await tester.pumpAndSettle();
      expect(find.text('已派发事项'), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('existing-event-$eventId')));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, '加入今日'));
      await tester.pumpAndSettle();

      expect(events.events, hasLength(1));
      expect(events.eventDayPlans, hasLength(1));
      expect(find.text('实现今日建议'), findsOneWidget);
    },
  );
}

class _WorldRepository implements WorldNodeRepository {
  _WorldRepository(DateTime now)
    : node = WorldNode(
        id: '00000000-0000-4000-8000-000000000006',
        name: 'Jax P3',
        status: WorldNodeStatus.inProgress,
        isFocused: true,
        sortOrder: 0,
        createdAt: now,
        updatedAt: now,
      );

  final WorldNode node;

  @override
  Future<List<WorldNode>> getWorldNodes() async => [node];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PlanningRepository
    implements PlanningRepository, PlanningDispatchRepository {
  _PlanningRepository(this.events, this.now)
    : plan = Plan(
        id: 'plan',
        worldNodeId: '00000000-0000-4000-8000-000000000006',
        status: PlanStatus.current,
        roundNumber: 1,
        title: 'Dispatch',
        createdAt: now,
        updatedAt: now,
      ),
      items = [
        PlanItem(
          id: 'next',
          planId: 'plan',
          title: '实现今日建议',
          status: PlanItemStatus.next,
          sortOrder: 0,
          createdAt: now,
          updatedAt: now,
        ),
        PlanItem(
          id: 'draft',
          planId: 'plan',
          title: '仍是草稿',
          status: PlanItemStatus.draft,
          sortOrder: 1,
          createdAt: now,
          updatedAt: now,
        ),
      ];

  final MemoryRepository events;
  final DateTime now;
  final Plan plan;
  final List<PlanItem> items;

  @override
  Future<List<Plan>> getPlans() async => [plan];

  @override
  Future<Plan?> getPlan(String id) async => id == plan.id ? plan : null;

  @override
  Future<List<PlanItem>> getPlanItems(String planId) async =>
      items.where((item) => item.planId == planId).toList();

  @override
  Future<List<JaxEvent>> dispatchPlanItems({
    required Map<String, String> eventIdsByPlanItemId,
    required String dayKey,
    required DateTime now,
  }) async {
    final selected = [
      for (final id in eventIdsByPlanItemId.keys)
        items.where((item) => item.id == id).firstOrNull,
    ];
    if (selected.any((item) => item?.status != PlanItemStatus.next)) {
      throw const DomainFailure('stale');
    }
    final created = <JaxEvent>[];
    for (final item in selected.nonNulls) {
      final event = JaxEvent(
        id: eventIdsByPlanItemId[item.id]!,
        name: item.title,
        status: EventStatus.pending,
        sourcePlanItemId: item.id,
        createdAt: now,
        updatedAt: now,
      );
      await events.insertEvent(event);
      await events.addEventDayPlan(
        EventDayPlan(
          eventId: event.id,
          dayKey: dayKey,
          order: events.eventDayPlans.length,
          createdAt: now,
        ),
      );
      final index = items.indexWhere((value) => value.id == item.id);
      items[index] = PlanItem(
        id: item.id,
        planId: item.planId,
        title: item.title,
        note: item.note,
        status: PlanItemStatus.dispatched,
        sortOrder: item.sortOrder,
        createdAt: item.createdAt,
        updatedAt: now,
      );
      created.add(event);
    }
    return created;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
