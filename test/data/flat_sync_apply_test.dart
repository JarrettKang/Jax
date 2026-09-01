import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/sync/sync_contract.dart';
import 'package:jax/core/sync/sync_mutation_plan.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/sync/sqlite_sync_mutation_executor.dart';
import 'package:jax/data/sync/sqlite_sync_readiness.dart';
import 'package:jax/data/sync/sqlite_sync_snapshot_adapter.dart';

void main() {
  const executor = SqliteSyncMutationExecutor();

  test('protocol 4 applies a planned flat Event graph and exports it', () async {
    final app = await AppDatabase.inMemory();
    addTearDown(app.close);
    final operations = _plannedEventGraph();

    await executor.applyDatabase(app, operations);

    expect(await SqliteSyncReadiness(app).validate(), isEmpty);
    final snapshot = await SqliteSyncSnapshotAdapter(app.database).read();
    final event = snapshot.records.singleWhere(
      (record) => record.kind == SyncEntityKind.event,
    );
    expect(event.payload['sourcePlanItemSyncId'], 'item');
    expect(event.payload['categorySyncId'], isNull);
    expect(
      snapshot.records
          .where((record) => record.kind == SyncEntityKind.event)
          .map((record) => record.metadata.id),
      ['event'],
    );
    expect(
      snapshot.lists.where((list) => list.kind == SyncListKind.eventSiblings),
      isEmpty,
    );
  });

  test('flat sync mutation transaction rolls back every dependency', () async {
    final app = await AppDatabase.inMemory();
    addTearDown(app.close);

    await expectLater(
      executor.applyDatabase(
        app,
        _plannedEventGraph(),
        injection: const SyncMutationFailureInjection(failAfterOperation: 4),
      ),
      throwsStateError,
    );

    for (final table in ['categories', 'world_nodes', 'plans', 'plan_items', 'events']) {
      final count = await app.database.rawQuery('SELECT count(*) count FROM $table');
      expect(count.single['count'], 0, reason: table);
    }
    expect(await app.database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });
}

List<SyncMutation> _plannedEventGraph() {
  const nodeId = '11111111-1111-4111-8111-111111111111';
  return [
    SyncMutation.upsertRecord(_record(SyncEntityKind.eventCategory, 'category', {
      'name': 'Jax',
      'order': 0,
      'colorKey': 0,
    })),
    SyncMutation.upsertRecord(_record(SyncEntityKind.worldNode, nodeId, {
      'name': 'Planning',
      'status': 'inProgress',
      'parentWorldNodeSyncId': null,
      'categorySyncId': 'category',
      'order': 0,
    })),
    SyncMutation.upsertRecord(_record(SyncEntityKind.plan, 'plan', {
      'worldNodeSyncId': nodeId,
      'title': null,
      'status': 'focused',
      'roundNumber': 1,
      'endedAtUtc': null,
    })),
    SyncMutation.upsertRecord(_record(SyncEntityKind.planItem, 'item', {
      'planSyncId': 'plan',
      'title': 'Flat Event',
      'note': null,
      'status': 'dispatched',
      'order': 0,
    })),
    SyncMutation.upsertRecord(_record(SyncEntityKind.event, 'event', {
      'name': 'Flat Event',
      'status': 'pending',
      'sourcePlanItemSyncId': 'item',
      'categorySyncId': null,
      'firstStartedAtUtc': null,
      'completedAtUtc': null,
    })),
    SyncMutation.applyList(
      const SyncList(
        kind: SyncListKind.eventCategories,
        scopeId: 'all',
        itemIds: ['category'],
      ),
    ),
    SyncMutation.applyList(
      const SyncList(
        kind: SyncListKind.worldNodeSiblings,
        scopeId: 'category:category',
        itemIds: [nodeId],
      ),
    ),
    SyncMutation.applyList(
      const SyncList(
        kind: SyncListKind.planItems,
        scopeId: 'plan',
        itemIds: ['item'],
      ),
    ),
  ];
}

SyncRecord _record(
  SyncEntityKind kind,
  String id,
  Map<String, Object?> payload,
) => SyncRecord(
  kind: kind,
  metadata: SyncMetadata(
    id: id,
    createdAtUtc: DateTime.fromMillisecondsSinceEpoch(1, isUtc: true),
    updatedAtUtc: DateTime.fromMillisecondsSinceEpoch(1, isUtc: true),
  ),
  payload: payload,
);
