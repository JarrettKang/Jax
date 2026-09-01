import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/sync/sync_contract.dart';
import 'package:jax/core/sync/sync_mutation_plan.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/sync/sqlite_sync_mutation_executor.dart';
import 'package:jax/data/sync/sqlite_sync_snapshot_adapter.dart';

void main() {
  late AppDatabase app;
  setUp(() async => app = await AppDatabase.inMemory());
  tearDown(() => app.close());

  test('Plan, PlanItem, and scoped order apply and round-trip', () async {
    await const SqliteSyncMutationExecutor().applyDatabase(app, _operations());
    final snapshot = await SqliteSyncSnapshotAdapter(app.database).read();
    expect(
      snapshot.records.where((r) => r.kind == SyncEntityKind.plan),
      hasLength(1),
    );
    expect(
      snapshot.records.where((r) => r.kind == SyncEntityKind.planItem),
      hasLength(2),
    );
    expect(
      snapshot.lists
          .singleWhere((l) => l.kind == SyncListKind.planItems)
          .itemIds,
      ['item-b', 'item-a'],
    );
  });

  test('Planning apply failure rolls back all related rows', () async {
    await expectLater(
      const SqliteSyncMutationExecutor().applyDatabase(
        app,
        _operations(),
        injection: SyncMutationFailureInjection(failAfterOperation: 2),
      ),
      throwsStateError,
    );
    expect(await app.database.query('world_nodes'), isEmpty);
    expect(await app.database.query('plans'), isEmpty);
    expect(await app.database.query('plan_items'), isEmpty);
  });

  test('PlanItem tombstone propagates without deleting its Plan', () async {
    await const SqliteSyncMutationExecutor().applyDatabase(app, _operations());
    await const SqliteSyncMutationExecutor().applyDatabase(app, [
      SyncMutation.deleteRecord(_deleted(SyncEntityKind.planItem, 'item-a')),
    ]);
    expect(await app.database.query('plans'), hasLength(1));
    expect(await app.database.query('plan_items'), hasLength(1));
    expect(
      await app.database.query(
        'sync_tombstones',
        where: 'entity_type = ? AND entity_id = ?',
        whereArgs: ['planItem', 'item-a'],
      ),
      hasLength(1),
    );
  });
}

const _nodeId = '11111111-1111-4111-8111-111111111111';
final _time = DateTime.fromMillisecondsSinceEpoch(100, isUtc: true);

List<SyncMutation> _operations() => [
  SyncMutation.upsertRecord(
    _record(SyncEntityKind.worldNode, _nodeId, {
      'name': 'Jax',
      'status': 'inProgress',
      'parentWorldNodeSyncId': null,
      'categorySyncId': null,
      'order': 0,
    }),
  ),
  SyncMutation.upsertRecord(
    _record(SyncEntityKind.plan, 'plan', {
      'worldNodeSyncId': _nodeId,
      'title': '本地同步',
      'status': 'focused',
      'roundNumber': 1,
      'endedAtUtc': null,
    }),
  ),
  SyncMutation.upsertRecord(
    _record(SyncEntityKind.planItem, 'item-a', {
      'planSyncId': 'plan',
      'title': 'A',
      'note': null,
      'status': 'draft',
      'order': 0,
    }),
  ),
  SyncMutation.upsertRecord(
    _record(SyncEntityKind.planItem, 'item-b', {
      'planSyncId': 'plan',
      'title': 'B',
      'note': 'note',
      'status': 'next',
      'order': 1,
    }),
  ),
  SyncMutation.applyList(
    const SyncList(
      kind: SyncListKind.worldNodeSiblings,
      scopeId: 'category:uncategorized',
      itemIds: [_nodeId],
    ),
  ),
  SyncMutation.applyList(
    const SyncList(
      kind: SyncListKind.planItems,
      scopeId: 'plan',
      itemIds: ['item-b', 'item-a'],
    ),
  ),
];

SyncRecord _record(
  SyncEntityKind kind,
  String id,
  Map<String, Object?> payload,
) => SyncRecord(
  kind: kind,
  metadata: SyncMetadata(id: id, createdAtUtc: _time, updatedAtUtc: _time),
  payload: payload,
);

SyncRecord _deleted(SyncEntityKind kind, String id) => SyncRecord(
  kind: kind,
  metadata: SyncMetadata(
    id: id,
    createdAtUtc: _time,
    updatedAtUtc: _time,
    deletedAtUtc: _time,
  ),
  payload: const {},
);
