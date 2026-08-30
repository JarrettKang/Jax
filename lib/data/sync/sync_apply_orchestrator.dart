import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core/sync/resolved_sync_plan.dart';
import '../../core/sync/sync_contract.dart';
import '../../core/sync/sync_plan_compiler.dart';
import '../../core/sync/sync_snapshot_validator.dart';
import 'sqlite_sync_mutation_executor.dart';
import 'sqlite_sync_snapshot_adapter.dart';

class FixtureSyncDatabase {
  FixtureSyncDatabase(String value) : path = p.normalize(p.absolute(value)) {
    final temporary = p.normalize(p.absolute(Directory.systemTemp.path));
    if (!p.isWithin(temporary, path)) {
      throw ArgumentError(
        'Phase 2B-1 Apply target must be inside the system temporary directory: $path',
      );
    }
  }
  final String path;

  Future<void> verifyBoundary() async {
    final resolved = p.normalize(
      p.absolute(await File(path).resolveSymbolicLinks()),
    );
    final temporary = p.normalize(p.absolute(Directory.systemTemp.path));
    if (!p.isWithin(temporary, resolved)) {
      throw ArgumentError(
        'Phase 2B-1 Apply target resolves outside the system temporary '
        'directory: $resolved',
      );
    }
  }
}

abstract interface class SyncBackupService {
  Future<SyncBackupHandle> backup(
    FixtureSyncDatabase target,
    Directory directory,
    String label,
  );
  Future<void> restore(FixtureSyncDatabase target, SyncBackupHandle backup);
}

class SyncBackupHandle {
  const SyncBackupHandle(this.path, this.fingerprint);
  final String path;
  final String fingerprint;
}

class SqliteSyncBackupService implements SyncBackupService {
  const SqliteSyncBackupService();

  @override
  Future<SyncBackupHandle> backup(
    FixtureSyncDatabase target,
    Directory directory,
    String label,
  ) async {
    await directory.create(recursive: true);
    final destination = p.join(directory.path, '$label.db');
    if (File(destination).existsSync()) {
      throw StateError('Backup already exists: $destination');
    }
    sqfliteFfiInit();
    final database = await databaseFactoryFfi.openDatabase(
      target.path,
      options: OpenDatabaseOptions(readOnly: true),
    );
    try {
      final escaped = destination.replaceAll("'", "''");
      await database.execute("VACUUM INTO '$escaped'");
    } finally {
      await database.close();
    }
    final snapshot = await _readSnapshot(destination);
    return SyncBackupHandle(destination, snapshot.businessFingerprintSha256);
  }

  @override
  Future<void> restore(
    FixtureSyncDatabase target,
    SyncBackupHandle backup,
  ) async {
    final staged = '${target.path}.restore';
    final stagedFile = File(staged);
    if (stagedFile.existsSync()) await stagedFile.delete();
    await File(backup.path).copy(staged);
    for (final candidate in [
      target.path,
      '${target.path}-wal',
      '${target.path}-shm',
    ]) {
      final file = File(candidate);
      if (file.existsSync()) await file.delete();
    }
    await stagedFile.rename(target.path);
  }
}

abstract interface class SyncBaselineStore {
  Future<void> writeSuccessfulBaseline(SyncSnapshot snapshot);
}

class InMemorySyncBaselineStore implements SyncBaselineStore {
  SyncSnapshot? value;
  @override
  Future<void> writeSuccessfulBaseline(SyncSnapshot snapshot) async =>
      value = snapshot;
}

enum SyncApplyStage {
  prepared,
  backedUp,
  windowsApplied,
  windowsValidated,
  androidApplied,
  androidValidated,
  finalVerified,
  baselineWritten,
  committed,
  rolledBack,
  failed,
}

enum SyncApplyOutcome { succeeded, appliedBaselineWriteFailed }

class SyncApplySession {
  final List<SyncApplyStage> stages = [SyncApplyStage.prepared];
  Object? error;
}

class SyncApplyResult {
  const SyncApplyResult({
    required this.outcome,
    required this.session,
    required this.finalSnapshot,
  });
  final SyncApplyOutcome outcome;
  final SyncApplySession session;
  final SyncSnapshot finalSnapshot;
}

