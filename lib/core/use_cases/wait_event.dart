import '../entities/event_status.dart';
import '../errors/domain_failure.dart';
import '../repositories/event_repository.dart';
import '../services/segment_lifecycle_log.dart';
import 'create_event.dart';

class WaitEvent {
  const WaitEvent({required this.repository, required this.now});
  final EventRepository repository;
  final Clock now;

  Future<void> call(String id) async {
    final current = await repository.getEvent(id);
    if (current == null) throw const DomainFailure('事件不存在');
    if (current.status == EventStatus.paused) {
      await repository.updateEvent(
        current.copyWith(status: EventStatus.waiting, updatedAt: now().toUtc()),
      );
      return;
    }
    if (current.status != EventStatus.running) {
      throw const DomainFailure('只有正在进行或已暂停的事件可以设为等待');
    }
    final open = (await repository.getRunSegments(id))
        .where((segment) => segment.endedAt == null)
        .firstOrNull;
    if (open == null) throw const DomainFailure('执行计时数据不完整');
    final timestamp = now().toUtc();
    await repository.pauseEvent(
      current.copyWith(status: EventStatus.waiting, updatedAt: timestamp),
      open.copyWith(endedAt: timestamp),
    );
    SegmentLifecycleLog.close(
      reason: 'event_wait',
      ownerType: 'event',
      ownerId: id,
      segmentId: open.id,
      startedAt: open.startedAt,
      endedAt: timestamp,
    );
  }
}
