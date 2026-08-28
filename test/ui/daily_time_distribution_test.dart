import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/daily_execution_segment.dart';
import 'package:jax/ui/widgets/daily_time_distribution.dart';

void main() {
  DailyExecutionSegment segment(String id, String name, int hour, int minutes) {
    final start = DateTime(2026, 8, 28, hour);
    return DailyExecutionSegment(
      id: id,
      source: ExecutionSource.event,
      ownerId: 'work',
      name: name,
      startedAt: start,
      endedAt: start.add(Duration(minutes: minutes)),
      createdAt: start,
      categoryBucketKey: 'event:science',
      categoryName: '科研',
    );
  }

  testWidgets('renders repeated segments at exact relative heights', (
    tester,
  ) async {
    final segments = [
      segment('short', '处理数据', 8, 8),
      segment('long', '处理数据', 9, 180),
      segment('third', '处理数据', 16, 80),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: DailyTimeDistribution(
              date: DateTime(2026, 8, 28),
              segments: segments,
              now: DateTime(2026, 8, 28, 20),
              colorForBucket: (_) => Colors.teal,
              onSegmentTap: (_) {},
            ),
          ),
        ),
      ),
    );
    final short = tester.getSize(
      find.byKey(const ValueKey('timeline-visual-short')),
    );
    final long = tester.getSize(
      find.byKey(const ValueKey('timeline-visual-long')),
    );
    expect(long.height / short.height, closeTo(22.5, 0.01));
    expect(find.byKey(const ValueKey('timeline-visual-third')), findsOneWidget);
    expect(find.text('处理数据'), findsNWidgets(2));
    expect(find.text('23:00'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('short visual block keeps true height with a larger tap target', (
    tester,
  ) async {
    final item = segment('tiny', '短记录', 8, 8);
    DailyExecutionSegment? tapped;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: DailyTimeDistribution(
              date: DateTime(2026, 8, 28),
              segments: [item],
              now: DateTime(2026, 8, 28, 20),
              colorForBucket: (_) => Colors.teal,
              onSegmentTap: (value) => tapped = value,
            ),
          ),
        ),
      ),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('timeline-visual-tiny'))).height,
      closeTo(4, 0.01),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('timeline-hit-tiny'))).height,
      40,
    );
    await tester.tap(find.byKey(const ValueKey('timeline-hit-tiny')));
    expect(tapped, same(item));
  });
}
