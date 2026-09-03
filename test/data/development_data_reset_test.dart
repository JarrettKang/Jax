import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/sync/sync_compare_engine.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/database/development_data_reset.dart';
import 'package:jax/core/sync/sync_contract.dart';
import 'package:jax/data/sync/sqlite_sync_snapshot_adapter.dart';

void main() {
  test('reset clears all business facts and establishes an explicit generation', () async {
    final app = await AppDatabase.inMemory();
    addTearDown(app.close);
    final db = app.database;
    await db.insert('categories', {
      'id': 'category', 'name': '开发', 'sort_order': 0, 'color_key': 0,
      'created_at_utc': 1, 'updated_at_utc': 1,
    });
    await db.insert('events', {
      'id': 'event', 'name': 'Event', 'status': 'pending',
      'source_plan_item_id': null, 'category_id': 'category',
      'created_at_utc': 1, 'updated_at_utc': 1,
    });
    await db.insert('event_day_plans', {
      'event_id': 'event', 'day_date': '2026-09-01', 'order_index': 0,
      'created_at_utc': 1, 'updated_at_utc': 1,
    });
    await db.insert('run_segments', {
      'id': 'segment', 'event_id': 'event',
      'started_at_utc': 1, 'ended_at_utc': 2,
      'created_at_utc': 1, 'updated_at_utc': 1,
    });
    const nodeId = '11111111-1111-4111-8111-111111111111';
    await db.insert('world_nodes', {
      'id': nodeId, 'name': 'World', 'status': 'inProgress',
      'is_focused': 1,
      'parent_world_node_id': null, 'category_id': 'category', 'sort_order': 0,
      'created_at_utc': 1, 'updated_at_utc': 1,
    });
    await db.insert('plans', {
      'id': 'plan', 'world_node_id': nodeId, 'title': null,
      'status': 'current', 'round_number': 1, 'ended_at_utc': null,
      'created_at_utc': 1, 'updated_at_utc': 1,
    });
    await db.insert('plan_items', {
      'id': 'item', 'plan_id': 'plan', 'title': 'Step', 'note': null,
      'status': 'draft', 'sort_order': 0,
      'created_at_utc': 1, 'updated_at_utc': 1,
    });
    await db.insert('routine_categories', {
      'id': 'routine-category', 'name': 'Daily', 'sort_order': 0,
      'color_key': 1, 'created_at_utc': 1, 'updated_at_utc': 1,
    });
    await db.insert('routines', {
      'id': 'routine', 'name': 'Review',
      'routine_category_id': 'routine-category', 'routine_type': 'scheduled',
      'recurrence_type': 'daily', 'weekday_mask': 0, 'is_active': 1,
      'sort_order': 0, 'created_at_utc': 1, 'updated_at_utc': 1,
    });
    await db.insert('routine_executions', {
      'id': 'routine-execution', 'routine_id': 'routine',
      'occurrence_date': '2026-09-01', 'status': 'completed',
      'completed_at_utc': 2, 'created_at_utc': 1, 'updated_at_utc': 2,
    });
    await db.insert('routine_run_segments', {
      'id': 'routine-segment', 'routine_execution_id': 'routine-execution',
      'started_at_utc': 1, 'ended_at_utc': 2,
      'created_at_utc': 1, 'updated_at_utc': 1,
    });
    await db.insert('world_category_collapse_preferences', {
      'section_key': 'world-category:category',
    });
    await db.insert('routine_category_collapse_preferences', {
      'section_key': 'routine-category:routine-category',
    });
    await db.insert('sync_tombstones', {
      'entity_type': 'event', 'entity_id': 'old-deleted',
      'deleted_at_utc': 1,
    });

    final reset = DevelopmentDataReset(app);
    await reset.run(generation: 'p25-clean-generation');
    expect((await reset.businessCounts()).values, everyElement(0));
    expect(
      (await db.query('dataset_metadata')).single['generation'],
      'p25-clean-generation',
    );
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    expect(await db.query('world_category_collapse_preferences'), isEmpty);
    expect(await db.query('routine_category_collapse_preferences'), isEmpty);
    final snapshot = await SqliteSyncSnapshotAdapter(db).read();
    expect(snapshot.datasetGeneration, 'p25-clean-generation');
    expect(snapshot.records, isEmpty);
  });

  test('sync comparison rejects snapshots from an old generation', () async {
    final windows = SyncSnapshot(
      schemaVersion: 16,
      datasetGeneration: 'new-generation',
      exportedAtUtc: DateTime.utc(2026),
      records: const [],
      lists: const [],
    );
    final android = SyncSnapshot(
      schemaVersion: 16,
      datasetGeneration: 'old-generation',
      exportedAtUtc: DateTime.utc(2026),
      records: const [],
      lists: const [],
    );
    expect(
      () => const SyncCompareEngine().compare(
        windows: windows,
        android: android,
      ),
      throwsStateError,
    );
  });
}
