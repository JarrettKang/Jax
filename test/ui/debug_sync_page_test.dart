import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/sync/resolved_sync_plan.dart';
import 'package:jax/core/sync/sync_compare_engine.dart';
import 'package:jax/core/sync/sync_contract.dart';
import 'package:jax/data/sync/windows_debug_sync_coordinator.dart';
import 'package:jax/data/sync/sync_storage_service.dart';
import 'package:jax/ui/pages/debug_sync_page.dart';

void main() {
  testWidgets('shows friendly no-device connection state', (tester) async {
    final coordinator = _FakeCoordinator(
      connection: const DebugSyncConnection(
        adbPath: 'adb.exe',
        devices: [],
        message: '未检测到设备。请连接手机、开启 USB 调试并允许当前电脑。',
      ),
    );
    await tester.pumpWidget(_app(coordinator));
    await tester.pumpAndSettle();
    expect(find.text('同步数据存储位置'), findsOneWidget);
    expect(find.text(r'C:\Users\test\AppData\Roaming\Jax'), findsOneWidget);
    await tester.tap(find.text('检查连接'));
    await tester.pumpAndSettle();
    expect(find.textContaining('未检测到设备'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '分析同步'))
          .onPressed,
      isNull,
    );
  });

  testWidgets('one device can be checked and analyzed entirely in UI', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final coordinator = _FakeCoordinator(connection: _oneDevice);
    await tester.pumpWidget(_app(coordinator));
    await tester.tap(find.text('检查连接'));
    await tester.pumpAndSettle();
    expect(find.text('V2403A'), findsOneWidget);
    await tester.tap(find.text('分析同步'));
    await tester.pumpAndSettle();
    expect(find.text('Sync Analysis'), findsOneWidget);
    expect(find.textContaining('Baseline：尚未建立'), findsOneWidget);
    await tester.tap(find.text('同步数据存储位置'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '更改位置'))
          .onPressed,
      isNull,
    );
    expect(coordinator.analyzeCalls, 1);
  });

  testWidgets('multiple devices require an explicit selection', (tester) async {
    final coordinator = _FakeCoordinator(
      connection: const DebugSyncConnection(
        adbPath: 'adb.exe',
        devices: [
          DebugAndroidDevice(serial: 'one', state: 'device', model: 'Phone 1'),
          DebugAndroidDevice(serial: 'two', state: 'device', model: 'Phone 2'),
        ],
      ),
    );
    await tester.pumpWidget(_app(coordinator));
    await tester.tap(find.text('检查连接'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '分析同步'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Phone 2'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '分析同步'))
          .onPressed,
      isNotNull,
    );
  });
}

Widget _app(DebugSyncCoordinator coordinator) =>
    MaterialApp(home: DebugSyncPage(coordinator: coordinator));

const _oneDevice = DebugSyncConnection(
  adbPath: 'adb.exe',
  devices: [
    DebugAndroidDevice(serial: 'real', state: 'device', model: 'V2403A'),
  ],
);

class _FakeCoordinator implements DebugSyncCoordinator {
  _FakeCoordinator({required this.connection});
  final DebugSyncConnection connection;
  int analyzeCalls = 0;

  @override
  String get projectRoot => '.';
  @override
  bool get running => false;
  @override
  Future<DebugSyncConnection> inspectDevices() async => connection;
  @override
  Future<String?> verifyDevice(String serial) async => null;

  @override
  Future<SyncStorageSettings> loadStorage() async => const SyncStorageSettings(
    root: r'C:\Users\test\AppData\Roaming\Jax',
    layoutVersion: 0,
    backupRetention: 5,
  );

  @override
  Future<SyncStorageInventory> storageInventory(
    SyncStorageSettings settings,
  ) async => const SyncStorageInventory(
    baselineExists: true,
    backupSessions: 1,
    totalBytes: 1024,
  );

  @override
  Future<String?> chooseStorageDirectory() async => null;
  @override
  Future<SyncStorageMigrationResult> migrateStorage(String destination) =>
      throw UnimplementedError();
  @override
  Future<void> updateBackupRetention(int count) async {}
  @override
  Future<void> openStorageFolder() async {}

  @override
  Future<DebugSyncAnalysis> analyze(
    String serial, {
    required DebugSyncStageChanged onStage,
  }) async {
    analyzeCalls++;
    onStage('Analyzing');
    final instant = DateTime.fromMillisecondsSinceEpoch(1, isUtc: true);
    final snapshot = SyncSnapshot(
      schemaVersion: 13,
      exportedAtUtc: instant,
      records: const [],
      lists: const [],
    );
    final plan = const SyncCompareEngine().compare(
      windows: snapshot,
      android: snapshot,
    );
    return DebugSyncAnalysis(
      plan: plan,
      windowsSnapshot: snapshot,
      androidSnapshot: snapshot,
      baseline: null,
      resolutionPath: 'resolution.json',
      report: const {},
    );
  }

  @override
  Future<DebugSyncRunResult> apply(
    String serial,
    DebugSyncAnalysis analysis,
    ResolvedSyncPlan resolved, {
    required DebugSyncStageChanged onStage,
  }) async => const DebugSyncRunResult({'status': 'Success'}, 0, '');
}
