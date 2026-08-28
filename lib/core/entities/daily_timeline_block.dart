import 'daily_execution_segment.dart';
import 'jax_day.dart';

class DailyTimelineHour {
  const DailyTimelineHour({required this.startedAt, required this.fragments});

  final DateTime startedAt;
  final List<DailyTimelineFragment> fragments;
}

class DailyTimelineFragment {
  const DailyTimelineFragment({
    required this.segment,
    required this.fragmentStart,
    required this.fragmentEnd,
    required this.startFraction,
    required this.durationFraction,
  });

  final DailyExecutionSegment segment;
  final DateTime fragmentStart;
  final DateTime fragmentEnd;
  final double startFraction;
  final double durationFraction;

  Duration get fragmentDuration => fragmentEnd.difference(fragmentStart);
}

class DailyTimelineLayout {
  static List<DailyTimelineHour> forJaxDay({
    required DateTime date,
    required List<DailyExecutionSegment> segments,
    required DateTime now,
  }) {
    final day = JaxDay.forDisplayDate(date);
    final rows = [
      for (var hour = 0; hour < 24; hour++) <DailyTimelineFragment>[],
    ];
    for (final segment in segments) {
      final rawStart = segment.startedAt.toLocal();
      final rawEnd = (segment.endedAt ?? now).toLocal();
      final clippedStart = rawStart.isAfter(day.start) ? rawStart : day.start;
      final clippedEnd = rawEnd.isBefore(day.end) ? rawEnd : day.end;
      if (!clippedEnd.isAfter(clippedStart)) {
        continue;
      }
      for (var rowIndex = 0; rowIndex < 24; rowIndex++) {
        final hourStart = day.start.add(Duration(hours: rowIndex));
        final hourEnd = hourStart.add(const Duration(hours: 1));
        final fragmentStart = clippedStart.isAfter(hourStart)
            ? clippedStart
            : hourStart;
        final fragmentEnd = clippedEnd.isBefore(hourEnd) ? clippedEnd : hourEnd;
        if (!fragmentEnd.isAfter(fragmentStart)) {
          continue;
        }
        rows[rowIndex].add(
          DailyTimelineFragment(
            segment: segment,
            fragmentStart: fragmentStart,
            fragmentEnd: fragmentEnd,
            startFraction:
                fragmentStart.difference(hourStart).inMicroseconds /
                const Duration(hours: 1).inMicroseconds,
            durationFraction:
                fragmentEnd.difference(fragmentStart).inMicroseconds /
                const Duration(hours: 1).inMicroseconds,
          ),
        );
      }
    }
    return [
      for (var rowIndex = 0; rowIndex < 24; rowIndex++)
        DailyTimelineHour(
          startedAt: day.start.add(Duration(hours: rowIndex)),
          fragments: rows[rowIndex]
            ..sort((a, b) => a.fragmentStart.compareTo(b.fragmentStart)),
        ),
    ];
  }
}
