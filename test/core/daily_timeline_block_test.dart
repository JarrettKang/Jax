import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/daily_execution_segment.dart';
import 'package:jax/core/entities/daily_timeline_block.dart';

void main() {
  DailyExecutionSegment segment(String id, DateTime start, DateTime? end) =>
      DailyExecutionSegment(
        id: id,
        source: ExecutionSource.event,
        ownerId: id,
        name: id,
        startedAt: start,
        endedAt: end,
        createdAt: start,
      );

  test('uses true 24-hour position and duration fractions', () {
    final date = DateTime(2026, 8, 28);
    final blocks = DailyTimelineBlock.forJaxDay(
      date: date,
      now: DateTime(2026, 8, 28, 20),
      segments: [
        segment('short', DateTime(2026, 8, 28, 8), DateTime(2026, 8, 28, 8, 8)),
        segment('long', DateTime(2026, 8, 28, 9), DateTime(2026, 8, 28, 12)),
      ],
    );
    expect(blocks[0].durationFraction, closeTo(8 / 1440, 0.000001));
    expect(blocks[1].durationFraction, closeTo(180 / 1440, 0.000001));
    expect(
      blocks[1].durationFraction / blocks[0].durationFraction,
      closeTo(22.5, 0.000001),
    );
  });

  test('clips crossing and open segments to the JaxDay display window', () {
    final date = DateTime(2026, 8, 28);
    final blocks = DailyTimelineBlock.forJaxDay(
      date: date,
      now: DateTime(2026, 8, 28, 1),
      segments: [
        segment(
          'crossing',
          DateTime(2026, 8, 27, 22, 40),
          DateTime(2026, 8, 27, 23, 20),
        ),
        segment('open', DateTime(2026, 8, 28, 0, 30), null),
      ],
    );
    expect(blocks[0].displayStart, DateTime(2026, 8, 27, 23));
    expect(blocks[0].displayDuration, const Duration(minutes: 20));
    expect(blocks[1].displayDuration, const Duration(minutes: 30));
    expect(blocks, hasLength(2));
  });
}
