import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/sync/resolved_sync_plan.dart';
import 'package:jax/core/sync/sync_compare_engine.dart';
import 'package:jax/core/sync/sync_contract.dart';
import 'package:jax/core/sync/sync_mutation_plan.dart';
import 'package:jax/core/sync/sync_plan_compiler.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/sync/sqlite_sync_mutation_executor.dart';
import 'package:jax/data/sync/sqlite_sync_snapshot_adapter.dart';
import 'package:jax/data/sync/sync_apply_orchestrator.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory root;
  late FixtureSyncDatabase windows;
  late FixtureSyncDatabase android;
  const compare = SyncCompareEngine();
  const orchestrator = SyncApplyOrchestrator();

  setUp(() async {
    root = await Directory.systemTemp.createTemp('jax-sync-apply-');
    windows = FixtureSyncDatabase(
      '${root.path}${Platform.pathSeparator}windows.db',
    );
    android = FixtureSyncDatabase(
      '${root.path}${Platform.pathSeparator}android.db',
    );
    await _createEmpty(windows.path);
    await _createEmpty(android.path);
  });
  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  test(
    'field/list resolution applies both sides and writes baseline last',
    () async {
      await _seed(windows.path, [
        event('a', 'PC'),
        event('b', 'B'),
      ], siblings(['a', 'b']));
      await _seed(android.path, [
        event('a', 'Phone'),
        event('b', 'B'),
        event('c', 'C'),
      ], siblings(['b', 'a', 'c']));
      final w = await _snapshot(windows.path),
          a = await _snapshot(android.path);
      final preview = compare.compare(windows: w, android: a);
      final baseline = InMemorySyncBaselineStore();
      final resolved = ResolvedSyncPlan(
        preview: preview,
        recordChoices: {'event:a': SyncSide.windows},
        listChoices: {'eventSiblings:root': SyncSide.android},
      );
      final mutation = const SyncPlanCompiler().compile(
        resolved: resolved,
        windows: w,
        android: a,
      );
      expect(
        mutation.windowsOperations
            .where((operation) => operation.list != null)
            .single
            .list!
            .itemIds,
        ['b', 'a', 'c'],
      );
      final result = await orchestrator.applyFixtureOnly(
        resolved: resolved,
        windows: windows,
        android: android,
        backupDirectory: Directory(
          '${root.path}${Platform.pathSeparator}backups',
        ),
        baselineStore: baseline,
      );
      expect(result.outcome, SyncApplyOutcome.succeeded);
      expect(result.session.stages.last, SyncApplyStage.committed);
      final finalW = await _snapshot(windows.path),
          finalA = await _snapshot(android.path);
      expect(
        finalW.businessFingerprintSha256,
        finalA.businessFingerprintSha256,
      );
      expect(
        baseline.value?.businessFingerprintSha256,
        finalW.businessFingerprintSha256,
      );
      for (final target in [windows, android]) {
        final db = await AppDatabase.open(target.path);
        final rows = await db.database.query(
          'events',
          columns: ['id', 'sort_order'],
          orderBy: 'sort_order',
        );
        expect(rows.map((row) => row['id']), ['b', 'a', 'c']);
        expect(rows.map((row) => row['sort_order']), [0, 1, 2]);
        await db.close();
      }
    },
  );

  test('mutation executor persists a committed sibling reorder', () async {
    await _seed(windows.path, [
      event('a', 'A'),
      event('b', 'B'),
    ], siblings(['a', 'b']));
    await const SqliteSyncMutationExecutor().apply(windows.path, [
      SyncMutation.upsertRecord(event('c', 'C')),
      SyncMutation.applyList(siblings(['b', 'a', 'c'])),
    ]);

    final db = await AppDatabase.open(windows.path);
    final rows = await db.database.query(
      'events',
      columns: ['id', 'sort_order'],
      orderBy: 'sort_order, id',
    );
    await db.close();
    expect(rows.map((row) => row['id']), ['b', 'a', 'c']);
    expect(rows.map((row) => row['sort_order']), [0, 1, 2]);
  });

  test(
    'delete tombstone propagates and choosing existing recreates identity',
    () async {
      final deleted = tombstone('d');
      await _seed(windows.path, [deleted], null);
      await _seed(android.path, [event('d', 'Keep')], siblings(['d']));
      var w = await _snapshot(windows.path), a = await _snapshot(android.path);
      var preview = compare.compare(windows: w, android: a);
      await orchestrator.applyFixtureOnly(
        resolved: ResolvedSyncPlan(
          preview: preview,
          recordChoices: {'event:d': SyncSide.windows},
        ),
        windows: windows,
        android: android,
        backupDirectory: Directory(
          '${root.path}${Platform.pathSeparator}delete-backups',
        ),
      );
      expect(
        (await _snapshot(android.path)).records
            .singleWhere((r) => r.metadata.id == 'd')
            .isDeleted,
        isTrue,
      );

      await root.delete(recursive: true);
      root = await Directory.systemTemp.createTemp('jax-sync-restore-');
      windows = FixtureSyncDatabase(
        '${root.path}${Platform.pathSeparator}windows.db',
      );
      android = FixtureSyncDatabase(
        '${root.path}${Platform.pathSeparator}android.db',
      );
      await _createEmpty(windows.path);
      await _createEmpty(android.path);
      await _seed(windows.path, [deleted], null);
      await _seed(android.path, [event('d', 'Keep')], siblings(['d']));
      w = await _snapshot(windows.path);
      a = await _snapshot(android.path);
      preview = compare.compare(windows: w, android: a);
      await orchestrator.applyFixtureOnly(
        resolved: ResolvedSyncPlan(
          preview: preview,
          recordChoices: {'event:d': SyncSide.android},
        ),
        windows: windows,
        android: android,
        backupDirectory: Directory(
          '${root.path}${Platform.pathSeparator}restore-backups',
        ),
      );
      final db = await AppDatabase.open(windows.path);
      expect(
        await db.database.query('events', where: 'id = ?', whereArgs: ['d']),
        hasLength(1),
      );
      expect(
        await db.database.query(
          'sync_tombstones',
          where: 'entity_id = ?',
          whereArgs: ['d'],
        ),
        isEmpty,
      );
      await db.close();
    },
  );

  test('stale and unresolved plans stop before backup', () async {
    await _seed(windows.path, [event('a', 'PC')], siblings(['a']));
    await _seed(android.path, [event('a', 'Phone')], siblings(['a']));
    final w = await _snapshot(windows.path), a = await _snapshot(android.path);
    final preview = compare.compare(windows: w, android: a);
    await expectLater(
      orchestrator.applyFixtureOnly(
        resolved: ResolvedSyncPlan(preview: preview),
        windows: windows,
        android: android,
        backupDirectory: Directory(
          '${root.path}${Platform.pathSeparator}unresolved',
        ),
      ),
      throwsA(predicate((error) => '$error'.contains('PLAN_NOT_RESOLVED'))),
    );
    await _seed(windows.path, [event('new', 'New')], null);
    await expectLater(
      orchestrator.applyFixtureOnly(
        resolved: ResolvedSyncPlan(
          preview: preview,
          recordChoices: {'event:a': SyncSide.windows},
        ),
        windows: windows,
        android: android,
        backupDirectory: Directory(
          '${root.path}${Platform.pathSeparator}stale',
        ),
      ),
      throwsA(predicate((error) => '$error'.contains('STALE_SYNC_PLAN'))),
    );
  });

  for (final scenario in <String, SyncApplyFailureInjection>{
    'Windows transaction failure': const SyncApplyFailureInjection(
      failWindowsAfterOperation: 1,
    ),
    'Android transaction failure': const SyncApplyFailureInjection(
      failAndroidAfterOperation: 1,
    ),
    'post-validation failure': const SyncApplyFailureInjection(
      failDuringPostValidation: true,
    ),
    'final verification failure': const SyncApplyFailureInjection(
      failFinalVerification: true,
    ),
  }.entries) {
    test('${scenario.key} restores both source fingerprints', () async {
      await _seed(windows.path, [event('a', 'A')], siblings(['a']));
      await _seed(android.path, [event('b', 'B')], siblings(['b']));
      final beforeW = await _snapshot(windows.path),
          beforeA = await _snapshot(android.path);
      final preview = compare.compare(windows: beforeW, android: beforeA);
      await expectLater(
        orchestrator.applyFixtureOnly(
          resolved: ResolvedSyncPlan(preview: preview),
          windows: windows,
          android: android,
          backupDirectory: Directory(
            '${root.path}${Platform.pathSeparator}${scenario.key}',
          ),
          injection: scenario.value,
        ),
        throwsA(
          predicate((error) => '$error'.contains('APPLY_FAILED_ROLLED_BACK')),
        ),
      );
      expect(
        (await _snapshot(windows.path)).businessFingerprintSha256,
        beforeW.businessFingerprintSha256,
      );
      expect(
        (await _snapshot(android.path)).businessFingerprintSha256,
        beforeA.businessFingerprintSha256,
      );
    });
  }

  test('second backup failure prevents all mutations', () async {
    await _seed(windows.path, [event('a', 'A')], siblings(['a']));
    await _seed(android.path, [event('b', 'B')], siblings(['b']));
    final beforeW = await _snapshot(windows.path),
        beforeA = await _snapshot(android.path);
    final guarded = SyncApplyOrchestrator(
      backups: _FailingBackupService(failSecondBackup: true),
    );

    await expectLater(
      guarded.applyFixtureOnly(
        resolved: ResolvedSyncPlan(
          preview: compare.compare(windows: beforeW, android: beforeA),
        ),
        windows: windows,
        android: android,
        backupDirectory: Directory(
          '${root.path}${Platform.pathSeparator}backup-failure',
        ),
      ),
      throwsA(
        isA<SyncApplyException>().having(
          (error) => error.code,
          'code',
          'BACKUP_FAILED',
        ),
      ),
    );
    expect(
      (await _snapshot(windows.path)).businessFingerprintSha256,
      beforeW.businessFingerprintSha256,
    );
    expect(
      (await _snapshot(android.path)).businessFingerprintSha256,
      beforeA.businessFingerprintSha256,
    );
  });

  test('restore failure is reported as critical rollback failure', () async {
    await _seed(windows.path, [event('a', 'A')], siblings(['a']));
    await _seed(android.path, [event('b', 'B')], siblings(['b']));
    final w = await _snapshot(windows.path), a = await _snapshot(android.path);
    final guarded = SyncApplyOrchestrator(
      backups: _FailingBackupService(failRestore: true),
    );

    await expectLater(
      guarded.applyFixtureOnly(
        resolved: ResolvedSyncPlan(
          preview: compare.compare(windows: w, android: a),
        ),
        windows: windows,
        android: android,
        backupDirectory: Directory(
          '${root.path}${Platform.pathSeparator}restore-failure',
        ),
        injection: const SyncApplyFailureInjection(
          failAfterWindowsCommit: true,
        ),
      ),
      throwsA(
        isA<SyncApplyException>().having(
          (error) => error.code,
          'code',
          'CRITICAL_ROLLBACK_FAILURE',
        ),
      ),
    );
  });

  test('baseline write failure preserves successful business apply', () async {
    await _seed(windows.path, [event('a', 'A')], siblings(['a']));
    await _seed(android.path, [event('b', 'B')], siblings(['b']));
    final w = await _snapshot(windows.path), a = await _snapshot(android.path);
    final result = await orchestrator.applyFixtureOnly(
      resolved: ResolvedSyncPlan(
        preview: compare.compare(windows: w, android: a),
      ),
      windows: windows,
      android: android,
      backupDirectory: Directory(
        '${root.path}${Platform.pathSeparator}baseline-fail',
      ),
      baselineStore: _FailingBaselineStore(),
    );
    expect(result.outcome, SyncApplyOutcome.appliedBaselineWriteFailed);
    expect(
      (await _snapshot(windows.path)).businessFingerprintSha256,
      (await _snapshot(android.path)).businessFingerprintSha256,
    );
    expect(result.session.stages, isNot(contains(SyncApplyStage.rolledBack)));
  });
}

