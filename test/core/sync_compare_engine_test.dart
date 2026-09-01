import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/sync/sync_compare_engine.dart';
import 'package:jax/core/sync/sync_contract.dart';

void main() {
  const engine = SyncCompareEngine();

  test('no baseline treats divergent shared identity as unknown history', () {
    final plan = engine.compare(
      windows: snapshot([event('a', name: 'PC')]),
      android: snapshot([event('a', name: 'Phone')]),
    );
    expect(plan.manualConflicts, hasLength(1));
    expect(plan.manualConflicts.single.conflictType, SyncConflictType.field);
    expect(plan.manualConflicts.single.unknownHistory, isTrue);
    expect(
      plan.manualConflicts.single.detail,
      contains('no successful-sync baseline'),
    );
    expect(plan.manualConflicts.single.changedFields.single.field, 'name');
  });

  test('three-way compare identifies one-side and compatible changes', () {
    final base = snapshot([event('a', name: 'Base'), event('b', name: 'Base')]);
    final plan = engine.compare(
      baseline: base,
      windows: snapshot([
        event('a', name: 'PC'),
        event('b', name: 'Same final'),
      ]),
      android: snapshot([
        event('a', name: 'Base'),
        event('b', name: 'Same final'),
      ]),
    );
    expect(plan.autoMergeable, hasLength(1));
    expect(plan.same, hasLength(1));
  });

  test('delete versus modify is an explicit conflict', () {
    final plan = engine.compare(
      windows: snapshot([deleted(SyncEntityKind.event, 'a')]),
      android: snapshot([event('a', name: 'Changed')]),
    );
    expect(
      plan.manualConflicts.single.conflictType,
      SyncConflictType.deleteModify,
    );
    expect(plan.manualConflicts.single.detail, contains('电脑：已删除'));
  });

  test('relation and segment field conflicts expose changed fields', () {
    final relation = engine.compare(
      windows: snapshot([event('child', sourcePlanItem: 'a')]),
      android: snapshot([event('child', sourcePlanItem: 'b')]),
    );
    expect(
      relation.manualConflicts.single.conflictType,
      SyncConflictType.field,
    );
    expect(
      relation.manualConflicts.single.changedFields.single.field,
      'sourcePlanItemSyncId',
    );

    final segmentPlan = engine.compare(
      windows: snapshot([segment('s', end: 20)]),
      android: snapshot([segment('s', end: 30)]),
    );
    expect(
      segmentPlan.manualConflicts.single.changedFields.single.field,
      'endedAtUtc',
    );
  });

  test('concurrent running startedAt corrections remain a field conflict', () {
    final baseline = snapshot([segment('s', start: 20)]);
    final plan = engine.compare(
      baseline: baseline,
      windows: snapshot([segment('s', start: 10)]),
      android: snapshot([segment('s', start: 15)]),
    );

    expect(plan.manualConflicts, hasLength(1));
    expect(plan.manualConflicts.single.conflictType, SyncConflictType.field);
    expect(
      plan.manualConflicts.single.changedFields.single.field,
      'startedAtUtc',
    );
  });

  test('different shared order is a list conflict, additions are not', () {
    final reordered = engine.compare(
      windows: snapshot(
        const [],
        lists: [
          list(['a', 'b', 'c']),
        ],
      ),
      android: snapshot(
        const [],
        lists: [
          list(['b', 'a', 'c']),
        ],
      ),
    );
    expect(reordered.listConflicts, hasLength(1));
    final additions = engine.compare(
      windows: snapshot(
        const [],
        lists: [
          list(['a', 'b']),
        ],
      ),
      android: snapshot(
        const [],
        lists: [
          list(['a', 'b', 'c']),
        ],
      ),
    );
    expect(additions.listConflicts, isEmpty);
    final integerOnly = engine.compare(
      windows: snapshot([
        record(SyncEntityKind.worldNode, 'a', {'name': 'A', 'order': 0}),
      ]),
      android: snapshot([
        record(SyncEntityKind.worldNode, 'a', {'name': 'A', 'order': 9}),
      ]),
    );
    expect(integerOnly.manualConflicts, isEmpty);
    expect(integerOnly.same, hasLength(1));
  });

  test(
    'different running objects and open segments are invariant conflicts',
    () {
      final plan = engine.compare(
        windows: snapshot([
          event('a', status: 'running'),
          segment('sa', owner: 'a'),
        ]),
        android: snapshot([
          routineExecution('b', status: 'running'),
          routineSegment('sb', owner: 'b'),
        ]),
      );
      expect(
        plan.invariantConflicts.map((item) => item.type),
        containsAll([
          SyncConflictType.globalOneRunning,
          SyncConflictType.openSegment,
          SyncConflictType.segmentOverlap,
        ]),
      );
    },
  );

  test('running versus paused history is an invariant conflict', () {
    final plan = engine.compare(
      windows: snapshot([
        event('a', status: 'running'),
        segment('s', owner: 'a'),
      ]),
      android: snapshot([
        event('a', status: 'paused'),
        segment('s', owner: 'a', end: 20),
      ]),
    );
    expect(
      plan.invariantConflicts,
      anyElement(
        predicate<SyncInvariantConflict>((item) => item.title == '状态与执行历史冲突'),
      ),
    );
  });

  test('protocol mismatch stops comparison', () {
    expect(
      () => engine.compare(
        windows: snapshot(const []),
        android: snapshot(const [], protocol: syncProtocolVersion + 1),
      ),
      throwsStateError,
    );
  });
}

final instant = DateTime.fromMillisecondsSinceEpoch(1, isUtc: true);

SyncSnapshot snapshot(
  List<SyncRecord> records, {
  List<SyncList> lists = const [],
  int protocol = syncProtocolVersion,
}) => SyncSnapshot(
  protocolVersion: protocol,
  schemaVersion: 16,
  exportedAtUtc: instant,
  records: records,
  lists: lists,
);

SyncRecord event(
  String id, {
  String name = 'Event',
  String status = 'paused',
  String? sourcePlanItem,
}) => record(SyncEntityKind.event, id, {
  'name': name,
  'status': status,
  'sourcePlanItemSyncId': sourcePlanItem,
  'categorySyncId': null,
  'firstStartedAtUtc': null,
  'completedAtUtc': null,
});
SyncRecord routineExecution(String id, {required String status}) => record(
  SyncEntityKind.routineExecution,
  id,
  {'routineSyncId': 'routine', 'status': status},
);
SyncRecord segment(
  String id, {
  String owner = 'event',
  int start = 10,
  int? end,
}) => record(SyncEntityKind.eventRunSegment, id, {
  'eventSyncId': owner,
  'startedAtUtc': start,
  'endedAtUtc': end,
});
SyncRecord routineSegment(String id, {required String owner}) => record(
  SyncEntityKind.routineRunSegment,
  id,
  {'routineExecutionSyncId': owner, 'startedAtUtc': 10, 'endedAtUtc': null},
);
SyncRecord record(
  SyncEntityKind kind,
  String id,
  Map<String, Object?> payload,
) => SyncRecord(
  kind: kind,
  metadata: SyncMetadata(id: id, createdAtUtc: instant, updatedAtUtc: instant),
  payload: payload,
);
SyncRecord deleted(SyncEntityKind kind, String id) => SyncRecord(
  kind: kind,
  metadata: SyncMetadata(
    id: id,
    createdAtUtc: instant,
    updatedAtUtc: instant,
    deletedAtUtc: instant,
  ),
  payload: const {},
);
SyncList list(List<String> ids) =>
    SyncList(kind: SyncListKind.eventCategories, scopeId: 'all', itemIds: ids);
