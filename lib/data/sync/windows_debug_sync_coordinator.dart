import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/sync/resolved_sync_plan.dart';
import '../../core/sync/sync_compare_engine.dart';
import '../../core/sync/sync_contract.dart';

class DebugAndroidDevice {
  const DebugAndroidDevice({
    required this.serial,
    required this.state,
    required this.model,
  });
  final String serial;
  final String state;
  final String model;
  bool get authorized => state == 'device';
}

class DebugSyncConnection {
  const DebugSyncConnection({
    required this.adbPath,
    required this.devices,
    this.message,
  });
  final String? adbPath;
  final List<DebugAndroidDevice> devices;
  final String? message;
  bool get adbAvailable => adbPath != null;
}

class DebugSyncAnalysis {
  const DebugSyncAnalysis({
    required this.plan,
    required this.windowsSnapshot,
    required this.androidSnapshot,
    required this.baseline,
    required this.resolutionPath,
    required this.report,
  });
  final SyncPlan plan;
  final SyncSnapshot windowsSnapshot;
  final SyncSnapshot androidSnapshot;
  final SyncSnapshot? baseline;
  final String resolutionPath;
  final Map<String, Object?> report;
}

class DebugSyncRunResult {
  const DebugSyncRunResult(this.report, this.exitCode, this.stderr);
  final Map<String, Object?> report;
  final int exitCode;
  final String stderr;
  String get status => report['status']?.toString() ?? 'Unknown';
}

typedef DebugSyncStageChanged = void Function(String stage);

abstract interface class DebugSyncCoordinator {
  String get projectRoot;
  bool get running;
  Future<DebugSyncConnection> inspectDevices();
  Future<String?> verifyDevice(String serial);
  Future<DebugSyncAnalysis> analyze(
    String serial, {
    required DebugSyncStageChanged onStage,
  });
  Future<DebugSyncRunResult> apply(
    String serial,
    DebugSyncAnalysis analysis,
    ResolvedSyncPlan resolved, {
    required DebugSyncStageChanged onStage,
  });
}

class WindowsDebugSyncCoordinator implements DebugSyncCoordinator {
  WindowsDebugSyncCoordinator({required this.projectRoot});

  @override
  final String projectRoot;
  bool _running = false;
  @override
  bool get running => _running;

  String? findAdb() {
    final roots = [
      Platform.environment['ANDROID_HOME'],
      Platform.environment['ANDROID_SDK_ROOT'],
      r'<android-sdk>',
    ].whereType<String>();
    for (final root in roots) {
      final value =
          '$root${Platform.pathSeparator}platform-tools'
          '${Platform.pathSeparator}adb.exe';
      if (File(value).existsSync()) return value;
    }
    return null;
  }

