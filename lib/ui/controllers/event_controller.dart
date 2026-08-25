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
import '../../core/use_cases/start_event.dart';
import '../../core/use_cases/update_event_parent.dart';

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
       _start = StartEvent(repository: repository, newId: newId, now: now),
       _hierarchy = EventHierarchyService(repository),
       _durations = HierarchyDurationService(repository, now: now),
       _updateParent = UpdateEventParent(repository: repository, now: now);
  final EventRepository _repository;
  final Clock _now;
  final CompleteEvent _complete;
  final CreateEvent _create;
  final EditEvent _edit;
  final DeleteEvent _delete;
  final DeleteHistoryRecord _deleteHistory;
  final PauseEvent _pause;
  final ResumeEvent _resume;
  final StartEvent _start;
  final EventHierarchyService _hierarchy;
  final HierarchyDurationService _durations;
  final UpdateEventParent _updateParent;
  final Map<String, List<RunSegment>> _segments = {};
  List<JaxEvent> _events = const [];
  List<JaxEvent> _history = const [];
  List<JaxEvent> _historyRoots = const [];
  JaxEvent? _runningParent;
  List<JaxEvent> _runningSiblings = const [];
  bool _loading = true;
  DateTime? _lastSavedAt;
  Timer? _ticker;
  List<JaxEvent> get events => List.unmodifiable(_events);
  List<JaxEvent> get history => List.unmodifiable(_history);
  List<JaxEvent> get historyRoots => List.unmodifiable(_historyRoots);
  bool get loading => _loading;
  DateTime? get lastSavedAt => _lastSavedAt;
  JaxEvent? get runningEvent =>
      _events.where((event) => event.status == EventStatus.running).firstOrNull;
  JaxEvent? get runningParent =>
      _runningSiblings.isEmpty ? null : _runningParent;
  List<JaxEvent> get runningSiblings => List.unmodifiable(_runningSiblings);

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    await _reload();
    _loading = false;
    notifyListeners();
  }

  Future<void> _reload() async {
    _events = await _repository.getIncompleteEvents();
    _history = await _repository.getCompletedEvents();
    final roots = <JaxEvent>[];
    for (final event in _history) {
      final parent = await _repository.getParent(event.id);
      if (parent == null || parent.status != EventStatus.completed) {
        roots.add(event);
      }
    }
    _historyRoots = roots;
    for (final event in [..._events, ..._history]) {
      _segments[event.id] = await _repository.getRunSegments(event.id);
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
    _syncTicker();
  }

  Future<String?> create(String name) => _change(() => _create(name));
  Future<String?> edit(String id, String name) =>
      _change(() => _edit(id, name));
  Future<String?> delete(String id) => _change(() => _delete(id));
  Future<String?> deleteHistory(String id) => _change(() => _deleteHistory(id));
  Future<String?> start(String id) => _change(() => _start(id));
  Future<String?> pause(String id) => _change(() => _pause(id));
  Future<String?> resume(String id) => _change(() => _resume(id));
  Future<String?> complete(String id) => _change(() => _complete(id));
  Future<JaxEvent?> parentOf(String id) => _repository.getParent(id);
  Future<List<JaxEvent>> childrenOf(String id) =>
      _repository.getDirectChildren(id);
  Future<List<JaxEvent>> parentCandidates(String id) =>
      _hierarchy.parentCandidates(id);
  Future<List<JaxEvent>> childCandidates(String id) =>
      _hierarchy.childCandidates(id);
  Future<String?> setParent(String id, String? parentId) =>
      _change(() => _updateParent(id, parentId));
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
