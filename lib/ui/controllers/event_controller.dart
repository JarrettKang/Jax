import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/entities/event_status.dart';
import '../../core/entities/jax_event.dart';
import '../../core/entities/run_segment.dart';
import '../../core/errors/domain_failure.dart';
import '../../core/repositories/event_repository.dart';
import '../../core/use_cases/complete_event.dart';
import '../../core/use_cases/create_event.dart';
import '../../core/use_cases/delete_event.dart';
import '../../core/use_cases/edit_event.dart';
import '../../core/use_cases/pause_event.dart';
import '../../core/use_cases/resume_event.dart';
import '../../core/use_cases/start_event.dart';

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
       _pause = PauseEvent(repository: repository, now: now),
       _resume = ResumeEvent(repository: repository, newId: newId, now: now),
       _start = StartEvent(repository: repository, newId: newId, now: now);
  final EventRepository _repository;
  final Clock _now;
  final CompleteEvent _complete;
  final CreateEvent _create;
  final EditEvent _edit;
  final DeleteEvent _delete;
  final PauseEvent _pause;
  final ResumeEvent _resume;
  final StartEvent _start;
  final Map<String, List<RunSegment>> _segments = {};
  List<JaxEvent> _events = const [];
  List<JaxEvent> _history = const [];
  bool _loading = true;
  Timer? _ticker;
  List<JaxEvent> get events => List.unmodifiable(_events);
  List<JaxEvent> get history => List.unmodifiable(_history);
  bool get loading => _loading;

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
    for (final event in _events) {
      _segments[event.id] = await _repository.getRunSegments(event.id);
    }
    _syncTicker();
  }

  Future<String?> create(String name) => _change(() => _create(name));
  Future<String?> edit(String id, String name) =>
      _change(() => _edit(id, name));
  Future<String?> delete(String id) => _change(() => _delete(id));
  Future<String?> start(String id) => _change(() => _start(id));
  Future<String?> pause(String id) => _change(() => _pause(id));
  Future<String?> resume(String id) => _change(() => _resume(id));
  Future<String?> complete(String id) => _change(() => _complete(id));
  Duration elapsedFor(JaxEvent event) =>
      (_segments[event.id] ?? const <RunSegment>[]).fold(
        Duration.zero,
        (total, segment) => total + segment.durationAt(_now()),
      );
  Future<String?> _change(Future<Object?> Function() action) async {
    try {
      await action();
      await _reload();
      notifyListeners();
      return null;
    } on DomainFailure catch (failure) {
      return failure.message;
    }
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
