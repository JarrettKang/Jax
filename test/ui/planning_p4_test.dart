import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/plan.dart';
import 'package:jax/core/entities/plan_item.dart';
import 'package:jax/core/entities/world_node.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/repositories/sqlite_event_repository.dart';
import 'package:jax/data/repositories/sqlite_planning_repository.dart';
import 'package:jax/data/repositories/sqlite_world_node_repository.dart';
import 'package:jax/data/sync/sqlite_sync_snapshot_adapter.dart';
import 'package:jax/ui/controllers/planning_controller.dart';
import 'package:jax/ui/pages/planning_page.dart';
import 'package:jax/ui/pages/world_node_detail_page.dart';

void main() {
  late AppDatabase app;
  late SqlitePlanningRepository planning;
  late SqliteWorldNodeRepository world;
  late PlanningController controller;
  late Plan historical;

  setUp(() async {
    app = await AppDatabase.inMemory();
    planning = SqlitePlanningRepository(app);
    world = SqliteWorldNodeRepository(app);
    final eventRepository = SqliteEventRepository(app);
    var id = 900;
    controller = PlanningController(
      planningRepository: planning,
      worldNodeRepository: world,
      eventRepository: eventRepository,
      newId: () =>
          '00000000-0000-4000-8000-${(id++).toString().padLeft(12, '0')}',
      now: () => _time(1000),
    );
    final node = WorldNode(
      id: _nodeId,
      name: 'Jax Project',
      status: WorldNodeStatus.inProgress,
      sortOrder: 0,
      createdAt: _time(1),
      updatedAt: _time(1),
    );
    await world.insertWorldNode(node);
    historical = await planning.createPlan(
      id: 'historical',
      worldNodeId: node.id,
      title: 'First round',
      now: _time(2),
    );
    await planning.createPlanItem(
      id: 'history-item',
      planId: historical.id,
      title: 'Planned execution',
      now: _time(3),
    );
    await planning.createPlanReviewNote(
      id: '22222222-2222-4222-8222-222222222222',
      planId: historical.id,
      content: 'Keep the useful part',
      now: _time(4),
    );
    await planning.setPlanStatus(historical.id, PlanStatus.ended, _time(5));
    await app.database.update(
      'plan_items',
      {'status': PlanItemStatus.done.name, 'updated_at_utc': 8},
      where: 'id = ?',
      whereArgs: ['history-item'],
    );
    await app.database.insert('events', {
      'id': 'planned-event',
      'name': 'Planned execution',
      'status': 'completed',
      'source_plan_item_id': 'history-item',
      'category_id': null,
      'first_started_at_utc': 6,
      'completed_at_utc': 8,
      'created_at_utc': 6,
      'updated_at_utc': 8,
    });
    await app.database.insert('run_segments', {
      'id': 'planned-segment',
      'event_id': 'planned-event',
      'started_at_utc': 6,
      'ended_at_utc': 8,
      'created_at_utc': 6,
      'updated_at_utc': 8,
    });
    await app.database.insert('events', {
      'id': 'standalone-event',
      'name': 'Standalone should be excluded',
      'status': 'completed',
      'source_plan_item_id': null,
      'category_id': null,
      'first_started_at_utc': 9,
      'completed_at_utc': 11,
      'created_at_utc': 9,
      'updated_at_utc': 11,
    });
    await app.database.insert('run_segments', {
      'id': 'standalone-segment',
      'event_id': 'standalone-event',
      'started_at_utc': 9,
      'ended_at_utc': 11,
      'created_at_utc': 9,
      'updated_at_utc': 11,
    });
    final current = await planning.createPlan(
      id: 'current',
      worldNodeId: node.id,
      title: 'Second round',
      now: _time(12),
    );
    await planning.createPlanItem(
      id: 'current-item',
      planId: current.id,
      title: 'Next action',
      now: _time(13),
    );
    await planning.setPlanItemStatus(
      'current-item',
      PlanItemStatus.next,
      _time(14),
    );
    await planning.setPlanStatus(current.id, PlanStatus.waiting, _time(15));
    await controller.load();
  });

  tearDown(() async {
    controller.dispose();
    await app.close();
  });

  testWidgets(
    'WorldNode detail derives exact-node plans and execution without mutation',
    (tester) async {
      final before = await tester.runAsync(
        () => SqliteSyncSnapshotAdapter(app.database).read(),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: WorldNodeDetailPage(
            controller: controller,
            worldNodeId: _nodeId,
          ),
        ),
      );
      await _pumpFrames(tester);

      expect(find.byKey(const ValueKey('world-node-detail')), findsOneWidget);
      expect(find.text('概览'), findsOneWidget);
      expect(find.text('Second round'), findsOneWidget);
      expect(find.textContaining('等待中 · 第 2 轮'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('执行历史'),
        250,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Planned execution'), findsOneWidget);
      expect(find.text('Standalone should be excluded'), findsNothing);
      expect(find.textContaining('直接用时'), findsOneWidget);
      expect(tester.takeException(), isNull);

      final after = await tester.runAsync(
        () => SqliteSyncSnapshotAdapter(app.database).read(),
      );
      expect(after!.businessFingerprint, before!.businessFingerprint);
    },
  );

  testWidgets('ended Plan offers a multiline review editor on a narrow screen', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: PlanDetailPage(controller: controller, planId: historical.id),
      ),
    );
    await _pumpFrames(tester);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('add-review-note')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const ValueKey('add-review-note')));
    await _pumpFrames(tester);
    await tester.enterText(
      find.byKey(const ValueKey('review-note-content')),
      'Line one\nLine two',
    );
    expect(find.text('Line one\nLine two'), findsOneWidget);
    expect(find.byKey(const ValueKey('save-review-note')), findsOneWidget);
    await tester.tap(find.text('取消'));
    await _pumpFrames(tester);
    expect(tester.takeException(), isNull);
  });
}

const _nodeId = '11111111-1111-4111-8111-111111111111';
DateTime _time(int value) =>
    DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);

Future<void> _pumpFrames(WidgetTester tester) async {
  for (var index = 0; index < 12; index++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
