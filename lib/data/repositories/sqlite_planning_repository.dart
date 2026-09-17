import 'package:sqflite/sqflite.dart';

import '../../core/entities/plan.dart';
import '../../core/entities/world_node.dart';
import '../../core/entities/world_node_ids.dart';
import '../../core/repositories/planning_promotion_repository.dart';
import '../../core/entities/plan_item.dart';
import '../../core/entities/plan_review_note.dart';
import '../../core/entities/event_status.dart';
import '../../core/entities/jax_event.dart';
import '../../core/errors/domain_failure.dart';
import '../../core/repositories/planning_dispatch_repository.dart';
import '../../core/repositories/planning_execution_repository.dart';
import '../../core/repositories/planning_repository.dart';
import '../database/app_database.dart';

class SqlitePlanningRepository
    implements
        PlanningRepository,
        PlanningDispatchRepository,
        PlanningExecutionRepository,
        PlanningPromotionRepository,
        FirstPlanningStepRepository {
  const SqlitePlanningRepository(this._app);
  final AppDatabase _app;

  @override
  Future<WorldNode> promotePlanItem({
    required String planItemId,
    required String worldNodeId,
    required DateTime now,
  }) => _app.database.transaction((tx) async {
    if (!WorldNodeIds.isValid(worldNodeId)) {
      throw const DomainFailure('世界节点 ID 必须为 UUID');
    }
    final item = await _requireItem(tx, planItemId);
    if (!item.isExecutable) {
      throw const DomainFailure('只有尚未执行的普通计划步骤可以提升');
    }
    await _requireEditablePlan(tx, item.planId);
    final linkedEvents = await tx.query(
      'events',
      columns: ['id'],
      where: 'source_plan_item_id = ?',
      whereArgs: [planItemId],
      limit: 1,
    );
    if (linkedEvents.isNotEmpty) {
      throw const DomainFailure('已有执行事项的步骤不能提升');
    }
    final parent = (await tx.rawQuery(
      '''
      SELECT n.id, n.is_focused FROM plans p
      JOIN world_nodes n ON n.id = p.world_node_id WHERE p.id = ?
      ''',
      [item.planId],
    )).single;
    final nextOrder =
        (await tx.rawQuery(
              '''
      SELECT COALESCE(MAX(sort_order), -1) + 1 value FROM world_nodes
      WHERE parent_world_node_id = ?
      ''',
              [parent['id']],
            )).single['value']!
            as int;
    final utc = now.toUtc();
    final node = WorldNode(
      id: worldNodeId,
      name: item.title,
      status: WorldNodeStatus.inProgress,
      isFocused: parent['is_focused'] == 1,
      parentWorldNodeId: parent['id']! as String,
      sortOrder: nextOrder,
      createdAt: utc,
      updatedAt: utc,
    );
    await tx.insert('world_nodes', {
      'id': node.id,
      'name': node.name,
      'status': 'inProgress',
      'is_focused': node.isFocused ? 1 : 0,
      'parent_world_node_id': node.parentWorldNodeId,
      'category_id': null,
      'sort_order': node.sortOrder,
      'created_at_utc': utc.millisecondsSinceEpoch,
      'updated_at_utc': utc.millisecondsSinceEpoch,
    });
    final changed = await tx.update(
      'plan_items',
      {
        'promoted_world_node_id': node.id,
        'updated_at_utc': utc.millisecondsSinceEpoch,
      },
      where: "id = ? AND status IN ('next','draft') AND promoted_world_node_id IS NULL",
      whereArgs: [item.id],
    );
    if (changed != 1) throw const DomainFailure('步骤已变化，请刷新后重试');
    return node;
  });

  @override
  Future<JaxEvent> startPlanItem({
    required String planItemId,
    required String eventId,
    required String segmentId,
    required String dayKey,
    required DateTime now,
  }) => _app.database.transaction((tx) async {
    final utc = now.toUtc();
    final stamp = utc.millisecondsSinceEpoch;
    final rows = await tx.rawQuery(
      '''
      SELECT i.title FROM plan_items i
      JOIN plans p ON p.id = i.plan_id
      JOIN world_nodes n ON n.id = p.world_node_id
      WHERE i.id = ? AND i.status IN ('next', 'draft')
        AND i.promoted_world_node_id IS NULL
        AND p.status = 'current' AND n.status = 'inProgress'
        AND n.is_focused = 1
        AND NOT EXISTS (SELECT 1 FROM events e WHERE e.source_plan_item_id = i.id)
      ''',
      [planItemId],
    );
    if (rows.length != 1) {
      throw const DomainFailure('计划步骤已变化，请刷新后重试');
    }
    // Pause the previous Event or Routine inside this same transaction. Reject
    // incomplete timing facts, rather than silently manufacturing execution.
    for (final owner in [
      ('events', 'run_segments', 'event_id'),
      ('routine_executions', 'routine_run_segments', 'routine_execution_id'),
    ]) {
      final running = await tx.query(owner.$1, where: "status = 'running'");
      for (final previous in running) {
        final open = await tx.query(
          owner.$2,
          where: '${owner.$3} = ? AND ended_at_utc IS NULL',
          whereArgs: [previous['id']],
        );
        if (open.length != 1 ||
            (open.single['started_at_utc']! as int) > stamp) {
          throw const DomainFailure('执行计时数据不完整或开始时间无效');
        }
        await tx.update(
          owner.$2,
          {'ended_at_utc': stamp},
          where: 'id = ?',
          whereArgs: [open.single['id']],
        );
        await tx.update(
          owner.$1,
          {'status': 'paused', 'updated_at_utc': stamp},
          where: 'id = ?',
          whereArgs: [previous['id']],
        );
      }
    }
    final event = JaxEvent(
      id: eventId,
      name: rows.single['title']! as String,
      status: EventStatus.running,
      sourcePlanItemId: planItemId,
      firstStartedAt: utc,
      createdAt: utc,
      updatedAt: utc,
    );
    await tx.insert('events', {
      'id': eventId,
      'name': event.name,
      'status': 'running',
      'source_plan_item_id': planItemId,
      'category_id': null,
      'first_started_at_utc': stamp,
      'completed_at_utc': null,
      'created_at_utc': stamp,
      'updated_at_utc': stamp,
    });
    final updated = await tx.update(
      'plan_items',
      {'status': 'dispatched', 'updated_at_utc': stamp},
      where: "id = ? AND status IN ('next','draft')",
      whereArgs: [planItemId],
    );
    if (updated != 1) throw const DomainFailure('计划步骤开始冲突');
    final order = await tx.rawQuery(
      'SELECT COALESCE(MAX(order_index), -1) + 1 value FROM event_day_plans WHERE day_date = ?',
      [dayKey],
    );
    await tx.insert('event_day_plans', {
      'event_id': eventId,
      'day_date': dayKey,
      'order_index': order.single['value'],
      'created_at_utc': stamp,
      'updated_at_utc': stamp,
    });
    await tx.insert('run_segments', {
      'id': segmentId,
      'event_id': eventId,
      'started_at_utc': stamp,
      'ended_at_utc': null,
      'created_at_utc': stamp,
    });
    return event;
  });

  @override
  Future<Plan> createFirstPlanningStep({
    required String planId,
    required String itemId,
    required String worldNodeId,
    required String title,
    String? note,
    PlanItemStatus initialStatus = PlanItemStatus.next,
    required DateTime now,
  }) => _app.database.transaction((tx) async {
    final history = await tx.query(
      'plans',
      columns: ['id'],
      where: 'world_node_id = ?',
      whereArgs: [worldNodeId],
      limit: 1,
    );
    if (history.isNotEmpty) {
      throw const DomainFailure('计划已变化，请返回重新打开；历史计划需要明确开始新一轮');
    }
    final plan = await _createPlan(
      tx,
      id: planId,
      worldNodeId: worldNodeId,
      now: now,
    );
    await _createPlanItem(
      tx,
      id: itemId,
      planId: plan.id,
      title: title,
      note: note,
      initialStatus: initialStatus,
      now: now,
    );
    return plan;
  });

  @override
  Future<List<JaxEvent>> dispatchPlanItems({
    required Map<String, String> eventIdsByPlanItemId,
    required String dayKey,
    required DateTime now,
  }) async {
    if (eventIdsByPlanItemId.isEmpty) {
      throw const DomainFailure('请至少选择一个计划步骤');
    }
    final utc = now.toUtc();
    try {
      return await _app.database.transaction((tx) async {
        final existingToday = await tx.rawQuery(
          'SELECT COALESCE(MAX(order_index), -1) value '
          'FROM event_day_plans WHERE day_date = ?',
          [dayKey],
        );
        var nextTodayOrder = (existingToday.single['value'] as num).toInt() + 1;
        final dispatched = <JaxEvent>[];
        for (final entry in eventIdsByPlanItemId.entries) {
          final rows = await tx.rawQuery(
            '''SELECT item.title, item.status item_status, item.promoted_world_node_id,
                      plan.status plan_status, node.status node_status,
                      node.is_focused node_is_focused
               FROM plan_items item
               JOIN plans plan ON plan.id = item.plan_id
               JOIN world_nodes node ON node.id = plan.world_node_id
               WHERE item.id = ? LIMIT 1''',
            [entry.key],
          );
          if (rows.isEmpty) throw const DomainFailure('计划项不存在');
          if (rows.single['plan_status'] != 'current' ||
              rows.single['node_status'] != 'inProgress' ||
              rows.single['node_is_focused'] != 1) {
            throw const DomainFailure('只有关注中世界节点的当前计划步骤可以加入今日');
          }
          if (rows.single['promoted_world_node_id'] != null ||
              !{'draft', 'next'}.contains(rows.single['item_status'])) {
            throw const DomainFailure('计划项已变化，请刷新后重试');
          }
          final linked = await tx.query(
            'events',
            columns: ['id'],
            where: 'source_plan_item_id = ?',
            whereArgs: [entry.key],
            limit: 1,
          );
          if (linked.isNotEmpty) {
            throw const DomainFailure('计划项已经派发');
          }
          final event = JaxEvent(
            id: entry.value,
            name: rows.single['title']! as String,
            status: EventStatus.pending,
            sourcePlanItemId: entry.key,
            createdAt: utc,
            updatedAt: utc,
          );
          await tx.insert('events', {
            'id': event.id,
            'name': event.name,
            'status': event.status.name,
            'source_plan_item_id': event.sourcePlanItemId,
            'category_id': null,
            'first_started_at_utc': null,
            'completed_at_utc': null,
            'created_at_utc': utc.millisecondsSinceEpoch,
            'updated_at_utc': utc.millisecondsSinceEpoch,
          });
          final updated = await tx.update(
            'plan_items',
            {
              'status': PlanItemStatus.dispatched.name,
              'updated_at_utc': utc.millisecondsSinceEpoch,
            },
            where: "id = ? AND status IN ('draft','next')",
            whereArgs: [entry.key],
          );
          if (updated != 1) {
            throw const DomainFailure('计划项派发冲突，请刷新后重试');
          }
          await tx.insert('event_day_plans', {
            'event_id': event.id,
            'day_date': dayKey,
            'order_index': nextTodayOrder++,
            'created_at_utc': utc.millisecondsSinceEpoch,
            'updated_at_utc': utc.millisecondsSinceEpoch,
          });
          dispatched.add(event);
        }
        return dispatched;
      });
    } on DatabaseException catch (_) {
      throw const DomainFailure('计划项派发冲突，请刷新后重试');
    }
  }

  @override
  Future<void> withdrawPlanItem({
    required String planItemId,
    required DateTime now,
  }) => _app.database.transaction((tx) async {
    final rows = await tx.rawQuery(
      '''
      SELECT e.id FROM events e
      JOIN plan_items i ON i.id = e.source_plan_item_id
      WHERE i.id = ? AND i.status = 'dispatched'
        AND e.status = 'pending'
        AND e.first_started_at_utc IS NULL AND e.completed_at_utc IS NULL
        AND NOT EXISTS (SELECT 1 FROM run_segments s WHERE s.event_id = e.id)
      ''',
      [planItemId],
    );
    if (rows.length != 1) {
      throw const DomainFailure('只有从未执行过的已派发事项可以收回到计划');
    }
    final eventId = rows.single['id']! as String;
    // Explicitly remove every JaxDay, including carry-over/history. Existing
    // DELETE triggers record both day-plan and Event tombstones in this txn.
    await tx.delete(
      'event_day_plans',
      where: 'event_id = ?',
      whereArgs: [eventId],
    );
    await tx.delete('events', where: 'id = ?', whereArgs: [eventId]);
    final updated = await tx.update(
      'plan_items',
      {
        'status': PlanItemStatus.next.name,
        'updated_at_utc': now.toUtc().millisecondsSinceEpoch,
      },
      where: "id = ? AND status = 'dispatched'",
      whereArgs: [planItemId],
    );
    if (updated != 1) throw const DomainFailure('计划项已变化，请刷新后重试');
  });

  @override
  Future<List<Plan>> getPlans() async => (await _app.database.query(
    'plans',
    orderBy: 'created_at_utc DESC, id DESC',
  )).map(_planFromRow).toList(growable: false);

  @override
  Future<Plan?> getPlan(String id) async {
    final rows = await _app.database.query(
      'plans',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : _planFromRow(rows.single);
  }

  @override
  Future<List<PlanItem>> getPlanItems(String planId) async =>
      (await _app.database.query(
        'plan_items',
        where: 'plan_id = ?',
        whereArgs: [planId],
        orderBy: 'sort_order, created_at_utc, id',
      )).map(_itemFromRow).toList(growable: false);

  @override
  Future<List<PlanReviewNote>> getPlanReviewNotes(String planId) async =>
      (await _app.database.query(
        'plan_review_notes',
        where: 'plan_id = ?',
        whereArgs: [planId],
        orderBy: 'created_at_utc DESC, id DESC',
      )).map(_reviewNoteFromRow).toList(growable: false);

  @override
  Future<Plan> createPlan({
    required String id,
    required String worldNodeId,
    String? title,
    required DateTime now,
  }) => _app.database.transaction(
    (tx) => _createPlan(
      tx,
      id: id,
      worldNodeId: worldNodeId,
      title: title,
      now: now,
    ),
  );

  Future<Plan> _createPlan(
    DatabaseExecutor tx, {
    required String id,
    required String worldNodeId,
    String? title,
    required DateTime now,
  }) async {
    final nodes = await tx.query(
      'world_nodes',
      columns: ['status'],
      where: 'id = ?',
      whereArgs: [worldNodeId],
      limit: 1,
    );
    if (nodes.isEmpty) throw const DomainFailure('世界节点不存在');
    if (nodes.single['status'] == 'completed') {
      throw const DomainFailure('该世界节点已完成，恢复节点后才能创建新计划');
    }
    final current = await tx.query(
      'plans',
      columns: ['id'],
      where: "world_node_id = ? AND status = 'current'",
      whereArgs: [worldNodeId],
      limit: 1,
    );
    if (current.isNotEmpty) {
      throw const DomainFailure('该世界节点已有当前计划');
    }
    final rounds = await tx.rawQuery(
      'SELECT COALESCE(MAX(round_number), 0) + 1 value FROM plans WHERE world_node_id = ?',
      [worldNodeId],
    );
    final utc = now.toUtc();
    final plan = Plan(
      id: id,
      worldNodeId: worldNodeId,
      status: PlanStatus.current,
      roundNumber: (rounds.single['value'] as num).toInt(),
      title: _cleanOptional(title),
      createdAt: utc,
      updatedAt: utc,
    );
    await tx.insert('plans', _planToRow(plan));
    return plan;
  }

  @override
  Future<void> renamePlan(String id, String? title, DateTime now) async {
    final plan = await getPlan(id);
    if (plan == null) throw const DomainFailure('计划不存在');
    if (plan.status == PlanStatus.ended) {
      throw const DomainFailure('已结束的计划不能编辑');
    }
    await _updateOne('plans', id, {
      'title': _cleanOptional(title),
      'updated_at_utc': now.toUtc().millisecondsSinceEpoch,
    });
  }

  @override
  Future<void> setPlanStatus(String id, PlanStatus status, DateTime now) async {
    final plan = await getPlan(id);
    if (plan == null) throw const DomainFailure('计划不存在');
    if (plan.status == PlanStatus.ended) {
      throw const DomainFailure('已结束的计划不能重新开启，请创建下一轮');
    }
    if (status == PlanStatus.ended) {
      await _updateOne('plans', id, {
        'status': status.name,
        'ended_at_utc': now.toUtc().millisecondsSinceEpoch,
        'updated_at_utc': now.toUtc().millisecondsSinceEpoch,
      });
      return;
    }
    // current is not a reopen action. An ended round remains immutable and a
    // new round must be created instead.
  }

  @override
  Future<void> deletePlan(String id) => _app.database.transaction((tx) async {
    final plan = await tx.query(
      'plans',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (plan.isEmpty) throw const DomainFailure('计划不存在');
    final executed = await tx.rawQuery(
      '''SELECT 1 FROM plan_items
         WHERE plan_id = ? AND status IN ('dispatched','done') LIMIT 1''',
      [id],
    );
    if (executed.isNotEmpty) {
      throw const DomainFailure('已有派发或完成记录的计划不能删除');
    }
    final linked = await tx.rawQuery(
      '''SELECT 1 FROM events event JOIN plan_items item
         ON item.id = event.source_plan_item_id
         WHERE item.plan_id = ? LIMIT 1''',
      [id],
    );
    if (linked.isNotEmpty) {
      throw const DomainFailure('已有执行事项的计划不能删除');
    }
    await tx.delete('plan_review_notes', where: 'plan_id = ?', whereArgs: [id]);
    await tx.delete('plan_items', where: 'plan_id = ?', whereArgs: [id]);
    final deleted = await tx.delete('plans', where: 'id = ?', whereArgs: [id]);
    if (deleted != 1) throw const DomainFailure('计划删除冲突');
  });

  @override
  Future<PlanItem> createPlanItem({
    required String id,
    required String planId,
    required String title,
    String? note,
    PlanItemStatus initialStatus = PlanItemStatus.next,
    required DateTime now,
  }) => _app.database.transaction(
    (tx) => _createPlanItem(
      tx,
      id: id,
      planId: planId,
      title: title,
      note: note,
      initialStatus: initialStatus,
      now: now,
    ),
  );

  Future<PlanItem> _createPlanItem(
    DatabaseExecutor tx, {
    required String id,
    required String planId,
    required String title,
    String? note,
    PlanItemStatus initialStatus = PlanItemStatus.next,
    required DateTime now,
  }) async {
    _requireTitle(title);
    if (initialStatus != PlanItemStatus.draft &&
        initialStatus != PlanItemStatus.next) {
      throw const DomainFailure('新计划步骤必须为未执行状态');
    }
    await _requireEditablePlan(tx, planId);
    final order = await tx.rawQuery(
      'SELECT COALESCE(MAX(sort_order), -1) + 1 value FROM plan_items WHERE plan_id = ?',
      [planId],
    );
    final utc = now.toUtc();
    final item = PlanItem(
      id: id,
      planId: planId,
      title: title.trim(),
      note: _cleanOptional(note),
      status: PlanItemStatus.next,
      sortOrder: (order.single['value'] as num).toInt(),
      createdAt: utc,
      updatedAt: utc,
    );
    await tx.insert('plan_items', _itemToRow(item));
    return item;
  }

  @override
  Future<void> editPlanItem(
    String id, {
    required String title,
    String? note,
    required DateTime now,
  }) => _app.database.transaction((tx) async {
    _requireTitle(title);
    final item = await _requireItem(tx, id);
    if (!item.isExecutable) {
      throw const DomainFailure('当前状态的计划项不能编辑');
    }
    await _requireEditablePlan(tx, item.planId);
    await tx.update(
      'plan_items',
      {
        'title': title.trim(),
        'note': _cleanOptional(note),
        'updated_at_utc': now.toUtc().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  });

  @override
  Future<void> setPlanItemStatus(
    String id,
    PlanItemStatus status,
    DateTime now,
  ) => _app.database.transaction((tx) async {
    final item = await _requireItem(tx, id);
    await _requireEditablePlan(tx, item.planId);
    if (item.isPromoted) throw const DomainFailure('世界节点引用不能恢复为普通步骤');
    // Legacy callers may still supply draft; never persist it on new writes.
    if (status == PlanItemStatus.draft) status = PlanItemStatus.next;
    if (status == item.status) return;
    final allowed = switch (item.status) {
      PlanItemStatus.draft => {PlanItemStatus.next, PlanItemStatus.dropped},
      PlanItemStatus.next => {PlanItemStatus.dropped},
      PlanItemStatus.dropped => {PlanItemStatus.next},
      PlanItemStatus.dispatched ||
      PlanItemStatus.done => const <PlanItemStatus>{},
    };
    if (!allowed.contains(status)) {
      throw const DomainFailure('该计划项状态不能由用户手工设置');
    }
    await tx.update(
      'plan_items',
      {
        'status': status.name,
        'updated_at_utc': now.toUtc().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  });

  @override
  Future<void> deletePlanItem(String id) =>
      _app.database.transaction((tx) async {
        final item = await _requireItem(tx, id);
        await _requireEditablePlan(tx, item.planId);
        if (!item.isExecutable) {
          throw const DomainFailure('只能删除从未执行的计划步骤');
        }
        await tx.delete('plan_items', where: 'id = ?', whereArgs: [id]);
        await _normalizeOrder(tx, item.planId);
      });

  @override
  Future<void> reorderPlanItem(String id, int targetIndex, DateTime now) =>
      _app.database.transaction((tx) async {
        final rows = await tx.query(
          'plan_items',
          where: 'id = ?',
          whereArgs: [id],
          limit: 1,
        );
        if (rows.isEmpty) throw const DomainFailure('计划项不存在');
        final item = _itemFromRow(rows.single);
        await _requireEditablePlan(tx, item.planId);
        if (!item.isExecutable) {
          throw const DomainFailure('当前状态的计划项不能排序');
        }
        final siblings = await tx.query(
          'plan_items',
          columns: ['id', 'updated_at_utc'],
          where: 'plan_id = ?',
          whereArgs: [item.planId],
          orderBy: 'sort_order, created_at_utc, id',
        );
        final current = siblings.indexWhere((row) => row['id'] == id);
        if (targetIndex < 0 || targetIndex >= siblings.length) {
          throw const DomainFailure('无效的排序位置');
        }
        final reordered = [...siblings];
        final moved = reordered.removeAt(current);
        reordered.insert(targetIndex, moved);
        for (var index = 0; index < reordered.length; index++) {
          await tx.update(
            'plan_items',
            {
              'sort_order': index,
              'updated_at_utc': reordered[index]['id'] == id
                  ? now.toUtc().millisecondsSinceEpoch
                  : reordered[index]['updated_at_utc'],
            },
            where: 'id = ?',
            whereArgs: [reordered[index]['id']],
          );
        }
      });

  @override
  Future<PlanReviewNote> createPlanReviewNote({
    required String id,
    required String planId,
    required String content,
    required DateTime now,
  }) => _app.database.transaction((tx) async {
    _requireReviewContent(content);
    final plans = await tx.query(
      'plans',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [planId],
      limit: 1,
    );
    if (plans.isEmpty) throw const DomainFailure('计划不存在');
    final utc = now.toUtc();
    final note = PlanReviewNote(
      id: id,
      planId: planId,
      content: content.trim(),
      createdAt: utc,
      updatedAt: utc,
    );
    await tx.insert('plan_review_notes', _reviewNoteToRow(note));
    return note;
  });

  @override
  Future<void> editPlanReviewNote(
    String id, {
    required String content,
    required DateTime now,
  }) async {
    _requireReviewContent(content);
    final rows = await _app.database.query(
      'plan_review_notes',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) throw const DomainFailure('复盘不存在');
    await _updateOne('plan_review_notes', id, {
      'content': content.trim(),
      'updated_at_utc': now.toUtc().millisecondsSinceEpoch,
    });
  }

  @override
  Future<void> deletePlanReviewNote(String id) async {
    final deleted = await _app.database.delete(
      'plan_review_notes',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (deleted != 1) throw const DomainFailure('复盘不存在');
  }

  Future<PlanItem> _requireItem(DatabaseExecutor tx, String id) async {
    final rows = await tx.query(
      'plan_items',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) throw const DomainFailure('计划项不存在');
    return _itemFromRow(rows.single);
  }

  Future<void> _requireEditablePlan(DatabaseExecutor db, String id) async {
    final rows = await db.rawQuery(
      '''SELECT plan.status plan_status, node.status node_status
         FROM plans plan
         JOIN world_nodes node ON node.id = plan.world_node_id
         WHERE plan.id = ? LIMIT 1''',
      [id],
    );
    if (rows.isEmpty) throw const DomainFailure('计划不存在');
    if (rows.single['plan_status'] == 'ended') {
      throw const DomainFailure('已结束的计划不能编辑');
    }
    if (rows.single['node_status'] == 'completed') {
      throw const DomainFailure('世界节点已完成，恢复节点后才能编辑计划');
    }
  }

  Future<void> _normalizeOrder(DatabaseExecutor tx, String planId) async {
    final rows = await tx.query(
      'plan_items',
      columns: ['id', 'sort_order', 'updated_at_utc'],
      where: 'plan_id = ?',
      whereArgs: [planId],
      orderBy: 'sort_order, created_at_utc, id',
    );
    for (var index = 0; index < rows.length; index++) {
      if (rows[index]['sort_order'] != index) {
        await tx.update(
          'plan_items',
          {
            'sort_order': index,
            'updated_at_utc': rows[index]['updated_at_utc'],
          },
          where: 'id = ?',
          whereArgs: [rows[index]['id']],
        );
      }
    }
  }

  Future<void> _updateOne(
    String table,
    String id,
    Map<String, Object?> values,
  ) async {
    if (await _app.database.update(
          table,
          values,
          where: 'id = ?',
          whereArgs: [id],
        ) !=
        1) {
      throw DomainFailure('$table 记录不存在');
    }
  }

  static String? _cleanOptional(String? value) {
    final clean = value?.trim();
    return clean == null || clean.isEmpty ? null : clean;
  }

  static void _requireTitle(String value) {
    if (value.trim().isEmpty) throw const DomainFailure('计划项标题不能为空');
  }

  static void _requireReviewContent(String value) {
    if (value.trim().isEmpty) throw const DomainFailure('复盘内容不能为空');
  }

  static Map<String, Object?> _planToRow(Plan plan) => {
    'id': plan.id,
    'world_node_id': plan.worldNodeId,
    'status': plan.status.name,
    'round_number': plan.roundNumber,
    'title': plan.title,
    'created_at_utc': plan.createdAt.millisecondsSinceEpoch,
    'updated_at_utc': plan.updatedAt.millisecondsSinceEpoch,
    'ended_at_utc': plan.endedAt?.millisecondsSinceEpoch,
  };

  static Plan _planFromRow(Map<String, Object?> row) => Plan(
    id: row['id']! as String,
    worldNodeId: row['world_node_id']! as String,
    status: PlanStatus.values.byName(row['status']! as String),
    roundNumber: (row['round_number']! as num).toInt(),
    title: row['title'] as String?,
    createdAt: _date(row['created_at_utc']),
    updatedAt: _date(row['updated_at_utc']),
    endedAt: row['ended_at_utc'] == null ? null : _date(row['ended_at_utc']),
  );

  static Map<String, Object?> _itemToRow(PlanItem item) => {
    'id': item.id,
    'plan_id': item.planId,
    'title': item.title,
    'note': item.note,
    'promoted_world_node_id': item.promotedWorldNodeId,
    'status': item.status.name,
    'sort_order': item.sortOrder,
    'created_at_utc': item.createdAt.millisecondsSinceEpoch,
    'updated_at_utc': item.updatedAt.millisecondsSinceEpoch,
  };

  static PlanItem _itemFromRow(Map<String, Object?> row) => PlanItem(
    id: row['id']! as String,
    planId: row['plan_id']! as String,
    title: row['title']! as String,
    note: row['note'] as String?,
    promotedWorldNodeId: row['promoted_world_node_id'] as String?,
    status: readPlanItemStatus(row['status']! as String),
    sortOrder: (row['sort_order']! as num).toInt(),
    createdAt: _date(row['created_at_utc']),
    updatedAt: _date(row['updated_at_utc']),
  );

  static Map<String, Object?> _reviewNoteToRow(PlanReviewNote note) => {
    'id': note.id,
    'plan_id': note.planId,
    'content': note.content,
    'created_at_utc': note.createdAt.millisecondsSinceEpoch,
    'updated_at_utc': note.updatedAt.millisecondsSinceEpoch,
  };

  static PlanReviewNote _reviewNoteFromRow(Map<String, Object?> row) =>
      PlanReviewNote(
        id: row['id']! as String,
        planId: row['plan_id']! as String,
        content: row['content']! as String,
        createdAt: _date(row['created_at_utc']),
        updatedAt: _date(row['updated_at_utc']),
      );

  static DateTime _date(Object? value) =>
      DateTime.fromMillisecondsSinceEpoch((value! as num).toInt(), isUtc: true);
}
