import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/sync/resolved_sync_plan.dart';
import 'package:jax/core/sync/sync_compare_engine.dart';
import 'package:jax/core/sync/sync_contract.dart';
import 'package:jax/core/sync/sync_plan_compiler.dart';
import 'package:jax/core/sync/sync_snapshot_validator.dart';

void main() {
  const compare = SyncCompareEngine();
  const compiler = SyncPlanCompiler();
  const validator = SyncSnapshotValidator();

  test('protocol 2 baseline upgrades to current protocol with no invented Plans or reviews', () {
    final old = _snapshot([_node()], protocol: 2);
    final upgraded = SyncSnapshot.fromJson(
      (jsonDecode(old.toJsonString()) as Map).cast<String, Object?>(),
    );
    expect(upgraded.protocolVersion, syncProtocolVersion);
    expect(
      upgraded.records.where((r) => r.kind == SyncEntityKind.plan),
      isEmpty,
    );
    expect(
      upgraded.records.where((r) => r.kind == SyncEntityKind.planReviewNote),
      isEmpty,
    );
  });

  test('Plan and PlanItem one-side changes merge and stale plans reject', () {
    final baseline = _snapshot([_node()]);
    final current = _snapshot(
      [_node(), _plan(), _item('a', 'A', 'draft', 0)],
      lists: [
        _itemList(['a']),
      ],
    );
    final preview = compare.compare(
      baseline: baseline,
      windows: current,
      android: baseline,
    );
    expect(
      preview.autoMergeable.map((i) => i.windows?.kind),
      containsAll([SyncEntityKind.plan, SyncEntityKind.planItem]),
    );
    expect(
      () => compiler.compile(
        resolved: ResolvedSyncPlan(preview: preview),
        windows: _snapshot(
          [_node(), _plan(title: 'changed'), _item('a', 'A', 'draft', 0)],
          lists: [
            _itemList(['a']),
          ],
        ),
        android: baseline,
        baseline: baseline,
      ),
      throwsA(predicate((e) => '$e'.startsWith('STALE_SYNC_PLAN'))),
    );
  });

  test('status and content differences are manual conflicts', () {
    final base = _snapshot(
      [_node(), _plan(), _item('a', 'A', 'draft', 0)],
      lists: [
        _itemList(['a']),
      ],
    );
    final windows = _snapshot(
      [_node(), _plan(), _item('a', 'Windows', 'next', 0)],
      lists: [
        _itemList(['a']),
      ],
    );
    final android = _snapshot(
      [_node(), _plan(), _item('a', 'Android', 'draft', 0)],
      lists: [
        _itemList(['a']),
      ],
    );
    final preview = compare.compare(
      baseline: base,
      windows: windows,
      android: android,
    );
    expect(
      preview.manualConflicts.single.windows?.kind,
      SyncEntityKind.planItem,
    );
  });

  test(
    'deleted unexecuted Plan versus remote edit is delete/modify conflict',
    () {
      final baseline = _snapshot([_node(), _plan()]);
      final deletedPlan = SyncRecord(
        kind: SyncEntityKind.plan,
        metadata: SyncMetadata(
          id: 'plan',
          createdAtUtc: _time,
          updatedAtUtc: _time,
          deletedAtUtc: _time,
        ),
        payload: const {},
      );
      final preview = compare.compare(
        baseline: baseline,
        windows: _snapshot([_node(), deletedPlan]),
        android: _snapshot([_node(), _plan(title: 'Android edit')]),
      );
      expect(
        preview.manualConflicts.single.conflictType,
        SyncConflictType.deleteModify,
      );
    },
  );

  test('PlanItem full-list order conflicts by Plan scope', () {
    final records = [
      _node(),
      _plan(),
      _item('a', 'A', 'draft', 0),
      _item('b', 'B', 'next', 1),
      _item('c', 'C', 'draft', 2),
    ];
    final preview = compare.compare(
      windows: _snapshot(
        records,
        lists: [
          _itemList(['a', 'b', 'c']),
        ],
      ),
      android: _snapshot(
        records,
        lists: [
          _itemList(['b', 'a', 'c']),
        ],
      ),
    );
    expect(
      preview.listConflicts.single.key,
      '${SyncListKind.planItems.name}:plan',
    );
  });

  test('Planning invariants reject dangling and duplicate current plans', () {
    final dangling = _snapshot(
      [_item('a', 'A', 'draft', 0)],
      lists: [
        _itemList(['a']),
      ],
    );
    expect(validator.validate(dangling), contains('plan-item-plan:a'));

    final duplicate = _snapshot([_node(), _plan(id: 'p1'), _plan(id: 'p2')]);
    expect(
      validator.validate(duplicate),
      contains('multiple-current-plans:11111111-1111-4111-8111-111111111111'),
    );

    final missingEvent = _snapshot(
      [_node(), _plan(), _item('a', 'A', 'dispatched', 0)],
      lists: [
        _itemList(['a']),
      ],
    );
    expect(
      validator.validate(missingEvent),
      contains('executed-plan-item-without-event:a'),
    );
  });

  test('concurrent dispatch of one PlanItem cannot silently merge', () {
    final common = [_node(), _plan(), _item('a', 'A', 'dispatched', 0)];
    final windows = _snapshot(
      [...common, _plannedEvent('windows-event', 'a')],
      lists: [
        _itemList(['a']),
      ],
    );
    final android = _snapshot(
      [...common, _plannedEvent('android-event', 'a')],
      lists: [
        _itemList(['a']),
      ],
    );
    final preview = compare.compare(windows: windows, android: android);

    expect(
      () => compiler.compile(
        resolved: ResolvedSyncPlan(preview: preview),
        windows: windows,
        android: android,
      ),
      throwsA(
        predicate(
          (error) =>
              '$error'.startsWith('PLAN_INVALID') &&
              '$error'.contains('duplicate-event-plan-item:a'),
        ),
      ),
    );
  });

  test(
    'PlanReviewNote create, edit, delete, and readiness use three-way sync',
    () {
      const noteId = '22222222-2222-4222-8222-222222222222';
      final baseline = _snapshot([_node(), _plan(), _review(noteId, 'base')]);
      final windows = _snapshot([_node(), _plan(), _review(noteId, 'windows')]);
      final android = _snapshot([_node(), _plan(), _review(noteId, 'android')]);
      final conflict = compare.compare(
        baseline: baseline,
        windows: windows,
        android: android,
      );
      expect(
        conflict.manualConflicts.single.windows?.kind,
        SyncEntityKind.planReviewNote,
      );
      expect(
        conflict.manualConflicts.single.changedFields.single.field,
        'content',
      );

      final created = _snapshot([_node(), _plan(), _review(noteId, 'new')]);
      final empty = _snapshot([_node(), _plan()]);
      expect(
        compare
            .compare(windows: created, android: empty)
            .autoMergeable
            .single
            .windows
            ?.kind,
        SyncEntityKind.planReviewNote,
      );

      final deleted = SyncRecord(
        kind: SyncEntityKind.planReviewNote,
        metadata: SyncMetadata(
          id: noteId,
          createdAtUtc: _time,
          updatedAtUtc: _time,
          deletedAtUtc: _time,
        ),
        payload: const {},
      );
      expect(
        compare
            .compare(
              baseline: baseline,
              windows: _snapshot([_node(), _plan(), deleted]),
              android: android,
            )
            .manualConflicts
            .single
            .conflictType,
        SyncConflictType.deleteModify,
      );

      expect(
        validator.validate(_snapshot([_review(noteId, 'valid')])),
        contains('plan-review-note-plan:$noteId'),
      );
      expect(
        validator.validate(
          _snapshot([_node(), _plan(), _review(noteId, '  ')]),
        ),
        contains('plan-review-note-content:$noteId'),
      );
    },
  );
}

