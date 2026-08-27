import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/app.dart';
import 'package:jax/core/entities/routine.dart';

import '../support/memory_repository.dart';

void main() {
  testWidgets(
    'Routine daily flow is usable on a narrow screen and stays out of World',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final now = DateTime(2026, 8, 27, 8);
      final repo = MemoryRepository();
      repo.routines.add(
        Routine(
          id: 'wash',
          name: '非常长的早上洗漱日常名称用于验证小屏布局',
          recurrence: RoutineRecurrence.daily,
          weekdayMask: 0,
          isActive: true,
          sortOrder: 0,
          createdAt: now,
          updatedAt: now,
        ),
      );
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
      expect(find.textContaining('非常长的早上洗漱'), findsWidgets);
      expect(find.text('未开始'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('开始').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('正在执行'), findsOneWidget);
      await tester.tap(find.text('首页'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('home-running-routine')),
        findsOneWidget,
      );
      expect(find.textContaining('日常 · 未分类'), findsOneWidget);
      await tester.tap(find.text('日常'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('暂停').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('已暂停'), findsOneWidget);
      await tester.tap(find.text('恢复').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('完成').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('完成 ·'), findsOneWidget);
      await tester.tap(find.text('世界'));
      await tester.pumpAndSettle();
      expect(find.textContaining('非常长的早上洗漱'), findsNothing);
    },
  );
}
