import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/entities/event_status.dart';
import '../../core/entities/jax_event.dart';
import '../../core/entities/run_segment.dart';
import '../../core/errors/domain_failure.dart';
import '../../core/repositories/event_repository.dart';
import '../../core/services/event_hierarchy_service.dart';
import '../../core/services/hierarchy_duration_service.dart';
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
  final UpdateEventParent _updateParent;
  final ReorderSibling _reorder;
  final Map<String, List<RunSegment>> _segments = {};
  final Map<String, bool> _hasDirectChildren = {};
  List<JaxEvent> _events = const [];
  List<JaxEvent> _history = const [];
  List<JaxEvent> _historyRoots = const [];
  List<JaxEvent> _worldEvents = const [];
  JaxEvent? _runningParent;
  List<JaxEvent> _runningSiblings = const [];
  HomeRunningContext? _homeRunningContext;
  List<HomeWaitingItem> _homeWaitingItems = const [];
  bool _loading = true;
  DateTime? _lastSavedAt;
  Timer? _ticker;
  List<JaxEvent> get events => List.unmodifiable(_events);
  List<JaxEvent> get history => List.unmodifiable(_history);
  List<JaxEvent> get historyRoots => List.unmodifiable(_historyRoots);
  List<JaxEvent> get worldEvents => List.unmodifiable(_worldEvents);
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

  Future<String?> create(String name) => _change(() => _create(name));
  Future<String?> edit(String id, String name) =>
      _change(() => _edit(id, name));
  Future<String?> delete(String id) => _change(() => _delete(id));
  Future<String?> deleteHistory(String id) => _change(() => _deleteHistory(id));
  Future<String?> start(String id) => _change(() => _start(id));
  Future<String?> pause(String id) => _change(() => _pause(id));
  Future<String?> resume(String id) => _change(() => _resume(id));
  Future<String?> wait(String id) => _change(() => _wait(id));
  Future<String?> complete(String id) => _change(() => _complete(id));
  Future<String?> restore(String id) => _change(() => _restore(id));
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
  Future<String?> moveUp(String id) async {
    final siblings = await _repository.getOrderedSiblings(id);
    final index = siblings.indexWhere((event) => event.id == id);
    return index <= 0 ? null : reorder(id, index - 1);
  }

  Future<String?> moveDown(String id) async {
    final siblings = await _repository.getOrderedSiblings(id);
    final index = siblings.indexWhere((event) => event.id == id);
    return index < 0 || index >= siblings.length - 1
        ? null
        : reorder(id, index + 1);
  }

  Future<Duration> directDuration(String id) => _durations.directDuration(id);
  Future<Duration> totalDuration(String id) => _durations.totalDuration(id);
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
    final running = _events.any((event) => event.status == EventStatus.running);
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

  @override
  void dispose() {
    _ticker?.cancel();
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
