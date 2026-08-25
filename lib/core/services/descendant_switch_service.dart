import '../entities/event_status.dart';
import '../entities/jax_event.dart';
import '../entities/run_segment.dart';
import '../errors/domain_failure.dart';
import '../repositories/event_repository.dart';
import '../use_cases/create_event.dart';

class DescendantSwitchResult {
  const DescendantSwitchResult(this.event, this.segment);

  final JaxEvent event;
  final RunSegment segment;
}

class DescendantSwitchService {
  const DescendantSwitchService(this.repository);
  final EventRepository repository;

  Future<DescendantSwitchResult?> switchIfNeeded(
    JaxEvent target,
    DateTime timestamp,
    IdGenerator newId,
  ) async {
    final running = (await repository.getIncompleteEvents())
        .where((event) => event.status == EventStatus.running)
        .firstOrNull;
    if (running == null || running.id == target.id) return null;
    final ancestors = <JaxEvent>[];
    var parent = await repository.getParent(target.id);
    while (parent != null && parent.id != running.id) {
      ancestors.add(parent);
      parent = await repository.getParent(parent.id);
    }
    if (parent == null) throw const DomainFailure('请先暂停或完成当前事件');
    parent = await repository.getParent(running.id);
    while (parent != null) {
      ancestors.add(parent);
      parent = await repository.getParent(parent.id);
    }
    final open = (await repository.getRunSegments(running.id))
        .where((segment) => segment.endedAt == null)
        .firstOrNull;
    if (open == null) throw const DomainFailure('执行计时数据不完整');
    final pausedRunning = running.copyWith(
      status: EventStatus.paused,
      updatedAt: timestamp,
    );
    final pausedAncestors = ancestors
        .where((event) => event.status != EventStatus.completed)
        .map(
          (event) =>
              event.copyWith(status: EventStatus.paused, updatedAt: timestamp),
        )
        .toList(growable: false);
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
      pausedAncestors: pausedAncestors,
    );
    return DescendantSwitchResult(runningTarget, newSegment);
  }
}
