import '../entities/completed_record.dart';
import '../entities/event_status.dart';
import '../errors/domain_failure.dart';
import '../repositories/event_repository.dart';
import '../services/segment_lifecycle_log.dart';
import 'create_event.dart';

class CompleteEvent {
  const CompleteEvent({required this.repository, required this.now});
  final EventRepository repository;
  final Clock now;
  Future<CompletedRecord> call(String id, {DateTime? endTime}) async {
    final current = await repository.getEvent(id);
    if (current == null) throw const DomainFailure('事件不存在');
    if (current.status != EventStatus.running &&
        current.status != EventStatus.waiting) {
      throw const DomainFailure('只有正在进行或等待中的事件可以完成');
    }
    if (current.status == EventStatus.completed) {
      throw const DomainFailure('事件已经完成');
    }
    final timestamp = now().toUtc();
    if (current.status != EventStatus.running) {
      final completed = current.copyWith(
        status: EventStatus.completed,
        completedAt: timestamp,
        updatedAt: timestamp,
      );
      await repository.updateEvent(completed);
      return CompletedRecord(event: completed, duration: Duration.zero);
    }
    final segments = await repository.getRunSegments(id);
    final open = segments
        .where((segment) => segment.endedAt == null)
        .firstOrNull;
    if (open == null) throw const DomainFailure('执行计时数据不完整');
    final correctedEnd = endTime?.toUtc() ?? timestamp;
    if (endTime != null && !correctedEnd.isAfter(open.startedAt)) {
      throw const DomainFailure('结束时间必须晚于开始时间');
    }
    if (endTime != null && correctedEnd.isAfter(timestamp)) {
      throw const DomainFailure('结束时间不能晚于当前时间');
    }
    final completed = current.copyWith(
      status: EventStatus.completed,
      completedAt: correctedEnd,
      updatedAt: timestamp,
    );
    final closed = open.copyWith(endedAt: correctedEnd);
    await repository.pauseEvent(completed, closed);
    SegmentLifecycleLog.close(
      reason: 'event_complete',
      ownerType: 'event',
      ownerId: id,
      segmentId: open.id,
      startedAt: open.startedAt,
      endedAt: correctedEnd,
    );
    final duration = segments.fold(
      Duration.zero,
      (total, segment) =>
          total +
          (segment.id == open.id ? closed : segment).durationAt(timestamp),
    );
    return CompletedRecord(event: completed, duration: duration);
  }
}
