import '../errors/domain_failure.dart';
import '../repositories/event_repository.dart';

class ReorderSibling {
  const ReorderSibling(this.repository);

  final EventRepository repository;

  Future<void> call(String eventId, int targetIndex) async {
    final siblings = await repository.getOrderedSiblings(eventId);
    final currentIndex = siblings.indexWhere((event) => event.id == eventId);
    if (currentIndex < 0) throw const DomainFailure('事件不存在');
    if (targetIndex < 0 || targetIndex >= siblings.length) {
      throw const DomainFailure('排序位置无效');
    }
    await repository.reorderSibling(eventId, targetIndex);
  }
}
