import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core/sync/sync_contract.dart';
import '../../core/sync/sync_mutation_plan.dart';
import '../database/app_database.dart';

class SyncMutationFailureInjection {
  const SyncMutationFailureInjection({this.failAfterOperation});
  final int? failAfterOperation;
}

class SqliteSyncMutationExecutor {
  const SqliteSyncMutationExecutor();

  Future<void> apply(
    String path,
    List<SyncMutation> operations, {
    SyncMutationFailureInjection injection =
        const SyncMutationFailureInjection(),
  }) async {
    final app = await AppDatabase.open(path);
    try {
      await applyDatabase(app, operations, injection: injection);
    } finally {
      await app.close();
    }
  }

  Future<void> applyDatabase(
    AppDatabase app,
    List<SyncMutation> operations, {
    SyncMutationFailureInjection injection =
        const SyncMutationFailureInjection(),
  }) async {
    await app.database.transaction((transaction) async {
      await transaction.execute('PRAGMA defer_foreign_keys = ON');
      var completed = 0;
      final records = operations
          .where((operation) => operation.record != null)
          .map((operation) => operation.record!)
          .toList();
      final deleted = records.where((record) => record.isDeleted).toList()
        ..sort((a, b) => _deleteRank(a.kind).compareTo(_deleteRank(b.kind)));
      final live = records.where((record) => !record.isDeleted).toList()
        ..sort((a, b) => _upsertRank(a.kind).compareTo(_upsertRank(b.kind)));
      for (final record in [...deleted, ...live]) {
        if (record.isDeleted) {
          await _applyDeletion(transaction, record);
        } else {
          await _upsert(transaction, record);
        }
        completed++;
        if (injection.failAfterOperation == completed) {
          throw StateError(
            'Injected mutation failure after operation $completed',
          );
        }
      }
      for (final operation in operations.where(
        (operation) => operation.list != null,
      )) {
        await _applyList(transaction, operation.list!);
        completed++;
        if (injection.failAfterOperation == completed) {
          throw StateError(
            'Injected mutation failure after operation $completed',
          );
        }
      }
      final foreignKeys = await transaction.rawQuery(
        'PRAGMA foreign_key_check',
      );
      if (foreignKeys.isNotEmpty) {
        throw StateError('Foreign key validation failed: $foreignKeys');
      }
    });
    for (final operation in operations.where(
      (operation) => operation.list != null,
    )) {
      await _verifyList(app.database, operation.list!);
    }
    // Validation and backup use fresh connections/files. Materialize the
    // committed WAL before crossing either boundary on Windows or Android.
    final checkpoint = await app.database.rawQuery(
      'PRAGMA wal_checkpoint(TRUNCATE)',
    );
    if (checkpoint.isNotEmpty &&
        (checkpoint.single['busy'] as num?)?.toInt() != 0) {
      throw StateError('SQLite WAL checkpoint remained busy: $checkpoint');
    }
  }