class SyncApplyException implements Exception {
  const SyncApplyException(this.code, this.message, this.session, [this.cause]);
  final String code;
  final String message;
  final SyncApplySession session;
  final Object? cause;
  @override
  String toString() => '$code: $message${cause == null ? '' : ' ($cause)'}';
}

class SyncApplyFailureInjection {
  const SyncApplyFailureInjection({
    this.failWindowsAfterOperation,
    this.failAndroidAfterOperation,
    this.failAfterWindowsCommit = false,
    this.failAfterAndroidCommit = false,
    this.failDuringPostValidation = false,
    this.failFinalVerification = false,
  });
  final int? failWindowsAfterOperation;
  final int? failAndroidAfterOperation;
  final bool failAfterWindowsCommit;
  final bool failAfterAndroidCommit;
  final bool failDuringPostValidation;
  final bool failFinalVerification;
}

class SyncApplyOrchestrator {
  const SyncApplyOrchestrator({
    this.compiler = const SyncPlanCompiler(),
    this.executor = const SqliteSyncMutationExecutor(),
    this.backups = const SqliteSyncBackupService(),
    this.validator = const SyncSnapshotValidator(),
  });
  final SyncPlanCompiler compiler;
  final SqliteSyncMutationExecutor executor;
  final SyncBackupService backups;
  final SyncSnapshotValidator validator;

  Future<SyncApplyResult> applyFixtureOnly({
    required ResolvedSyncPlan resolved,
    required FixtureSyncDatabase windows,
    required FixtureSyncDatabase android,
    required Directory backupDirectory,
    SyncSnapshot? baseline,
    SyncBaselineStore? baselineStore,
    SyncApplyFailureInjection injection = const SyncApplyFailureInjection(),
  }) async {
    await windows.verifyBoundary();
    await android.verifyBoundary();
    if (p.equals(windows.path, android.path)) {
      throw ArgumentError('Windows and Android fixture targets must differ.');
    }
    final session = SyncApplySession();
    final currentWindows = await _readSnapshot(windows.path);
    final currentAndroid = await _readSnapshot(android.path);
    final mutationPlan = compiler.compile(
      resolved: resolved,
      windows: currentWindows,
      android: currentAndroid,
      baseline: baseline,
    );

    SyncBackupHandle windowsBackup;
    SyncBackupHandle androidBackup;
    try {
      windowsBackup = await backups.backup(
        windows,
        backupDirectory,
        'windows_before',
      );
      androidBackup = await backups.backup(
        android,
        backupDirectory,
        'android_before',
      );
      session.stages.add(SyncApplyStage.backedUp);
    } catch (error) {
      session.error = error;
      session.stages.add(SyncApplyStage.failed);
      throw SyncApplyException(
        'BACKUP_FAILED',
        'Both backups must succeed before Apply starts.',
        session,
        error,
      );
    }

    try {
      await executor.apply(
        windows.path,
        mutationPlan.windowsOperations,
        injection: SyncMutationFailureInjection(
          failAfterOperation: injection.failWindowsAfterOperation,
        ),
      );
      session.stages.add(SyncApplyStage.windowsApplied);
      if (injection.failAfterWindowsCommit) {
        throw StateError('Injected failure after Windows commit');
      }
      await _validateApplied(
        windows.path,
        mutationPlan.expectedFinalSnapshot,
        injection.failDuringPostValidation,
      );
      session.stages.add(SyncApplyStage.windowsValidated);

      await executor.apply(
        android.path,
        mutationPlan.androidOperations,
        injection: SyncMutationFailureInjection(
          failAfterOperation: injection.failAndroidAfterOperation,
        ),
      );
      session.stages.add(SyncApplyStage.androidApplied);
      if (injection.failAfterAndroidCommit) {
        throw StateError('Injected failure after Android commit');
      }
      await _validateApplied(
        android.path,
        mutationPlan.expectedFinalSnapshot,
        injection.failDuringPostValidation,
      );
      session.stages.add(SyncApplyStage.androidValidated);

      final finalWindows = await _readSnapshot(windows.path);
      final finalAndroid = await _readSnapshot(android.path);
      final expected =
          mutationPlan.expectedFinalSnapshot.businessFingerprintSha256;
      if (injection.failFinalVerification ||
          finalWindows.businessFingerprintSha256 != expected ||
          finalAndroid.businessFingerprintSha256 != expected) {
        throw StateError(
          'Final synchronized business state differs from MutationPlan.',
        );
      }
      session.stages.add(SyncApplyStage.finalVerified);

      if (baselineStore != null) {
        try {
          await baselineStore.writeSuccessfulBaseline(finalWindows);
          session.stages.add(SyncApplyStage.baselineWritten);
        } catch (error) {
          session.error = error;
          session.stages.add(SyncApplyStage.committed);
          return SyncApplyResult(
            outcome: SyncApplyOutcome.appliedBaselineWriteFailed,
            session: session,
            finalSnapshot: finalWindows,
          );
        }
      }
      session.stages.add(SyncApplyStage.committed);
      return SyncApplyResult(
        outcome: SyncApplyOutcome.succeeded,
        session: session,
        finalSnapshot: finalWindows,
      );
    } catch (error) {
      session.error = error;
      try {
        await backups.restore(windows, windowsBackup);
        await backups.restore(android, androidBackup);
        final restoredWindows = await _readSnapshot(windows.path);
        final restoredAndroid = await _readSnapshot(android.path);
        if (restoredWindows.businessFingerprintSha256 !=
                currentWindows.businessFingerprintSha256 ||
            restoredAndroid.businessFingerprintSha256 !=
                currentAndroid.businessFingerprintSha256) {
          throw StateError(
            'Restored fingerprints differ from pre-Apply state.',
          );
        }
        session.stages.add(SyncApplyStage.rolledBack);
      } catch (rollbackError) {
        session.stages.add(SyncApplyStage.failed);
        throw SyncApplyException(
          'CRITICAL_ROLLBACK_FAILURE',
          'Could not restore both fixture databases.',
          session,
          rollbackError,
        );
      }
      throw SyncApplyException(
        'APPLY_FAILED_ROLLED_BACK',
        'Apply failed and both fixture databases were restored.',
        session,
        error,
      );
    }
  }

