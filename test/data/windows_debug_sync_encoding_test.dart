import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/sync/sync_compare_engine.dart';
import 'package:jax/core/sync/sync_contract.dart';
import 'package:jax/data/sync/sync_storage_service.dart';
import 'package:jax/data/sync/windows_debug_sync_coordinator.dart';

void main() {
  test('strict UTF-8 JSON round-trips ASCII and Jax Chinese business text', () {
    const values = ['ASCII only', '检查超算', '优化界面和操作', '复现WCA粒子KT熔化', '科研'];
    final bytes = utf8.encode(jsonEncode(values));
    expect(bytes.take(3), isNot([0xEF, 0xBB, 0xBF]));
    expect(jsonDecode(utf8.decode(bytes)), values);
  });

  test(
    'Windows PowerShell standalone Analyze uses UTF-8 stdout and result JSON',
    () async {
      if (!Platform.isWindows) return;
      final root = await Directory.systemTemp.createTemp('jax_sync_utf8_');
      addTearDown(() => root.deleteSync(recursive: true));
      final tool = Directory('${root.path}${Platform.pathSeparator}tool')
        ..createSync();
      final snapshots = Directory(
        '${root.path}${Platform.pathSeparator}fixtures',
      )..createSync();
      final instant = DateTime.fromMillisecondsSinceEpoch(1, isUtc: true);
      SyncRecord event(String id, String name) => SyncRecord(
        kind: SyncEntityKind.event,
        metadata: SyncMetadata(
          id: id,
          createdAtUtc: instant,
          updatedAtUtc: instant,
        ),
        payload: {'name': name, 'status': 'pending'},
      );
      final windows = SyncSnapshot(
        schemaVersion: 13,
        exportedAtUtc: instant,
        records: [event('a', '检查超算'), event('b', '优化界面和操作')],
        lists: const [],
      );
      final android = SyncSnapshot(
        schemaVersion: 13,
        exportedAtUtc: instant,
        records: [event('a', '检查超算'), event('b', '复现WCA粒子KT熔化')],
        lists: const [],
      );
      final plan = const SyncCompareEngine().compare(
        windows: windows,
        android: android,
      );
      final planFile = File(
        '${snapshots.path}${Platform.pathSeparator}plan.json',
      );
      final windowsFile = File(
        '${snapshots.path}${Platform.pathSeparator}windows.json',
      );
      final androidFile = File(
        '${snapshots.path}${Platform.pathSeparator}android.json',
      );
      final resolution = File(
        '${snapshots.path}${Platform.pathSeparator}resolution.json',
      )..writeAsStringSync('{}');
      planFile.writeAsStringSync(plan.toJsonString(pretty: true));
      windowsFile.writeAsStringSync(windows.toJsonString(pretty: true));
      androidFile.writeAsStringSync(android.toJsonString(pretty: true));
      final reportTemplate = File(
        '${snapshots.path}${Platform.pathSeparator}report.json',
      );
      reportTemplate.writeAsStringSync(
        jsonEncode({
          'status': 'AnalysisReady',
          'device': 'real-device',
          'planPath': planFile.path,
          'windowsSnapshotPath': windowsFile.path,
          'androidSnapshotPath': androidFile.path,
          'resolutionTemplate': resolution.path,
        }),
      );
      File('${tool.path}${Platform.pathSeparator}sync_phase2b2.ps1')
          .writeAsStringSync(r'''
param([string]$Action,[string]$Device,[int]$KeepWindowsProcessId,[switch]$NoLaunchPreview,[string]$StatusPath,[string]$ResultPath,[string]$StorageRoot,[int]$StorageLayoutVersion,[int]$BackupRetention)
$utf8 = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = $utf8
Write-Output ([string]([char]0x68C0)+[char]0x67E5+[char]0x8D85+[char]0x7B97)
$report = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\fixtures\report.json'),$utf8) | ConvertFrom-Json
$report | Add-Member -NotePropertyName storageRoot -NotePropertyValue $StorageRoot
[IO.File]::WriteAllText($ResultPath,($report | ConvertTo-Json -Depth 20),$utf8)
''');
      final storageService = SyncStorageService(appDataRoot: root.path);
      final analysis = await WindowsDebugSyncCoordinator(
        projectRoot: root.path,
        storageService: storageService,
      ).analyze('real-device', onStage: (_) {});
      expect(analysis.plan.manualConflicts.single.title, '优化界面和操作');
      expect(
        analysis.windowsSnapshot.records.map((r) => r.payload['name']),
        contains('检查超算'),
      );
      final settings = await storageService.load();
      expect(analysis.report['storageRoot'], settings.root);
      final resultBytes = Directory(settings.sessionsPath)
          .listSync(recursive: true)
          .whereType<File>()
          .firstWhere((file) => file.path.endsWith('result.json'))
          .readAsBytesSync();
      expect(resultBytes.take(3), isNot([0xEF, 0xBB, 0xBF]));
      expect(() => utf8.decode(resultBytes), returnsNormally);
    },
  );
}
