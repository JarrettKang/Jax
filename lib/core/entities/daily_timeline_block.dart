import 'daily_execution_segment.dart';
import 'jax_day.dart';

class DailyTimelineBlock {
  const DailyTimelineBlock({
    required this.segment,
    required this.displayStart,
    required this.displayEnd,
    required this.startFraction,
    required this.durationFraction,
  });

  final DailyExecutionSegment segment;
  final DateTime displayStart;
  final DateTime displayEnd;
  final double startFraction;
  final double durationFraction;

  Duration get displayDuration => displayEnd.difference(displayStart);

  static List<DailyTimelineBlock> forJaxDay({
    required DateTime date,
    required List<DailyExecutionSegment> segments,
    required DateTime now,
  }) {
    final day = JaxDay.forDisplayDate(date);
    final dayMicros = day.end.difference(day.start).inMicroseconds;
    final blocks = <DailyTimelineBlock>[];
    for (final segment in segments) {
      final rawStart = segment.startedAt.toLocal();
      final rawEnd = (segment.endedAt ?? now).toLocal();
      final start = rawStart.isAfter(day.start) ? rawStart : day.start;
      final end = rawEnd.isBefore(day.end) ? rawEnd : day.end;
      if (!end.isAfter(start)) {
        continue;
      }
      blocks.add(
        DailyTimelineBlock(
          segment: segment,
          displayStart: start,
          displayEnd: end,
          startFraction: start.difference(day.start).inMicroseconds / dayMicros,
          durationFraction: end.difference(start).inMicroseconds / dayMicros,
        ),
      );
    }
    blocks.sort((a, b) => a.displayStart.compareTo(b.displayStart));
    return blocks;
  }
}
