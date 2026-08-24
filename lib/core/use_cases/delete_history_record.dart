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
    await repository.deleteEvent(id);
  }
}
