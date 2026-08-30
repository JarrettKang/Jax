import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'data/database/platform_database.dart';
import 'data/preferences/sqlite_world_category_collapse_store.dart';
import 'data/preferences/sqlite_routine_category_collapse_store.dart';
import 'data/repositories/sqlite_event_repository.dart';
import 'data/services/sqlite_save_service.dart';
import 'core/sync/sync_compare_engine.dart';
import 'core/sync/sync_contract.dart';
import 'core/sync/resolved_sync_plan.dart';
import 'data/sync/android_debug_sync_command.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kDebugMode && Platform.isAndroid) {
    const channel = MethodChannel('com.example.jax/debug_sync');
    final commandPath = await channel.invokeMethod<String>('takeCommandPath');
    if (commandPath != null && commandPath.isNotEmpty) {
      final succeeded = await runAndroidDebugSyncCommand(commandPath);
      exit(succeeded ? 0 : 2);
    }
  }
  final database = await openPlatformDatabase();
  SyncPlan? debugSyncPlan;
  SyncSnapshot? debugWindowsSnapshot;
  SyncSnapshot? debugAndroidSnapshot;
  SyncSnapshot? debugBaseline;
  Future<void> Function(ResolvedSyncPlan)? onConfirmedSyncApply;
  final planPath = Platform.environment['JAX_SYNC_PLAN'];
  if (kDebugMode && Platform.isWindows && planPath != null) {
    debugSyncPlan = SyncPlan.fromJsonString(
      await File(planPath).readAsString(),
    );
    final windowsPath = Platform.environment['JAX_SYNC_WINDOWS_SNAPSHOT'];
    final androidPath = Platform.environment['JAX_SYNC_ANDROID_SNAPSHOT'];
    final baselinePath = Platform.environment['JAX_SYNC_BASELINE'];
    final resolutionPath = Platform.environment['JAX_SYNC_RESOLUTION'];
    final device = Platform.environment['JAX_SYNC_DEVICE'];
    final projectRoot = Platform.environment['JAX_SYNC_PROJECT_ROOT'];
    if (windowsPath != null && androidPath != null) {
      debugWindowsSnapshot = SyncSnapshot.fromJsonString(
        await File(windowsPath).readAsString(),
      );
      debugAndroidSnapshot = SyncSnapshot.fromJsonString(
        await File(androidPath).readAsString(),
      );
      if (baselinePath != null && await File(baselinePath).exists()) {
        debugBaseline = SyncSnapshot.fromJsonString(
          await File(baselinePath).readAsString(),
        );
      }
      if (resolutionPath != null && device != null && projectRoot != null) {
        onConfirmedSyncApply = (ResolvedSyncPlan resolved) async {
          await File(resolutionPath).writeAsString(
            const JsonEncoder.withIndent('  ')
                .convert(resolved.toResolutionJson()),
            flush: true,
          );
          final script =
              '$projectRoot${Platform.pathSeparator}'
              'tool${Platform.pathSeparator}sync_phase2b2.ps1';
          await Process.start(
            'powershell.exe',
            [
              '-NoProfile',
              '-ExecutionPolicy',
              'Bypass',
              '-File',
              script,
              '-Action',
              'Apply',
              '-Device',
              device,
              '-Resolution',
              resolutionPath,
              '-Confirmation',
              'FIRST_REAL_DUAL_DEVICE_SYNC',
            ],
            workingDirectory: projectRoot,
            runInShell: true,
          );
          exit(0);
        };
      }
    }
  }
  runApp(
    JaxApp(
      repository: SqliteEventRepository(database),
      saveService: SqliteSaveService(database),
      worldCategoryCollapseStore: SqliteWorldCategoryCollapseStore(database),
      routineCategoryCollapseStore: SqliteRoutineCategoryCollapseStore(
        database,
      ),
      debugSyncPlan: debugSyncPlan,
      debugSyncWindowsSnapshot: debugWindowsSnapshot,
      debugSyncAndroidSnapshot: debugAndroidSnapshot,
      debugSyncBaseline: debugBaseline,
      onConfirmedSyncApply: onConfirmedSyncApply,
    ),
  );
}
