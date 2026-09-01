import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/category.dart';
import 'package:jax/core/entities/plan.dart';
import 'package:jax/core/entities/plan_item.dart';
import 'package:jax/core/entities/world_node.dart';
import 'package:jax/core/preferences/world_category_collapse_store.dart';
import 'package:jax/core/repositories/planning_repository.dart';
import 'package:jax/core/repositories/world_node_repository.dart';
import 'package:jax/ui/controllers/planning_controller.dart';
import 'package:jax/ui/pages/planning_page.dart';
import 'package:jax/ui/pages/world_page.dart';

import '../support/memory_repository.dart';

void main() {
  late MemoryRepository events;
  late _WorldRepository nodes;
  late _PlanningRepository plans;
  late PlanningController controller;

  setUp(() {
    events = MemoryRepository();
    nodes = _WorldRepository();
    plans = _PlanningRepository();
    var sequence = 0;
    controller = PlanningController(
      planningRepository: plans,
      worldNodeRepository: nodes,
      eventRepository: events,
      newId: () => 'generated-${sequence++}',
      now: () => _time(100 + sequence),
    );
    events.categories.addAll([
      _category('a', 'Category A', 0),
      _category('b', 'Category B', 1),
    ]);
  });

  tearDown(() => controller.dispose());

  testWidgets('picker groups categories, collapses branches, and explains disabled nodes', (
    tester,
  ) async {
    await _seedPickerTree(nodes, plans);
    await tester.pumpWidget(
      MaterialApp(home: PlanningPage(controller: controller)),
    );
    await _pumpFrames(tester);
    await tester.tap(find.byKey(const ValueKey('add-plan')));
    await _pumpFrames(tester);

    expect(find.text('Category A'), findsOneWidget);
    expect(find.text('Category B'), findsOneWidget);
    expect(find.text('Child A1'), findsOneWidget);
    await tester.drag(
      find.byKey(const ValueKey('planning-world-node-selector')),
      const Offset(0, -100),
    );
    await _pumpFrames(tester);
    expect(
      find.byKey(
        const ValueKey(
          'select-world-node-66666666-6666-4666-8666-666666666666',
        ),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('已完成：只能查看历史'), findsOneWidget);
    expect(find.textContaining('已有当前计划'), findsOneWidget);
    expect(
      tester.widget<ListTile>(
        find.byKey(
          const ValueKey(
            'select-world-node-55555555-5555-4555-8555-555555555555',
          ),
        ),
      ).enabled,
      isFalse,
    );
    expect(
      tester.widget<ListTile>(
        find.byKey(
          const ValueKey(
            'select-world-node-66666666-6666-4666-8666-666666666666',
          ),
        ),
      ).enabled,
      isFalse,
    );

    await tester.drag(
      find.byKey(const ValueKey('planning-world-node-selector')),
      const Offset(0, 100),
    );
    await _pumpFrames(tester);
    await tester.tap(
      find.descendant(
        of: find.byKey(
          const ValueKey(
            'select-world-node-11111111-1111-4111-8111-111111111111',
          ),
        ),
        matching: find.byType(IconButton),
      ),
    );
    await _pumpFrames(tester);
    expect(find.text('Child A1'), findsNothing);
    expect(
      find.byKey(
        const ValueKey(
          'select-world-node-66666666-6666-4666-8666-666666666666',
        ),
      ),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('planning-selector-category-a')),
    );
    await _pumpFrames(tester);
    expect(find.text('Root A'), findsNothing);
    expect(find.text('Root B'), findsNothing);
    expect(find.text('Root C'), findsOneWidget);
    await tester.drag(
      find.byKey(const ValueKey('planning-world-node-selector')),
      const Offset(0, -400),
    );
    await _pumpFrames(tester);
    expect(find.text('未分类'), findsOneWidget);
    expect(find.text('Root D'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await _pumpFrames(tester);
  });

  testWidgets('WorldNode More exposes create, current, next round, and history states', (
    tester,
  ) async {
    final noPlan = _node('11111111-1111-4111-8111-111111111111', 'No plan');
    final current = _node('22222222-2222-4222-8222-222222222222', 'Current');
    final history = _node('33333333-3333-4333-8333-333333333333', 'History');
    final completed = _node(
      '44444444-4444-4444-8444-444444444444',
      'Completed',
      status: WorldNodeStatus.completed,
    );
    for (final node in [noPlan, current, history, completed]) {
      nodes.nodes.add(node);
    }
    await plans.createPlan(id: 'current', worldNodeId: current.id, now: _time(2));
    final ended = await plans.createPlan(
      id: 'history',
      worldNodeId: history.id,
      now: _time(2),
    );
    await plans.setPlanStatus(ended.id, PlanStatus.ended, _time(3));
    plans.plans.add(
      Plan(
        id: 'completed-history',
        worldNodeId: completed.id,
        status: PlanStatus.ended,
        roundNumber: 1,
        endedAt: _time(3),
        createdAt: _time(2),
        updatedAt: _time(3),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: WorldPage(
          controller: controller,
          worldCategoryCollapseStore: InMemoryWorldCategoryCollapseStore(),
        ),
      ),
    );
    await _pumpFrames(tester);

    await _openMenu(tester, noPlan.id);
    expect(find.text('添加计划'), findsOneWidget);
    await _dismissMenu(tester);

    await _openMenu(tester, current.id);
    expect(find.text('查看当前计划'), findsOneWidget);
    expect(find.text('添加计划'), findsNothing);
    await _dismissMenu(tester);

    await _openMenu(tester, history.id);
    expect(find.text('添加新一轮计划'), findsOneWidget);
    expect(find.text('查看历史计划'), findsOneWidget);
    await _dismissMenu(tester);

    await _openMenu(tester, completed.id);
    expect(find.text('查看历史计划'), findsOneWidget);
    expect(find.text('添加计划'), findsNothing);
    expect(find.text('添加新一轮计划'), findsNothing);
    await _dismissMenu(tester);
  });
}

Future<void> _seedPickerTree(
  _WorldRepository nodes,
  _PlanningRepository plans,
) async {
  final rootA = _node('11111111-1111-4111-8111-111111111111', 'Root A');
  final rootB = _node('22222222-2222-4222-8222-222222222222', 'Root B', order: 1);
  final rootC = _node(
    '33333333-3333-4333-8333-333333333333',
    'Root C',
    categoryId: 'b',
  );
  final rootD = _node(
    '44444444-4444-4444-8444-444444444444',
    'Root D',
    categoryId: null,
  );
  final childA1 = _node(
    '55555555-5555-4555-8555-555555555555',
    'Child A1',
    parentId: rootA.id,
    categoryId: null,
    status: WorldNodeStatus.completed,
  );
  final childA2 = _node(
    '66666666-6666-4666-8666-666666666666',
    'Child A2',
    parentId: rootA.id,
    categoryId: null,
    order: 1,
  );
  for (final node in [rootA, rootB, rootC, rootD, childA1, childA2]) {
    nodes.nodes.add(node);
  }
  await plans.createPlan(id: 'occupied', worldNodeId: childA2.id, now: _time(2));
}

Category _category(String id, String name, int order) => Category(
  id: id,
  name: name,
  sortOrder: order,
  colorKey: order,
  createdAt: _time(1),
  updatedAt: _time(1),
);

WorldNode _node(
  String id,
  String name, {
  String? parentId,
  String? categoryId = 'a',
  int order = 0,
  WorldNodeStatus status = WorldNodeStatus.inProgress,
}) => WorldNode(
  id: id,
  name: name,
  status: status,
  parentWorldNodeId: parentId,
  categoryId: categoryId,
  sortOrder: order,
  createdAt: _time(1),
  updatedAt: _time(1),
);

Future<void> _openMenu(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(ValueKey('world-node-more-$id')));
  await _pumpFrames(tester);
}

Future<void> _dismissMenu(WidgetTester tester) async {
  await tester.tapAt(const Offset(4, 4));
  await _pumpFrames(tester);
}

Future<void> _pumpFrames(WidgetTester tester) async {
  for (var index = 0; index < 8; index++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

DateTime _time(int value) =>
    DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);

class _WorldRepository implements WorldNodeRepository {
  final nodes = <WorldNode>[];

  @override
  Future<List<WorldNode>> getWorldNodes() async => List.unmodifiable(nodes);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PlanningRepository implements PlanningRepository {
  final plans = <Plan>[];

  @override
  Future<List<Plan>> getPlans() async => List.unmodifiable(plans);

  @override
  Future<List<PlanItem>> getPlanItems(String planId) async => const [];

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
            .map((plan) => plan.roundNumber)
            .fold(0, (left, right) => left > right ? left : right) +
        1;
    final plan = Plan(
      id: id,
      worldNodeId: worldNodeId,
      title: title,
      status: PlanStatus.focused,
      roundNumber: round,
      createdAt: now,
      updatedAt: now,
    );
    plans.add(plan);
    return plan;
  }

  @override
  Future<void> setPlanStatus(String id, PlanStatus status, DateTime now) async {
    final index = plans.indexWhere((plan) => plan.id == id);
    final old = plans[index];
    plans[index] = Plan(
      id: old.id,
      worldNodeId: old.worldNodeId,
      title: old.title,
      status: status,
      roundNumber: old.roundNumber,
      endedAt: status == PlanStatus.ended ? now : null,
      createdAt: old.createdAt,
      updatedAt: now,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
