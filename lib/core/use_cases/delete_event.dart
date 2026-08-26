import '../entities/event_status.dart';
import '../errors/domain_failure.dart';
import '../repositories/event_repository.dart';

class DeleteEvent {
  const DeleteEvent(this.repository);
  final EventRepository repository;

  Future<void> call(String id) async {
    final event = await repository.getEvent(id);
    if (event == null) throw const DomainFailure('事件不存在');
    if (event.status != EventStatus.pending &&
        event.status != EventStatus.paused &&
        event.status != EventStatus.waiting) {
      throw const DomainFailure('当前状态不允许删除');
    }
    if ((await repository.getDirectChildren(id)).isNotEmpty) {
      throw const DomainFailure('该事件仍包含下层事件，请先解除或调整层级关系');
    }
    await repository.deleteEvent(id);
  }
}
