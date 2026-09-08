import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/app.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/entities/plan.dart';
import 'package:jax/core/entities/plan_item.dart';
import 'package:jax/core/entities/plan_review_note.dart';
import 'package:jax/core/entities/run_segment.dart';
import 'package:jax/core/entities/world_node.dart';
import 'package:jax/core/repositories/planning_repository.dart';
import 'package:jax/core/repositories/world_node_repository.dart';
import 'package:jax/ui/controllers/event_controller.dart';
import 'package:jax/ui/controllers/planning_controller.dart';
import 'package:jax/ui/pages/home_page.dart';

import '../support/memory_repository.dart';

void main() {
  test(
    'next refinement on a not-focused node does not become a recommendation',
    () async {
      final fixture = _Fixture.current();
      var sequence = 0;
      final controller = PlanningController(
        planningRepository: fixture.planning,
        worldNodeRepository: fixture.world,
        eventRepository: fixture.events,
        newId: () => 'next-${sequence++}',
        now: () => _time(20),
      );
      addTearDown(controller.dispose);
      await controller.load();
      final plan = fixture.planning.plans.single;
      await controller.addItem(
        plan,
        'Next but not focused',
        null,
        initialStatus: PlanItemStatus.next,
      );

      expect(fixture.world.nodes.single.isFocused, isFalse);
      expect(controller.recommendationGroups, isEmpty);
      expect(fixture.events.events, hasLength(1));
    },
  );

  test('stale source relation is rejected without guessing a target', () async {
    final fixture = _Fixture.current();
    final controller = PlanningController(
      planningRepository: fixture.planning,
      worldNodeRepository: fixture.world,
      eventRepository: fixture.events,
      newId: () => 'unused',
      now: () => _time(20),
    );
    addTearDown(controller.dispose);
    fixture.planning.items.clear();

    await expectLater(
      controller.resolvePlanStepRefinement('source-item'),
      throwsA(anything),
    );
    expect(fixture.planning.plans, hasLength(1));
  });

  testWidgets(
    'running Planned Event opens canonical editor and appends next without execution disturbance',
    (tester) async {
      await _setViewport(tester, const Size(1200, 800));
      final fixture = _Fixture.current();
      await tester.pumpWidget(fixture.app());
      await tester.pumpAndSettle();

      final eventBefore = fixture.events.events.single;
      final segmentBefore = fixture.events.segments.single;
      await tester.tap(find.byKey(const ValueKey('home-running-more')));
      await tester.pumpAndSettle();
      expect(find.text('补充计划步骤…'), findsOneWidget);
      await tester.tap(find.text('补充计划步骤…'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('当前计划 · 第 1 轮'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('plan-item-title')),
        '补实验图',
      );
      await tester.tap(find.text('说明'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('plan-item-note')),
        '先整理原始数据',
      );
      await tester.tap(find.byKey(const ValueKey('plan-item-initial-status')));
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('add-plan-item')));
      await tester.pumpAndSettle();

      expect(fixture.planning.items, hasLength(2));
      expect(fixture.planning.items.first.status, PlanItemStatus.dispatched);
      final added = fixture.planning.items.last;
      expect(added.title, '补实验图');
      expect(added.note, '先整理原始数据');
      expect(added.status, PlanItemStatus.next);
      expect(added.sortOrder, 1);
      expect(fixture.events.events.single, eventBefore);
      expect(fixture.events.segments.single.id, segmentBefore.id);
      expect(fixture.events.segments.single.startedAt, segmentBefore.startedAt);
      expect(fixture.events.segments.single.endedAt, isNull);
      expect(fixture.events.events.single.status, EventStatus.running);
      expect(fixture.events.eventDayPlans, isEmpty);
    },
  );

  testWidgets(
    'cancel is a no-op and standalone Event has no refinement action',
    (tester) async {
      await _setViewport(tester, const Size(360, 800), textScaleFactor: 1.3);
      final fixture = _Fixture.current();
      await tester.pumpWidget(fixture.app());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('home-running-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('补充计划步骤…'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('plan-item-initial-status')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(fixture.planning.items, hasLength(1));

      final now = _time(20);
      final standaloneRepository =
          MemoryRepository([
              JaxEvent(
                id: 'standalone',
                name: 'Standalone',
                status: EventStatus.running,
                firstStartedAt: _time(10),
                createdAt: _time(1),
                updatedAt: _time(10),
              ),
            ])
            ..segments.add(
              RunSegment(
                id: 'standalone-open',
                eventId: 'standalone',
                startedAt: _time(10),
                createdAt: _time(10),
              ),
            );
      final controller = EventController(
        repository: standaloneRepository,
        newId: () => 'unused',
        now: () => now,
      );
      await controller.load();
      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(
            controller: controller,
            now: () => now,
            onOpenEvents: () {},
            onAddPlanStep: (_, _) async {},
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('home-running-more')));
      await tester.pumpAndSettle();
      expect(find.text('补充计划步骤…'), findsNothing);
      controller.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('ended source uses current round after an explicit choice', (
    tester,
  ) async {
    final fixture = _Fixture.endedWithCurrent();
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-running-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('补充计划步骤…'));
    await tester.pumpAndSettle();

    expect(find.text('来源计划已经结束'), findsOneWidget);
    expect(find.text('补充到当前计划'), findsOneWidget);
    await tester.tap(find.text('补充到当前计划'));
    await tester.pumpAndSettle();
    expect(find.text('当前计划 · 第 2 轮'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('plan-item-title')),
      '新一轮步骤',
    );
    await tester.tap(find.byKey(const ValueKey('add-plan-item')));
    await tester.pumpAndSettle();
    expect(fixture.planning.items.last.planId, 'current-plan');
    expect(fixture.planning.items.first.planId, 'source-plan');
  });

  testWidgets('ended source without current round offers new round', (
    tester,
  ) async {
    final fixture = _Fixture.endedWithoutCurrent();
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-running-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('补充计划步骤…'));
    await tester.pumpAndSettle();
    expect(find.text('添加新一轮'), findsOneWidget);
    await tester.tap(find.text('添加新一轮'));
    await tester.pumpAndSettle();
    expect(find.text('当前计划 · 第 2 轮'), findsOneWidget);
    expect(fixture.planning.plans.last.status, PlanStatus.current);
  });

  testWidgets('completed WorldNode requires explicit restoration', (
    tester,
  ) async {
    final fixture = _Fixture.endedWithoutCurrent(completed: true);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-running-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('补充计划步骤…'));
    await tester.pumpAndSettle();
    expect(find.text('世界节点已经完成'), findsOneWidget);
    expect(find.textContaining('先在“世界”中恢复'), findsOneWidget);
    expect(find.text('添加新一轮'), findsNothing);
    expect(fixture.world.nodes.single.status, WorldNodeStatus.completed);
  });
}