  @override
  Future<DebugSyncConnection> inspectDevices() async {
    final adb = findAdb();
    if (adb == null) {
      return const DebugSyncConnection(
        adbPath: null,
        devices: [],
        message: '未找到 adb。请安装 Android SDK Platform Tools。',
      );
    }
    final result = await Process.run(adb, ['devices', '-l']);
    if (result.exitCode != 0) {
      return DebugSyncConnection(
        adbPath: adb,
        devices: const [],
        message: 'adb 无法启动：${result.stderr}',
      );
    }
    final devices = <DebugAndroidDevice>[];
    for (final raw in '${result.stdout}'.split(RegExp(r'\r?\n')).skip(1)) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final parts = line.split(RegExp(r'\s+'));
      if (parts.length < 2) continue;
      final model = RegExp(r'(?:^|\s)model:([^\s]+)')
          .firstMatch(line)
          ?.group(1);
      devices.add(
        DebugAndroidDevice(
          serial: parts[0],
          state: parts[1],
          model: model ?? '未知设备',
        ),
      );
    }
    String? message;
    if (devices.isEmpty) {
      message = '未检测到设备。请连接手机、开启 USB 调试并允许当前电脑。';
    } else if (devices.any((device) => device.state == 'unauthorized')) {
      message = '检测到未授权设备，请在手机上允许 USB 调试授权。';
    }
    return DebugSyncConnection(
      adbPath: adb,
      devices: devices,
      message: message,
    );
  }

  @override
  Future<String?> verifyDevice(String serial) async {
    final adb = findAdb();
    if (adb == null) return '未找到 adb。';
    final windowsDb =
        '${Platform.environment['APPDATA']}'
        '${Platform.pathSeparator}Jax${Platform.pathSeparator}jax.db';
    if (!File(windowsDb).existsSync()) return 'Windows Jax 数据库不可读取。';
    Future<ProcessResult> run(List<String> args) =>
        Process.run(adb, ['-s', serial, ...args]);
    final package = await run(['shell', 'pm', 'path', 'com.example.jax']);
    if (package.exitCode != 0 || !'${package.stdout}'.contains('package:')) {
      return '手机上未安装 Jax Debug。';
    }
    final access = await run(['shell', 'run-as', 'com.example.jax', 'pwd']);
    if (access.exitCode != 0) return 'Jax Debug 无法通过 run-as 读取。';
    final database = await run([
      'shell',
      'run-as',
      'com.example.jax',
      'test',
      '-r',
      'databases/jax.db',
    ]);
    if (database.exitCode != 0) return 'Android Jax 数据库不可读取。';
    return null;
  }

  @override
  Future<DebugSyncAnalysis> analyze(
    String serial, {
    required DebugSyncStageChanged onStage,
  }) async {
    final result = await _run(
      action: 'Analyze',
      serial: serial,
      onStage: onStage,
    );
    if (result.exitCode != 0 || result.status != 'AnalysisReady') {
      throw StateError(_friendlyFailure(result));
    }
    return loadAnalysisReport(result.report);
  }

  Future<DebugSyncAnalysis> loadAnalysisReport(
    Map<String, Object?> report,
  ) async {
    final plan = SyncPlan.fromJsonString(
      await File(report['planPath']! as String).readAsString(),
    );
    final windows = SyncSnapshot.fromJsonString(
      await File(report['windowsSnapshotPath']! as String).readAsString(),
    );
    final android = SyncSnapshot.fromJsonString(
      await File(report['androidSnapshotPath']! as String).readAsString(),
    );
    final baselinePath = report['baselinePath']?.toString();
    final baseline = baselinePath != null && File(baselinePath).existsSync()
        ? SyncSnapshot.fromJsonString(await File(baselinePath).readAsString())
        : null;
    return DebugSyncAnalysis(
      plan: plan,
      windowsSnapshot: windows,
      androidSnapshot: android,
      baseline: baseline,
      resolutionPath: report['resolutionTemplate']! as String,
      report: report,
    );
  }

  @override
  Future<DebugSyncRunResult> apply(
    String serial,
    DebugSyncAnalysis analysis,
    ResolvedSyncPlan resolved, {
    required DebugSyncStageChanged onStage,
  }) async {
    await File(analysis.resolutionPath).writeAsString(
      const JsonEncoder.withIndent('  ').convert(resolved.toResolutionJson()),
      flush: true,
    );
    return _run(
      action: 'Apply',
      serial: serial,
      resolution: analysis.resolutionPath,
      onStage: onStage,
    );
  }

  Future<DebugSyncRunResult> _run({
    required String action,
    required String serial,
    required DebugSyncStageChanged onStage,
    String? resolution,
  }) async {
    if (_running) throw StateError('SYNC_SESSION_ACTIVE：已有同步任务正在运行。');
    _running = true;
    final session = DateTime.now().microsecondsSinceEpoch;
    final exchange = Directory(
      '$projectRoot${Platform.pathSeparator}.debug_snapshots'
      '${Platform.pathSeparator}sync_ui_$session',
    )..createSync(recursive: true);
    final statusPath = '${exchange.path}${Platform.pathSeparator}status.json';
    final resultPath = '${exchange.path}${Platform.pathSeparator}result.json';
    final script =
        '$projectRoot${Platform.pathSeparator}tool'
        '${Platform.pathSeparator}sync_phase2b2.ps1';
    String quote(String value) => "'${value.replaceAll("'", "''")}'";
    final invocation = <String>[
      '& ${quote(script)}',
      '-Action ${quote(action)}',
      '-Device ${quote(serial)}',
      '-KeepWindowsProcessId ${quote('$pid')}',
      '-NoLaunchPreview',
      '-StatusPath ${quote(statusPath)}',
      '-ResultPath ${quote(resultPath)}',
      if (resolution != null) '-Resolution ${quote(resolution)}',
      if (action == 'Apply')
        '-Confirmation ${quote('FIRST_REAL_DUAL_DEVICE_SYNC')}',
    ].join(' ');
    final command = <String>[
      r'$utf8 = [Text.UTF8Encoding]::new($false)',
      r'$OutputEncoding = $utf8',
      r'[Console]::OutputEncoding = $utf8',
      invocation,
    ].join('; ');
    final args = [
      '-NoProfile',
      '-WindowStyle',
      'Hidden',
      '-ExecutionPolicy',
      'Bypass',
      '-Command',
      command,
    ];
    Timer? timer;
    try {
      final process = await Process.start(
        'powershell.exe',
        args,
        workingDirectory: projectRoot,
      );
      String? lastStage;
      timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
        try {
          if (!File(statusPath).existsSync()) return;
          final json = jsonDecode(File(statusPath).readAsStringSync()) as Map;
          final stage = json['status']?.toString();
          if (stage != null && stage != lastStage) {
            lastStage = stage;
            onStage(stage);
          }
        } catch (_) {}
      });
      final values = await Future.wait<Object>([
        process.exitCode,
        // The PowerShell launch prefix and structured IPC contract guarantee
        // strict UTF-8. Malformed output is a producer-contract failure.
        process.stdout.transform(const Utf8Decoder()).join(),
        process.stderr.transform(const Utf8Decoder()).join(),
      ]);
      final report = File(resultPath).existsSync()
          ? (jsonDecode(await File(resultPath).readAsString()) as Map)
                .cast<String, Object?>()
          : <String, Object?>{'status': 'CoordinatorFailed'};
      return DebugSyncRunResult(report, values[0] as int, values[2] as String);
    } finally {
      timer?.cancel();
      _running = false;
    }
  }

  String _friendlyFailure(DebugSyncRunResult result) {
    final raw = result.report['error']?.toString() ?? result.stderr;
    if (raw.contains('STALE_SYNC_PLAN')) return '数据在分析后发生变化。没有执行同步，请重新分析。';
    if (raw.contains('unauthorized')) return '手机尚未授权 USB 调试，请查看手机上的授权提示。';
    if (raw.contains('Package is not installed')) return '手机上未安装 Jax Debug。';
    if (raw.contains('run-as')) return 'Jax 不是可通过 run-as 访问的 Debug 安装。';
    return raw.isEmpty ? '同步工具执行失败。' : raw;
  }
}
