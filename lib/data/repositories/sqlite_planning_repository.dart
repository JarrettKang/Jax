import 'package:sqflite/sqflite.dart';

import '../../core/entities/plan.dart';
import '../../core/entities/plan_item.dart';
import '../../core/entities/plan_review_note.dart';
import '../../core/entities/event_status.dart';
import '../../core/entities/jax_event.dart';
import '../../core/errors/domain_failure.dart';
import '../../core/repositories/planning_dispatch_repository.dart';
import '../../core/repositories/planning_repository.dart';
import '../database/app_database.dart';

class SqlitePlanningRepository
    implements PlanningRepository, PlanningDispatchRepository {
  const SqlitePlanningRepository(this._app);
  final AppDatabase _app;

  @override
  Future<List<JaxEvent>> dispatchPlanItems({
    required Map<String, String> eventIdsByPlanItemId,
    required String dayKey,
    required DateTime now,
  }) async {
    if (eventIdsByPlanItemId.isEmpty) {
      throw const DomainFailure('请至少选择一个今日建议');
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
            '''SELECT item.title, item.status item_status,
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
            throw const DomainFailure('只有关注中世界节点的当前计划下一步可以加入今日');
          }
          if (rows.single['item_status'] != PlanItemStatus.next.name) {
            throw const DomainFailure('计划项已变化，请刷新今日建议');
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
            where: "id = ? AND status = 'next'",
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
  }) => _app.database.transaction((tx) async {
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
  });

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
    PlanItemStatus initialStatus = PlanItemStatus.draft,
    required DateTime now,
  }) => _app.database.transaction((tx) async {
    _requireTitle(title);
    if (initialStatus != PlanItemStatus.draft &&
        initialStatus != PlanItemStatus.next) {
      throw const DomainFailure('新计划步骤只能保存为草稿或下一步');
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
      status: initialStatus,
      sortOrder: (order.single['value'] as num).toInt(),
      createdAt: utc,
      updatedAt: utc,
    );
    await tx.insert('plan_items', _itemToRow(item));
    return item;
  });

  @override
  Future<void> editPlanItem(
    String id, {
    required String title,
    String? note,
    required DateTime now,
  }) async {
    _requireTitle(title);
    final item = await _requireItem(id);
    if (item.status != PlanItemStatus.draft &&
        item.status != PlanItemStatus.next) {
      throw const DomainFailure('当前状态的计划项不能编辑');
    }
    await _requireEditablePlan(_app.database, item.planId);
    await _updateOne('plan_items', id, {
      'title': title.trim(),
      'note': _cleanOptional(note),
      'updated_at_utc': now.toUtc().millisecondsSinceEpoch,
    });
  }

  @override
  Future<void> setPlanItemStatus(
    String id,
    PlanItemStatus status,
    DateTime now,
  ) async {
    final item = await _requireItem(id);
    await _requireEditablePlan(_app.database, item.planId);
    final allowed = switch (item.status) {
      PlanItemStatus.draft => {PlanItemStatus.next, PlanItemStatus.dropped},
      PlanItemStatus.next => {PlanItemStatus.draft, PlanItemStatus.dropped},
      PlanItemStatus.dropped => {PlanItemStatus.draft},
      PlanItemStatus.dispatched ||
      PlanItemStatus.done => const <PlanItemStatus>{},
    };
    if (!allowed.contains(status)) {
      throw const DomainFailure('该计划项状态不能由用户手工设置');
    }
    await _updateOne('plan_items', id, {
      'status': status.name,
      'updated_at_utc': now.toUtc().millisecondsSinceEpoch,
    });
  }

  @override
  Future<void> deletePlanItem(String id) async {
    final item = await _requireItem(id);
    await _requireEditablePlan(_app.database, item.planId);
    if (item.status != PlanItemStatus.draft &&
        item.status != PlanItemStatus.next) {
      throw const DomainFailure('只能删除从未派发的草稿或下一步');
    }
    await _app.database.transaction((tx) async {
      await tx.delete('plan_items', where: 'id = ?', whereArgs: [id]);
      await _normalizeOrder(tx, item.planId);
    });
  }

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
        if (item.status != PlanItemStatus.draft &&
            item.status != PlanItemStatus.next) {
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

  Future<PlanItem> _requireItem(String id) async {
    final rows = await _app.database.query(
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
    status: PlanItemStatus.values.byName(row['status']! as String),
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
