import 'dart:developer' as developer;

class SegmentLifecycleLog {
  const SegmentLifecycleLog._();

  static void open({
    required String reason,
    required String ownerType,
    required String ownerId,
    String? executionId,
    required String segmentId,
    required DateTime startedAt,
  }) {
    assert(() {
      developer.log(
        'action=SEGMENT_OPEN reason=$reason ownerType=$ownerType '
        'ownerId=$ownerId executionId=${executionId ?? '-'} '
        'segmentId=$segmentId startedAt=${startedAt.toUtc().toIso8601String()}',
        name: 'jax.segment',
      );
      return true;
    }());
  }

  static void close({
    required String reason,
    required String ownerType,
    required String ownerId,
    String? executionId,
    required String segmentId,
    required DateTime startedAt,
    required DateTime endedAt,
  }) {
    assert(() {
      developer.log(
        'action=SEGMENT_CLOSE reason=$reason ownerType=$ownerType '
        'ownerId=$ownerId executionId=${executionId ?? '-'} '
        'segmentId=$segmentId startedAt=${startedAt.toUtc().toIso8601String()} '
        'endedAt=${endedAt.toUtc().toIso8601String()} '
        'durationMs=${endedAt.difference(startedAt).inMilliseconds}',
        name: 'jax.segment',
      );
      return true;
    }());
  }
}