class _Fixture {
  _Fixture({required this.events, required this.planning, required this.world});

  factory _Fixture.current() => _build(sourceEnded: false);
  factory _Fixture.endedWithCurrent() =>
      _build(sourceEnded: true, withCurrent: true);
  factory _Fixture.endedWithoutCurrent({bool completed = false}) =>
      _build(sourceEnded: true, completed: completed);

  static _Fixture _build({
    required bool sourceEnded,
    bool withCurrent = false,
    bool completed = false,
  }) {
    final sourcePlan = Plan(
      id: 'source-plan',
      worldNodeId: 'node',
      status: sourceEnded ? PlanStatus.ended : PlanStatus.current,
      roundNumber: 1,
      createdAt: _time(1),
      updatedAt: _time(2),
      endedAt: sourceEnded ? _time(2) : null,
    );
    final plans = <Plan>[sourcePlan];
    if (withCurrent) {
      plans.add(
        Plan(
          id: 'current-plan',
          worldNodeId: 'node',
          status: PlanStatus.current,
          roundNumber: 2,
          createdAt: _time(3),
          updatedAt: _time(3),
        ),
      );
    }
    final planning = _PlanningRepository(
      plans: plans,
      items: [
        PlanItem(
          id: 'source-item',
          planId: sourcePlan.id,
          title: '执行中的步骤',
          status: PlanItemStatus.dispatched,
          sortOrder: 0,
          createdAt: _time(1),
          updatedAt: _time(1),
        ),
      ],
    );
    final event = JaxEvent(
      id: 'event',
      name: '执行中的步骤',
      status: EventStatus.running,
      sourcePlanItemId: 'source-item',
      firstStartedAt: _time(10),
      createdAt: _time(1),
      updatedAt: _time(10),
    );
    final events = MemoryRepository([event])
      ..segments.add(
        RunSegment(
          id: 'open',
          eventId: event.id,
          startedAt: _time(10),
          createdAt: _time(10),
        ),
      );
    final world = _WorldRepository([
      WorldNode(
        id: 'node',
        name: '论文',
        status: completed
            ? WorldNodeStatus.completed
            : WorldNodeStatus.inProgress,
        isFocused: false,
        sortOrder: 0,
        createdAt: _time(1),
        updatedAt: _time(1),
      ),
    ]);
    return _Fixture(events: events, planning: planning, world: world);
  }

