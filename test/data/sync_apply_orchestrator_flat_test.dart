import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/sync/resolved_sync_plan.dart';
import 'package:jax/core/sync/sync_compare_engine.dart';
import 'package:jax/core/sync/sync_contract.dart';
import 'package:jax/core/sync/sync_mutation_plan.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/sync/sqlite_sync_mutation_executor.dart';
import 'package:jax/data/sync/sqlite_sync_snapshot_adapter.dart';
import 'package:jax/data/sync/sync_apply_orchestrator.dart';

void main() {
  late Directory root;
  late FixtureSyncDatabase windows;
  late FixtureSyncDatabase android;
  const orchestrator = SyncApplyOrchestrator();
  const compare = SyncCompareEngine();

  setUp(() async {
    root = await Directory.systemTemp.createTemp('jax-flat-sync-');
    windows = FixtureSyncDatabase('${root.path}${Platform.pathSeparator}windows.db');
    android = FixtureSyncDatabase('${root.path}${Platform.pathSeparator}android.db');
    await _create(windows.path, generation: 'clean-generation');
    await _create(android.path, generation: 'clean-generation');
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  test('orchestrator backs up, applies both flat datasets, then writes baseline', () async {
    await _seed(windows.path, _event('windows', 'Windows'));
    await _seed(android.path, _event('android', 'Android'));
    final beforeWindows = await _snapshot(windows.path);
    final beforeAndroid = await _snapshot(android.path);
    final baseline = InMemorySyncBaselineStore();
    final result = await orchestrator.applyFixtureOnly(
      resolved: ResolvedSyncPlan(
        preview: compare.compare(
          windows: beforeWindows,
          android: beforeAndroid,
        ),
      ),
      windows: windows,
      android: android,
      backupDirectory: Directory('${root.path}${Platform.pathSeparator}backups'),
      baselineStore: baseline,
    );

    expect(result.outcome, SyncApplyOutcome.succeeded);
    expect(result.session.stages, contains(SyncApplyStage.backedUp));
    expect(result.session.stages.last, SyncApplyStage.committed);
    final finalWindows = await _snapshot(windows.path);
    final finalAndroid = await _snapshot(android.path);
    expect(
      finalWindows.businessFingerprintSha256,
      finalAndroid.businessFingerprintSha256,
    );
    expect(
      baseline.value?.businessFingerprintSha256,
      finalWindows.businessFingerprintSha256,
    );
    expect(finalWindows.datasetGeneration, 'clean-generation');
  });

  test('post-Windows failure restores both original flat fingerprints', () async {
    await _seed(windows.path, _event('windows', 'Windows'));
    await _seed(android.path, _event('android', 'Android'));
    final beforeWindows = await _snapshot(windows.path);
    final beforeAndroid = await _snapshot(android.path);

    await expectLater(
      orchestrator.applyFixtureOnly(
        resolved: ResolvedSyncPlan(
          preview: compare.compare(
            windows: beforeWindows,
            android: beforeAndroid,
          ),
        ),
        windows: windows,
        android: android,
        backupDirectory: Directory(
          '${root.path}${Platform.pathSeparator}rollback-backups',
        ),
        injection: const SyncApplyFailureInjection(
          failAfterWindowsCommit: true,
        ),
      ),
      throwsA(predicate((error) => '$error'.contains('APPLY_FAILED_ROLLED_BACK'))),
    );
    expect(
      (await _snapshot(windows.path)).businessFingerprintSha256,
      beforeWindows.businessFingerprintSha256,
    );
    expect(
      (await _snapshot(android.path)).businessFingerprintSha256,
      beforeAndroid.businessFingerprintSha256,
    );
  });
}

Future<void> _create(String path, {required String generation}) async {
  final app = await AppDatabase.open(path);
  await app.database.update(
    'dataset_metadata',
    {'generation': generation},
    where: 'singleton = 1',
  );
  await app.close();
}

Future<void> _seed(String path, SyncRecord record) =>
    const SqliteSyncMutationExecutor().apply(path, [
      SyncMutation.upsertRecord(record),
    ]);

Future<SyncSnapshot> _snapshot(String path) async {
  final app = await AppDatabase.open(path);
  try {
    return await SqliteSyncSnapshotAdapter(app.database).read();
  } finally {
    await app.close();
  }
}

SyncRecord _event(String id, String name) => SyncRecord(
  kind: SyncEntityKind.event,
  metadata: SyncMetadata(
    id: id,
    createdAtUtc: DateTime.fromMillisecondsSinceEpoch(1, isUtc: true),
    updatedAtUtc: DateTime.fromMillisecondsSinceEpoch(1, isUtc: true),
  ),
  payload: {
    'name': name,
    'status': 'pending',
    'sourcePlanItemSyncId': null,
    'categorySyncId': null,
    'firstStartedAtUtc': null,
    'completedAtUtc': null,
  },
);
