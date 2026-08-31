import 'sync_contract.dart';
import '../entities/world_node_ids.dart';

class SyncSnapshotValidator {
  const SyncSnapshotValidator();

  List<String> validate(SyncSnapshot snapshot) {
    final issues = <String>[];
    final live = {
      for (final record in snapshot.records.where((r) => !r.isDeleted))
        record.key: record,
    };
    bool has(SyncEntityKind kind, Object? id) =>
        id == null || live.containsKey('${kind.name}:$id');
    for (final record in live.values) {
      final p = record.payload;
      switch (record.kind) {
        case SyncEntityKind.event:
          if (!{
            'pending',
            'running',
            'paused',
            'waiting',
            'completed',
          }.contains(p['status'])) {
            issues.add('event-status:${record.metadata.id}');
          }
          if (!has(SyncEntityKind.event, p['parentSyncId'])) {
            issues.add('event-parent:${record.metadata.id}');
          }
          if (!has(SyncEntityKind.eventCategory, p['categorySyncId'])) {
            issues.add('event-category:${record.metadata.id}');
          }
          if (p['parentSyncId'] != null && p['categorySyncId'] != null) {
            issues.add('child-direct-category:${record.metadata.id}');
          }
        case SyncEntityKind.eventRunSegment:
          if (!has(SyncEntityKind.event, p['eventSyncId'])) {
            issues.add('segment-owner:${record.metadata.id}');
          }
          _segmentRange(record, issues);
        case SyncEntityKind.routine:
          if (!has(
            SyncEntityKind.routineCategory,
            p['routineCategorySyncId'],
          )) {
            issues.add('routine-category:${record.metadata.id}');
          }
          if (!{'scheduled', 'onDemand'}.contains(p['routineType'])) {
            issues.add('routine-type:${record.metadata.id}');
          }
          if (!{
            'daily',
            'weekdays',
            'weekends',
            'selectedWeekdays',
          }.contains(p['recurrenceType'])) {
            issues.add('routine-recurrence:${record.metadata.id}');
          }
        case SyncEntityKind.routineExecution:
          if (!has(SyncEntityKind.routine, p['routineSyncId'])) {
            issues.add('execution-owner:${record.metadata.id}');
          }
          if (!{'running', 'paused', 'completed'}.contains(p['status'])) {
            issues.add('execution-status:${record.metadata.id}');
          }
        case SyncEntityKind.routineRunSegment:
          if (!has(
            SyncEntityKind.routineExecution,
            p['routineExecutionSyncId'],
          )) {
            issues.add('routine-segment-owner:${record.metadata.id}');
          }
          _segmentRange(record, issues);
        case SyncEntityKind.eventDayPlan:
          if (!has(SyncEntityKind.event, p['eventSyncId'])) {
            issues.add('today-owner:${record.metadata.id}');
          }
        case SyncEntityKind.worldNode:
          if (!WorldNodeIds.isValid(record.metadata.id)) {
            issues.add('world-node-invalid-uuid:${record.metadata.id}');
          }
          if (!{'inProgress', 'completed'}.contains(p['status'])) {
            issues.add('world-node-status:${record.metadata.id}');
          }
          if (!has(SyncEntityKind.worldNode, p['parentWorldNodeSyncId'])) {
            issues.add('world-node-parent:${record.metadata.id}');
          }
          if (!has(SyncEntityKind.eventCategory, p['categorySyncId'])) {
            issues.add('world-node-category:${record.metadata.id}');
          }
          if (p['parentWorldNodeSyncId'] != null &&
              p['categorySyncId'] != null) {
            issues.add(
              'world-node-child-direct-category:${record.metadata.id}',
            );
          }
        case SyncEntityKind.legacyEventWorldNodeLink:
          if (!has(SyncEntityKind.event, p['legacyEventSyncId'])) {
            issues.add('legacy-link-event:${record.metadata.id}');
          }
          if (!has(SyncEntityKind.worldNode, p['worldNodeSyncId'])) {
            issues.add('legacy-link-world-node:${record.metadata.id}');
          }
          final legacyId = p['legacyEventSyncId'];
          if (legacyId is! String ||
              record.metadata.id != legacyId ||
              p['worldNodeSyncId'] != WorldNodeIds.fromLegacyEvent(legacyId)) {
            issues.add('legacy-link-deterministic:${record.metadata.id}');
          }
        case SyncEntityKind.eventCategory || SyncEntityKind.routineCategory:
          break;
      }
    }
    _eventRules(live, issues);
    _routineRules(live, issues);
    _executionRules(live, issues);
    _worldNodeRules(live, issues);
    _listRules(snapshot, live, issues);
    return issues;
  }

