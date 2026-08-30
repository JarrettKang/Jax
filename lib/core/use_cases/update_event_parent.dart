import '../entities/event_status.dart';
import '../entities/jax_event.dart';
import '../errors/domain_failure.dart';
import '../repositories/event_repository.dart';
import 'create_event.dart';

class UpdateEventParent {
  const UpdateEventParent({required this.repository, required this.now});
  final EventRepository repository;
  final Clock now;

  Future<void> call(String eventId, String? parentEventId) async {
    final event = await repository.getEvent(eventId);
    if (event == null) throw const DomainFailure('事件不存在');
    if (parentEventId == null) {
      await repository.updateParent(eventId, null, now().toUtc());
      return;
    }
    if (eventId == parentEventId) {
      throw const DomainFailure('事件不能成为自己的上层事件');
    }
    final parent = await repository.getEvent(parentEventId);
    if (parent == null) throw const DomainFailure('上层事件不存在');
    final eventCategoryId = await _effectiveCategoryId(event);
    final parentCategoryId = await _effectiveCategoryId(parent);
    if (eventCategoryId != parentCategoryId) {
      throw const DomainFailure('只能在同一分类内调整事件层级');
    }
    if (event.status != EventStatus.completed &&
        parent.status == EventStatus.completed) {
      throw const DomainFailure('未完成事件不能归属到已完成的上层事件');
    }
    var ancestor = parent;
    final visited = <String>{};
    while (visited.add(ancestor.id)) {
      if (ancestor.id == eventId) {
        throw const DomainFailure('该层级关系会形成循环');
      }
      final next = await repository.getParent(ancestor.id);
      if (next == null) break;
      ancestor = next;
    }
    await repository.updateParent(eventId, parentEventId, now().toUtc());
  }

  Future<String?> _effectiveCategoryId(JaxEvent event) async {
    var current = event;
    final visited = <String>{};
    while (current.parentEventId != null && visited.add(current.id)) {
      final parent = await repository.getParent(current.id);
      if (parent == null) break;
      current = parent;
    }
    return current.categoryId;
  }
}
