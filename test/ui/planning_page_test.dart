import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/plan.dart';
import 'package:jax/core/entities/plan_item.dart';
import 'package:jax/core/entities/world_node.dart';
import 'package:jax/core/repositories/planning_repository.dart';
import 'package:jax/core/repositories/world_node_repository.dart';
import 'package:jax/ui/controllers/planning_controller.dart';
import 'package:jax/ui/pages/planning_page.dart';

import '../support/memory_repository.dart';

void main() {
  testWidgets('focused WorldNode without a Plan appears in the overview', (
    tester,
  ) async {
    const nodeId = '11111111-1111-4111-8111-111111111111';
    final controller = PlanningController(
      planningRepository: _PlanningRepository(),
      worldNodeRepository: _WorldRepository([
        WorldNode(
          id: nodeId,
          name: 'Only attention',
          status: WorldNodeStatus.inProgress,
          isFocused: true,
          sortOrder: 0,
          createdAt: _time(1),
          updatedAt: _time(1),
        ),
      ]),
      eventRepository: MemoryRepository(),
      newId: () => 'unused',
      now: () => _time(10),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: PlanningPage(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('focused-world-node-$nodeId')),
      findsOneWidget,
    );
    expect(find.textContaining('暂无当前计划'), findsOneWidget);
    expect(find.byKey(const ValueKey('add-plan-for-$nodeId')), findsOneWidget);
  });

  testWidgets('creates Plan and quickly toggles a PlanItem next state', (
    tester,
  ) async {
    const nodeId = '11111111-1111-4111-8111-111111111111';
    final node = WorldNode(
      id: nodeId,
      name: 'Jax Planning',
      status: WorldNodeStatus.inProgress,
      isFocused: true,
      sortOrder: 0,
      createdAt: _time(1),
      updatedAt: _time(1),
    );
    final plans = _PlanningRepository();
    var sequence = 0;
    final controller = PlanningController(
      planningRepository: plans,
      worldNodeRepository: _WorldRepository([node]),
      eventRepository: MemoryRepository(),
      newId: () => 'generated-${sequence++}',
      now: () => _time(10 + sequence),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(home: PlanningPage(controller: controller)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('add-plan')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('select-world-node-$nodeId')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('select-world-node-$nodeId')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('plan-detail')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('add-plan-item')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('plan-item-title')),
      '设计 schema',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('设计 schema'), findsOneWidget);
    expect(plans.items.single.status, PlanItemStatus.draft);

    await tester.tap(find.byKey(const ValueKey('toggle-next-generated-1')));
    await tester.pumpAndSettle();
    expect(plans.items.single.status, PlanItemStatus.next);
  });
}

class _WorldRepository implements WorldNodeRepository {
  _WorldRepository(this.nodes);
  final List<WorldNode> nodes;

  @override
  Future<List<WorldNode>> getWorldNodes() async => nodes;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PlanningRepository implements PlanningRepository {
  final plans = <Plan>[];
  final items = <PlanItem>[];

  @override
  Future<List<Plan>> getPlans() async => List.unmodifiable(plans);

  @override
  Future<Plan?> getPlan(String id) async =>
      plans.where((plan) => plan.id == id).firstOrNull;

  @override
  Future<List<PlanItem>> getPlanItems(String planId) async =>
      items.where((item) => item.planId == planId).toList();

  @override
  Future<Plan> createPlan({
    required String id,
    required String worldNodeId,
    String? title,
    required DateTime now,
  }) async {
    final plan = Plan(
      id: id,
      worldNodeId: worldNodeId,
      status: PlanStatus.current,
      roundNumber: 1,
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
    final item = PlanItem(
      id: id,
      planId: planId,
      title: title,
      note: note,
      status: initialStatus,
      sortOrder: items.length,
      createdAt: now,
      updatedAt: now,
    );
    items.add(item);
    return item;
  }

  @override
  Future<void> setPlanItemStatus(
    String id,
    PlanItemStatus status,
    DateTime now,
  ) async {
    final index = items.indexWhere((item) => item.id == id);
    final item = items[index];
    items[index] = PlanItem(
      id: item.id,
      planId: item.planId,
      title: item.title,
      note: item.note,
      status: status,
      sortOrder: item.sortOrder,
      createdAt: item.createdAt,
      updatedAt: now,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

DateTime _time(int value) =>
    DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
