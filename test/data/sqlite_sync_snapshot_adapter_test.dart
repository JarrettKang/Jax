import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/sync/sync_contract.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/sync/sqlite_sync_snapshot_adapter.dart';

void main() {
  late AppDatabase database;
  setUp(() async => database = await AppDatabase.inMemory());
  tearDown(() => database.close());

  Future<List<Map<String, Object?>>> facts() async {
    final result = <Map<String, Object?>>[];
    for (final table in [
      'categories',
      'events',
      'run_segments',
      'routine_categories',
      'routines',
      'routine_executions',
      'routine_run_segments',
      'event_day_plans',
      'world_nodes',
      'sync_tombstones',
    ]) {
      result.addAll(
        (await database.database.query(table))
            .map((row) => {'table': table, ...row}),
      );
    }
    return result;
  }

  test(
    'snapshot is deterministic, complete, and excludes UI preferences',
    () async {
      final db = database.database;
      await db.insert('categories', {
        'id': 'category',
        'name': '开发',
        'sort_order': 0,
        'color_key': 2,
        'created_at_utc': 10,
        'updated_at_utc': 10,
      });
      await db.insert('events', {
        'id': 'event',
        'name': 'Jax',
        'status': 'paused',
        'source_plan_item_id': null,
        'category_id': 'category',
        'first_started_at_utc': 20,
        'completed_at_utc': null,
        'created_at_utc': 10,
        'updated_at_utc': 20,
      });
      await db.insert('event_day_plans', {
        'event_id': 'event',
        'day_date': '2026-08-30',
        'order_index': 0,
        'created_at_utc': 10,
        'updated_at_utc': 10,
      });
      await db.insert('run_segments', {
        'id': 'event-segment',
        'event_id': 'event',
        'started_at_utc': 30,
        'ended_at_utc': 40,
        'created_at_utc': 30,
        'updated_at_utc': 40,
      });
      await db.insert('routine_categories', {
        'id': 'routine-category',
        'name': '起居',
        'sort_order': 0,
        'color_key': 3,
        'created_at_utc': 10,
        'updated_at_utc': 10,
      });
      await db.insert('routines', {
        'id': 'routine',
        'name': '洗漱',
        'routine_category_id': 'routine-category',
        'routine_type': 'scheduled',
        'recurrence_type': 'daily',
        'weekday_mask': 0,
        'is_active': 1,
        'sort_order': 0,
        'created_at_utc': 10,
        'updated_at_utc': 10,
      });
      await db.insert('routine_executions', {
        'id': 'execution',
        'routine_id': 'routine',
        'occurrence_date': '2026-08-30',
        'status': 'completed',
        'completed_at_utc': 60,
        'created_at_utc': 50,
        'updated_at_utc': 60,
      });
      await db.insert('routine_run_segments', {
        'id': 'routine-segment',
        'routine_execution_id': 'execution',
        'started_at_utc': 50,
        'ended_at_utc': 60,
        'created_at_utc': 50,
        'updated_at_utc': 60,
      });
      await db.insert('world_category_collapse_preferences', {
        'section_key': 'category',
      });
      await db.insert('world_nodes', {
        'id': '11111111-1111-4111-8111-111111111111',
        'name': 'Jax 世界',
        'status': 'inProgress',
        'is_focused': 0,
        'parent_world_node_id': null,
        'sort_order': 0,
        'category_id': 'category',
        'created_at_utc': 10,
        'updated_at_utc': 10,
      });

      final adapter = SqliteSyncSnapshotAdapter(
        db,
        now: () => DateTime.utc(2026),
      );
      final before = await facts();
      final first = await adapter.read();
      final second = await adapter.read();
      final after = await facts();

      expect(first.protocolVersion, syncProtocolVersion);
      expect(first.businessFingerprint, second.businessFingerprint);
      expect(
        first.records.map((r) => r.kind),
        containsAll([
          SyncEntityKind.eventCategory,
          SyncEntityKind.event,
          SyncEntityKind.eventDayPlan,
          SyncEntityKind.worldNode,
        ]),
      );
      final event = first.records.singleWhere(
        (r) => r.kind == SyncEntityKind.event,
      );
      expect(event.payload, containsPair('categorySyncId', 'category'));
      expect(event.payload, containsPair('firstStartedAtUtc', 20));
      expect(event.payload.keys.toSet(), {
        'name',
        'status',
        'sourcePlanItemSyncId',
        'categorySyncId',
        'firstStartedAtUtc',
        'completedAtUtc',
      });
      expect(first.datasetGeneration, isNotEmpty);
      expect(
        first.records
            .singleWhere((r) => r.kind == SyncEntityKind.routine)
            .payload
            .keys
            .toSet(),
        {
          'name',
          'routineCategorySyncId',
          'routineType',
          'recurrenceType',
          'weekdayMask',
          'isActive',
          'order',
        },
      );
      expect(
        first.records
            .singleWhere((r) => r.kind == SyncEntityKind.routineExecution)
            .payload
            .keys
            .toSet(),
        {'routineSyncId', 'jaxDay', 'status', 'completedAtUtc'},
      );
      expect(
        first.records
            .singleWhere((r) => r.kind == SyncEntityKind.eventRunSegment)
            .payload
            .keys
            .toSet(),
        {'eventSyncId', 'startedAtUtc', 'endedAtUtc'},
      );
      expect(
        first.records
            .singleWhere((r) => r.kind == SyncEntityKind.routineRunSegment)
            .payload
            .keys
            .toSet(),
        {'routineExecutionSyncId', 'startedAtUtc', 'endedAtUtc'},
      );
      expect(
        first.lists
            .singleWhere((l) => l.kind == SyncListKind.eventDayPlans)
            .itemIds,
        ['event'],
      );
      expect(
        first.lists
            .singleWhere((l) => l.kind == SyncListKind.worldNodeSiblings)
            .scopeId,
        'category:category',
      );
      expect(first.toJsonString(), second.toJsonString());
      expect(after, before, reason: 'Analyze must not mutate business facts');
      expect(first.toJsonString(), isNot(contains('collapse_preferences')));
    },
  );

  test('snapshot includes tombstones and readiness warnings', () async {
    final db = database.database;
    for (final id in ['a', 'b']) {
      await db.insert('categories', {
        'id': id,
        'name': id,
        'sort_order': 5,
        'color_key': 0,
        'created_at_utc': 10,
        'updated_at_utc': 10,
      });
    }
    await db.delete('categories', where: 'id = ?', whereArgs: ['a']);
    final snapshot = await SqliteSyncSnapshotAdapter(db).read();
    final tombstone = snapshot.records.singleWhere((r) => r.metadata.id == 'a');
    expect(tombstone.isDeleted, isTrue);
    // Only one live category remains, so create another duplicate after deletion.
    await db.insert('categories', {
      'id': 'c',
      'name': 'c',
      'sort_order': 5,
      'color_key': 0,
      'created_at_utc': 10,
      'updated_at_utc': 10,
    });
    final warned = await SqliteSyncSnapshotAdapter(db).read();
    expect(warned.warnings, anyElement(contains('category-order')));
  });

  test('blocking readiness issue stops export without repair', () async {
    final db = database.database;
    await db.insert('events', {
      'id': 'event',
      'name': 'Broken',
      'status': 'running',
      'source_plan_item_id': null,
      'category_id': null,
      'first_started_at_utc': 10,
      'completed_at_utc': null,
      'created_at_utc': 10,
      'updated_at_utc': 10,
    });
    await expectLater(
      SqliteSyncSnapshotAdapter(db).read(),
      throwsA(isA<SyncReadinessException>()),
    );
    expect((await db.query('events')).single['status'], 'running');
  });
}
