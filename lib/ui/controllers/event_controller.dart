import 'dart:async';

import 'package:flutter/foundation.dart' hide Category;

import '../../core/entities/event_status.dart';
import '../../core/entities/event_day_plan.dart';
import '../../core/entities/jax_day.dart';
import '../../core/entities/category.dart';
import '../../core/entities/jax_event.dart';
import '../../core/entities/run_segment.dart';
import '../../core/errors/domain_failure.dart';
import '../../core/repositories/event_repository.dart';
import '../../core/repositories/event_day_plan_repository.dart';
import '../../core/services/event_hierarchy_service.dart';
import '../../core/services/hierarchy_duration_service.dart';
import '../../core/services/world_display_state_service.dart';
import '../../core/services/time_summary_service.dart';
import '../../core/entities/time_summary.dart';
import '../../core/entities/routine.dart';
import '../../core/repositories/routine_repository.dart';
import '../../core/services/routine_service.dart';
import '../../core/services/category_service.dart';
import '../../core/entities/world_display_state.dart';
import '../../core/use_cases/complete_event.dart';
import '../../core/use_cases/create_event.dart';
import '../../core/use_cases/delete_event.dart';
import '../../core/use_cases/delete_history_record.dart';
import '../../core/use_cases/edit_event.dart';
import '../../core/use_cases/pause_event.dart';
import '../../core/use_cases/resume_event.dart';
import '../../core/use_cases/restore_event.dart';
import '../../core/use_cases/start_event.dart';
import '../../core/use_cases/update_event_parent.dart';
import '../../core/use_cases/reorder_sibling.dart';
import '../../core/use_cases/wait_event.dart';

class EventController extends ChangeNotifier {
  EventController({
    required EventRepository repository,
    required IdGenerator newId,
    required Clock now,
  }) : _repository = repository,
       _now = now,
       _complete = CompleteEvent(repository: repository, now: now),
       _create = CreateEvent(repository: repository, newId: newId, now: now),
       _edit = EditEvent(repository: repository, now: now),
       _delete = DeleteEvent(repository),
       _deleteHistory = DeleteHistoryRecord(repository),
       _pause = PauseEvent(repository: repository, now: now),
       _resume = ResumeEvent(repository: repository, newId: newId, now: now),
       _restore = RestoreEvent(repository: repository, now: now),
       _start = StartEvent(repository: repository, newId: newId, now: now),
       _wait = WaitEvent(repository: repository, now: now),
       _hierarchy = EventHierarchyService(repository),
       _durations = HierarchyDurationService(repository, now: now),
       _worldDisplayStates = const WorldDisplayStateService(),
       _summaries = TimeSummaryService(repository, now),
       _dayPlans = repository is EventDayPlanRepository
           ? repository as EventDayPlanRepository
           : null,
       _routineRepository = repository is RoutineRepository
           ? repository as RoutineRepository
           : null,
       _routineService = repository is RoutineRepository
           ? RoutineService(
               repository: repository as RoutineRepository,
               newId: newId,
               now: now,
             )
           : null,
       _categories = CategoryService(
         repository: repository,
         newId: newId,
         now: now,
       ),
       _updateParent = UpdateEventParent(repository: repository, now: now),
       _reorder = ReorderSibling(repository);
  final EventRepository _repository;
  final Clock _now;
  final CompleteEvent _complete;
  final CreateEvent _create;
  final EditEvent _edit;
  final DeleteEvent _delete;
  final DeleteHistoryRecord _deleteHistory;
  final PauseEvent _pause;
  final ResumeEvent _resume;
  final RestoreEvent _restore;
  final StartEvent _start;
  final WaitEvent _wait;
  final EventHierarchyService _hierarchy;
  final HierarchyDurationService _durations;
  final WorldDisplayStateService _worldDisplayStates;
  final TimeSummaryService _summaries;
  final EventDayPlanRepository? _dayPlans;
  final RoutineRepository? _routineRepository;
  final RoutineService? _routineService;
  final CategoryService _categories;
  final UpdateEventParent _updateParent;
  final ReorderSibling _reorder;
  final Map<String, List<RunSegment>> _segments = {};
  final Map<String, bool> _hasDirectChildren = {};
  List<JaxEvent> _events = const [];
  List<JaxEvent> _history = const [];
  List<JaxEvent> _historyRoots = const [];
  List<JaxEvent> _worldEvents = const [];
  Map<String, WorldDisplayState> _worldStates = const {};
  List<Category> _categoryItems = const [];
  List<Routine> _routines = const [];
  final Map<String, RoutineExecution?> _todayExecutions = {};
  final Map<String, List<RoutineRunSegment>> _routineSegments = {};
  List<EventDayPlan> _todayPlans = const [];
  JaxEvent? _runningParent;
  List<JaxEvent> _runningSiblings = const [];
  HomeRunningContext? _homeRunningContext;
  List<HomeWaitingItem> _homeWaitingItems = const [];
  bool _loading = true;
  DateTime? _lastSavedAt;
  Timer? _ticker;
  Timer? _dayBoundaryTimer;
  Future<void> _reorderTail = Future.value();
  List<JaxEvent> get events => List.unmodifiable(_events);
  List<JaxEvent> get history => List.unmodifiable(_history);
  List<JaxEvent> get historyRoots => List.unmodifiable(_historyRoots);
  List<JaxEvent> get worldEvents => List.unmodifiable(_worldEvents);
  WorldDisplayState worldDisplayStateFor(String eventId) =>
      _worldStates[eventId] ?? WorldDisplayState.pending;
  List<Category> get categories => List.unmodifiable(_categoryItems);
  List<Routine> get routines => List.unmodifiable(_routines);
  JaxDay get currentJaxDay => JaxDay.containing(_now());
  List<JaxEvent> get todayEvents {
    final byId = {for (final event in _worldEvents) event.id: event};
    return _todayPlans.map((plan) => byId[plan.eventId]).nonNulls.toList();
  }

