import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/run_segment.dart';
import 'package:jax/core/entities/category.dart';
import 'package:jax/core/entities/routine.dart';
import 'package:jax/core/repositories/event_repository.dart';
import 'package:jax/core/repositories/routine_repository.dart';

class MemoryRepository implements EventRepository, RoutineRepository {
  MemoryRepository([Iterable<JaxEvent> seed = const []])
    : events = List.of(seed);
  final List<JaxEvent> events;
  final List<RunSegment> segments = [];
  final List<Category> categories = [];
  final List<Routine> routines = [];
  final List<RoutineExecution> routineExecutions = [];
  final List<RoutineRunSegment> routineSegments = [];
  @override
  Future<void> insertEvent(JaxEvent event) async {
    final siblings = events.where(
      (item) => item.parentEventId == event.parentEventId,
    );
    final next =
        siblings.fold<int>(-1, (max, item) {
          final order = item.sortOrder ?? -1;
          return order > max ? order : max;
        }) +
        1;
    events.add(event.copyWith(sortOrder: event.sortOrder ?? next));
  }

  @override
  Future<List<JaxEvent>> getIncompleteEvents() async =>
      events.where((event) => event.status.name != 'completed').toList();
  @override
  Future<List<JaxEvent>> getCompletedEvents() async =>
      events.where((event) => event.status.name == 'completed').toList();
  @override
  Future<JaxEvent?> getEvent(String id) async =>
      events.where((event) => event.id == id).firstOrNull;
  @override
  Future<void> updateEvent(JaxEvent event) async =>
      events[events.indexWhere((item) => item.id == event.id)] = event;
  @override
  Future<void> startEvent(JaxEvent event, RunSegment segment) async {
    await pauseRunningRoutine(event.updatedAt);
    await updateEvent(event);
    segments.add(segment);
  }

  @override
  Future<List<RunSegment>> getRunSegments(String eventId) async =>
      segments.where((segment) => segment.eventId == eventId).toList();
  @override
  Future<void> pauseEvent(JaxEvent event, RunSegment segment) async {
    await updateEvent(event);
    segments[segments.indexWhere((item) => item.id == segment.id)] = segment;
  }

  @override
  Future<void> restoreCompletedEvents(List<JaxEvent> restored) async {
    for (final event in restored) {
      final current = await getEvent(event.id);
      if (current == null || current.status.name != 'completed') {
        throw StateError('Invalid completed Event restoration');
      }
    }
    for (final event in restored) {
      await updateEvent(event);
    }
  }

  @override
  Future<JaxEvent?> getParent(String eventId) async {
    final event = await getEvent(eventId);
    return event?.parentEventId == null
        ? null
        : getEvent(event!.parentEventId!);
  }

  @override
  Future<List<JaxEvent>> getDirectChildren(String parentEventId) async =>
      _ordered(events.where((event) => event.parentEventId == parentEventId));

  @override
  Future<List<JaxEvent>> getOrderedSiblings(String eventId) async {
    final event = await getEvent(eventId);
    if (event == null) throw StateError('Event not found: $eventId');
    return _ordered(
      events.where((item) => item.parentEventId == event.parentEventId),
    );
  }

  @override
  Future<List<JaxEvent>> getOrderedTopLevelEvents() async =>
      _ordered(events.where((event) => event.parentEventId == null));

  @override
  Future<void> reorderSibling(String eventId, int targetIndex) async {
    final siblings = await getOrderedSiblings(eventId);
    final current = siblings.indexWhere((event) => event.id == eventId);
    if (targetIndex < 0 || targetIndex >= siblings.length) {
      throw StateError('Invalid target index');
    }
    final moved = siblings.removeAt(current);
    siblings.insert(targetIndex, moved);
    for (var index = 0; index < siblings.length; index++) {
      await updateEvent(siblings[index].copyWith(sortOrder: index));
    }
  }

  List<JaxEvent> _ordered(Iterable<JaxEvent> source) => source.toList()
    ..sort((a, b) {
      final order = (a.sortOrder ?? 1 << 30).compareTo(b.sortOrder ?? 1 << 30);
      if (order != 0) return order;
      final created = a.createdAt.compareTo(b.createdAt);
      return created != 0 ? created : a.id.compareTo(b.id);
    });

  @override
  Future<void> updateParent(
    String eventId,
    String? parentEventId,
    DateTime updatedAt,
  ) async {
    final event = await getEvent(eventId);
    if (event == null) throw StateError('Event not found: $eventId');
    final siblings = events.where(
      (item) => item.parentEventId == parentEventId,
    );
    final next =
        siblings.fold<int>(-1, (max, item) {
          final order = item.sortOrder ?? -1;
          return order > max ? order : max;
        }) +
        1;
    String? categoryId;
    if (parentEventId == null) {
      var root = event;
      while (root.parentEventId != null) {
        root = (await getEvent(root.parentEventId!))!;
      }
      categoryId = root.categoryId;
    }
    await updateEvent(
      event.copyWith(
        parentEventId: parentEventId,
        sortOrder: next,
        updatedAt: updatedAt,
        categoryId: categoryId,
      ),
    );
  }

