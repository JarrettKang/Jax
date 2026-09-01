import '../entities/event_status.dart';
import '../entities/jax_event.dart';
import '../errors/domain_failure.dart';
import '../repositories/event_repository.dart';
import 'create_event.dart';

class RestoreEvent {
  const RestoreEvent({required this.repository, required this.now});

  final EventRepository repository;
  final Clock now;

  Future<JaxEvent> call(String id) async {
    final current = await repository.getEvent(id);
    if (current == null) throw const DomainFailure('事件不存在');
    if (current.status != EventStatus.completed) {
      throw const DomainFailure('只有已完成事件可以恢复');
    }

    final timestamp = now().toUtc();
    final restored = current.copyWith(
      status: EventStatus.paused,
      completedAt: null,
      updatedAt: timestamp,
    );
    await repository.restoreCompletedEvents([restored]);
    return restored;
  }
}