  bool isPlannedToday(String eventId) =>
      _todayPlans.any((plan) => plan.eventId == eventId);
  List<Routine> get todayRoutines {
    final displayDate = currentJaxDay.displayDate;
    final runningId = runningRoutineExecution?.routineId;
    return _routines
        .where(
          (r) => (r.isActive && r.appliesTo(displayDate)) || r.id == runningId,
        )
        .toList();
  }

  RoutineExecution? executionFor(Routine r) => _todayExecutions[r.id];
  RoutineExecution? get runningRoutineExecution => _todayExecutions.values
      .where((e) => e?.status == RoutineExecutionStatus.running)
      .firstOrNull;
  Routine? get runningRoutine {
    final e = runningRoutineExecution;
    return e == null
        ? null
        : _routines.where((r) => r.id == e.routineId).firstOrNull;
  }

  bool get loading => _loading;
  DateTime? get lastSavedAt => _lastSavedAt;
  JaxEvent? get runningEvent =>
      _events.where((event) => event.status == EventStatus.running).firstOrNull;
  JaxEvent? get runningParent => _runningParent;
  List<JaxEvent> get runningSiblings => List.unmodifiable(_runningSiblings);
  HomeRunningContext? get homeRunningContext => _homeRunningContext;
  List<HomeWaitingItem> get homeWaitingItems =>
      List.unmodifiable(_homeWaitingItems);
  int siblingIndexFor(String eventId) {
    final event = _worldEvents.where((item) => item.id == eventId).firstOrNull;
    if (event == null) return -1;
    return _worldEvents
        .where((item) => item.parentEventId == event.parentEventId)
        .toList()
        .indexWhere((item) => item.id == eventId);
  }

  int siblingCountFor(String eventId) {
    final event = _worldEvents.where((item) => item.id == eventId).firstOrNull;
    return event == null
        ? 0
        : _worldEvents
              .where((item) => item.parentEventId == event.parentEventId)
              .length;
  }