  final MemoryRepository events;
  final _PlanningRepository planning;
  final _WorldRepository world;

  Widget app() {
    var sequence = 0;
    return JaxApp(
      repository: events,
      planningRepository: planning,
      worldNodeRepository: world,
      newId: () => 'generated-${sequence++}',
      now: () => _time(20),
    );
  }
}

class _PlanningRepository implements PlanningRepository {
  _PlanningRepository({required this.plans, required this.items});

  final List<Plan> plans;
  final List<PlanItem> items;

  @override
  Future<List<Plan>> getPlans() async => List.of(plans);

  @override
  Future<Plan?> getPlan(String id) async =>
      plans.where((plan) => plan.id == id).firstOrNull;

  @override
  Future<List<PlanItem>> getPlanItems(String planId) async =>
      items.where((item) => item.planId == planId).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  @override
  Future<List<PlanReviewNote>> getPlanReviewNotes(String planId) async => [];

  @override
  Future<Plan> createPlan({
    required String id,
    required String worldNodeId,
    String? title,
    required DateTime now,
  }) async {
    final round =
        plans
            .where((plan) => plan.worldNodeId == worldNodeId)
            .fold<int>(
              0,
              (value, plan) =>
                  value < plan.roundNumber ? plan.roundNumber : value,
            ) +
        1;
    final plan = Plan(
      id: id,
      worldNodeId: worldNodeId,
      status: PlanStatus.current,
      roundNumber: round,
      title: title,
      createdAt: now,
      updatedAt: now,
    );
    plans.add(plan);
    return plan;
  }

  @override
  Future<PlanItem> createPlanItem({
    required String id,
    required String planId,
    required String title,
    String? note,
    PlanItemStatus initialStatus = PlanItemStatus.draft,
    required DateTime now,
  }) async {
    final plan = await getPlan(planId);
    if (plan == null || !plan.isCurrent) throw StateError('stale plan');
    final order = items.where((item) => item.planId == planId).length;
    final item = PlanItem(
      id: id,
      planId: planId,
      title: title.trim(),
      note: note,
      status: initialStatus,
      sortOrder: order,
      createdAt: now,
      updatedAt: now,
    );
    items.add(item);
    return item;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _WorldRepository implements WorldNodeRepository {
  _WorldRepository(this.nodes);
  final List<WorldNode> nodes;

  @override
  Future<List<WorldNode>> getWorldNodes() async => List.of(nodes);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

DateTime _time(int minute) => DateTime.utc(2026, 9, 4, 10, minute);

Future<void> _setViewport(
  WidgetTester tester,
  Size size, {
  double textScaleFactor = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.platformDispatcher.textScaleFactorTestValue = textScaleFactor;
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
}
