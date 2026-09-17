import '../../core/services/temporal_routine.dart';

import 'dart:async';

import 'package:flutter/foundation.dart' hide Category;

import '../../core/entities/event_status.dart';
import '../../core/entities/event_day_plan.dart';
import '../../core/entities/jax_day.dart';
import '../../core/entities/category.dart';
import '../../core/entities/category_palette.dart';
import '../../core/entities/jax_event.dart';
import '../../core/entities/run_segment.dart';
import '../../core/errors/domain_failure.dart';
import '../../core/repositories/event_repository.dart';
import '../../core/repositories/event_day_plan_repository.dart';
import '../../core/services/time_summary_service.dart';
import '../../core/entities/time_summary.dart';
import '../../core/entities/daily_execution_segment.dart';
import '../../core/entities/available_time_gap.dart';
import '../../core/services/execution_segment_service.dart';
import '../../core/entities/routine.dart';
import '../../core/recommendation/recommendation_engine.dart';
import '../../core/entities/routine_category.dart';
import '../../core/repositories/routine_repository.dart';
import '../../core/services/routine_service.dart';
import '../../core/services/routine_category_service.dart';
import '../../core/services/category_service.dart';
import '../../core/use_cases/complete_event.dart';
import '../../core/use_cases/create_event.dart';
import '../../core/use_cases/delete_event.dart';
import '../../core/use_cases/delete_history_record.dart';
import '../../core/use_cases/edit_event.dart';
import '../../core/use_cases/pause_event.dart';
import '../../core/use_cases/resume_event.dart';
import '../../core/use_cases/restore_event.dart';
import '../../core/use_cases/start_event.dart';
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
       _summaries = TimeSummaryService(repository, now),
       _executionSegments = ExecutionSegmentService(
         repository: repository,
         now: now,
       ),
       _newId = newId,
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
       _routineCategoryService = repository is RoutineRepository
           ? RoutineCategoryService(
               repository: repository as RoutineRepository,
               newId: newId,
               now: now,
             )
           : null,
       _categories = CategoryService(
         repository: repository,
         newId: newId,
         now: now,
       );
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
  final TimeSummaryService _summaries;
  final ExecutionSegmentService _executionSegments;
  final IdGenerator _newId;
  final EventDayPlanRepository? _dayPlans;
  final RoutineRepository? _routineRepository;
  final RoutineService? _routineService;
  final RoutineCategoryService? _routineCategoryService;
  final CategoryService _categories;
  final Map<String, List<RunSegment>> _segments = {};
  final Map<String, String?> _effectiveCategoryIds = {};
  List<JaxEvent> _events = const [];
  List<JaxEvent> _history = const [];
  List<JaxEvent> _historyRoots = const [];
  List<JaxEvent> _worldEvents = const [];
  List<Category> _categoryItems = const [];
  List<Routine> _routines = const [];
  List<RoutineCategory> _routineCategories = const [];
  final Map<String, RoutineExecution?> _todayExecutions = {};
  final Map<String, RoutineExecution?> _occurrenceExecutions = {};
  final Map<String, List<RoutineRunSegment>> _routineSegments = {};
  List<EventDayPlan> _todayPlans = const [];
  HomeRunningContext? _homeRunningContext;
  List<HomeWaitingItem> _homeWaitingItems = const [];
  bool _loading = true;
  DateTime? _lastSavedAt;
  Timer? _ticker;
  Timer? _dayBoundaryTimer;
  Future<void> _routineReorderTail = Future.value();
  Future<void> _executionTail = Future.value();
  List<JaxEvent> get events => List.unmodifiable(_events);
  List<JaxEvent> get history => List.unmodifiable(_history);
  List<JaxEvent> get historyRoots => List.unmodifiable(_historyRoots);
  List<JaxEvent> get worldEvents => List.unmodifiable(_worldEvents);
  List<Category> get categories => List.unmodifiable(_categoryItems);
  List<Routine> get routines => List.unmodifiable(_routines);
  List<RoutineCategory> get routineCategories =>
      List.unmodifiable(_routineCategories);
  int get recommendedCategoryColorKey => CategoryPalette.leastUsed([
    ..._categoryItems.map((category) => category.colorKey),
    ..._routineCategories.map((category) => category.colorKey),
  ]);
  JaxDay get currentJaxDay => JaxDay.containing(_now());
  DateTime get currentTime => _now().toLocal();
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
          (r) =>
              r.isScheduled &&
              ((r.isActive &&
                      (r.appliesTo(displayDate) ||
                          TemporalRoutine.actionable(
                                r,
                                currentJaxDay,
                                _now(),
                              ) !=
                              null)) ||
                  r.id == runningId),
        )
        .toList();
  }

  List<Routine> get activeOnDemandRoutines => _routines
      .where((routine) => routine.isActive && !routine.isScheduled)
      .toList(growable: false);

  List<Routine> get homeQuickActionRoutines => _routines
      .where((routine) => routine.isHomeQuickAction)
      .toList(growable: false);

  List<JaxEvent> get historicalEventCandidates => todayEvents
      .where(
        (event) =>
            event.status != EventStatus.running &&
            event.status != EventStatus.completed,
      )
      .toList(growable: false);

  List<Routine> get historicalScheduledRoutineCandidates => todayRoutines
      .where((routine) {
        final status = executionFor(routine)?.status;
        return status != RoutineExecutionStatus.running &&
            status != RoutineExecutionStatus.completed;
      })
      .toList(growable: false);

  List<Routine> get historicalOnDemandRoutineCandidates =>
      homeQuickActionRoutines
          .where(
            (routine) =>
                executionFor(routine)?.status != RoutineExecutionStatus.running,
          )
          .toList(growable: false);

  List<RoutineExecution> _pausedExecutions = [];
  List<RoutineExecution> get pausedRoutineExecutions =>
      List.unmodifiable(_pausedExecutions);
  List<RoutineExecution> _waitingExecutions = [];
  List<RoutineExecution> get waitingRoutineExecutions =>
      List.unmodifiable(_waitingExecutions);
  List<Routine> get waitingRoutines => _routines
      .where((r) => _waitingExecutions.any((e) => e.routineId == r.id))
      .toList();

  RoutineExecution? executionFor(Routine r) {
    final running = _todayExecutions[r.id];
    if (running?.status != RoutineExecutionStatus.running) {
      final waiting = _waitingExecutions
          .where((e) => e.routineId == r.id)
          .firstOrNull;
      if (waiting != null) return waiting;
      final paused = _pausedExecutions
          .where((e) => e.routineId == r.id)
          .firstOrNull;
      if (paused != null) return paused;
    }
    if (!r.isScheduled || running?.status == RoutineExecutionStatus.running) {
      return running;
    }
    return _occurrenceExecutions['${r.id}@${TemporalRoutine.occurrenceKey(r, _now())}'];
  }

  RoutineExecution? executionForOccurrence(
    Routine routine,
    String occurrenceKey,
  ) => _occurrenceExecutions['${routine.id}@$occurrenceKey'];

  List<ResolvedTemporalWindow> temporalOccurrencesFor(Routine r) =>
      TemporalRoutine.windows(r, currentJaxDay);
  RoutineExecution? get runningRoutineExecution => _todayExecutions.values
      .where((e) => e?.status == RoutineExecutionStatus.running)
      .firstOrNull;
  Routine? get runningRoutine {
    final e = runningRoutineExecution;
    return e == null
        ? null
        : _routines.where((r) => r.id == e.routineId).firstOrNull;
  }

  List<Recommendation> get homeRecommendations {
    final localNow = _now().toLocal();
    final context = RecommendationContext(
      currentLocalDateTime: localNow,
      currentJaxDay: JaxDay.containing(localNow),
      todayEvents: todayEvents,
      todayScheduledRoutines: todayRoutines,
      routineExecutions: {for (final r in todayRoutines) r.id: executionFor(r)},
      runningEventId: runningEvent?.id,
      runningRoutineId: runningRoutine?.id,
    );
    const provider = HomeCandidateProvider();
    const engine = RecommendationEngine(rules: [TimeRecommendationRule()]);
    return engine.recommend(context, provider.provide(context));
  }

  bool get loading => _loading;
  DateTime? get lastSavedAt => _lastSavedAt;
  JaxEvent? get runningEvent =>
      _events.where((event) => event.status == EventStatus.running).firstOrNull;
  HomeRunningContext? get homeRunningContext => _homeRunningContext;
  List<HomeWaitingItem> get homeWaitingItems =>
      List.unmodifiable(_homeWaitingItems);
  String? effectiveCategoryIdFor(String eventId) =>
      _effectiveCategoryIds[eventId];

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    await _reload();
    _loading = false;
    notifyListeners();
  }

  Future<void> _reload() async {
    _events = _sortEvents(await _repository.getIncompleteEvents());
    _history = await _repository.getCompletedEvents();
    _historyRoots = _sortEvents(_history);
    _worldEvents = _sortEvents([..._events, ..._history]);
    _categoryItems = await _repository.getCategories();
    _effectiveCategoryIds.clear();
    for (final event in _worldEvents) {
      _effectiveCategoryIds[event.id] = await _repository
          .getEffectiveCategoryId(event.id);
    }
    final currentDay = JaxDay.containing(_now());
    final dayKey = currentDay.key;
    await _dayPlans?.initializeDayFromPrevious(
      previousDayKey: currentDay.previous.key,
      currentDayKey: dayKey,
      initializedAt: _now().toUtc(),
    );
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
      _routineCategories = await _routineRepository.getRoutineCategories();
      _routines = await _routineRepository.getRoutines();
      _todayExecutions.clear();
      _occurrenceExecutions.clear();
      _routineSegments.clear();
      for (final r in _routines) {
        if (r.isScheduled) {
          for (final owner in [currentDay.previous, currentDay]) {
            final occurrence = await _routineRepository.getRoutineExecution(
              r.id,
              owner.key,
            );
            _occurrenceExecutions['${r.id}@${owner.key}'] = occurrence;
            if (occurrence != null) {
              _routineSegments[occurrence.id] = await _routineRepository
                  .getRoutineRunSegments(occurrence.id);
            }
          }
        }
        final e = r.isScheduled
            ? _occurrenceExecutions['${r.id}@${TemporalRoutine.occurrenceKey(r, _now())}']
            : await _routineRepository.getUnfinishedRoutineExecution(r.id);
        _todayExecutions[r.id] = e;
        if (e != null) {
          _routineSegments[e.id] = await _routineRepository
              .getRoutineRunSegments(e.id);
        }
      }
      _waitingExecutions =
          (await _routineRepository.getRoutineExecutions())
              .where((e) => e.status == RoutineExecutionStatus.waiting)
              .toList()
            ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
      _pausedExecutions =
          (await _routineRepository.getRoutineExecutions())
              .where((e) => e.status == RoutineExecutionStatus.paused)
              .toList()
            ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
      for (final e in [..._waitingExecutions, ..._pausedExecutions]) {
        _occurrenceExecutions['${e.routineId}@${e.occurrenceDate}'] = e;
        _routineSegments[e.id] = await _routineRepository.getRoutineRunSegments(
          e.id,
        );
      }
      final runningRoutine = await _routineRepository
          .getRunningRoutineExecution();
      if (runningRoutine != null) {
        _todayExecutions[runningRoutine.routineId] = runningRoutine;
        _routineSegments[runningRoutine.id] = await _routineRepository
            .getRoutineRunSegments(runningRoutine.id);
      }
    }
    for (final event in [..._events, ..._history]) {
      _segments[event.id] = await _repository.getRunSegments(event.id);
    }
    final running = runningEvent;
    _homeRunningContext = running == null
        ? null
        : HomeRunningContext(
            subject: running,
            ancestors: const [],
            visibleSteps: [running],
          );
    _homeWaitingItems = [
      for (final event in _events.where(
        (event) => event.status == EventStatus.waiting,
      ))
        HomeWaitingItem(event: event, ancestors: const []),
    ];
    _syncTicker();
    _scheduleDayBoundaryRefresh();
  }

  Future<String?> create(String name, {String? categoryId}) =>
      _change(() => _create(name, categoryId: categoryId));

  Future<String?> createAndStartStandalone(String name, {String? categoryId}) =>
      _enqueueExecution(
        () => _change(() async {
          final event = await _create(name, categoryId: categoryId);
          await _start(event.id);
          await _ensureToday(event.id);
          return null;
        }),
      );

  Future<String?> createStandaloneForToday(String name, {String? categoryId}) =>
      _change(() async {
        final event = await _create(name, categoryId: categoryId);
        await _ensureToday(event.id);
        return null;
      });
  Future<String?> edit(String id, String name) =>
      _change(() => _edit(id, name));
  Future<String?> createCategory(String name, {int? colorKey}) =>
      _change(() => _categories.create(name, colorKey: colorKey));
  Future<String?> updateCategory(String id, String name, {int? colorKey}) =>
      _change(() => _categories.update(id, name, colorKey: colorKey));
  Future<String?> renameCategory(String id, String name) =>
      updateCategory(id, name);
  Future<String?> deleteCategory(String id) =>
      _change(() => _categories.delete(id));
  Future<String?> reorderCategory(String id, int index) =>
      _change(() => _categories.reorder(id, index));
  Future<String?> assignCategory(String eventId, String? categoryId) =>
      _change(() => _categories.assign(eventId, categoryId));
  Future<String?> delete(String id) => _change(() => _delete(id));
  Future<String?> deleteHistory(String id) => _change(() => _deleteHistory(id));
  Future<String?> start(String id) => _enqueueExecution(
    () => _change(() async {
      await _start(id);
      await _ensureToday(id);
      return null;
    }),
  );
  Future<String?> pause(String id) =>
      _enqueueExecution(() => _change(() => _pause(id)));
  Future<String?> resume(String id) => _enqueueExecution(
    () => _change(() async {
      await _resume(id);
      await _ensureToday(id);
      return null;
    }),
  );
  Future<String?> wait(String id) =>
      _enqueueExecution(() => _change(() => _wait(id)));
  Future<String?> complete(String id) =>
      _enqueueExecution(() => _change(() => _complete(id)));
  Future<String?> completeAt(String id, DateTime endTime) =>
      correctedEventEndAction(id)(endTime);
  Future<String?> pauseAt(String id, DateTime endTime) =>
      correctedEventEndAction(id, pause: true)(endTime);

  Future<String?> Function(DateTime) correctedEventEndAction(
    String id, {
    bool pause = false,
  }) {
    final expected = _events.where((e) => e.id == id).firstOrNull;
    final open = (_segments[id] ?? const <RunSegment>[])
        .where((s) => s.endedAt == null)
        .toList();
    return (end) => _enqueueExecution(
      () => _change(() async {
        if (expected == null || open.length != 1) {
          throw const DomainFailure('执行计时数据不完整');
        }
        await _executionSegments.closeRunningEventAt(
          expected: expected,
          segment: open.single,
          end: end,
          pause: pause,
        );
        return null;
      }),
    );
  }

  Future<String?> adjustRunningEventStart(
    String id,
    DateTime expectedStartedAt,
    DateTime newStartedAt,
  ) => _enqueueExecution(
    () => _change(() async {
      final open = (_segments[id] ?? const <RunSegment>[])
          .where((segment) => segment.endedAt == null)
          .toList(growable: false);
      if (open.length != 1) {
        throw const DomainFailure('当前执行状态已发生变化，请重新操作');
      }
      await _executionSegments.adjustRunningEventStart(
        eventId: id,
        segmentId: open.single.id,
        expectedStartedAt: expectedStartedAt,
        newStartedAt: newStartedAt,
      );
      return null;
    }),
  );
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
  bool canDeferToday(JaxEvent event) =>
      event.isStandalone && event.status == EventStatus.pending;

  Future<String?> removeFromToday(String id) => _enqueueExecution(
    () => _change(() async {
      final event = await _repository.getEvent(id);
      if (event == null || !canDeferToday(event)) {
        throw const DomainFailure('只有尚未开始的独立事项可以选择今天先不处理');
      }
      await _dayPlans?.removeEventDayPlan(id, currentJaxDay.key);
      return null;
    }),
  );
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

  Future<String?> createRoutine(
    String name,
    String? category,
    RoutineRecurrence recurrence,
    int mask, {
    RoutineType type = RoutineType.scheduled,
    bool showInHomeQuickActions = false,
    RoutineTimeRecommendation? timeRecommendation,
  }) => _change(
    () => _routineService!.create(
      name,
      category,
      recurrence,
      mask,
      type: type,
      showInHomeQuickActions: showInHomeQuickActions,
      timeRecommendation: timeRecommendation,
    ),
  );
  Future<String?> updateRoutine(
    Routine r,
    String name,
    String? category,
    RoutineRecurrence recurrence,
    int mask, {
    RoutineType? type,
    bool? showInHomeQuickActions,
    RoutineTimeRecommendation? timeRecommendation,
    bool updateTimeRecommendation = false,
  }) => _change(
    () => _routineService!.update(
      r,
      name,
      category,
      recurrence,
      mask,
      type: type,
      timeRecommendation: timeRecommendation,
      updateTimeRecommendation: updateTimeRecommendation,
      showInHomeQuickActions: showInHomeQuickActions,
    ),
  );
  Future<String?> setRoutineActive(Routine r, bool active) =>
      _change(() => _routineService!.setActive(r, active));
  Future<String?> createRoutineCategory(String name, {int? colorKey}) =>
      _change(() => _routineCategoryService!.create(name, colorKey: colorKey));
  Future<String?> updateRoutineCategory(
    RoutineCategory c,
    String name, {
    int? colorKey,
  }) => _change(
    () => _routineCategoryService!.update(c, name, colorKey: colorKey),
  );
  Future<String?> renameRoutineCategory(RoutineCategory c, String name) =>
      updateRoutineCategory(c, name);
  Future<String?> deleteRoutineCategory(String id) =>
      _change(() => _routineCategoryService!.delete(id));
  Future<String?> reorderRoutineCategory(String id, int target) =>
      _change(() => _routineCategoryService!.reorder(id, target));
  Future<String?> reorderRoutine(String id, int targetIndex) {
    final repository = _routineRepository;
    if (repository == null) return Future.value('日常不可用');
    return _enqueueRoutineReorder(
      () => _change(() => repository.reorderRoutine(id, targetIndex)),
    );
  }

  Future<String?> moveRoutineUp(String id) => _moveRoutine(id, -1);
  Future<String?> moveRoutineDown(String id) => _moveRoutine(id, 1);

  Future<String?> _moveRoutine(String id, int direction) {
    final repository = _routineRepository;
    if (repository == null) return Future.value('日常不可用');
    return _enqueueRoutineReorder(() async {
      final routines = await repository.getRoutines();
      final current = routines.where((routine) => routine.id == id).firstOrNull;
      if (current == null) return '日常不存在';
      final group = routines
          .where(
            (routine) =>
                routine.isActive == current.isActive &&
                routine.routineCategoryId == current.routineCategoryId,
          )
          .toList(growable: false);
      final index = group.indexWhere((routine) => routine.id == id);
      final targetInGroup = index + direction;
      if (index < 0 || targetInGroup < 0 || targetInGroup >= group.length) {
        return null;
      }
      final targetId = group[targetInGroup].id;
      final targetIndex = group.indexWhere((routine) => routine.id == targetId);
      return _change(() => repository.reorderRoutine(id, targetIndex));
    });
  }

  Future<String?> _enqueueRoutineReorder(Future<String?> Function() action) {
    final queued = _routineReorderTail.then((_) => action());
    _routineReorderTail = queued.then<void>((_) {}, onError: (_, _) {});
    return queued;
  }

  Future<String?> _enqueueExecution(Future<String?> Function() action) {
    final queued = _executionTail.then((_) => action());
    _executionTail = queued.then<void>((_) {}, onError: (_, _) {});
    return queued;
  }

  Future<String?> startRoutineOccurrence(Routine r, String key) =>
      _enqueueExecution(
        () => _change(
          () => _routineService!.start(
            r,
            execution: executionForOccurrence(r, key),
            occurrenceDayKey: key,
          ),
        ),
      );
  Future<String?> pauseRoutineOccurrence(Routine r, String key) =>
      _enqueueExecution(
        () => _change(
          () => _routineService!.pause(executionForOccurrence(r, key)!),
        ),
      );
  Future<String?> completeRoutineOccurrence(Routine r, String key) =>
      _enqueueExecution(
        () => _change(
          () => _routineService!.complete(executionForOccurrence(r, key)!),
        ),
      );

  Future<String?> startRoutine(Routine r) => _enqueueExecution(
    () => _change(() => _routineService!.start(r, execution: executionFor(r))),
  );
  Future<String?> waitRoutine(Routine r) => _enqueueExecution(
    () => _change(() => _routineService!.wait(executionFor(r)!)),
  );
  Future<String?> resumeWaitingRoutine(RoutineExecution e) => _enqueueExecution(
    () => _change(
      () => _routineService!.start(
        _routines.firstWhere((r) => r.id == e.routineId),
        execution: e,
      ),
    ),
  );
  Future<String?> completeRoutineExecution(RoutineExecution e) =>
      _enqueueExecution(() => _change(() => _routineService!.complete(e)));
  Future<String?> resumeRoutineExecution(RoutineExecution e) =>
      _enqueueExecution(
        () => _change(() async {
          final r = _routines.where((r) => r.id == e.routineId).firstOrNull;
          if (r == null) throw const DomainFailure('日常不存在');
          await _routineService!.start(r, execution: e);
          return null;
        }),
      );
  Future<String?> completeWaitingRoutine(RoutineExecution e) =>
      _enqueueExecution(() => _change(() => _routineService!.complete(e)));
  Future<String?> pauseRoutine(Routine r) => _enqueueExecution(
    () => _change(() => _routineService!.pause(executionFor(r)!)),
  );
  Future<String?> completeRoutine(Routine r) => _enqueueExecution(
    () => _change(() => _routineService!.complete(executionFor(r)!)),
  );
  Future<String?> completeRoutineAt(Routine r, DateTime endTime) =>
      correctedRoutineEndAction(r)(endTime);
  Future<String?> pauseRoutineAt(Routine r, DateTime endTime) =>
      correctedRoutineEndAction(r, pause: true)(endTime);

  Future<String?> Function(DateTime) correctedRoutineEndAction(
    Routine r, {
    bool pause = false,
  }) {
    final expected = executionFor(r);
    final open = (_routineSegments[expected?.id] ?? const <RoutineRunSegment>[])
        .where((s) => s.endedAt == null)
        .toList();
    return (end) => _enqueueExecution(
      () => _change(() async {
        if (expected == null || open.length != 1) {
          throw const DomainFailure('执行计时数据不完整');
        }
        await _executionSegments.closeRunningRoutineAt(
          expected: expected,
          segment: open.single,
          end: end,
          pause: pause,
        );
        return null;
      }),
    );
  }

  Future<String?> adjustRunningRoutineStart(
    Routine routine,
    DateTime expectedStartedAt,
    DateTime newStartedAt,
  ) => _enqueueExecution(
    () => _change(() async {
      final execution = executionFor(routine);
      if (execution == null) {
        throw const DomainFailure('当前执行状态已发生变化，请重新操作');
      }
      final open =
          (_routineSegments[execution.id] ?? const <RoutineRunSegment>[])
              .where((segment) => segment.endedAt == null)
              .toList(growable: false);
      if (open.length != 1) {
        throw const DomainFailure('当前执行状态已发生变化，请重新操作');
      }
      await _executionSegments.adjustRunningRoutineStart(
        executionId: execution.id,
        segmentId: open.single.id,
        expectedStartedAt: expectedStartedAt,
        newStartedAt: newStartedAt,
      );
      return null;
    }),
  );

  bool hasEventRunSegments(String eventId) =>
      (_segments[eventId] ?? const <RunSegment>[]).isNotEmpty;

  DateTime? runningEventStartedAt(String eventId) =>
      (_segments[eventId] ?? const <RunSegment>[])
          .where((segment) => segment.endedAt == null)
          .firstOrNull
          ?.startedAt
          .toLocal();

  DateTime? runningRoutineStartedAt(Routine routine) {
    final execution = executionFor(routine);
    if (execution == null) return null;
    return (_routineSegments[execution.id] ?? const <RoutineRunSegment>[])
        .where((segment) => segment.endedAt == null)
        .firstOrNull
        ?.startedAt
        .toLocal();
  }

  String historicalEventContext(JaxEvent event) {
    final category = _categoryItems
        .where((item) => item.id == _effectiveCategoryIds[event.id])
        .firstOrNull;
    return category?.name ?? '未分类';
  }

  String historicalRoutineContext(Routine routine) {
    final category = _routineCategories
        .where((item) => item.id == routine.routineCategoryId)
        .firstOrNull;
    return '${category?.name ?? '未分类'} · ${routine.isScheduled ? _routineRecurrence(routine.recurrence) : '按需'}';
  }

  String _routineRecurrence(RoutineRecurrence recurrence) =>
      switch (recurrence) {
        RoutineRecurrence.daily => '每日',
        RoutineRecurrence.weekdays => '工作日',
        RoutineRecurrence.weekends => '周末',
        RoutineRecurrence.selectedWeekdays => '指定星期',
      };
  Duration routineElapsed(Routine r) =>
      (_routineSegments[executionFor(r)?.id] ?? const []).fold(
        Duration.zero,
        (a, s) => a + s.durationAt(_now()),
      );
  Future<Duration> directDuration(String id) async =>
      (await _repository.getRunSegments(id)).fold<Duration>(
        Duration.zero,
        (total, segment) => total + segment.durationAt(_now()),
      );
  Future<TimeSummary> dailySummary(DateTime date) => _summaries.day(date);
  Future<WeeklyTimeSummary> weeklySummary(DateTime date) =>
      _summaries.week(date);
  Future<List<DailyExecutionSegment>> dailyExecutionSegments(DateTime date) =>
      _executionSegments.forJaxDay(date);
  Future<List<AvailableTimeGap>> availableTimeGaps(DateTime date) =>
      _executionSegments.availableGapsForJaxDay(date);
  Future<String?> validateHistoricalSegmentRange(
    DateTime start,
    DateTime end,
  ) async {
    try {
      await _executionSegments.validateNewRange(start, end);
      return null;
    } on DomainFailure catch (failure) {
      return failure.message;
    }
  }

  Future<String?> updateClosedExecutionSegment(
    DailyExecutionSegment segment,
    DateTime start,
    DateTime end,
  ) => _change(() => _executionSegments.updateClosed(segment, start, end));
  Future<String?> deleteClosedExecutionSegment(DailyExecutionSegment segment) =>
      _change(() => _executionSegments.deleteClosed(segment));
  Future<String?> addHistoricalEventSegment(
    String eventId,
    DateTime start,
    DateTime end,
  ) =>
      _change(() => _executionSegments.addEvent(eventId, _newId(), start, end));
  Future<String?> addHistoricalRoutineSegment(
    String routineId,
    DateTime day,
    DateTime start,
    DateTime end,
  ) => _change(() {
    final routine = _routines.where((item) => item.id == routineId).firstOrNull;
    if (routine == null) throw const DomainFailure('日常不存在');
    return _executionSegments.addRoutine(
      routineId,
      _newId(),
      _newId(),
      routine.isScheduled ? currentJaxDay.key : JaxDay.forDisplayDate(day).key,
      start,
      end,
    );
  });
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

  List<JaxEvent> _sortEvents(Iterable<JaxEvent> source) =>
      source.toList()..sort((a, b) {
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