final instant = DateTime.fromMillisecondsSinceEpoch(100, isUtc: true);
SyncRecord event(String id, String name) => SyncRecord(
  kind: SyncEntityKind.event,
  metadata: SyncMetadata(id: id, createdAtUtc: instant, updatedAtUtc: instant),
  payload: {
    'name': name,
    'status': 'paused',
    'parentSyncId': null,
    'order': 0,
    'categorySyncId': null,
    'firstStartedAtUtc': null,
    'completedAtUtc': null,
  },
);
SyncRecord tombstone(String id) => SyncRecord(
  kind: SyncEntityKind.event,
  metadata: SyncMetadata(
    id: id,
    createdAtUtc: instant,
    updatedAtUtc: instant,
    deletedAtUtc: instant,
  ),
  payload: const {},
);
SyncList siblings(List<String> ids) =>
    SyncList(kind: SyncListKind.eventSiblings, scopeId: 'root', itemIds: ids);

Future<void> _createEmpty(String file) async =>
    (await AppDatabase.open(file)).close();
Future<void> _seed(String file, List<SyncRecord> records, SyncList? list) =>
    const SqliteSyncMutationExecutor().apply(file, [
      for (final record in records) SyncMutation.upsertRecord(record),
      if (list != null) SyncMutation.applyList(list),
    ]);
Future<SyncSnapshot> _snapshot(String file) async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(file);
  try {
    return await SqliteSyncSnapshotAdapter(db).read();
  } finally {
    await db.close();
  }
}

class _FailingBaselineStore implements SyncBaselineStore {
  @override
  Future<void> writeSuccessfulBaseline(SyncSnapshot snapshot) =>
      throw StateError('Injected baseline failure');
}

class _FailingBackupService implements SyncBackupService {
  _FailingBackupService({
    this.failSecondBackup = false,
    this.failRestore = false,
  });

  final bool failSecondBackup;
  final bool failRestore;
  final SqliteSyncBackupService delegate = const SqliteSyncBackupService();
  int backupCalls = 0;

  @override
  Future<SyncBackupHandle> backup(
    FixtureSyncDatabase target,
    Directory directory,
    String label,
  ) {
    backupCalls++;
    if (failSecondBackup && backupCalls == 2) {
      throw StateError('Injected second backup failure');
    }
    return delegate.backup(target, directory, label);
  }

  @override
  Future<void> restore(FixtureSyncDatabase target, SyncBackupHandle backup) {
    if (failRestore) throw StateError('Injected restore failure');
    return delegate.restore(target, backup);
  }
}
