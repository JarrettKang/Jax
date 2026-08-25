import '../entities/event_status.dart';
import '../errors/domain_failure.dart';
import '../repositories/event_repository.dart';

class DeleteHistoryRecord {
  const DeleteHistoryRecord(this.repository);
  final EventRepository repository;
  Future<void> call(String id) async {
    final event = await repository.getEvent(id);
    if (event == null) throw const DomainFailure('历史记录不存在');
    if (event.status != EventStatus.completed) {
      throw const DomainFailure('只能删除已完成记录');
    }
    if ((await repository.getDirectChildren(id)).isNotEmpty) {
      throw const DomainFailure('该事件仍包含下层事件，请先解除或调整层级关系');
    }
    await repository.deleteEvent(id);
  }
}
