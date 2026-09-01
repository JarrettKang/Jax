import '../entities/event_status.dart';
import '../entities/jax_event.dart';
import '../entities/run_segment.dart';
import '../errors/domain_failure.dart';
import '../repositories/event_repository.dart';
import '../use_cases/create_event.dart';
import 'segment_lifecycle_log.dart';

class RunningEventSwitchResult {
  const RunningEventSwitchResult(this.event, this.segment);

  final JaxEvent event;
  final RunSegment segment;
}

/// Atomically pauses the current Event and starts an unrelated flat Event.
class RunningEventSwitchService {
  const RunningEventSwitchService(this.repository);

  final EventRepository repository;

  Future<RunningEventSwitchResult?> switchIfNeeded(
    JaxEvent target,
    DateTime timestamp,
    IdGenerator newId,
  ) async {
    final running = (await repository.getIncompleteEvents())
        .where((event) => event.status == EventStatus.running)
        .firstOrNull;
    if (running == null || running.id == target.id) return null;

    final open = (await repository.getRunSegments(running.id))
        .where((segment) => segment.endedAt == null)
        .firstOrNull;
    if (open == null) throw const DomainFailure('执行计时数据不完整');

    final pausedRunning = running.copyWith(
      status: EventStatus.paused,
      updatedAt: timestamp,
    );
    final runningTarget = target.copyWith(
      status: EventStatus.running,
      firstStartedAt: target.firstStartedAt ?? timestamp,
      updatedAt: timestamp,
    );
    final newSegment = RunSegment(
      id: newId(),
      eventId: target.id,
      startedAt: timestamp,
      createdAt: timestamp,
    );
    await repository.switchRunningEvent(
      pausedRunning: pausedRunning,
      closedSegment: open.copyWith(endedAt: timestamp),
      runningTarget: runningTarget,
      newSegment: newSegment,
    );
    SegmentLifecycleLog.close(
      reason: 'event_switch',
      ownerType: 'event',
      ownerId: running.id,
      segmentId: open.id,
      startedAt: open.startedAt,
      endedAt: timestamp,
    );
    SegmentLifecycleLog.open(
      reason: 'event_switch',
      ownerType: 'event',
      ownerId: target.id,
      segmentId: newSegment.id,
      startedAt: timestamp,
    );
    return RunningEventSwitchResult(runningTarget, newSegment);
  }
}
