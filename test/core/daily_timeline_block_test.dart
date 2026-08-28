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

  test('builds 24 JaxDay hours in 23:00 through 22:00 order', () {
    final date = DateTime(2026, 8, 28);
    final rows = DailyTimelineLayout.forJaxDay(
      date: date,
      now: DateTime(2026, 8, 28, 20),
      segments: const [],
    );
    expect(rows, hasLength(24));
    expect(rows.first.startedAt, DateTime(2026, 8, 27, 23));
    expect(rows.last.startedAt, DateTime(2026, 8, 28, 22));
  });

  test('splits one real segment into exact hourly rendering fragments', () {
    final date = DateTime(2026, 8, 28);
    final item = segment(
      'work',
      DateTime(2026, 8, 28, 8, 40),
      DateTime(2026, 8, 28, 10, 20),
    );
    final rows = DailyTimelineLayout.forJaxDay(
      date: date,
      now: DateTime(2026, 8, 28, 20),
      segments: [item],
    );
    final fragments = rows.expand((row) => row.fragments).toList();
    expect(fragments, hasLength(3));
    expect(
      fragments.map((fragment) => fragment.segment),
      everyElement(same(item)),
    );
    expect(fragments[0].startFraction, closeTo(40 / 60, 0.000001));
    expect(fragments[0].durationFraction, closeTo(20 / 60, 0.000001));
    expect(fragments[1].startFraction, 0);
    expect(fragments[1].durationFraction, 1);
    expect(fragments[2].durationFraction, closeTo(20 / 60, 0.000001));
  });

  test('clips crossing and open segments to the JaxDay display window', () {
    final date = DateTime(2026, 8, 28);
    final rows = DailyTimelineLayout.forJaxDay(
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
    final fragments = rows.expand((row) => row.fragments).toList();
    expect(fragments[0].fragmentStart, DateTime(2026, 8, 27, 23));
    expect(fragments[0].fragmentDuration, const Duration(minutes: 20));
    expect(fragments[1].fragmentDuration, const Duration(minutes: 30));
    expect(fragments, hasLength(2));
  });
}
