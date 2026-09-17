import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/plan.dart';
import 'package:jax/core/entities/plan_item.dart';
import 'package:jax/core/entities/world_node.dart';
import 'package:jax/core/sync/sync_contract.dart';
import 'package:jax/core/sync/sync_compare_engine.dart';
import 'package:jax/core/sync/resolved_sync_plan.dart';
import 'package:jax/core/sync/sync_mutation_plan.dart';
import 'package:jax/core/sync/sync_plan_compiler.dart';
import 'package:jax/core/sync/sync_snapshot_validator.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/repositories/sqlite_planning_repository.dart';
import 'package:jax/data/repositories/sqlite_world_node_repository.dart';
import 'package:jax/data/sync/sqlite_sync_mutation_executor.dart';
import 'package:jax/data/sync/sqlite_sync_snapshot_adapter.dart';

import '../support/world_map_fixture.dart';

String childId(int n) =>
    'eeeeeeee-0000-4000-8000-${n.toString().padLeft(12, '0')}';
void main() {
  late Directory dir;
  late AppDatabase windows, android;
  late SyncSnapshot baseline;
  final now = DateTime.utc(2026, 9, 14, 7);
  const executor = SqliteSyncMutationExecutor();
  Future<SyncSnapshot> snapshot(AppDatabase db) =>
      SqliteSyncSnapshotAdapter(db.database).read();
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('jax-promotion-sync-');
    windows = await AppDatabase.open('${dir.path}/windows.db');
    android = await AppDatabase.open('${dir.path}/android.db');
    await seedWorldMapFixture(windows);
    baseline = await snapshot(windows);
    await android.database.update('dataset_metadata', {
      'generation': baseline.datasetGeneration,
    });
    await executor.applyDatabase(android, [
      for (final r in baseline.records) SyncMutation.upsertRecord(r),
      for (final l in baseline.lists) SyncMutation.applyList(l),
    ]);
  });
  tearDown(() async {
    await windows.close();
    await android.close();
    await dir.delete(recursive: true);
  });
  test(
    'old peer database must upgrade before producing a Sync snapshot',
    () async {
      await android.database.execute('PRAGMA user_version = 21');
      await expectLater(snapshot(android), throwsStateError);
      await android.database.execute(
        'PRAGMA user_version = ${AppDatabase.schemaVersion}',
      );
      expect((await snapshot(android)).protocolVersion, syncProtocolVersion);
    },
  );
  Future<SyncMutationPlan> compile() async {
    final w = await snapshot(windows), a = await snapshot(android);
    final preview = const SyncCompareEngine().compare(
      windows: w,
      android: a,
      baseline: baseline,
    );
    final resolved = ResolvedSyncPlan(preview: preview);
    return const SyncPlanCompiler().compile(
      resolved: resolved,
      windows: w,
      android: a,
      baseline: baseline,
    );
  }

  Future<void> sync() async {
    final plan = await compile();
    await executor.applyDatabase(windows, plan.windowsOperations);
    await executor.applyDatabase(android, plan.androidOperations);
    baseline = await snapshot(windows);
    expect(
      (await snapshot(android)).businessFingerprintSha256,
      baseline.businessFingerprintSha256,
    );
    expect(const SyncSnapshotValidator().validate(baseline), isEmpty);
  }

  Future<WorldNode> promote(AppDatabase db, int id) =>
      SqlitePlanningRepository(db).promotePlanItem(
        planItemId: 'fixture-step-0',
        worldNodeId: childId(id),
        now: now,
      );
  test('promotion, rename, completed child and ended parent sync in both directions', () async {
    await promote(windows, 1);
    await sync();
    for (final db in [windows, android]) {
      final ref = (await SqlitePlanningRepository(
        db,
      ).getPlanItems('fixture-plan')).first;
      expect(ref.type, PlanItemType.worldNodeReference);
      expect(ref.promotedWorldNodeId, childId(1));
      expect(
        (await SqliteWorldNodeRepository(db).getWorldNode(childId(1)))!
            .isFocused,
        isTrue,
      );
      expect(await db.database.query('plans'), hasLength(1));
      expect(await db.database.query('events'), isEmpty);
    }
    final worlds = SqliteWorldNodeRepository(android);
    final child = (await worlds.getWorldNode(childId(1)))!;
    await worlds.updateWorldNode(
      child.copyWith(
        name: 'Renamed',
        updatedAt: now.add(const Duration(seconds: 1)),
      ),
    );
    await sync();
    expect(
      (await SqliteWorldNodeRepository(windows).getWorldNode(child.id))!.name,
      'Renamed',
    );
    await worlds.updateWorldNode(
      (await worlds.getWorldNode(child.id))!
          .copyWith(status: WorldNodeStatus.completed),
    );
    await SqlitePlanningRepository(windows)
        .setPlanStatus('fixture-plan', PlanStatus.ended, now);
    await sync();
    expect(
      (await SqlitePlanningRepository(android).getPlanItems('fixture-plan'))
          .first
          .isPromoted,
      isTrue,
    );
    expect(
      (await SqliteWorldNodeRepository(windows).getWorldNode(child.id))!.status,
      WorldNodeStatus.completed,
    );
  });
  test('Sync apply failure cannot leave half a promotion', () async {
    await promote(windows, 1);
    final plan = await compile();
    final before = (await snapshot(android)).businessFingerprintSha256;
    await expectLater(
      executor.applyDatabase(
        android,
        plan.androidOperations,
        injection: const SyncMutationFailureInjection(failAfterOperation: 1),
      ),
      throwsA(anything),
    );
    expect((await snapshot(android)).businessFingerprintSha256, before);
    expect(
      await SqliteWorldNodeRepository(android).getWorldNode(childId(1)),
      isNull,
    );
    expect(
      (await SqlitePlanningRepository(android).getPlanItems('fixture-plan'))
          .first
          .isPromoted,
      isFalse,
    );
    await sync();
  });
  for (final action in ['start', 'promote']) {
    test(
      'concurrent promotion versus $action remains an explicit conflict',
      () async {
        await promote(windows, 1);
        if (action == 'promote') {
          await promote(android, 2);
        } else {
          await SqlitePlanningRepository(android).startPlanItem(
            planItemId: 'fixture-step-0',
            eventId: 'event',
            segmentId: 'segment',
            dayKey: '2026-09-14',
            now: now,
          );
        }
        final w = await snapshot(windows), a = await snapshot(android);
        final preview = const SyncCompareEngine().compare(
          windows: w,
          android: a,
          baseline: baseline,
        );
        final resolved = ResolvedSyncPlan(preview: preview);
        expect(resolved.unresolvedKeys, isNotEmpty);
        expect(
          () => const SyncPlanCompiler().compile(
            resolved: resolved,
            windows: w,
            android: a,
            baseline: baseline,
          ),
          throwsA(isA<SyncPlanException>()),
        );
      },
    );
  }
  test('dangling target is rejected by validator and raw executor without tombstones', () async {
    await promote(windows, 1);
    await sync();
    final node = baseline.records.singleWhere(
      (r) => r.kind == SyncEntityKind.worldNode && r.metadata.id == childId(1),
    );
    final deleted = SyncRecord(
      kind: node.kind,
      metadata: SyncMetadata(
        id: node.metadata.id,
        createdAtUtc: node.metadata.createdAtUtc,
        updatedAtUtc: now,
        deletedAtUtc: now,
      ),
      payload: const {},
    );
    final invalid = SyncSnapshot(
      schemaVersion: 22,
      exportedAtUtc: now,
      records: [
        for (final r in baseline.records)
          if (r.key == node.key) deleted else r,
      ],
      lists: baseline.lists,
    );
    expect(
      const SyncSnapshotValidator().validate(invalid),
      contains('plan-item-promoted-world-node:fixture-step-0'),
    );
    await expectLater(
      executor.applyDatabase(android, [SyncMutation.deleteRecord(deleted)]),
      throwsA(anything),
    );
    expect(
      (await snapshot(android)).businessFingerprintSha256,
      baseline.businessFingerprintSha256,
    );
    // Removing the parent Plan is an explicit removal of its references, not a child cascade.
    await SqlitePlanningRepository(windows).deletePlan('fixture-plan');
    await sync();
    expect(
      await SqliteWorldNodeRepository(android).getWorldNode(childId(1)),
      isNotNull,
    );
    await executor.applyDatabase(windows, [SyncMutation.deleteRecord(deleted)]);
    await sync();
    expect(
      await SqliteWorldNodeRepository(android).getWorldNode(childId(1)),
      isNull,
    );
    expect(
      await android.database.rawQuery('PRAGMA foreign_key_check'),
      isEmpty,
    );
  });
  test('protocol 8 baseline adds null references without changing historical fields', () async {
    final old = baseline.toJson();
    old['syncProtocolVersion'] = 8;
    old['schemaVersion'] = 21;
    for (final record in old['records']! as List) {
      if (record['kind'] == 'planItem') {
        (record['payload'] as Map).remove('promotedWorldNodeSyncId');
      }
    }
    final upgraded = SyncSnapshot.fromJson(old);
    expect(upgraded.protocolVersion, syncProtocolVersion);
    expect(upgraded.datasetGeneration, baseline.datasetGeneration);
    expect(
      upgraded.businessFingerprintSha256,
      baseline.businessFingerprintSha256,
    );
    expect(
      upgraded.records.map((r) => r.metadata.toJson()),
      baseline.records.map((r) => r.metadata.toJson()),
    );
    baseline = upgraded;
    await promote(windows, 1);
    await sync();
  });
}
