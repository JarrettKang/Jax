import '../entities/event_status.dart';
import '../repositories/event_repository.dart';
import '../services/save_service.dart';
import 'create_event.dart';
import 'pause_event.dart';

class PrepareForShutdown {
  PrepareForShutdown({
    required EventRepository repository,
    required this._saveService,
    required Clock now,
  }) : _repository = repository,
       _pause = PauseEvent(repository: repository, now: now);

  final EventRepository _repository;
  final SaveService _saveService;
  final PauseEvent _pause;
  Future<void>? _inFlight;

  Future<void> call() {
    final existing = _inFlight;
    if (existing != null) return existing;
    final operation = _execute();
    _inFlight = operation;
    operation.then((_) => _inFlight = null, onError: (_) => _inFlight = null);
    return operation;
  }

  Future<void> _execute() async {
    final events = await _repository.getIncompleteEvents();
    final running = events
        .where((event) => event.status == EventStatus.running)
        .firstOrNull;
    if (running != null) await _pause(running.id);
    await _saveService.flush();
  }
}
