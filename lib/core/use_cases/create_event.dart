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

  Future<JaxEvent> call(
    String rawName, {
    String? parentEventId,
    String? categoryId,
  }) async {
    final name = rawName.trim();
    if (name.isEmpty) {
      throw const DomainFailure('事件名称不能为空');
    }

    if (parentEventId != null) {
      final parent = await _repository.getEvent(parentEventId);
      if (parent == null) throw const DomainFailure('上层事件不存在');
      if (parent.status == EventStatus.completed) {
        throw const DomainFailure('未完成事件不能归属到已完成的上层事件');
      }
      // Descendants always derive their Category from their root.  They never
      // persist an independent category_id.
      categoryId = null;
    } else if (categoryId != null &&
        !(await _repository.getCategories()).any(
          (category) => category.id == categoryId,
        )) {
      throw const DomainFailure('分类不存在');
    }

    final timestamp = _now().toUtc();
    final event = JaxEvent(
      id: _newId(),
      name: name,
      status: EventStatus.pending,
      createdAt: timestamp,
      updatedAt: timestamp,
      parentEventId: parentEventId,
      categoryId: categoryId,
    );
    await _repository.insertEvent(event);
    return event;
  }
}
