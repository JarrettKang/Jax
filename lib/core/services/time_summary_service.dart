import '../entities/jax_event.dart';
import '../entities/jax_day.dart';
import '../entities/time_summary.dart';
import '../repositories/event_repository.dart';
import '../repositories/routine_repository.dart';
import '../entities/routine_category.dart';

class TimeSummaryService {
  TimeSummaryService(this._repository, this._now);

  final EventRepository _repository;
  final DateTime Function() _now;
  RoutineRepository? get _routines => _repository is RoutineRepository
      ? _repository as RoutineRepository
      : null;

  Future<TimeSummary> day(DateTime date) async {
    final jaxDay = JaxDay.forDisplayDate(date);
    return _within(jaxDay.start, jaxDay.end);
  }

  Future<WeeklyTimeSummary> week(DateTime date) async {
    final local = DateTime(date.year, date.month, date.day);
    final monday = local.subtract(
      Duration(days: local.weekday - DateTime.monday),
    );
    final start = JaxDay.forDisplayDate(monday).start;
    final end = start.add(const Duration(days: 7));
    final days = <TimeSummary>[];
    for (var offset = 0; offset < 7; offset++) {
      days.add(await day(monday.add(Duration(days: offset))));
    }
    final total = await _within(start, end);
    return WeeklyTimeSummary(
      start: total.start,
      end: total.end,
      isCurrent: total.isCurrent,
      categories: total.categories,
      days: days,
    );
  }

  Future<TimeSummary> _within(DateTime start, DateTime nominalEnd) async {
    final now = _now().toLocal();
    final end = nominalEnd.isAfter(now) ? now : nominalEnd;
    if (!end.isAfter(start)) {
      return TimeSummary(
        start: start,
        end: end,
        isCurrent: nominalEnd.isAfter(now),
        categories: const [],
      );
    }
    final events = [
      ...await _repository.getIncompleteEvents(),
      ...await _repository.getCompletedEvents(),
    ];
    final byId = {for (final event in events) event.id: event};
    final categories = await _repository.getCategories();
    final categoryById = {
      for (final category in categories) category.id: category,
    };
    final totals = <String, Duration>{};
    const unclassified = 'unclassified';
    for (final event in events) {
      final categoryId = _rootCategory(event, byId)?.categoryId;
      final bucket = categoryId == null ? unclassified : 'event:$categoryId';
      for (final segment in await _repository.getRunSegments(event.id)) {
        final segmentEnd = (segment.endedAt ?? now).toLocal();
        final segmentStart = segment.startedAt.toLocal();
        final overlapStart = segmentStart.isAfter(start) ? segmentStart : start;
        final overlapEnd = segmentEnd.isBefore(end) ? segmentEnd : end;
        if (overlapEnd.isAfter(overlapStart)) {
          totals[bucket] =
              (totals[bucket] ?? Duration.zero) +
              overlapEnd.difference(overlapStart);
        }
      }
    }
    final routineRepository = _routines;
    var routineCategories = const <RoutineCategory>[];
    var routineCategoryById = const <String, RoutineCategory>{};
    if (routineRepository != null) {
      final routines = await routineRepository.getRoutines();
      routineCategories = await routineRepository.getRoutineCategories();
      routineCategoryById = {for (final c in routineCategories) c.id: c};
      final routineById = {for (final r in routines) r.id: r};
      for (final execution in await routineRepository.getRoutineExecutions()) {
        final routine = routineById[execution.routineId];
        if (routine == null) continue;
        for (final segment in await routineRepository.getRoutineRunSegments(
          execution.id,
        )) {
          final segmentEnd = (segment.endedAt ?? now).toLocal();
          final segmentStart = segment.startedAt.toLocal();
          final overlapStart = segmentStart.isAfter(start)
              ? segmentStart
              : start;
          final overlapEnd = segmentEnd.isBefore(end) ? segmentEnd : end;
          if (overlapEnd.isAfter(overlapStart)) {
            final categoryId = routine.routineCategoryId;
            final bucket = categoryId == null
                ? unclassified
                : 'routine:$categoryId';
            totals[bucket] =
                (totals[bucket] ?? Duration.zero) +
                overlapEnd.difference(overlapStart);
          }
        }
      }
    }
    final result =
        totals.entries.where((entry) => entry.value > Duration.zero).map((
          entry,
        ) {
          final isEvent = entry.key.startsWith('event:');
          final isRoutine = entry.key.startsWith('routine:');
          final id = entry.key.contains(':')
              ? entry.key.substring(entry.key.indexOf(':') + 1)
              : null;
          final category = isEvent && id != null ? categoryById[id] : null;
          final RoutineCategory? routineCategory = isRoutine && id != null
              ? routineCategoryById[id]
              : null;
          return CategoryDuration(
            categoryId: id,
            bucketKey: entry.key,
            source: isEvent
                ? SummaryCategorySource.event
                : isRoutine
                ? SummaryCategorySource.routine
                : SummaryCategorySource.unclassified,
            name: category?.name ?? routineCategory?.name ?? '未分类',
            colorKey: category?.colorKey ?? routineCategory?.colorKey,
            duration: entry.value,
            order: category != null
                ? categories.indexOf(category)
                : routineCategory != null
                ? categories.length + routineCategories.indexOf(routineCategory)
                : categories.length + routineCategories.length,
          );
        }).toList()..sort((a, b) {
          final duration = b.duration.compareTo(a.duration);
          return duration != 0 ? duration : a.order.compareTo(b.order);
        });
    return TimeSummary(
      start: start,
      end: end,
      isCurrent: nominalEnd.isAfter(now),
      categories: result,
    );
  }

  JaxEvent? _rootCategory(JaxEvent event, Map<String, JaxEvent> byId) {
    var current = event;
    final seen = <String>{};
    while (current.parentEventId != null && seen.add(current.id)) {
      final parent = byId[current.parentEventId];
      if (parent == null) break;
      current = parent;
    }
    return current;
  }
}