  void _worldNodeRules(Map<String, SyncRecord> live, List<String> issues) {
    final nodes = {
      for (final record in live.values.where(
        (record) => record.kind == SyncEntityKind.worldNode,
      ))
        record.metadata.id: record,
    };
    for (final node in nodes.values) {
      final seen = <String>{node.metadata.id};
      var parent = node.payload['parentWorldNodeSyncId'] as String?;
      while (parent != null) {
        if (!seen.add(parent)) {
          issues.add('world-node-cycle:${node.metadata.id}');
          break;
        }
        parent = nodes[parent]?.payload['parentWorldNodeSyncId'] as String?;
      }
    }
    final links = live.values.where(
      (record) => record.kind == SyncEntityKind.legacyEventWorldNodeLink,
    );
    final eventIds = <String>{};
    final nodeIds = <String>{};
    for (final link in links) {
      final eventId = link.payload['legacyEventSyncId'];
      final nodeId = link.payload['worldNodeSyncId'];
      if (eventId is String && !eventIds.add(eventId)) {
        issues.add('duplicate-legacy-event-link:$eventId');
      }
      if (nodeId is String && !nodeIds.add(nodeId)) {
        issues.add('duplicate-world-node-link:$nodeId');
      }
    }
  }

  void _segmentRange(SyncRecord record, List<String> issues) {
    final start = record.payload['startedAtUtc'] as int?;
    final end = record.payload['endedAtUtc'] as int?;
    if (start == null || end != null && start >= end) {
      issues.add('segment-range:${record.metadata.id}');
    }
  }

  void _eventRules(Map<String, SyncRecord> live, List<String> issues) {
    final events = {
      for (final r in live.values.where((r) => r.kind == SyncEntityKind.event))
        r.metadata.id: r,
    };
    for (final event in events.values) {
      final seen = <String>{event.metadata.id};
      var parent = event.payload['parentSyncId'] as String?;
      while (parent != null) {
        if (!seen.add(parent)) {
          issues.add('event-cycle:${event.metadata.id}');
          break;
        }
        parent = events[parent]?.payload['parentSyncId'] as String?;
      }
      if (event.payload['status'] == 'completed') {
        final unfinished = events.values.any(
          (candidate) =>
              candidate.payload['parentSyncId'] == event.metadata.id &&
              candidate.payload['status'] != 'completed',
        );
        if (unfinished) issues.add('completed-parent:${event.metadata.id}');
      }
    }
  }

  void _routineRules(Map<String, SyncRecord> live, List<String> issues) {
    final routines = {
      for (final r in live.values.where(
        (r) => r.kind == SyncEntityKind.routine,
      ))
        r.metadata.id: r,
    };
    final executions = live.values.where(
      (r) =>
          r.kind == SyncEntityKind.routineExecution &&
          r.payload['status'] != 'completed',
    );
    final counts = <String, int>{};
    for (final execution in executions) {
      final id = execution.payload['routineSyncId'] as String;
      if (routines[id]?.payload['routineType'] == 'onDemand') {
        counts[id] = (counts[id] ?? 0) + 1;
      }
    }
    for (final entry in counts.entries.where((e) => e.value > 1)) {
      issues.add('multiple-unfinished-on-demand:${entry.key}');
    }
  }

  void _executionRules(Map<String, SyncRecord> live, List<String> issues) {
    final runnable = live.values
        .where(
          (r) =>
              r.kind == SyncEntityKind.event ||
              r.kind == SyncEntityKind.routineExecution,
        )
        .toList();
    final segments = live.values
        .where(
          (r) =>
              r.kind == SyncEntityKind.eventRunSegment ||
              r.kind == SyncEntityKind.routineRunSegment,
        )
        .toList();
    if (runnable.where((r) => r.payload['status'] == 'running').length > 1) {
      issues.add('global-one-running');
    }
    final open = segments
        .where((r) => r.payload['endedAtUtc'] == null)
        .toList();
    if (open.length > 1) issues.add('global-one-open-segment');
    for (final entity in runnable) {
      final hasOpen = open.any(
        (s) =>
            s.payload['eventSyncId'] == entity.metadata.id ||
            s.payload['routineExecutionSyncId'] == entity.metadata.id,
      );
      if ((entity.payload['status'] == 'running') != hasOpen) {
        issues.add('status-open-segment:${entity.metadata.id}');
      }
    }
    for (var i = 0; i < segments.length; i++) {
      for (var j = i + 1; j < segments.length; j++) {
        final a = segments[i], b = segments[j];
        final as = a.payload['startedAtUtc'] as int,
            bs = b.payload['startedAtUtc'] as int;
        final ae = a.payload['endedAtUtc'] as int? ?? 0x7fffffffffffffff;
        final be = b.payload['endedAtUtc'] as int? ?? 0x7fffffffffffffff;
        if (as < be && bs < ae) {
          issues.add('segment-overlap:${a.metadata.id}:${b.metadata.id}');
        }
      }
    }
  }