  Future<void> _applyDeletion(DatabaseExecutor db, SyncRecord record) async {
    final target = _target(record);
    await db.delete(
      target.table,
      where: target.where,
      whereArgs: target.whereArgs,
    );
    await db.insert('sync_tombstones', {
      'entity_type': _tombstoneType(record.kind),
      'entity_id': record.metadata.id,
      'deleted_at_utc': record.metadata.deletedAtUtc!.millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _upsert(DatabaseExecutor db, SyncRecord record) async {
    final target = _target(record);
    final row = _row(record);
    final existing = await db.query(
      target.table,
      columns: ['updated_at_utc'],
      where: target.where,
      whereArgs: target.whereArgs,
      limit: 1,
    );
    if (existing.isEmpty) {
      await db.insert(target.table, row);
      return;
    }
    // Ordering is a separate SyncList concern. A field-level resolution must
    // not copy one side's raw storage index over an already-correct list.
    switch (record.kind) {
      case SyncEntityKind.eventCategory:
      case SyncEntityKind.routineCategory:
      case SyncEntityKind.routine:
      case SyncEntityKind.worldNode:
      case SyncEntityKind.planItem:
      case SyncEntityKind.planReviewNote:
        row.remove('sort_order');
        break;
      case SyncEntityKind.event:
        break;
      case SyncEntityKind.eventDayPlan:
        row.remove('order_index');
        break;
      case SyncEntityKind.eventRunSegment:
      case SyncEntityKind.routineExecution:
      case SyncEntityKind.routineRunSegment:
      case SyncEntityKind.legacyEventWorldNodeLink:
      case SyncEntityKind.plan:
        break;
    }
    final oldUpdated = (existing.single['updated_at_utc'] as num).toInt();
    final desired = record.metadata.updatedAtUtc.millisecondsSinceEpoch;
    if (oldUpdated == desired) row['updated_at_utc'] = desired + 1;
    await db.update(
      target.table,
      row,
      where: target.where,
      whereArgs: target.whereArgs,
    );
    if (oldUpdated == desired) {
      await db.update(
        target.table,
        {'updated_at_utc': desired},
        where: target.where,
        whereArgs: target.whereArgs,
      );
    }
  }

  Future<void> _applyList(DatabaseExecutor db, SyncList list) async {
    // Move every row out of the normal ordering range first. This makes the
    // reorder deterministic even when a database adds a uniqueness constraint
    // for a sibling scope in a later schema version.
    for (var index = 0; index < list.itemIds.length; index++) {
      await _setListItemOrder(db, list, list.itemIds[index], -index - 1);
    }
    for (var index = 0; index < list.itemIds.length; index++) {
      await _setListItemOrder(db, list, list.itemIds[index], index);
    }
    await _verifyList(db, list);
  }

  Future<void> _verifyList(DatabaseExecutor db, SyncList list) async {
    final actual = await _readListItemIds(db, list);
    if (!_sameIds(actual, list.itemIds)) {
      throw StateError(
        'List write verification failed for ${list.key}: '
        'expected=${list.itemIds.join(',')} actual=${actual.join(',')}',
      );
    }
  }

  Future<void> _setListItemOrder(
    DatabaseExecutor db,
    SyncList list,
    String id,
    int index,
  ) => switch (list.kind) {
    SyncListKind.eventCategories => _setOrder(db, 'categories', 'id = ?', [
      id,
    ], index),
    SyncListKind.eventSiblings => throw StateError(
      'Event hierarchy lists are not supported by sync protocol 5.',
    ),
    SyncListKind.routineCategories => _setOrder(
      db,
      'routine_categories',
      'id = ?',
      [id],
      index,
    ),
    SyncListKind.routines => _setOrder(db, 'routines', 'id = ?', [id], index),
    SyncListKind.eventDayPlans => _setOrder(
      db,
      'event_day_plans',
      'event_id = ? AND day_date = ?',
      [id, list.scopeId],
      index,
      column: 'order_index',
    ),
    SyncListKind.worldNodeSiblings => _setOrder(db, 'world_nodes', 'id = ?', [
      id,
    ], index),
    SyncListKind.planItems => _setOrder(db, 'plan_items', 'id = ?', [
      id,
    ], index),
  };

  Future<List<String>> _readListItemIds(
    DatabaseExecutor db,
    SyncList list,
  ) async {
    final (table, idColumn, orderColumn, where, args) = switch (list.kind) {
      SyncListKind.eventCategories => (
        'categories',
        'id',
        'sort_order',
        null,
        <Object?>[],
      ),
      SyncListKind.eventSiblings => throw StateError(
        'Event hierarchy lists are not supported by sync protocol 5.',
      ),
      SyncListKind.routineCategories => (
        'routine_categories',
        'id',
        'sort_order',
        null,
        <Object?>[],
      ),
      SyncListKind.routines =>
        list.scopeId == 'uncategorized'
            ? (
                'routines',
                'id',
                'sort_order',
                'routine_category_id IS NULL',
                <Object?>[],
              )
            : (
                'routines',
                'id',
                'sort_order',
                'routine_category_id = ?',
                <Object?>[list.scopeId],
              ),
      SyncListKind.eventDayPlans => (
        'event_day_plans',
        'event_id',
        'order_index',
        'day_date = ?',
        <Object?>[list.scopeId],
      ),
      SyncListKind.worldNodeSiblings =>
        list.scopeId.startsWith('parent:')
            ? (
                'world_nodes',
                'id',
                'sort_order',
                'parent_world_node_id = ?',
                <Object?>[list.scopeId.substring('parent:'.length)],
              )
            : list.scopeId == 'category:uncategorized'
            ? (
                'world_nodes',
                'id',
                'sort_order',
                'parent_world_node_id IS NULL AND category_id IS NULL',
                <Object?>[],
              )
            : (
                'world_nodes',
                'id',
                'sort_order',
                'parent_world_node_id IS NULL AND category_id = ?',
                <Object?>[list.scopeId.substring('category:'.length)],
              ),
      SyncListKind.planItems => (
        'plan_items',
        'id',
        'sort_order',
        'plan_id = ?',
        <Object?>[list.scopeId],
      ),
    };
    final rows = await db.query(
      table,
      columns: [idColumn],
      where: where,
      whereArgs: args,
      orderBy: '$orderColumn, created_at_utc, $idColumn',
    );
    return rows.map((row) => row[idColumn]! as String).toList();
  }

  bool _sameIds(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }

  Future<void> _setOrder(
    DatabaseExecutor db,
    String table,
    String where,
    List<Object?> args,
    int index, {
    String column = 'sort_order',
  }) async {
    final current = await db.query(
      table,
      columns: ['updated_at_utc'],
      where: where,
      whereArgs: args,
      limit: 1,
    );
    if (current.isEmpty) {
      throw StateError('List item missing from $table: $args');
    }
    final updatedAt = (current.single['updated_at_utc'] as num).toInt();
    final changed = await db.update(
      table,
      {column: index},
      where: where,
      whereArgs: args,
    );
    if (changed != 1) {
      throw StateError(
        'Expected one list row update in $table for $args, changed $changed.',
      );
    }
    // SyncList owns order, but reordering is not a new entity edit. The normal
    // update trigger fires for the storage write, so restore the exact history
    // metadata captured before it.
    await db.update(
      table,
      {'updated_at_utc': updatedAt},
      where: where,
      whereArgs: args,
    );
  }

  Map<String, Object?> _row(SyncRecord record) {
    final p = record.payload;
    final metadata = {
      'created_at_utc': record.metadata.createdAtUtc.millisecondsSinceEpoch,
      'updated_at_utc': record.metadata.updatedAtUtc.millisecondsSinceEpoch,
    };
    return switch (record.kind) {
      SyncEntityKind.eventCategory => {
        'id': record.metadata.id,
        'name': p['name'],
        'sort_order': p['order'],
        'color_key': p['colorKey'],
        ...metadata,
      },
      SyncEntityKind.event => {
        'id': record.metadata.id,
        'name': p['name'],
        'status': p['status'],
        'source_plan_item_id': p['sourcePlanItemSyncId'],
        'category_id': p['categorySyncId'],
        'first_started_at_utc': p['firstStartedAtUtc'],
        'completed_at_utc': p['completedAtUtc'],
        ...metadata,
      },
      SyncEntityKind.eventRunSegment => {
        'id': record.metadata.id,
        'event_id': p['eventSyncId'],
        'started_at_utc': p['startedAtUtc'],
        'ended_at_utc': p['endedAtUtc'],
        ...metadata,
      },
      SyncEntityKind.routineCategory => {
        'id': record.metadata.id,
        'name': p['name'],
        'sort_order': p['order'],
        'color_key': p['colorKey'],
        ...metadata,
      },
      SyncEntityKind.routine => {
        'id': record.metadata.id,
        'name': p['name'],
        'routine_category_id': p['routineCategorySyncId'],
        'routine_type': p['routineType'],
        'recurrence_type': p['recurrenceType'],
        'weekday_mask': p['weekdayMask'],
        'is_active': p['isActive'],
        'time_recommendation_enabled': p['timeRecommendationEnabled'],
        'show_in_home_quick_actions': p['showInHomeQuickActions'],
        'time_recommendation_start_minute': p['timeRecommendationStartMinute'],
        'time_recommendation_end_minute': p['timeRecommendationEndMinute'],
        'time_recommendation_reason': p['timeRecommendationReason'],
        'sort_order': p['order'],
        ...metadata,
      },
      SyncEntityKind.routineExecution => {
        'id': record.metadata.id,
        'routine_id': p['routineSyncId'],
        'occurrence_date': p['jaxDay'],
        'status': p['status'],
        'completed_at_utc': p['completedAtUtc'],
        ...metadata,
      },
      SyncEntityKind.routineRunSegment => {
        'id': record.metadata.id,
        'routine_execution_id': p['routineExecutionSyncId'],
        'started_at_utc': p['startedAtUtc'],
        'ended_at_utc': p['endedAtUtc'],
        ...metadata,
      },
      SyncEntityKind.eventDayPlan => {
        'event_id': p['eventSyncId'],
        'day_date': p['jaxDay'],
        'order_index': p['order'],
        ...metadata,
      },
      SyncEntityKind.worldNode => {
        'id': record.metadata.id,
        'name': p['name'],
        'status': p['status'],
        'is_focused': p['isFocused'],
        'parent_world_node_id': p['parentWorldNodeSyncId'],
        'sort_order': p['order'],
        'category_id': p['categorySyncId'],
        ...metadata,
      },
      SyncEntityKind.legacyEventWorldNodeLink => throw StateError(
        'Legacy Event/WorldNode links are not supported by protocol 7.',
      ),
      SyncEntityKind.plan => {
        'id': record.metadata.id,
        'world_node_id': p['worldNodeSyncId'],
        'title': p['title'],
        'status': p['status'],
        'round_number': p['roundNumber'],
        'ended_at_utc': p['endedAtUtc'],
        ...metadata,
      },
      SyncEntityKind.planItem => {
        'id': record.metadata.id,
        'plan_id': p['planSyncId'],
        'title': p['title'],
        'note': p['note'],
        'status': p['status'],
        'sort_order': p['order'],
        ...metadata,
      },
      SyncEntityKind.planReviewNote => {
        'id': record.metadata.id,
        'plan_id': p['planSyncId'],
        'content': p['content'],
        ...metadata,
      },
    };
  }

  _SqlTarget _target(SyncRecord record) => switch (record.kind) {
    SyncEntityKind.eventCategory => _SqlTarget('categories', 'id = ?', [
      record.metadata.id,
    ]),
    SyncEntityKind.event => _SqlTarget('events', 'id = ?', [
      record.metadata.id,
    ]),
    SyncEntityKind.eventRunSegment => _SqlTarget('run_segments', 'id = ?', [
      record.metadata.id,
    ]),
    SyncEntityKind.routineCategory => _SqlTarget(
      'routine_categories',
      'id = ?',
      [record.metadata.id],
    ),
    SyncEntityKind.routine => _SqlTarget('routines', 'id = ?', [
      record.metadata.id,
    ]),
    SyncEntityKind.routineExecution => _SqlTarget(
      'routine_executions',
      'id = ?',
      [record.metadata.id],
    ),
    SyncEntityKind.routineRunSegment => _SqlTarget(
      'routine_run_segments',
      'id = ?',
      [record.metadata.id],
    ),
    SyncEntityKind.eventDayPlan when record.isDeleted => _SqlTarget(
      'event_day_plans',
      "event_id || '@' || day_date = ?",
      [record.metadata.id],
    ),
    SyncEntityKind.eventDayPlan => _SqlTarget(
      'event_day_plans',
      'event_id = ? AND day_date = ?',
      [record.payload['eventSyncId'], record.payload['jaxDay']],
    ),
    SyncEntityKind.worldNode => _SqlTarget('world_nodes', 'id = ?', [
      record.metadata.id,
    ]),
    SyncEntityKind.legacyEventWorldNodeLink => throw StateError(
      'Legacy Event/WorldNode links are not supported by protocol 5.',
    ),
    SyncEntityKind.plan => _SqlTarget('plans', 'id = ?', [record.metadata.id]),
    SyncEntityKind.planItem => _SqlTarget('plan_items', 'id = ?', [
      record.metadata.id,
    ]),
    SyncEntityKind.planReviewNote => _SqlTarget('plan_review_notes', 'id = ?', [
      record.metadata.id,
    ]),
  };

  int _deleteRank(SyncEntityKind kind) => switch (kind) {
    SyncEntityKind.eventDayPlan ||
    SyncEntityKind.eventRunSegment ||
    SyncEntityKind.routineRunSegment => 0,
    SyncEntityKind.event || SyncEntityKind.routineExecution => 1,
    SyncEntityKind.planReviewNote => 2,
    SyncEntityKind.planItem || SyncEntityKind.routine => 3,
    SyncEntityKind.plan => 4,
    SyncEntityKind.worldNode => 5,
    SyncEntityKind.routineCategory || SyncEntityKind.eventCategory => 6,
    SyncEntityKind.legacyEventWorldNodeLink => 7,
  };
  int _upsertRank(SyncEntityKind kind) => switch (kind) {
    SyncEntityKind.eventCategory || SyncEntityKind.routineCategory => 0,
    SyncEntityKind.event => 4,
    SyncEntityKind.routine => 2,
    SyncEntityKind.routineExecution => 3,
    SyncEntityKind.eventRunSegment || SyncEntityKind.routineRunSegment => 5,
    SyncEntityKind.eventDayPlan => 6,
    SyncEntityKind.worldNode => 1,
    SyncEntityKind.plan => 2,
    SyncEntityKind.planItem => 3,
    SyncEntityKind.planReviewNote => 3,
    SyncEntityKind.legacyEventWorldNodeLink => 7,
  };
  String _tombstoneType(SyncEntityKind kind) => switch (kind) {
    SyncEntityKind.eventCategory => 'category',
    SyncEntityKind.event => 'event',
    SyncEntityKind.eventDayPlan => 'eventDayPlan',
    SyncEntityKind.eventRunSegment => 'eventRunSegment',
    SyncEntityKind.routineCategory => 'routineCategory',
    SyncEntityKind.routine => 'routine',
    SyncEntityKind.routineExecution => 'routineExecution',
    SyncEntityKind.routineRunSegment => 'routineRunSegment',
    SyncEntityKind.worldNode => 'worldNode',
    SyncEntityKind.legacyEventWorldNodeLink => 'legacyEventWorldNodeLink',
    SyncEntityKind.plan => 'plan',
    SyncEntityKind.planItem => 'planItem',
    SyncEntityKind.planReviewNote => 'planReviewNote',
  };
}

class _SqlTarget {
  const _SqlTarget(this.table, this.where, this.whereArgs);
  final String table;
  final String where;
  final List<Object?> whereArgs;
}
