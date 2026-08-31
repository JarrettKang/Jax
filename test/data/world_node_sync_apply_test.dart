import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/world_node_ids.dart';
import 'package:jax/core/sync/sync_contract.dart';
import 'package:jax/core/sync/sync_mutation_plan.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/sync/sqlite_sync_mutation_executor.dart';
import 'package:jax/data/sync/sqlite_sync_snapshot_adapter.dart';

void main() {
  late AppDatabase app;
  setUp(() async => app = await AppDatabase.inMemory());
  tearDown(() => app.close());

  test('WorldNode records, mapping, and scoped order apply normally', () async {
    final operations = _operations();
    await const SqliteSyncMutationExecutor().applyDatabase(app, operations);

    final snapshot = await SqliteSyncSnapshotAdapter(app.database).read();
    expect(
      snapshot.records.where((r) => r.kind == SyncEntityKind.worldNode),
      hasLength(1),
    );
    expect(
      snapshot.records.where(
        (r) => r.kind == SyncEntityKind.legacyEventWorldNodeLink,
      ),
      hasLength(1),
    );
    expect(
      snapshot.lists
          .singleWhere((l) => l.kind == SyncListKind.worldNodeSiblings)
          .itemIds,
      [WorldNodeIds.fromLegacyEvent('legacy-event')],
    );
  });

  test(
    'WorldNode apply failure rolls back entity and mapping together',
    () async {
      await expectLater(
        const SqliteSyncMutationExecutor().applyDatabase(
          app,
          _operations(),
          injection: SyncMutationFailureInjection(failAfterOperation: 2),
        ),
        throwsStateError,
      );

      expect(await app.database.query('events'), isEmpty);
      expect(await app.database.query('world_nodes'), isEmpty);
      expect(
        await app.database.query('legacy_event_world_node_links'),
        isEmpty,
      );
    },
  );
}

final _instant = DateTime.fromMillisecondsSinceEpoch(100, isUtc: true);

List<SyncMutation> _operations() {
  final nodeId = WorldNodeIds.fromLegacyEvent('legacy-event');
  return [
    SyncMutation.upsertRecord(
      _record(SyncEntityKind.event, 'legacy-event', {
        'name': '复现WCA粒子KT熔化',
        'status': 'paused',
        'parentSyncId': null,
        'categorySyncId': null,
        'order': 0,
        'firstStartedAtUtc': null,
        'completedAtUtc': null,
      }),
    ),
    SyncMutation.upsertRecord(
      _record(SyncEntityKind.worldNode, nodeId, {
        'name': '复现WCA粒子KT熔化',
        'status': 'inProgress',
        'parentWorldNodeSyncId': null,
        'categorySyncId': null,
        'order': 0,
      }),
    ),
    SyncMutation.upsertRecord(
      _record(SyncEntityKind.legacyEventWorldNodeLink, 'legacy-event', {
        'legacyEventSyncId': 'legacy-event',
        'worldNodeSyncId': nodeId,
      }),
    ),
    SyncMutation.applyList(
      SyncList(
        kind: SyncListKind.eventSiblings,
        scopeId: 'root',
        itemIds: const ['legacy-event'],
      ),
    ),
    SyncMutation.applyList(
      SyncList(
        kind: SyncListKind.worldNodeSiblings,
        scopeId: 'category:uncategorized',
        itemIds: [nodeId],
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
    createdAtUtc: _instant,
    updatedAtUtc: _instant,
  ),
  payload: payload,
);
