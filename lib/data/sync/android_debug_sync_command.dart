import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/sync/sync_mutation_plan.dart';
import '../../core/sync/sync_snapshot_validator.dart';
import '../database/android_database.dart';
import 'sqlite_sync_mutation_executor.dart';
import 'sqlite_sync_snapshot_adapter.dart';

/// Executes an ADB-authorized Debug sync command before the normal Jax UI and
/// repository are opened. Release builds and non-Android platforms refuse it.
Future<bool> runAndroidDebugSyncCommand(String commandPath) async {
  if (!kDebugMode || !Platform.isAndroid) {
    throw StateError('Android sync commands are Debug-only.');
  }
  final commandFile = File(commandPath);
  final command = (jsonDecode(await commandFile.readAsString()) as Map)
      .cast<String, Object?>();
  final resultPath = command['resultPath']! as String;
  final resultFile = File(resultPath);
  try {
    if (command['action'] != 'applyMutationPlan') {
      throw StateError('Unsupported Android sync action: ${command['action']}');
    }
    final plan = SyncMutationPlan.fromJson(
      (command['mutationPlan']! as Map).cast<String, Object?>(),
    );
    final app = await openAndroidDatabase();
    try {
      final before = await SqliteSyncSnapshotAdapter(app.database).read();
      if (before.businessFingerprintSha256 != plan.androidSourceFingerprint) {
        throw StateError('STALE_SYNC_PLAN: Android source changed.');
      }
      await const SqliteSyncMutationExecutor().applyDatabase(
        app,
        plan.androidOperations,
      );
      final after = await SqliteSyncSnapshotAdapter(app.database).read();
      final issues = const SyncSnapshotValidator().validate(after);
      if (issues.isNotEmpty) {
        throw StateError('APPLY_VALIDATION_FAILED: ${issues.join(', ')}');
      }
      final expected = plan.expectedFinalSnapshot.businessFingerprintSha256;
      if (after.businessFingerprintSha256 != expected) {
        throw StateError(
          'FINAL_STATE_MISMATCH: '
          '${after.businessFingerprintSha256} != $expected',
        );
      }
      await _writeResult(resultFile, {
        'ok': true,
        'stage': 'androidValidated',
        'finalFingerprint': after.businessFingerprintSha256,
        'warnings': after.warnings,
      });
      return true;
    } finally {
      await app.close();
    }
  } catch (error, stackTrace) {
    await _writeResult(resultFile, {
      'ok': false,
      'stage': 'failed',
      'error': '$error',
      'stackTrace': '$stackTrace',
    });
    return false;
  }
}

Future<void> _writeResult(File destination, Map<String, Object?> result) async {
  final staged = File('${destination.path}.pending');
  if (await staged.exists()) await staged.delete();
  await staged.writeAsString(jsonEncode(result), flush: true);
  if (await destination.exists()) await destination.delete();
  await staged.rename(destination.path);
}
