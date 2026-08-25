import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/app.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/entities/run_segment.dart';

import '../support/memory_repository.dart';

void main() {
  final time = DateTime.utc(2026, 8, 25, 8);
  JaxEvent completed(
    String id,
    String name, {
    String? parent,
    int? sortOrder,
  }) => JaxEvent(
    id: id,
    name: name,
    status: EventStatus.completed,
    parentEventId: parent,
    firstStartedAt: time,
    completedAt: time.add(const Duration(hours: 1)),
    createdAt: time,
    updatedAt: time,
    sortOrder: sortOrder,
  );
  RunSegment segment(String eventId, int minutes) => RunSegment(
    id: 'segment-$eventId',
    eventId: eventId,
    startedAt: time,
    endedAt: time.add(Duration(minutes: minutes)),
    createdAt: time,
  );

  testWidgets('history shows highest completed nodes and drills into totals', (
    tester,
  ) async {
    final incompleteParent = JaxEvent(
      id: 'incomplete',
      name: '尚未完成项目',
      status: EventStatus.paused,
      createdAt: time,
      updatedAt: time,
    );
    final repository =
        MemoryRepository([
            completed('root', '完成项目', sortOrder: 1),
            completed('root-first', '先完成项目', sortOrder: 0),
            completed('child', '完成阶段', parent: 'root'),
            completed('grandchild', '完成步骤', parent: 'child'),
            incompleteParent,
            completed('visible', '已完成但上层未完成', parent: 'incomplete'),
          ])
          ..segments.addAll([
            segment('root', 2),
            segment('root-first', 1),
            segment('child', 3),
            segment('grandchild', 9),
            segment('visible', 4),
          ]);
    await tester.pumpWidget(JaxApp(repository: repository, now: () => time));
    await tester.pumpAndSettle();
    await tester.tap(find.text('记录'));
    await tester.pumpAndSettle();

    expect(find.text('完成项目'), findsOneWidget);
    expect(find.text('先完成项目'), findsOneWidget);
    expect(find.text('已完成但上层未完成'), findsOneWidget);
    expect(find.text('完成阶段'), findsNothing);
    expect(find.text('完成步骤'), findsNothing);
    final firstY = tester.getTopLeft(find.text('先完成项目')).dy;
    final secondY = tester.getTopLeft(find.text('完成项目')).dy;
    expect(firstY, lessThan(secondY));

    await tester.tap(find.byKey(const ValueKey('history-detail-root')));
    await tester.pumpAndSettle();
    expect(find.text('总投入：14 分钟'), findsOneWidget);
    expect(find.text('直接执行：2 分钟'), findsOneWidget);
    expect(find.text('完成阶段'), findsOneWidget);
    expect(find.text('总投入：12 分钟'), findsOneWidget);

    await tester.tap(find.text('完成阶段'));
    await tester.pumpAndSettle();
    expect(find.text('总投入：12 分钟'), findsOneWidget);
    expect(find.text('直接执行：3 分钟'), findsOneWidget);
    expect(find.text('完成步骤'), findsOneWidget);
    expect(find.text('总投入：9 分钟'), findsOneWidget);

    await tester.tap(find.text('调整层级'));
    await tester.pumpAndSettle();
    expect(find.text('设置上层'), findsOneWidget);
    expect(find.text('添加下层'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
