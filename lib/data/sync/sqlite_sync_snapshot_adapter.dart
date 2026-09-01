import 'package:sqflite_common_ffi/sqflite_ffi.dart' show Database;

import '../../core/sync/sync_contract.dart';
import '../database/app_database.dart';
import 'sqlite_sync_readiness.dart';

/// Read-only current-schema SQLite to transport-neutral snapshot adapter.
class SqliteSyncSnapshotAdapter {
  const SqliteSyncSnapshotAdapter(this.database, {this.now = DateTime.now});
  final Database database;
  final DateTime Function() now;

  Future<SyncSnapshot> read() async {
    final version =
        (await database.rawQuery('PRAGMA user_version')).single.values.single
            as int;
    if (version != AppDatabase.schemaVersion) {
      throw StateError(
        'Schema $version cannot map to sync protocol $syncProtocolVersion; expected ${AppDatabase.schemaVersion}.',
      );
    }
    final issues = await SqliteSyncReadiness.fromDatabase(database).validate();
    final blockers = issues.where((issue) => issue.isBlocking).toList();
    if (blockers.isNotEmpty) throw SyncReadinessException(blockers);

    final records = <SyncRecord>[
      ...await _readTable('categories', SyncEntityKind.eventCategory),
      ...await _readTable('events', SyncEntityKind.event),
      ...await _readTable('run_segments', SyncEntityKind.eventRunSegment),
      ...await _readTable('routine_categories', SyncEntityKind.routineCategory),
      ...await _readTable('routines', SyncEntityKind.routine),
      ...await _readTable(
        'routine_executions',
        SyncEntityKind.routineExecution,
      ),
      ...await _readTable(
        'routine_run_segments',
        SyncEntityKind.routineRunSegment,
      ),
      ...await _readEventDayPlans(),
      ...await _readTable('world_nodes', SyncEntityKind.worldNode),
      ...await _readTable(
        'legacy_event_world_node_links',
        SyncEntityKind.legacyEventWorldNodeLink,
      ),
      ...await _readTable('plans', SyncEntityKind.plan),
      ...await _readTable('plan_items', SyncEntityKind.planItem),
    ];
    records.addAll(await _readTombstones(records));
    return SyncSnapshot(
      schemaVersion: version,
      exportedAtUtc: now().toUtc(),
      records: records,
      lists: await _readLists(),
      warnings: issues
          .where((issue) => !issue.isBlocking)
          .map((issue) => '${issue.code}: ${issue.detail}')
          .toList(),
    );
  }

  Future<List<SyncRecord>> _readTable(
    String table,
    SyncEntityKind kind,
  ) async => (await database.query(
    table,
    orderBy: 'id ASC',
  )).map((row) => _record(kind, row)).toList();

  SyncRecord _record(SyncEntityKind kind, Map<String, Object?> row) {
    final payload = Map<String, Object?>.from(row)
      ..remove('id')
      ..remove('created_at_utc')
      ..remove('updated_at_utc');
    return SyncRecord(
      kind: kind,
      metadata: SyncMetadata(
        id: row['id']! as String,
        createdAtUtc: _date(row['created_at_utc']),
        updatedAtUtc: _date(row['updated_at_utc']),
      ),
      payload: {
        for (final entry in payload.entries) _rename(entry.key): entry.value,
      },
    );
  }

  Future<List<SyncRecord>> _readEventDayPlans() async =>
      (await database.query(
        'event_day_plans',
        orderBy: 'event_id ASC, day_date ASC',
      )).map((row) {
        final eventId = row['event_id']! as String;
        final day = row['day_date']! as String;
        return SyncRecord(
          kind: SyncEntityKind.eventDayPlan,
          metadata: SyncMetadata(
            id: '$eventId@$day',
            createdAtUtc: _date(row['created_at_utc']),
            updatedAtUtc: _date(row['updated_at_utc']),
          ),
          payload: {
            'eventSyncId': eventId,
            'jaxDay': day,
            'order': row['order_index'],
          },
        );
      }).toList();

  Future<List<SyncRecord>> _readTombstones(List<SyncRecord> liveRecords) async {
    final live = {for (final record in liveRecords) record.key};
    final result = <SyncRecord>[];
    for (final row in await database.query(
      'sync_tombstones',
      orderBy: 'entity_type ASC, entity_id ASC',
    )) {
      final kind = _tombstoneKind(row['entity_type']! as String);
      final id = row['entity_id']! as String;
      if (live.contains('${kind.name}:$id')) {
        throw StateError('Live row and tombstone share ${kind.name}:$id');
      }
      final deleted = _date(row['deleted_at_utc']);
      result.add(
        SyncRecord(
          kind: kind,
          metadata: SyncMetadata(
            id: id,
            createdAtUtc: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
            updatedAtUtc: deleted,
            deletedAtUtc: deleted,
          ),
          payload: const {},
        ),
      );
    }
    return result;
  }

