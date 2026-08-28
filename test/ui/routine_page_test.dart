import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/app.dart';
import 'package:jax/core/entities/routine.dart';

import '../support/memory_repository.dart';

void main() {
  testWidgets(
    'Routine page is a narrow management page while Today remains execution entry',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final now = DateTime(2026, 8, 27, 8);
      Routine routine(
        String id,
        String name,
        int order, {
        bool active = true,
      }) => Routine(
        id: id,
        name: name,
        recurrence: RoutineRecurrence.daily,
        weekdayMask: 0,
        isActive: active,
        sortOrder: order,
        createdAt: now,
        updatedAt: now,
      );
      final repo = MemoryRepository()
        ..routines.addAll([
          routine('wash', '非常长的早上洗漱日常名称用于验证小屏布局', 0),
          routine('sleep', '睡觉', 1),
          routine('inactive', '已停用日常', 2, active: false),
        ]);
      await tester.pumpWidget(
        JaxApp(
          repository: repo,
          now: () => now,
          newId: (() {
            var i = 0;
            return () => 'id-${i++}';
          })(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('日常'));
      await tester.pumpAndSettle();

      expect(find.text('今日备用执行'), findsNothing);
      expect(find.text('管理日常'), findsNothing);
      expect(find.textContaining('非常长的早上洗漱'), findsOneWidget);
      expect(find.text('每天 · 未分类'), findsNWidgets(2));
      expect(find.text('开始'), findsNothing);
      expect(find.text('暂停'), findsNothing);
      expect(find.text('恢复'), findsNothing);
      expect(find.text('完成'), findsNothing);
      expect(find.byKey(const ValueKey('create-routine')), findsOneWidget);
      expect(find.text('已停用'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const ValueKey('routine-up-sleep')));
      await tester.pumpAndSettle();
      expect((await repo.getRoutines()).map((item) => item.id), [
        'sleep',
        'wash',
        'inactive',
      ]);
      await tester.tap(find.byKey(const ValueKey('routine-more-wash')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('停用'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('已停用'));
      await tester.pumpAndSettle();
      expect(find.text('非常长的早上洗漱日常名称用于验证小屏布局'), findsOneWidget);
      await tester.tap(find.text('重新启用').first);
      await tester.pumpAndSettle();
      expect(
        (await repo.getRoutines())
            .firstWhere((item) => item.id == 'wash')
            .isActive,
        isTrue,
      );

      await tester.tap(find.text('今日'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('today-routine-start-wash')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('日常'));
      await tester.pumpAndSettle();
      expect(find.text('每天 · 未分类 · 正在执行'), findsOneWidget);
      expect(find.text('开始'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
