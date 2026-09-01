import '../entities/event_status.dart';
import '../entities/run_segment.dart';
import '../errors/domain_failure.dart';
import '../repositories/event_repository.dart';
import '../services/running_event_switch_service.dart';
import '../services/segment_lifecycle_log.dart';
import 'create_event.dart';

class ResumeEvent {
  const ResumeEvent({
    required this.repository,
    required this.newId,
    required this.now,
  });
  final EventRepository repository;
  final IdGenerator newId;
  final Clock now;
  Future<void> call(String id) async {
    final current = await repository.getEvent(id);
    if (current == null) throw const DomainFailure('事件不存在');
    if (current.status != EventStatus.paused &&
        current.status != EventStatus.waiting) {
      throw const DomainFailure('只有已暂停或等待中事件可以恢复');
    }
    final timestamp = now().toUtc();
    if (await RunningEventSwitchService(repository)
            .switchIfNeeded(current, timestamp, newId) !=
        null) {
      return;
    }
    final segment = RunSegment(
      id: newId(),
      eventId: id,
      startedAt: timestamp,
      createdAt: timestamp,
    );
    final running = current.copyWith(
      status: EventStatus.running,
      updatedAt: timestamp,
    );
    await repository.startEvent(running, segment);
    SegmentLifecycleLog.open(
      reason: current.status == EventStatus.waiting
          ? 'event_waiting_resume'
          : 'event_resume',
      ownerType: 'event',
      ownerId: id,
      segmentId: segment.id,
      startedAt: timestamp,
    );
  }
}
