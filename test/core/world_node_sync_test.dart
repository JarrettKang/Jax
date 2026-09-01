import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/sync/resolved_sync_plan.dart';
import 'package:jax/core/sync/sync_compare_engine.dart';
import 'package:jax/core/sync/sync_contract.dart';
import 'package:jax/core/sync/sync_plan_compiler.dart';

void main() {
  const compare = SyncCompareEngine();
  const compiler = SyncPlanCompiler();

  test('protocol 1 baseline normalizes deterministic WorldNodes', () {
    final old = _snapshot(
      [_event('legacy-a', '检查超算')],
      lists: [
        _eventList(['legacy-a']),
      ],
      protocol: 1,
    );
    final upgraded = SyncSnapshot.fromJson(
      (jsonDecode(old.toJsonString()) as Map).cast<String, Object?>(),
    );
    expect(upgraded.protocolVersion, syncProtocolVersion);
    expect(
      upgraded.records.where(
        (record) => record.kind == SyncEntityKind.legacyEventWorldNodeLink,
      ),
      isEmpty,
    );
    expect(
      upgraded.records
          .singleWhere((record) => record.kind == SyncEntityKind.event)
          .payload['sourcePlanItemSyncId'],
      isNull,
    );
    expect(
      upgraded.lists.where(
        (list) => list.kind == SyncListKind.eventSiblings,
      ),
      isEmpty,
    );
    final preview = compare.compare(
      baseline: upgraded,
      windows: upgraded,
      android: upgraded,
    );
    expect(preview.count(SyncComparisonKind.onlyWindows), 0);
    expect(preview.count(SyncComparisonKind.onlyAndroid), 0);
    expect(preview.manualConflicts, isEmpty);
  });

  test('WorldNode field, hierarchy, order, and tombstone use sync engine', () {
    const rootA = '11111111-1111-4111-8111-111111111111';
    const rootB = '22222222-2222-4222-8222-222222222222';
    const child = '33333333-3333-4333-8333-333333333333';
    final baseline = _snapshot(
      [_node(rootA, 'A'), _node(rootB, 'B'), _node(child, 'C', parent: rootA)],
      lists: [
        _worldList([rootA, rootB]),
        _worldList([child], parent: rootA),
      ],
    );

    final oneSide = compare.compare(
      baseline: baseline,
      windows: _replace(baseline, _node(rootA, 'A renamed')),
      android: baseline,
    );
    expect(
      oneSide.autoMergeable.single.windows?.kind,
      SyncEntityKind.worldNode,
    );

    final hierarchy = compare.compare(
      baseline: baseline,
      windows: _replace(baseline, _node(child, 'C', parent: rootB)),
      android: _replace(baseline, _node(child, 'C', parent: null)),
    );
    expect(
      hierarchy.manualConflicts.single.conflictType,
      SyncConflictType.hierarchy,
    );

    final order = compare.compare(
      baseline: baseline,
      windows: _withRootOrder(baseline, [rootB, rootA]),
      android: _withRootOrder(baseline, [rootA, rootB].reversed.toList()),
    );
    // Both sides selected the same final order above, so it is compatible.
    expect(order.listConflicts, isEmpty);
    final orderConflict = compare.compare(
      windows: _withRootOrder(baseline, [rootB, rootA]),
      android: _withRootOrder(baseline, [rootA, rootB]),
    );
    expect(orderConflict.listConflicts, hasLength(1));

    final deleted = _deletedNode(rootA);
    final deletion = compare.compare(
      baseline: baseline,
      windows: _replace(baseline, deleted),
      android: baseline,
    );
    expect(deletion.autoMergeable.single.windows?.isDeleted, isTrue);
  });

  test('WorldNode stale plan protection uses snapshot fingerprint', () {
    const nodeId = '11111111-1111-4111-8111-111111111111';
    final baseline = _snapshot(
      [_node(nodeId, 'Base')],
      lists: [
        _worldList([nodeId]),
      ],
    );
    final windows = _replace(baseline, _node(nodeId, 'Windows'));
    final preview = compare.compare(
      baseline: baseline,
      windows: windows,
      android: baseline,
    );
    expect(
      () => compiler.compile(
        resolved: ResolvedSyncPlan(preview: preview),
        windows: _replace(windows, _node(nodeId, 'Changed after Analyze')),
        android: baseline,
        baseline: baseline,
      ),
      throwsA(predicate((error) => '$error'.startsWith('STALE_SYNC_PLAN'))),
    );
  });
}

final _instant = DateTime.fromMillisecondsSinceEpoch(100, isUtc: true);

SyncSnapshot _snapshot(
  List<SyncRecord> records, {
  List<SyncList> lists = const [],
  int protocol = syncProtocolVersion,
}) => SyncSnapshot(
  protocolVersion: protocol,
  schemaVersion: protocol == syncProtocolVersion ? 16 : 14,
  exportedAtUtc: _instant,
  records: records,
  lists: lists,
);

SyncRecord _event(String id, String name) => _record(SyncEntityKind.event, id, {
  'name': name,
  'status': 'paused',
  'parentSyncId': null,
  'categorySyncId': null,
  'order': 0,
  'firstStartedAtUtc': null,
  'completedAtUtc': null,
});

SyncRecord _node(String id, String name, {String? parent}) =>
    _record(SyncEntityKind.worldNode, id, {
      'name': name,
      'status': 'inProgress',
      'parentWorldNodeSyncId': parent,
      'categorySyncId': null,
      'order': 0,
    });

SyncRecord _record(
  SyncEntityKind kind,
  String id,
  Map<String, Object?> payload,
) => SyncRecord(
  kind: kind,
  metadata: SyncMetadata(
    id: id,
    createdAtUtc: _instant,
    updatedAtUtc: _instant,
  ),
  payload: payload,
);

SyncRecord _deletedNode(String id) => SyncRecord(
  kind: SyncEntityKind.worldNode,
  metadata: SyncMetadata(
    id: id,
    createdAtUtc: _instant,
    updatedAtUtc: _instant,
    deletedAtUtc: _instant,
  ),
  payload: const {},
);

SyncList _eventList(List<String> ids) =>
    SyncList(kind: SyncListKind.eventSiblings, scopeId: 'root', itemIds: ids);

SyncList _worldList(List<String> ids, {String? parent}) => SyncList(
  kind: SyncListKind.worldNodeSiblings,
  scopeId: parent == null ? 'category:uncategorized' : 'parent:$parent',
  itemIds: ids,
);

SyncSnapshot _replace(SyncSnapshot source, SyncRecord replacement) =>
    _snapshot([
      for (final record in source.records)
        if (record.key != replacement.key) record,
      replacement,
    ], lists: source.lists);

SyncSnapshot _withRootOrder(SyncSnapshot source, List<String> ids) => _snapshot(
  source.records,
  lists: [
    for (final list in source.lists)
      if (list.key != 'worldNodeSiblings:category:uncategorized') list,
    _worldList(ids),
  ],
);
