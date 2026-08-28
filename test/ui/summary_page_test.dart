import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/app.dart';
import 'package:jax/core/entities/category.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/entities/run_segment.dart';

import '../support/memory_repository.dart';

void main() {
  testWidgets('daily and weekly summaries remain readable on a narrow screen', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 700);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    final now = DateTime(2026, 8, 27, 12);
    final repo =
        MemoryRepository([
            JaxEvent(
              id: 'root',
              name: '一个很长的开发项目根事件',
              status: EventStatus.paused,
              categoryId: 'dev',
              createdAt: now,
              updatedAt: now,
            ),
          ])
          ..categories.add(
            Category(
              id: 'dev',
              name: '一个很长的开发项目分类名称',
              sortOrder: 0,
              createdAt: now,
              updatedAt: now,
            ),
          )
          ..segments.add(
            RunSegment(
              id: 's',
              eventId: 'root',
              startedAt: DateTime(2026, 8, 27, 8),
              endedAt: DateTime(2026, 8, 27, 9),
              createdAt: now,
            ),
          );
    await tester.pumpWidget(JaxApp(repository: repo, now: () => now));
    await tester.pumpAndSettle();
    await tester.tap(find.text('记录'));
    await tester.pumpAndSettle();
    expect(find.text('今天 · 进行中'), findsOneWidget);
    expect(find.text('一个很长的开发项目分类名称'), findsOneWidget);
    expect(find.textContaining('1h 00m · 100%'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('今日时间分布'), findsOneWidget);
    expect(find.byKey(const ValueKey('timeline-visual-s-9-0')), findsOneWidget);
    await tester.scrollUntilVisible(find.text('执行记录'), 500);
    expect(find.text('执行记录'), findsOneWidget);
    expect(find.text('08:00 → 09:00'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('周总结'), -500);
    await tester.tap(find.text('周总结'));
    await tester.pumpAndSettle();
    expect(find.text('每日时间分配'), findsOneWidget);
    expect(find.text('周一'), findsOneWidget);
    expect(find.text('周日'), findsOneWidget);
    expect(find.byType(Scrollable), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('日总结'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(find.text('今日时间分布'), findsOneWidget);
    for (var switchIndex = 0; switchIndex < 3; switchIndex++) {
      await tester.tap(find.text('周总结'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('日总结'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
    await tester.pumpAndSettle();
    expect(find.text('今天 · 进行中'), findsOneWidget);
    expect(find.text('今日时间分布'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('执行记录'), 500);
    expect(find.text('执行记录'), findsOneWidget);
  });
}