  bool hasDirectChildren(String eventId) =>
      _hasDirectChildren[eventId] ?? false;

  int hierarchyDepthFor(String eventId) {
    final byId = {for (final event in _worldEvents) event.id: event};
    var depth = 0;
    var current = byId[eventId];
    final visited = <String>{};
    while (current?.parentEventId != null &&
        visited.add(current!.id) &&
        byId.containsKey(current.parentEventId)) {
      depth++;
      current = byId[current.parentEventId];
    }
    return depth;
  }

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    await _reload();
    _loading = false;
    notifyListeners();
  }

  Future<void> _reload() async {
    _events = _orderTree(await _repository.getIncompleteEvents());
    _history = await _repository.getCompletedEvents();
    final roots = <JaxEvent>[];
    for (final event in _history) {
      final parent = await _repository.getParent(event.id);
      if (parent == null || parent.status != EventStatus.completed) {
        roots.add(event);
      }
    }
    _historyRoots = _sortByOrder(roots);
    _worldEvents = _orderTree([..._events, ..._history]);
    _worldStates = _worldDisplayStates.derive(_worldEvents);
    _categoryItems = await _repository.getCategories();
    final dayKey = currentJaxDay.key;
    final runningEventNow = _worldEvents
        .where((event) => event.status == EventStatus.running)
        .firstOrNull;
    var plans =
        await _dayPlans?.getEventDayPlans(dayKey) ?? const <EventDayPlan>[];
    if (runningEventNow != null &&
        !plans.any((plan) => plan.eventId == runningEventNow.id)) {
      await _dayPlans?.addEventDayPlan(
        EventDayPlan(
          eventId: runningEventNow.id,
          dayKey: dayKey,
          order: plans.length,
          createdAt: _now().toUtc(),
        ),
      );
      plans =
          await _dayPlans?.getEventDayPlans(dayKey) ?? const <EventDayPlan>[];
    }
    _todayPlans = plans;
    if (_routineRepository != null) {
      _routines = await _routineRepository.getRoutines();
      _todayExecutions.clear();
      _routineSegments.clear();
      final day = currentJaxDay.key;
      for (final r in _routines) {
        final e = await _routineRepository.getRoutineExecution(r.id, day);
        _todayExecutions[r.id] = e;
        if (e != null) {
          _routineSegments[e.id] = await _routineRepository
              .getRoutineRunSegments(e.id);
        }
      }
      final runningRoutine = await _routineRepository
          .getRunningRoutineExecution();
      if (runningRoutine != null && runningRoutine.occurrenceDate != day) {
        _todayExecutions[runningRoutine.routineId] = runningRoutine;
        _routineSegments[runningRoutine.id] = await _routineRepository
            .getRoutineRunSegments(runningRoutine.id);
      }
    }
    for (final event in [..._events, ..._history]) {
      _segments[event.id] = await _repository.getRunSegments(event.id);
      _hasDirectChildren[event.id] = (await _repository.getDirectChildren(
        event.id,
      )).isNotEmpty;
    }
    final running = runningEvent;
    _runningParent = running == null
        ? null
        : await _repository.getParent(running.id);
    _runningSiblings = _runningParent == null || running == null
        ? const []
        : (await _repository.getDirectChildren(_runningParent!.id))
              .where((event) => event.id != running.id)
              .toList(growable: false);
    _homeRunningContext = running == null
        ? null
        : await _buildHomeRunningContext(running, _runningParent);
    final waitingItems = <HomeWaitingItem>[];
    for (final event in _events.where(
      (event) => event.status == EventStatus.waiting,
    )) {
      final ancestors = <JaxEvent>[];
      var parent = await _repository.getParent(event.id);
      final visited = <String>{event.id};
      while (parent != null && visited.add(parent.id)) {
        ancestors.add(parent);
        parent = await _repository.getParent(parent.id);
      }
      waitingItems.add(
        HomeWaitingItem(event: event, ancestors: ancestors.reversed.toList()),
      );
    }
    _homeWaitingItems = waitingItems;
    _syncTicker();
    _scheduleDayBoundaryRefresh();
  }

  Future<HomeRunningContext> _buildHomeRunningContext(
    JaxEvent running,
    JaxEvent? parent,
  ) async {
    final subject = parent ?? running;
    final ancestors = <JaxEvent>[];
    final visited = <String>{subject.id};
    var ancestor = await _repository.getParent(subject.id);
    while (ancestor != null && visited.add(ancestor.id)) {
      ancestors.add(ancestor);
      ancestor = await _repository.getParent(ancestor.id);
    }
    final orderedAncestors = ancestors.reversed.toList(growable: false);
    final steps = parent == null
        ? <JaxEvent>[running]
        : await _repository.getDirectChildren(parent.id);
    const windowSize = 7;
    if (steps.length <= windowSize) {
      return HomeRunningContext(
        subject: subject,
        ancestors: orderedAncestors,
        visibleSteps: steps,
      );
    }
    final runningIndex = steps.indexWhere((event) => event.id == running.id);
    var start = runningIndex - 3;
    if (start < 0) start = 0;
    if (start > steps.length - windowSize) start = steps.length - windowSize;
    final end = start + windowSize;
    return HomeRunningContext(
      subject: subject,
      ancestors: orderedAncestors,
      visibleSteps: steps.sublist(start, end),
      omittedBefore: start > 0,
      omittedAfter: end < steps.length,
    );
  }

  Future<String?> create(
    String name, {
    String? parentEventId,
    String? categoryId,
  }) => _change(
    () => _create(name, parentEventId: parentEventId, categoryId: categoryId),
  );
  Future<String?> edit(String id, String name) =>
      _change(() => _edit(id, name));
  Future<String?> createCategory(String name) =>
      _change(() => _categories.create(name));
  Future<String?> renameCategory(String id, String name) =>
      _change(() => _categories.rename(id, name));
  Future<String?> deleteCategory(String id) =>
      _change(() => _categories.delete(id));
  Future<String?> reorderCategory(String id, int index) =>
      _change(() => _categories.reorder(id, index));
  Future<String?> assignCategory(String eventId, String? categoryId) =>
      _change(() => _categories.assign(eventId, categoryId));
  Future<String?> delete(String id) => _change(() => _delete(id));
  Future<String?> deleteHistory(String id) => _change(() => _deleteHistory(id));
  Future<String?> start(String id) => _change(() async {
    await _start(id);
    await _ensureToday(id);
    return null;
  });
  Future<String?> pause(String id) => _change(() => _pause(id));
  Future<String?> resume(String id) => _change(() async {
    await _resume(id);
    await _ensureToday(id);
    return null;
  });
  Future<String?> wait(String id) => _change(() => _wait(id));
  Future<String?> complete(String id) => _change(() => _complete(id));
  Future<String?> restore(String id) => _change(() => _restore(id));
  Future<String?> addToToday(String id) => _change(() => _ensureToday(id));
  Future<String?> addManyToToday(Iterable<String> ids) => _change(() async {
    final requestedIds = ids.toList(growable: false);
    if (requestedIds.isEmpty) return null;
    final uniqueIds = <String>{};
    final additions = <String>[];
    for (final id in requestedIds) {
      if (!uniqueIds.add(id)) continue;
      final event = await _repository.getEvent(id);
      if (event == null) throw const DomainFailure('事件不存在');
      if (event.status == EventStatus.completed) {
        throw const DomainFailure('请先恢复已完成事件');
      }
      additions.add(id);
    }
    final dayKey = currentJaxDay.key;
    final existing =
        await _dayPlans?.getEventDayPlans(dayKey) ?? const <EventDayPlan>[];
    final planned = existing.map((plan) => plan.eventId).toSet();
    final newIds = additions.where((id) => !planned.contains(id)).toList();
    await _dayPlans?.addEventDayPlans([
      for (var i = 0; i < newIds.length; i++)
        EventDayPlan(
          eventId: newIds[i],
          dayKey: dayKey,
          order: existing.length + i,
          createdAt: _now().toUtc(),
        ),
    ]);
    return null;
  });
  Future<String?> removeFromToday(String id) => _change(() async {
    final event = await _repository.getEvent(id);
    if (event?.status == EventStatus.running) {
      throw const DomainFailure('请先暂停或完成正在执行的事件');
    }
    if (event?.status == EventStatus.completed) {
      throw const DomainFailure('当天已完成事项会保留到今日结束');
    }
    await _dayPlans?.removeEventDayPlan(id, currentJaxDay.key);
    return null;
  });
  Future<String?> moveToday(String id, int targetIndex) => _change(
    () => _dayPlans!.reorderEventDayPlan(id, currentJaxDay.key, targetIndex),
  );
  Future<void> _ensureToday(String id) async {
    final event = await _repository.getEvent(id);
    if (event == null) throw const DomainFailure('事件不存在');
    if (event.status == EventStatus.completed) {
      throw const DomainFailure('请先恢复已完成事件');
    }
    final plans =
        await _dayPlans?.getEventDayPlans(currentJaxDay.key) ??
        const <EventDayPlan>[];
    if (plans.any((plan) => plan.eventId == id)) return;
    await _dayPlans?.addEventDayPlan(
      EventDayPlan(
        eventId: id,
        dayKey: currentJaxDay.key,
        order: plans.length,
        createdAt: _now().toUtc(),
      ),
    );
  }

  String eventBreadcrumb(JaxEvent event) {
    final byId = {for (final item in _worldEvents) item.id: item};
    final names = <String>[];
    var parentId = event.parentEventId;
    final seen = <String>{event.id};
    while (parentId != null && seen.add(parentId)) {
      final parent = byId[parentId];
      if (parent == null) break;
      names.add(parent.name);
      parentId = parent.parentEventId;
    }
    return names.reversed.join(' › ');
  }

  Future<String?> createRoutine(
    String name,
    String? category,
    RoutineRecurrence recurrence,
    int mask,
  ) => _change(() => _routineService!.create(name, category, recurrence, mask));
  Future<String?> updateRoutine(
    Routine r,
    String name,
    String? category,
    RoutineRecurrence recurrence,
    int mask,
  ) => _change(
    () => _routineService!.update(r, name, category, recurrence, mask),
  );
  Future<String?> setRoutineActive(Routine r, bool active) =>
      _change(() => _routineService!.setActive(r, active));
  Future<String?> reorderRoutine(String id, int targetIndex) =>
      _change(() => _routineRepository!.reorderRoutine(id, targetIndex));
  Future<String?> startRoutine(Routine r) =>
      _change(() => _routineService!.start(r, execution: executionFor(r)));
  Future<String?> pauseRoutine(Routine r) =>
      _change(() => _routineService!.pause(executionFor(r)!));
  Future<String?> completeRoutine(Routine r) =>
      _change(() => _routineService!.complete(executionFor(r)!));
  Duration routineElapsed(Routine r) =>
      (_routineSegments[executionFor(r)?.id] ?? const []).fold(
        Duration.zero,
        (a, s) => a + s.durationAt(_now()),
      );
  Future<JaxEvent?> parentOf(String id) => _repository.getParent(id);
  Future<List<JaxEvent>> childrenOf(String id) =>
      _repository.getDirectChildren(id);
  Future<List<JaxEvent>> parentCandidates(String id) =>
      _hierarchy.parentCandidates(id);
  Future<List<JaxEvent>> childCandidates(String id) =>
      _hierarchy.childCandidates(id);
  Future<String?> setParent(String id, String? parentId) =>
      _change(() => _updateParent(id, parentId));
  Future<String?> reorder(String id, int targetIndex) =>
      _change(() => _reorder(id, targetIndex));
  Future<String?> moveUp(String id) => _enqueueReorder(() async {
    final siblings = await _repository.getOrderedSiblings(id);
    final index = siblings.indexWhere((event) => event.id == id);
    return index <= 0 ? null : reorder(id, index - 1);
  });

  Future<String?> moveDown(String id) => _enqueueReorder(() async {
    final siblings = await _repository.getOrderedSiblings(id);
    final index = siblings.indexWhere((event) => event.id == id);
    return index < 0 || index >= siblings.length - 1
        ? null
        : reorder(id, index + 1);
  });

  Future<String?> _enqueueReorder(Future<String?> Function() action) {
    final queued = _reorderTail.then((_) => action());
    _reorderTail = queued.then<void>((_) {}, onError: (_, _) {});
    return queued;
  }

  Future<Duration> directDuration(String id) => _durations.directDuration(id);
  Future<Duration> totalDuration(String id) => _durations.totalDuration(id);
  Future<TimeSummary> dailySummary(DateTime date) => _summaries.day(date);
  Future<WeeklyTimeSummary> weeklySummary(DateTime date) =>
      _summaries.week(date);
  Duration elapsedFor(JaxEvent event) =>
      (_segments[event.id] ?? const <RunSegment>[]).fold(
        Duration.zero,
        (total, segment) => total + segment.durationAt(_now()),
      );
  Future<String?> _change(Future<Object?> Function() action) async {
    try {
      await action();
      await _reload();
      recordSaveSuccess();
      return null;
    } on DomainFailure catch (failure) {
      return failure.message;
    } catch (_) {
      return '保存失败，请重试';
    }
  }

  void recordSaveSuccess() {
    _lastSavedAt = _now().toLocal();
    notifyListeners();
  }

  List<JaxEvent> _orderTree(List<JaxEvent> source) {
    final byParent = <String?, List<JaxEvent>>{};
    final ids = source.map((event) => event.id).toSet();
    for (final event in source) {
      final parent = ids.contains(event.parentEventId)
          ? event.parentEventId
          : null;
      byParent.putIfAbsent(parent, () => []).add(event);
    }
    final result = <JaxEvent>[];
    void visit(String? parent) {
      for (final event in _sortByOrder(byParent[parent] ?? const [])) {
        result.add(event);
        visit(event.id);
      }
    }

    visit(null);
    return result;
  }

  List<JaxEvent> _sortByOrder(Iterable<JaxEvent> source) => source.toList()
    ..sort((a, b) {
      final order = (a.sortOrder ?? 1 << 30).compareTo(b.sortOrder ?? 1 << 30);
      if (order != 0) return order;
      final created = a.createdAt.compareTo(b.createdAt);
      return created != 0 ? created : a.id.compareTo(b.id);
    });

  void _syncTicker() {
    final running =
        _events.any((event) => event.status == EventStatus.running) ||
        runningRoutineExecution != null;
    if (running && _ticker == null) {
      _ticker = Timer.periodic(
        const Duration(seconds: 1),
        (_) => notifyListeners(),
      );
    }
    if (!running) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  void _scheduleDayBoundaryRefresh() {
    _dayBoundaryTimer?.cancel();
    final delay = currentJaxDay.end.difference(_now().toLocal());
    _dayBoundaryTimer = Timer(
      delay.isNegative || delay == Duration.zero
          ? const Duration(milliseconds: 1)
          : delay,
      load,
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _dayBoundaryTimer?.cancel();
    super.dispose();
  }
}

class HomeWaitingItem {
  const HomeWaitingItem({required this.event, required this.ancestors});
  final JaxEvent event;
  final List<JaxEvent> ancestors;
}

class HomeRunningContext {
  const HomeRunningContext({
    required this.subject,
    required this.ancestors,
    required this.visibleSteps,
    this.omittedBefore = false,
    this.omittedAfter = false,
  });

  final JaxEvent subject;
  final List<JaxEvent> ancestors;
  final List<JaxEvent> visibleSteps;
  final bool omittedBefore;
  final bool omittedAfter;
}
