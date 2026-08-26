import '../entities/event_status.dart';
import '../entities/jax_event.dart';
import '../errors/domain_failure.dart';
import '../repositories/event_repository.dart';
import 'create_event.dart';

class EditEvent {
  const EditEvent({required this.repository, required this.now});
  final EventRepository repository;
  final Clock now;

  Future<JaxEvent> call(String id, String rawName) async {
    final name = rawName.trim();
    if (name.isEmpty) throw const DomainFailure('事件名称不能为空');
    final current = await repository.getEvent(id);
    if (current == null) throw const DomainFailure('事件不存在');
    if (current.status != EventStatus.pending &&
        current.status != EventStatus.paused &&
        current.status != EventStatus.waiting) {
      throw const DomainFailure('当前状态不允许编辑');
    }
    final edited = current.copyWith(name: name, updatedAt: now().toUtc());
    await repository.updateEvent(edited);
    return edited;
  }
}
