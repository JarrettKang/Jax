import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/app.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/entities/run_segment.dart';

import '../support/memory_repository.dart';

void main() {
  testWidgets('history confirms restore and returns event to events page', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 700);
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    final time = DateTime.utc(2026, 8, 26, 8);
    JaxEvent completed(String id, {String? parent}) => JaxEvent(
      id: id,
      name: '$id 的长事件名称',
      status: EventStatus.completed,
      parentEventId: parent,
      firstStartedAt: time,
      completedAt: time.add(const Duration(minutes: 5)),
      createdAt: time,
      updatedAt: time,
    );
    final repository =
        MemoryRepository([completed('root'), completed('leaf', parent: 'root')])
          ..segments.add(
            RunSegment(
              id: 'segment',
              eventId: 'leaf',
              startedAt: time,
              endedAt: time.add(const Duration(minutes: 5)),
              createdAt: time,
            ),
          );
    await tester.pumpWidget(JaxApp(repository: repository, now: () => time));
    await tester.pumpAndSettle();
    await tester.tap(find.text('记录'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('more-history-root')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('restore-history-root')));
    await tester.pumpAndSettle();
    expect(find.text('恢复事件'), findsWidgets);
    expect(find.textContaining('原有执行记录会保留'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '恢复事件'));
    await tester.pumpAndSettle();

    expect(find.text('root 的长事件名称'), findsNothing);
    expect(find.text('leaf 的长事件名称'), findsOneWidget);
    await tester.tap(find.text('事件'));
    await tester.pumpAndSettle();
    expect(find.text('root 的长事件名称'), findsOneWidget);
    expect(find.textContaining('已暂停'), findsOneWidget);
    expect(await repository.getRunSegments('leaf'), hasLength(1));
    expect(tester.takeException(), isNull);
  });
}
