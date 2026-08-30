import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/sync/sync_compare_engine.dart';
import 'package:jax/core/sync/sync_contract.dart';
import 'package:jax/ui/pages/sync_preview_page.dart';

void main() {
  testWidgets(
    'preview shows summary and readable field diff without apply sources',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final instant = DateTime.fromMillisecondsSinceEpoch(1, isUtc: true);
      SyncRecord event(String name) => SyncRecord(
        kind: SyncEntityKind.event,
        metadata: SyncMetadata(
          id: 'event',
          createdAtUtc: instant,
          updatedAtUtc: instant,
        ),
        payload: {'name': name, 'status': 'paused'},
      );
      final windows = event('电脑名称');
      final android = event('手机名称');
      final plan = SyncPlan(
        hasBaseline: false,
        windowsSourceFingerprint: 'windows',
        androidSourceFingerprint: 'android',
        items: [
          SyncPlanItem(
            key: windows.key,
            title: '开发 Jax',
            comparison: SyncComparisonKind.different,
            classification: SyncMergeClassification.manualConflict,
            conflictType: SyncConflictType.unknownHistory,
            windows: windows,
            android: android,
            changedFields: const [
              SyncFieldDiff(
                field: 'name',
                windowsValue: '电脑名称',
                androidValue: '手机名称',
              ),
            ],
            detail: 'Unknown history',
          ),
        ],
        listConflicts: const [],
        invariantConflicts: const [],
        warnings: const ['Android: category-order duplicate'],
      );
      await tester.pumpWidget(MaterialApp(home: SyncPreviewPage(plan: plan)));
      expect(find.text('Jax Sync · Debug'), findsOneWidget);
      expect(find.text('实体/字段冲突'), findsOneWidget);
      expect(find.text('开发 Jax'), findsOneWidget);
      await tester.tap(find.text('开发 Jax'));
      await tester.pumpAndSettle();
      expect(find.textContaining('电脑：电脑名称'), findsOneWidget);
      await tester.ensureVisible(find.text('使用电脑'));
      await tester.tap(find.text('使用电脑'));
      await tester.pumpAndSettle();
      final readOnly = find.textContaining('当前仅加载了 Preview');
      await tester.ensureVisible(readOnly);
      expect(readOnly, findsOneWidget);
    },
  );

  testWidgets('Dry Run gates confirmation and duplicate Apply clicks', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final instant = DateTime.fromMillisecondsSinceEpoch(1, isUtc: true);
    SyncRecord event(String name) => SyncRecord(
      kind: SyncEntityKind.event,
      metadata: SyncMetadata(
        id: 'event',
        createdAtUtc: instant,
        updatedAtUtc: instant,
      ),
      payload: {
        'name': name,
        'status': 'paused',
        'parentSyncId': null,
        'categorySyncId': null,
        'order': 0,
        'firstStartedAtUtc': null,
        'completedAtUtc': null,
      },
    );
    SyncSnapshot snapshot(String name) => SyncSnapshot(
      schemaVersion: 13,
      exportedAtUtc: instant,
      records: [event(name)],
      lists: const [
        SyncList(
          kind: SyncListKind.eventSiblings,
          scopeId: 'root',
          itemIds: ['event'],
        ),
      ],
    );
    final windows = snapshot('电脑名称');
    final android = snapshot('手机名称');
    final plan = const SyncCompareEngine().compare(
      windows: windows,
      android: android,
    );
    final pending = Completer<void>();
    var applyCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: SyncPreviewPage(
          plan: plan,
          windowsSnapshot: windows,
          androidSnapshot: android,
          onConfirmedApply: (resolved) {
            applyCalls++;
            return pending.future;
          },
        ),
      ),
    );
    // The generated title is the entity name, not a fixed fixture label.
    await tester.tap(find.text('电脑名称'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('使用电脑'));
    await tester.tap(find.text('使用电脑'));
    await tester.ensureVisible(find.byKey(const ValueKey('sync-dry-run')));
    await tester.tap(find.byKey(const ValueKey('sync-dry-run')));
    await tester.pumpAndSettle();
    expect(find.textContaining('PLAN_VALID'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('sync-apply')));
    await tester.pumpAndSettle();
    expect(find.text('执行真实双端同步？'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('confirm-real-sync')));
    await tester.pump();
    expect(applyCalls, 1);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('sync-apply')))
          .onPressed,
      isNull,
    );
    pending.complete();
    await tester.pumpAndSettle();
  });
}
