import 'dart:convert';
import 'dart:io';

import 'package:jax/core/sync/resolved_sync_plan.dart';
import 'package:jax/core/sync/sync_compare_engine.dart';
import 'package:jax/core/sync/sync_contract.dart';
import 'package:jax/core/sync/sync_mutation_plan.dart';
import 'package:jax/core/sync/sync_plan_compiler.dart';
import 'package:jax/core/sync/sync_snapshot_validator.dart';
import 'package:jax/data/sync/file_sync_baseline_store.dart';
import 'package:jax/data/sync/sqlite_sync_mutation_executor.dart';
import 'package:jax/data/sync/sqlite_sync_snapshot_adapter.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) _usage();
  switch (args.first) {
    case 'resolution-template' when args.length == 3:
      await _resolutionTemplate(args[1], args[2]);
    case 'compile' when args.length == 6 || args.length == 7:
      await _compile(
        planPath: args[1],
        windowsSnapshotPath: args[2],
        androidSnapshotPath: args[3],
        resolutionPath: args[4],
        outputPath: args[5],
        baselinePath: args.length == 7 ? args[6] : null,
      );
    case 'apply-windows' when args.length == 4:
      await _applyWindows(args[1], args[2], args[3]);
    case 'verify' when args.length == 3:
      await _verify(args[1], args[2]);
    case 'baseline-write' when args.length == 3:
      await _writeBaseline(args[1], args[2]);
    case 'baseline-read' when args.length == 2:
      await _readBaseline(args[1]);
    default:
      _usage();
  }
}

Never _usage() {
  stderr.writeln('''Phase 2B-2 guarded Debug transport.
Usage:
  dart run tool/sync_phase2b2.dart resolution-template <plan.json> <resolution.json>
  dart run tool/sync_phase2b2.dart compile <plan.json> <windows.json> <android.json> <resolution.json> <mutation.json> [baseline.json]
  dart run tool/sync_phase2b2.dart apply-windows <real-windows.db> <mutation.json> <verified-backup.db>
  dart run tool/sync_phase2b2.dart verify <database.db> <mutation.json>
  dart run tool/sync_phase2b2.dart baseline-write <baseline.json> <mutation.json>
  dart run tool/sync_phase2b2.dart baseline-read <baseline.json>''');
  exit(64);
}

Future<void> _resolutionTemplate(String planPath, String outputPath) async {
  final plan = SyncPlan.fromJsonString(await File(planPath).readAsString());
  final output = {
    'syncProtocolVersion': plan.protocolVersion,
    'windowsSourceFingerprint': plan.windowsSourceFingerprint,
    'androidSourceFingerprint': plan.androidSourceFingerprint,
    if (plan.baselineFingerprint != null)
      'baselineFingerprint': plan.baselineFingerprint,
    'recordChoices': {
      for (final item in plan.manualConflicts)
        item.key: SyncSide.unresolved.name,
    },
    'listChoices': {
      for (final item in plan.listConflicts) item.key: SyncSide.unresolved.name,
    },
    'invariantResolutions': <String, Object?>{},
  };
  await _writeJson(outputPath, output);
  stdout.writeln('RESOLUTION_TEMPLATE_WRITTEN $outputPath');
}

Future<void> _compile({
  required String planPath,
  required String windowsSnapshotPath,
  required String androidSnapshotPath,
  required String resolutionPath,
  required String outputPath,
  required String? baselinePath,
}) async {
  final preview = SyncPlan.fromJsonString(await File(planPath).readAsString());
  final windows = _snapshotFile(windowsSnapshotPath);
  final android = _snapshotFile(androidSnapshotPath);
  final baseline = baselinePath == null ? null : _snapshotFile(baselinePath);
  final resolutionJson = (jsonDecode(
    await File(resolutionPath).readAsString(),
  ) as Map).cast<String, Object?>();
  final resolved = ResolvedSyncPlan.fromResolutionJson(preview, resolutionJson);
  final mutation = const SyncPlanCompiler().compile(
    resolved: resolved,
    windows: windows,
    android: android,
    baseline: baseline,
  );
  final output = mutation.toJson()
    ..['windowsSummary'] = _operationSummary(
      mutation.windowsOperations,
      windows,
    )
    ..['androidSummary'] = _operationSummary(
      mutation.androidOperations,
      android,
    )
    ..['resolvedConflicts'] =
        preview.manualConflicts.length +
        preview.listConflicts.length +
        preview.invariantConflicts.length;
  await _writeJson(outputPath, output);
  stdout.writeln('PLAN_VALID');
  stdout.writeln('Windows operations: ${mutation.windowsOperations.length}');
  stdout.writeln('Android operations: ${mutation.androidOperations.length}');
  stdout.writeln(
    'Expected final fingerprint: '
    '${mutation.expectedFinalSnapshot.businessFingerprintSha256}',
  );
}

