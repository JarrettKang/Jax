import '../entities/event_status.dart';
import '../entities/jax_event.dart';
import '../errors/domain_failure.dart';
import '../repositories/event_repository.dart';

typedef IdGenerator = String Function();
typedef Clock = DateTime Function();

class CreateEvent {
  const CreateEvent({
    required this._repository,
    required this._newId,
    required this._now,
  });

  final EventRepository _repository;
  final IdGenerator _newId;
  final Clock _now;

  Future<JaxEvent> call(String rawName) async {
    final name = rawName.trim();
    if (name.isEmpty) {
      throw const DomainFailure('事件名称不能为空');
    }

    final timestamp = _now().toUtc();
    final event = JaxEvent(
      id: _newId(),
      name: name,
      status: EventStatus.pending,
      createdAt: timestamp,
      updatedAt: timestamp,
    );
    await _repository.insertEvent(event);
    return event;
  }
}
