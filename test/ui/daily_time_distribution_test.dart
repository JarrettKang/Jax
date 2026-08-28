import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/daily_execution_segment.dart';
import 'package:jax/ui/widgets/daily_time_distribution.dart';

void main() {
  DailyExecutionSegment segment(
    String id,
    String name,
    int hour,
    int startMinute,
    int durationMinutes,
  ) {
    final start = DateTime(2026, 8, 28, hour, startMinute);
    return DailyExecutionSegment(
      id: id,
      source: ExecutionSource.event,
      ownerId: 'work',
      name: name,
      startedAt: start,
      endedAt: start.add(Duration(minutes: durationMinutes)),
      createdAt: start,
      categoryBucketKey: 'event:science',
      categoryName: '科研',
    );
  }

  testWidgets('renders 24 equal rows and exact hourly fragment widths', (
    tester,
  ) async {
    final segments = [
      segment('work', '处理数据', 8, 40, 100),
      segment('third', '处理数据', 16, 0, 80),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 360,
              child: DailyTimeDistribution(
                date: DateTime(2026, 8, 28),
                segments: segments,
                now: DateTime(2026, 8, 28, 20),
                colorForSegment: (_) => Colors.teal,
                onSegmentTap: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('timeline-hour-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('timeline-hour-23')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('timeline-hour-0'))).height,
      tester.getSize(find.byKey(const ValueKey('timeline-hour-23'))).height,
    );
    final first = tester.getSize(
      find.byKey(const ValueKey('timeline-visual-work-9-0')),
    );
    final full = tester.getSize(
      find.byKey(const ValueKey('timeline-visual-work-10-0')),
    );
    final last = tester.getSize(
      find.byKey(const ValueKey('timeline-visual-work-11-0')),
    );
    expect(full.width / first.width, closeTo(3, 0.01));
    expect(last.width, closeTo(first.width, 0.01));
    expect(first.height, full.height);
    expect(find.text('23:00'), findsOneWidget);
    expect(find.text('22:00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fragment tap returns its complete underlying segment', (
    tester,
  ) async {
    final item = segment('work', '处理数据', 8, 40, 100);
    DailyExecutionSegment? tapped;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 360,
              child: DailyTimeDistribution(
                date: DateTime(2026, 8, 28),
                segments: [item],
                now: DateTime(2026, 8, 28, 20),
                colorForSegment: (_) => Colors.teal,
                onSegmentTap: (value) => tapped = value,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('timeline-hit-work-10-0')));
    expect(tapped, same(item));
  });
}