Map<String, int> _operationSummary(
  List<SyncMutation> operations,
  SyncSnapshot source,
) {
  final current = {for (final record in source.records) record.key: record};
  var inserts = 0, updates = 0, deletes = 0, lists = 0;
  for (final operation in operations) {
    switch (operation.type) {
      case SyncMutationType.deleteRecord:
        deletes++;
      case SyncMutationType.upsertRecord:
        final before = current[operation.key];
        if (before == null || before.isDeleted) {
          inserts++;
        } else {
          updates++;
        }
      case SyncMutationType.applyList:
        lists++;
    }
  }
  return {
    'insert': inserts,
    'update': updates,
    'delete': deletes,
    'list': lists,
  };
}

Future<void> _applyWindows(
  String databasePath,
  String mutationPath,
  String backupPath,
) async {
  final appData = Platform.environment['APPDATA'];
  if (appData == null || appData.isEmpty) {
    throw StateError('APPDATA unavailable.');
  }
  final expectedPath = p.normalize(
    p.absolute(p.join(appData, 'Jax', 'jax.db')),
  );
  final actualPath = p.normalize(p.absolute(databasePath));
  if (!p.equals(expectedPath, actualPath)) {
    throw StateError('REAL_TARGET_GUARD: unexpected Windows DB $actualPath');
  }
  final mutation = _mutationFile(mutationPath);
  final before = await _databaseSnapshot(actualPath);
  final backup = await _databaseSnapshot(backupPath);
  if (before.businessFingerprintSha256 != mutation.windowsSourceFingerprint ||
      backup.businessFingerprintSha256 != mutation.windowsSourceFingerprint) {
    throw StateError(
      'STALE_SYNC_PLAN: live Windows DB or verified backup differs.',
    );
  }
  await const SqliteSyncMutationExecutor().apply(
    actualPath,
    mutation.windowsOperations,
  );
  await _verifySnapshot(
    await _databaseSnapshot(actualPath),
    mutation.expectedFinalSnapshot,
  );
  stdout.writeln('WINDOWS_APPLY_VALIDATED');
}

Future<void> _verify(String databasePath, String mutationPath) async {
  final mutation = _mutationFile(mutationPath);
  final snapshot = await _databaseSnapshot(databasePath);
  await _verifySnapshot(snapshot, mutation.expectedFinalSnapshot);
  stdout.writeln('FINAL_STATE_VERIFIED ${snapshot.businessFingerprintSha256}');
}

Future<void> _writeBaseline(String path, String mutationPath) async {
  final mutation = _mutationFile(mutationPath);
  final store = FileSyncBaselineStore(path);
  await store.writeSuccessfulBaseline(mutation.expectedFinalSnapshot);
  final persisted = await store.read();
  stdout.writeln(
    'BASELINE_WRITTEN path=$path '
    'fingerprint=${persisted!.businessFingerprintSha256}',
  );
}

Future<void> _readBaseline(String path) async {
  final snapshot = await FileSyncBaselineStore(path).read();
  if (snapshot == null) throw StateError('Baseline does not exist: $path');
  stdout.writeln(
    'BASELINE_OK path=$path fingerprint=${snapshot.businessFingerprintSha256}',
  );
}

SyncSnapshot _snapshotFile(String path) =>
    SyncSnapshot.fromJsonString(File(path).readAsStringSync());
SyncMutationPlan _mutationFile(String path) => SyncMutationPlan.fromJson(
  (jsonDecode(File(path).readAsStringSync()) as Map).cast<String, Object?>(),
);

Future<SyncSnapshot> _databaseSnapshot(String path) async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(readOnly: true),
  );
  try {
    return await SqliteSyncSnapshotAdapter(db).read();
  } finally {
    await db.close();
  }
}

Future<void> _verifySnapshot(SyncSnapshot actual, SyncSnapshot expected) async {
  final issues = const SyncSnapshotValidator().validate(actual);
  if (issues.isNotEmpty) {
    throw StateError('APPLY_VALIDATION_FAILED: ${issues.join(', ')}');
  }
  if (actual.businessFingerprintSha256 != expected.businessFingerprintSha256) {
    throw StateError(
      'FINAL_STATE_MISMATCH: ${actual.businessFingerprintSha256} != '
      '${expected.businessFingerprintSha256}',
    );
  }
}

Future<void> _writeJson(String path, Object? value) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsString(
    const JsonEncoder.withIndent('  ').convert(value),
    flush: true,
  );
}