  void _listRules(
    SyncSnapshot snapshot,
    Map<String, SyncRecord> live,
    List<String> issues,
  ) {
    final keys = <String>{};
    final actual = <String, Set<String>>{};
    for (final list in snapshot.lists) {
      if (!keys.add(list.key)) issues.add('duplicate-list:${list.key}');
      if (list.itemIds.toSet().length != list.itemIds.length) {
        issues.add('duplicate-list-item:${list.key}');
      }
      actual[list.key] = list.itemIds.toSet();
      for (final id in list.itemIds) {
        final kind = switch (list.kind) {
          SyncListKind.eventCategories => SyncEntityKind.eventCategory,
          SyncListKind.eventSiblings => SyncEntityKind.event,
          SyncListKind.routineCategories => SyncEntityKind.routineCategory,
          SyncListKind.routines => SyncEntityKind.routine,
          SyncListKind.eventDayPlans => SyncEntityKind.event,
          SyncListKind.worldNodeSiblings => SyncEntityKind.worldNode,
        };
        if (!live.containsKey('${kind.name}:$id')) {
          issues.add('list-owner:${list.key}:$id');
        }
        if (list.kind == SyncListKind.eventSiblings &&
            (live['${SyncEntityKind.event.name}:$id']
                        ?.payload['parentSyncId'] ??
                    'root') !=
                list.scopeId) {
          issues.add('list-scope:${list.key}:$id');
        }
        if (list.kind == SyncListKind.routines &&
            (live['${SyncEntityKind.routine.name}:$id']
                        ?.payload['routineCategorySyncId'] ??
                    'uncategorized') !=
                list.scopeId) {
          issues.add('list-scope:${list.key}:$id');
        }
        if (list.kind == SyncListKind.eventDayPlans &&
            !live.values.any(
              (record) =>
                  record.kind == SyncEntityKind.eventDayPlan &&
                  record.payload['eventSyncId'] == id &&
                  record.payload['jaxDay'] == list.scopeId,
            )) {
          issues.add('list-scope:${list.key}:$id');
        }
        if (list.kind == SyncListKind.worldNodeSiblings) {
          final node = live['${SyncEntityKind.worldNode.name}:$id'];
          final expectedScope = node?.payload['parentWorldNodeSyncId'] == null
              ? 'category:${node?.payload['categorySyncId'] ?? 'uncategorized'}'
              : 'parent:${node!.payload['parentWorldNodeSyncId']}';
          if (expectedScope != list.scopeId) {
            issues.add('list-scope:${list.key}:$id');
          }
        }
      }
    }

    final expected = <String, Set<String>>{};
    void addExpected(String key, String id) =>
        expected.putIfAbsent(key, () => <String>{}).add(id);
    for (final record in live.values) {
      final id = record.metadata.id;
      switch (record.kind) {
        case SyncEntityKind.eventCategory:
          addExpected('${SyncListKind.eventCategories.name}:all', id);
        case SyncEntityKind.event:
          addExpected(
            '${SyncListKind.eventSiblings.name}:'
            '${record.payload['parentSyncId'] ?? 'root'}',
            id,
          );
        case SyncEntityKind.routineCategory:
          addExpected('${SyncListKind.routineCategories.name}:all', id);
        case SyncEntityKind.routine:
          addExpected(
            '${SyncListKind.routines.name}:'
            '${record.payload['routineCategorySyncId'] ?? 'uncategorized'}',
            id,
          );
        case SyncEntityKind.eventDayPlan:
          addExpected(
            '${SyncListKind.eventDayPlans.name}:${record.payload['jaxDay']}',
            record.payload['eventSyncId']! as String,
          );
        case SyncEntityKind.worldNode:
          final parent = record.payload['parentWorldNodeSyncId'];
          addExpected(
            '${SyncListKind.worldNodeSiblings.name}:'
            '${parent == null ? 'category:${record.payload['categorySyncId'] ?? 'uncategorized'}' : 'parent:$parent'}',
            id,
          );
        case SyncEntityKind.legacyEventWorldNodeLink:
          break;
        case SyncEntityKind.eventRunSegment ||
            SyncEntityKind.routineExecution ||
            SyncEntityKind.routineRunSegment:
          break;
      }
    }
    for (final entry in expected.entries) {
      final found = actual[entry.key] ?? const <String>{};
      if (found.length != entry.value.length ||
          !found.containsAll(entry.value)) {
        issues.add('list-incomplete:${entry.key}');
      }
    }
  }
}
