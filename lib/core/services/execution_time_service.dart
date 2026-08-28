import '../entities/execution_time_segment.dart';
import '../errors/domain_failure.dart';
import '../repositories/execution_time_repository.dart';
import '../use_cases/create_event.dart';

class ExecutionTimeService {
  const ExecutionTimeService({
    required this.repository,
    required this.newId,
    required this.now,
  });
  final ExecutionTimeRepository repository;
  final IdGenerator newId;
  final Clock now;

  Future<List<ExecutionTimeSegment>> segmentsFor(
    ExecutionOwnerType type,
    String ownerId,
  ) async =>
      (await repository.getAllExecutionTimeSegments())
          .where((s) => s.ownerType == type && s.ownerId == ownerId)
          .toList()
        ..sort((a, b) => a.startedAt.compareTo(b.startedAt));

  Future<void> add({
    required ExecutionOwnerType type,
    required String ownerId,
    required String ownerName,
    required DateTime start,
    required DateTime end,
  }) async {
    await _requireEditable(type, ownerId);
    await _validate(start, end);
    final timestamp = now().toUtc();
    await repository.insertExecutionTimeSegment(
      ExecutionTimeSegment(
        id: newId(),
        ownerType: type,
        ownerId: ownerId,
        ownerName: ownerName,
        startedAt: start.toUtc(),
        endedAt: end.toUtc(),
        createdAt: timestamp,
      ),
    );
  }

  Future<void> edit(
    ExecutionTimeSegment original,
    DateTime start,
    DateTime end,
  ) async {
    await _requireEditable(original.ownerType, original.ownerId);
    await _validate(start, end, ignoredId: original.id);
    await repository.updateExecutionTimeSegment(
      ExecutionTimeSegment(
        id: original.id,
        ownerType: original.ownerType,
        ownerId: original.ownerId,
        ownerName: original.ownerName,
        startedAt: start.toUtc(),
        endedAt: end.toUtc(),
        createdAt: original.createdAt,
      ),
    );
  }

  Future<void> delete(ExecutionTimeSegment segment) async {
    await _requireEditable(segment.ownerType, segment.ownerId);
    await repository.deleteExecutionTimeSegment(segment.ownerType, segment.id);
  }

  Future<void> finishRunning(
    ExecutionTimeSegment open,
    DateTime end, {
    required bool complete,
  }) async {
    if (open.endedAt != null) throw const DomainFailure('该执行记录已经结束');
    if (complete &&
        !await repository.canCompleteExecutionOwner(
          open.ownerType,
          open.ownerId,
        )) {
      throw const DomainFailure('仍存在未完成的下层事件');
    }
    await _validate(open.startedAt, end, ignoredId: open.id);
    await repository.finishRunningAt(
      ownerType: open.ownerType,
      ownerId: open.ownerId,
      segmentId: open.id,
      endedAt: end.toUtc(),
      complete: complete,
    );
  }

  Future<void> _requireEditable(ExecutionOwnerType type, String ownerId) async {
    final owners = await repository.getEditableExecutionTimeOwners();
    if (!owners.any((owner) => owner.type == type && owner.id == ownerId)) {
      throw const DomainFailure('只有已暂停或已完成的记录可以编辑执行时间');
    }
  }

  Future<void> _validate(
    DateTime start,
    DateTime end, {
    String? ignoredId,
  }) async {
    final s = start.toUtc(), e = end.toUtc(), current = now().toUtc();
    if (!s.isBefore(e)) throw const DomainFailure('结束时间必须晚于开始时间');
    if (s.isAfter(current) || e.isAfter(current)) {
      throw const DomainFailure('执行时间不能晚于当前时间');
    }
    for (final other in await repository.getAllExecutionTimeSegments()) {
      if (other.id == ignoredId) continue;
      final otherEnd = other.endedAt ?? current;
      if (s.isBefore(otherEnd) && other.startedAt.isBefore(e)) {
        final localStart = other.startedAt.toLocal();
        final localEnd = otherEnd.toLocal();
        String two(int v) => v.toString().padLeft(2, '0');
        throw DomainFailure(
          '该时间段与“${other.ownerName}” '
          '${two(localStart.hour)}:${two(localStart.minute)}–'
          '${two(localEnd.hour)}:${two(localEnd.minute)} 重叠',
        );
      }
    }
  }
}
