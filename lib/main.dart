import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import 'data/preferences/file_app_preferences_store.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'data/database/platform_database.dart';
import 'data/preferences/sqlite_world_category_collapse_store.dart';
import 'data/preferences/sqlite_routine_category_collapse_store.dart';
import 'data/repositories/sqlite_event_repository.dart';
import 'data/repositories/sqlite_planning_repository.dart';
import 'data/repositories/sqlite_world_node_repository.dart';
import 'data/services/sqlite_save_service.dart';
import 'core/sync/sync_compare_engine.dart';
import 'core/sync/sync_contract.dart';
import 'core/sync/resolved_sync_plan.dart';
import 'data/sync/android_debug_sync_command.dart';
import 'data/sync/windows_debug_sync_coordinator.dart';
import 'ui/pages/debug_sync_page.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kDebugMode && Platform.isWindows && args.contains('--debug-sync')) {
    final projectRoot = _findProjectRoot();
    final coordinator = WindowsDebugSyncCoordinator(projectRoot: projectRoot);
    final reportArgument = args
        .where((value) => value.startsWith('--debug-sync-report='))
        .firstOrNull;
    DebugSyncAnalysis? initialAnalysis;
    String? initialSerial;
    if (reportArgument != null) {
      final report = (jsonDecode(
        await File(reportArgument.substring(reportArgument.indexOf('=') + 1))
            .readAsString(),
      ) as Map).cast<String, Object?>();
      initialAnalysis = await coordinator.loadAnalysisReport(report);
      initialSerial = report['device']?.toString();
    }
    runApp(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildJaxTheme(TargetPlatform.windows),
        home: DebugSyncPage(
          coordinator: coordinator,
          initialAnalysis: initialAnalysis,
          initialSerial: initialSerial,
        ),
      ),
    );
    return;
  }
  if (kDebugMode && Platform.isAndroid) {
    const channel = MethodChannel('com.jarrett.jax/debug_sync');
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
              '-Package',
              'com.jarrett.jax',
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
  final eventRepository = SqliteEventRepository(database);
  final planningRepository = SqlitePlanningRepository(database);
  runApp(
    JaxApp(
      repository: eventRepository,
      preferencesStore: FileAppPreferencesStore(
        File(
          path.join(
            path.dirname(database.database.path),
            'app_preferences.json',
          ),
        ),
      ),
      planningRepository: planningRepository,
      worldNodeRepository: SqliteWorldNodeRepository(database),
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
      onOpenDebugSync: kDebugMode && Platform.isWindows
          ? () async {
              await Process.start(Platform.resolvedExecutable, const [
                '--debug-sync',
              ], workingDirectory: _findProjectRoot());
              exit(0);
            }
          : null,
    ),
  );
}

String _findProjectRoot() {
  var current = Directory.current.absolute;
  final executable = File(Platform.resolvedExecutable).parent;
  for (final start in [current, executable]) {
    current = start;
    for (var i = 0; i < 8; i++) {
      if (File(
        '${current.path}${Platform.pathSeparator}tool'
        '${Platform.pathSeparator}sync_phase2b2.ps1',
      ).existsSync()) {
        return current.path;
      }
      if (current.parent.path == current.path) break;
      current = current.parent;
    }
  }
  throw StateError('Cannot locate the Jax project root for Debug Sync.');
}