  Future<void> _validateApplied(
    String path,
    SyncSnapshot expected,
    bool injectFailure,
  ) async {
    if (injectFailure) {
      throw StateError('Injected post-Apply validation failure');
    }
    final snapshot = await _readSnapshot(path);
    final issues = validator.validate(snapshot);
    if (issues.isNotEmpty) {
      throw StateError('Post-Apply invariant validation failed: $issues');
    }
    if (snapshot.businessFingerprintSha256 !=
        expected.businessFingerprintSha256) {
      final actualRecords = {
        for (final record in snapshot.records)
          record.key: record.entityFingerprint,
      };
      final expectedRecords = {
        for (final record in expected.records)
          record.key: record.entityFingerprint,
      };
      final recordDiffs = {
        ...actualRecords.keys,
        ...expectedRecords.keys,
      }.where((key) => actualRecords[key] != expectedRecords[key]).toList();
      final actualLists = {
        for (final list in snapshot.lists) list.key: list.itemIds.join(','),
      };
      final expectedLists = {
        for (final list in expected.lists) list.key: list.itemIds.join(','),
      };
      final listDiffs = {
        ...actualLists.keys,
        ...expectedLists.keys,
      }.where((key) => actualLists[key] != expectedLists[key]).toList();
      throw StateError(
        'Post-Apply snapshot differs from expected final state: '
        '${snapshot.businessFingerprintSha256} != '
        '${expected.businessFingerprintSha256}; records=$recordDiffs; '
        'lists=$listDiffs actual=$actualLists expected=$expectedLists.',
      );
    }
  }
}

Future<SyncSnapshot> _readSnapshot(String source) async {
  sqfliteFfiInit();
  final database = await databaseFactoryFfi.openDatabase(source);
  try {
    return await SqliteSyncSnapshotAdapter(database).read();
  } finally {
    await database.close();
  }
}
