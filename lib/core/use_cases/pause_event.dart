import '../entities/event_status.dart';
import '../errors/domain_failure.dart';
import '../repositories/event_repository.dart';
import '../services/segment_lifecycle_log.dart';
import 'create_event.dart';

class PauseEvent {
  const PauseEvent({required this.repository, required this.now});
  final EventRepository repository;
  final Clock now;
  Future<void> call(String id) async {
    final current = await repository.getEvent(id);
    if (current == null) throw const DomainFailure('事件不存在');
    if (current.status == EventStatus.waiting) {
      await repository.updateEvent(
        current.copyWith(status: EventStatus.paused, updatedAt: now().toUtc()),
      );
      return;
    }
    if (current.status != EventStatus.running) {
      throw const DomainFailure('只有正在进行或等待中的事件可以暂停');
    }
    final segments = await repository.getRunSegments(id);
    final open = segments
        .where((segment) => segment.endedAt == null)
        .firstOrNull;
    if (open == null) throw const DomainFailure('执行计时数据不完整');
    final timestamp = now().toUtc();
    final paused = current.copyWith(
      status: EventStatus.paused,
      updatedAt: timestamp,
    );
    await repository.pauseEvent(paused, open.copyWith(endedAt: timestamp));
    SegmentLifecycleLog.close(
      reason: 'event_pause',
      ownerType: 'event',
      ownerId: id,
      segmentId: open.id,
      startedAt: open.startedAt,
      endedAt: timestamp,
    );
  }
}
