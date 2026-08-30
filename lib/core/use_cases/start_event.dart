import '../entities/event_status.dart';
import '../entities/jax_event.dart';
import '../entities/run_segment.dart';
import '../errors/domain_failure.dart';
import '../repositories/event_repository.dart';
import '../services/descendant_switch_service.dart';
import '../services/segment_lifecycle_log.dart';
import 'create_event.dart';

class StartResult {
  const StartResult(this.event, this.segment);
  final JaxEvent event;
  final RunSegment segment;
}

class StartEvent {
  const StartEvent({
    required this.repository,
    required this.newId,
    required this.now,
  });
  final EventRepository repository;
  final IdGenerator newId;
  final Clock now;
  Future<StartResult> call(String id) async {
    final current = await repository.getEvent(id);
    if (current == null) throw const DomainFailure('事件不存在');
    if (current.status != EventStatus.pending) {
      throw const DomainFailure('只有未开始事件可以开始');
    }
    final timestamp = now().toUtc();
    final switched = await DescendantSwitchService(repository)
        .switchIfNeeded(current, timestamp, newId);
    if (switched != null) {
      return StartResult(switched.event, switched.segment);
    }
    final segment = RunSegment(
      id: newId(),
      eventId: id,
      startedAt: timestamp,
      createdAt: timestamp,
    );
    final running = current.copyWith(
      status: EventStatus.running,
      firstStartedAt: timestamp,
      updatedAt: timestamp,
    );
    await repository.startEvent(running, segment);
    SegmentLifecycleLog.open(
      reason: 'event_start',
      ownerType: 'event',
      ownerId: id,
      segmentId: segment.id,
      startedAt: timestamp,
    );
    return StartResult(running, segment);
  }
}