  Future<List<SyncList>> _readLists() async {
    final result = <SyncList>[];
    Future<void> add(SyncListKind kind, String sql) async {
      final groups = <String, List<String>>{};
      for (final row in await database.rawQuery(sql)) {
        groups
            .putIfAbsent(row['scope']! as String, () => [])
            .add(row['id']! as String);
      }
      for (final entry in groups.entries) {
        result.add(
          SyncList(kind: kind, scopeId: entry.key, itemIds: entry.value),
        );
      }
    }

    await add(
      SyncListKind.eventCategories,
      "SELECT id, 'all' scope FROM categories ORDER BY sort_order, created_at_utc, id",
    );
    await add(
      SyncListKind.eventSiblings,
      "SELECT id, COALESCE(parent_event_id, 'root') scope FROM events ORDER BY scope, sort_order, created_at_utc, id",
    );
    await add(
      SyncListKind.routineCategories,
      "SELECT id, 'all' scope FROM routine_categories ORDER BY sort_order, created_at_utc, id",
    );
    await add(
      SyncListKind.routines,
      "SELECT id, COALESCE(routine_category_id, 'uncategorized') scope FROM routines ORDER BY scope, sort_order, created_at_utc, id",
    );
    await add(
      SyncListKind.eventDayPlans,
      'SELECT event_id id, day_date scope FROM event_day_plans ORDER BY scope, order_index, created_at_utc, event_id',
    );
    await add(SyncListKind.worldNodeSiblings, '''SELECT id,
        CASE
          WHEN parent_world_node_id IS NOT NULL THEN 'parent:' || parent_world_node_id
          ELSE 'category:' || COALESCE(category_id, 'uncategorized')
        END scope
      FROM world_nodes
      ORDER BY scope, sort_order, created_at_utc, id''');
    await add(
      SyncListKind.planItems,
      'SELECT id, plan_id scope FROM plan_items ORDER BY scope, sort_order, created_at_utc, id',
    );
    return result;
  }

  String _rename(String sql) => switch (sql) {
    'parent_event_id' => 'parentSyncId',
    'parent_world_node_id' => 'parentWorldNodeSyncId',
    'category_id' => 'categorySyncId',
    'event_id' => 'eventSyncId',
    'routine_category_id' => 'routineCategorySyncId',
    'routine_id' => 'routineSyncId',
    'routine_execution_id' => 'routineExecutionSyncId',
    'sort_order' || 'order_index' => 'order',
    'routine_type' => 'routineType',
    'recurrence_type' => 'recurrenceType',
    'weekday_mask' => 'weekdayMask',
    'is_active' => 'isActive',
    'first_started_at_utc' => 'firstStartedAtUtc',
    'completed_at_utc' => 'completedAtUtc',
    'started_at_utc' => 'startedAtUtc',
    'ended_at_utc' => 'endedAtUtc',
    'occurrence_date' => 'jaxDay',
    'color_key' => 'colorKey',
    'legacy_event_id' => 'legacyEventSyncId',
    'world_node_id' => 'worldNodeSyncId',
    'plan_id' => 'planSyncId',
    'round_number' => 'roundNumber',
    _ => sql,
  };
  DateTime _date(Object? value) =>
      DateTime.fromMillisecondsSinceEpoch((value! as num).toInt(), isUtc: true);
  SyncEntityKind _tombstoneKind(String value) => switch (value) {
    'category' => SyncEntityKind.eventCategory,
    'event' => SyncEntityKind.event,
    'eventDayPlan' => SyncEntityKind.eventDayPlan,
    'eventRunSegment' => SyncEntityKind.eventRunSegment,
    'routineCategory' => SyncEntityKind.routineCategory,
    'routine' => SyncEntityKind.routine,
    'routineExecution' => SyncEntityKind.routineExecution,
    'routineRunSegment' => SyncEntityKind.routineRunSegment,
    'worldNode' => SyncEntityKind.worldNode,
    'legacyEventWorldNodeLink' => SyncEntityKind.legacyEventWorldNodeLink,
    'plan' => SyncEntityKind.plan,
    'planItem' => SyncEntityKind.planItem,
    _ => throw StateError('Unknown tombstone entity type: $value'),
  };
}

class SyncReadinessException implements Exception {
  const SyncReadinessException(this.issues);
  final List<SyncReadinessIssue> issues;
  @override
  String toString() => 'Sync readiness blocked: ${issues.join('; ')}';
}