final _time = DateTime.fromMillisecondsSinceEpoch(100, isUtc: true);

SyncSnapshot _snapshot(
  List<SyncRecord> records, {
  List<SyncList> lists = const [],
  int protocol = syncProtocolVersion,
}) => SyncSnapshot(
  protocolVersion: protocol,
  schemaVersion: 17,
  exportedAtUtc: _time,
  records: records,
  lists: lists,
);

SyncRecord _record(
  SyncEntityKind kind,
  String id,
  Map<String, Object?> payload,
) => SyncRecord(
  kind: kind,
  metadata: SyncMetadata(id: id, createdAtUtc: _time, updatedAtUtc: _time),
  payload: payload,
);

SyncRecord _node() =>
    _record(SyncEntityKind.worldNode, '11111111-1111-4111-8111-111111111111', {
      'name': 'Jax',
      'status': 'inProgress',
      'parentWorldNodeSyncId': null,
      'categorySyncId': null,
      'order': 0,
    });

SyncRecord _plan({String id = 'plan', String? title}) =>
    _record(SyncEntityKind.plan, id, {
      'worldNodeSyncId': '11111111-1111-4111-8111-111111111111',
      'title': title,
      'status': 'focused',
      'roundNumber': id == 'p2' ? 2 : 1,
      'endedAtUtc': null,
    });

SyncRecord _item(String id, String title, String status, int order) =>
    _record(SyncEntityKind.planItem, id, {
      'planSyncId': 'plan',
      'title': title,
      'note': null,
      'status': status,
      'order': order,
    });

SyncRecord _plannedEvent(String id, String sourceId) =>
    _record(SyncEntityKind.event, id, {
      'name': 'A',
      'status': 'pending',
      'sourcePlanItemSyncId': sourceId,
      'categorySyncId': null,
      'firstStartedAtUtc': null,
      'completedAtUtc': null,
    });

SyncRecord _review(String id, String content) => _record(
  SyncEntityKind.planReviewNote,
  id,
  {'planSyncId': 'plan', 'content': content},
);

SyncList _itemList(List<String> ids) =>
    SyncList(kind: SyncListKind.planItems, scopeId: 'plan', itemIds: ids);