  @override
  Future<void> switchRunningEvent({
    required JaxEvent pausedRunning,
    required RunSegment closedSegment,
    required JaxEvent runningTarget,
    required RunSegment newSegment,
    required List<JaxEvent> pausedAncestors,
  }) async {
    await updateEvent(pausedRunning);
    segments[segments.indexWhere((item) => item.id == closedSegment.id)] =
        closedSegment;
    for (final ancestor in pausedAncestors) {
      await updateEvent(ancestor);
    }
    await updateEvent(runningTarget);
    segments.add(newSegment);
  }

  @override
  Future<void> deleteEvent(String id) async {
    events.removeWhere((event) => event.id == id);
    segments.removeWhere((segment) => segment.eventId == id);
  }

  @override
  Future<List<Category>> getCategories() async => _orderedCategories();
  List<Category> _orderedCategories() =>
      categories.toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  @override
  Future<void> insertCategory(Category category) async =>
      categories.add(category);
  @override
  Future<void> updateCategory(Category category) async =>
      categories[categories.indexWhere((item) => item.id == category.id)] =
          category;
  @override
  Future<void> deleteCategory(String id) async {
    categories.removeWhere((item) => item.id == id);
    for (var i = 0; i < categories.length; i++) {
      categories[i] = categories[i].copyWith(sortOrder: i);
    }
    for (var i = 0; i < events.length; i++) {
      if (events[i].categoryId == id) {
        events[i] = events[i].copyWith(categoryId: null);
      }
    }
    for (var i = 0; i < routines.length; i++) {
      if (routines[i].categoryId == id) {
        routines[i] = routines[i].copyWith(clearCategory: true);
      }
    }
  }

  @override
  Future<void> reorderCategory(String id, int targetIndex) async {
    final ordered = _orderedCategories();
    final current = ordered.indexWhere((item) => item.id == id);
    if (current < 0 || targetIndex < 0 || targetIndex >= ordered.length) {
      throw StateError('Invalid category order');
    }
    final moved = ordered.removeAt(current);
    ordered.insert(targetIndex, moved);
    for (var i = 0; i < ordered.length; i++) {
      categories[categories.indexWhere((item) => item.id == ordered[i].id)] =
          ordered[i].copyWith(sortOrder: i);
    }
  }

  @override
  Future<void> setRootCategory(String eventId, String? categoryId) async {
    final event = await getEvent(eventId);
    if (event == null) throw StateError('Event not found: $eventId');
    if (event.parentEventId != null) {
      throw StateError('Only root events can have a category');
    }
    if (categoryId != null &&
        !categories.any((item) => item.id == categoryId)) {
      throw StateError('Category not found');
    }
    await updateEvent(event.copyWith(categoryId: categoryId));
  }

  @override
  Future<List<Routine>> getRoutines() async =>
      List.of(routines)..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  @override
  Future<void> insertRoutine(Routine r) async {
    if (routines.any((x) => x.id == r.id)) throw StateError('duplicate');
    routines.add(r);
  }

  @override
  Future<void> updateRoutine(Routine r) async =>
      routines[routines.indexWhere((x) => x.id == r.id)] = r;
  @override
  Future<RoutineExecution?> getRoutineExecution(String id, String day) async =>
      routineExecutions
          .where((e) => e.routineId == id && e.occurrenceDate == day)
          .firstOrNull;
  @override
  Future<List<RoutineExecution>> getRoutineExecutions() async =>
      List.of(routineExecutions);
  @override
  Future<List<RoutineRunSegment>> getRoutineRunSegments(String id) async =>
      routineSegments.where((s) => s.executionId == id).toList();
  @override
  Future<void> startRoutineExecution(
    RoutineExecution e,
    RoutineRunSegment s,
    DateTime now,
  ) async {
    final running = events.where((x) => x.status.name == 'running').firstOrNull;
    if (running != null) {
      final open = segments
          .where((x) => x.eventId == running.id && x.endedAt == null)
          .firstOrNull;
      await updateEvent(
        running.copyWith(status: EventStatus.paused, updatedAt: now),
      );
      if (open != null) {
        segments[segments.indexOf(open)] = open.copyWith(endedAt: now);
      }
    }
    await pauseRunningRoutine(now);
    final i = routineExecutions.indexWhere((x) => x.id == e.id);
    if (i < 0) {
      routineExecutions.add(e);
    } else {
      routineExecutions[i] = e;
    }
    routineSegments.add(s);
  }

  @override
  Future<void> pauseRoutineExecution(
    RoutineExecution e,
    RoutineRunSegment s,
  ) async {
    await updateRoutineExecutionOnly(e);
    routineSegments[routineSegments.indexWhere((x) => x.id == s.id)] = s;
  }

  @override
  Future<void> completeRoutineExecution(
    RoutineExecution e,
    RoutineRunSegment s,
  ) => pauseRoutineExecution(e, s);
  @override
  Future<void> updateRoutineExecutionOnly(RoutineExecution e) async {
    routineExecutions[routineExecutions.indexWhere((x) => x.id == e.id)] = e;
  }

  @override
  Future<void> pauseRunningRoutine(DateTime now) async {
    final e = routineExecutions
        .where((x) => x.status == RoutineExecutionStatus.running)
        .firstOrNull;
    if (e == null) return;
    final s = routineSegments
        .where((x) => x.executionId == e.id && x.endedAt == null)
        .firstOrNull;
    await updateRoutineExecutionOnly(
      e.copyWith(status: RoutineExecutionStatus.paused, updatedAt: now),
    );
    if (s != null) {
      routineSegments[routineSegments.indexOf(s)] = s.copyWith(endedAt: now);
    }
  }
}
