import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/sync/sync_compare_engine.dart';
import 'package:jax/core/sync/sync_contract.dart';
import 'package:jax/ui/pages/sync_preview_page.dart';

void main() {
  testWidgets(
    'preview shows summary, readable field diff, and memory-only choices',
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
      expect(find.text('Jax Sync · 仅预览'), findsOneWidget);
      expect(find.text('实体/字段冲突'), findsOneWidget);
      expect(find.text('开发 Jax'), findsOneWidget);
      await tester.tap(find.text('开发 Jax'));
      await tester.pumpAndSettle();
      expect(find.textContaining('电脑：电脑名称'), findsOneWidget);
      await tester.ensureVisible(find.text('使用电脑'));
      await tester.tap(find.text('使用电脑'));
      await tester.pumpAndSettle();
      final readOnly = find.textContaining('不会写入任一数据库');
      await tester.ensureVisible(readOnly);
      expect(readOnly, findsOneWidget);
    },
  );
}
