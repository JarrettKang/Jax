import 'package:sqflite_common_ffi/sqflite_ffi.dart' show Database;

import '../../core/entities/world_node_ids.dart';
import '../database/app_database.dart';

class SyncReadinessIssue {
  const SyncReadinessIssue(this.code, this.detail, {this.isBlocking = true});
  final String code;
  final String detail;
  final bool isBlocking;

  @override
  String toString() => '$code: $detail';
}

/// Read-only database health audit to run before snapshot export and after a
/// future sync apply. It deliberately does not repair or resolve conflicts.
class SqliteSyncReadiness {
  const SqliteSyncReadiness(this.database);
  final AppDatabase database;

  SqliteSyncReadiness.fromDatabase(Database database)
    : database = AppDatabase.fromOpenDatabase(database);

  Future<List<SyncReadinessIssue>> validate() async {
    final issues = <SyncReadinessIssue>[];
    final db = database.database;

    final foreignKeys = await db.rawQuery('PRAGMA foreign_key_check');
    for (final row in foreignKeys) {
      issues.add(SyncReadinessIssue('foreign-key', row.toString()));
    }

    for (final row in await db.rawQuery(
      "SELECT id FROM routine_executions WHERE is_waiting NOT IN (0,1) OR (is_waiting = 1 AND status != 'paused')",
    )) {
      issues.add(SyncReadinessIssue('routine-waiting-state', row.toString()));
    }

    const identityTables = [
      'categories',
      'events',
      'run_segments',
      'routine_categories',
      'routines',
      'routine_executions',
      'routine_run_segments',
      'world_nodes',
      'plans',
      'plan_items',
      'plan_review_notes',
    ];
    for (final table in identityTables) {
      final invalid = await db.rawQuery(
        "SELECT id FROM $table WHERE id IS NULL OR trim(id) = ''",
      );
      for (final row in invalid) {
        issues.add(SyncReadinessIssue('missing-identity', '$table $row'));
      }
      final metadata = await db.rawQuery(
        'SELECT id FROM $table WHERE created_at_utc IS NULL OR updated_at_utc IS NULL',
      );
      for (final row in metadata) {
        issues.add(SyncReadinessIssue('missing-metadata', '$table $row'));
      }
    }
    final planMetadata = await db.rawQuery('''SELECT event_id, day_date
      FROM event_day_plans
      WHERE created_at_utc IS NULL OR updated_at_utc IS NULL''');
    for (final row in planMetadata) {
      issues.add(
        SyncReadinessIssue('missing-metadata', 'event_day_plans $row'),
      );
    }

    for (final row in await db.rawQuery('''SELECT event.id FROM events event
      LEFT JOIN plan_items item ON item.id = event.source_plan_item_id
      WHERE event.source_plan_item_id IS NOT NULL AND item.id IS NULL''')) {
      issues.add(SyncReadinessIssue('event-plan-item', row['id'].toString()));
    }
    for (final row in await db.rawQuery(
      '''SELECT source_plan_item_id, count(*) count
      FROM events WHERE source_plan_item_id IS NOT NULL
      GROUP BY source_plan_item_id HAVING count(*) > 1''',
    )) {
      issues.add(
        SyncReadinessIssue('duplicate-event-plan-item', row.toString()),
      );
    }
    for (final row in await db.rawQuery('''SELECT id FROM events
      WHERE source_plan_item_id IS NOT NULL AND category_id IS NOT NULL''')) {
      issues.add(
        SyncReadinessIssue(
          'planned-event-direct-category',
          row['id'].toString(),
        ),
      );
    }

    final worldCycles = await db.rawQuery(
      '''WITH RECURSIVE ancestry(origin, id, path, cycle) AS (
      SELECT id, parent_world_node_id, '|' || id || '|', 0
      FROM world_nodes WHERE parent_world_node_id IS NOT NULL
      UNION ALL
      SELECT ancestry.origin, world_nodes.parent_world_node_id,
        ancestry.path || world_nodes.id || '|',
        instr(ancestry.path, '|' || world_nodes.id || '|') > 0
      FROM ancestry JOIN world_nodes ON world_nodes.id = ancestry.id
      WHERE world_nodes.parent_world_node_id IS NOT NULL AND ancestry.cycle = 0
    ) SELECT DISTINCT origin FROM ancestry WHERE cycle = 1''',
    );
    for (final row in worldCycles) {
      issues.add(
        SyncReadinessIssue('world-node-cycle', row['origin'].toString()),
      );
    }
    for (final row in await db.rawQuery('''SELECT id FROM world_nodes
      WHERE parent_world_node_id IS NOT NULL AND category_id IS NOT NULL''')) {
      issues.add(
        SyncReadinessIssue(
          'world-node-child-direct-category',
          row['id'].toString(),
        ),
      );
    }
    for (final row in await db.query('world_nodes', columns: ['id'])) {
      final id = row['id']! as String;
      if (!WorldNodeIds.isValid(id)) {
        issues.add(SyncReadinessIssue('world-node-invalid-uuid', id));
      }
    }
    for (final row in await db.rawQuery('''SELECT id FROM world_nodes
      WHERE is_focused NOT IN (0,1)''')) {
      issues.add(SyncReadinessIssue('world-node-focus', row['id'].toString()));
    }
    for (final row in await db.rawQuery('''SELECT id FROM world_nodes
      WHERE status = 'completed' AND is_focused != 0''')) {
      issues.add(
        SyncReadinessIssue(
          'completed-world-node-focused',
          row['id'].toString(),
        ),
      );
    }
    final generations = await db.query('dataset_metadata');
    if (generations.length != 1 ||
        (generations.single['generation'] as String?)?.trim().isEmpty !=
            false) {
      issues.add(const SyncReadinessIssue('dataset-generation', '缺少唯一的数据代际'));
    }

    for (final row in await db.rawQuery('''SELECT p.id FROM plans p
      LEFT JOIN world_nodes w ON w.id = p.world_node_id
      WHERE w.id IS NULL''')) {
      issues.add(SyncReadinessIssue('plan-world-node', row['id'].toString()));
    }
    for (final row in await db.rawQuery('''SELECT i.id FROM plan_items i
      LEFT JOIN plans p ON p.id = i.plan_id WHERE p.id IS NULL''')) {
      issues.add(SyncReadinessIssue('plan-item-plan', row['id'].toString()));
    }
    for (final row in await db.rawQuery(
      '''SELECT i.id FROM plan_items i
      LEFT JOIN world_nodes n ON n.id = i.promoted_world_node_id
      WHERE i.promoted_world_node_id IS NOT NULL AND
        (n.id IS NULL OR i.status NOT IN ('next','draft') OR
         EXISTS(SELECT 1 FROM events e WHERE e.source_plan_item_id = i.id))''',
    )) {
      issues.add(
        SyncReadinessIssue('plan-item-promotion', row['id'].toString()),
      );
    }
    for (final row in await db.rawQuery('''SELECT n.id FROM plan_review_notes n
      LEFT JOIN plans p ON p.id = n.plan_id WHERE p.id IS NULL''')) {
      issues.add(
        SyncReadinessIssue('plan-review-note-plan', row['id'].toString()),
      );
    }
    for (final row in await db.rawQuery('''SELECT id FROM plan_review_notes
      WHERE length(trim(content)) = 0''')) {
      issues.add(
        SyncReadinessIssue('plan-review-note-content', row['id'].toString()),
      );
    }
    for (final row in await db.rawQuery('''SELECT id FROM plan_review_notes
      WHERE updated_at_utc < created_at_utc''')) {
      issues.add(
        SyncReadinessIssue('plan-review-note-timestamps', row['id'].toString()),
      );
    }
    for (final row in await db.query('plan_review_notes', columns: ['id'])) {
      final id = row['id']! as String;
      if (!WorldNodeIds.isValid(id)) {
        issues.add(SyncReadinessIssue('plan-review-note-invalid-uuid', id));
      }
    }
    for (final row in await db.rawQuery('''SELECT id FROM plans WHERE
      (status = 'ended' AND ended_at_utc IS NULL) OR
      (status = 'current' AND ended_at_utc IS NOT NULL) OR
      status NOT IN ('current','ended')''')) {
      issues.add(SyncReadinessIssue('plan-ended-at', row['id'].toString()));
    }
    for (final row in await db.rawQuery('''SELECT world_node_id, count(*) count
      FROM plans WHERE status = 'current'
      GROUP BY world_node_id HAVING count(*) > 1''')) {
      issues.add(SyncReadinessIssue('multiple-current-plans', row.toString()));
    }
    for (final row in await db.rawQuery('''SELECT p.id FROM plans p
      JOIN world_nodes w ON w.id = p.world_node_id
      WHERE p.status = 'current' AND w.status = 'completed' ''')) {
      issues.add(
        SyncReadinessIssue(
          'completed-world-node-current-plan',
          row['id'].toString(),
        ),
      );
    }
    for (final row in await db.rawQuery('''SELECT i.id FROM plan_items i
      LEFT JOIN events e ON e.source_plan_item_id = i.id
      WHERE i.status IN ('dispatched','done') AND e.id IS NULL''')) {
      issues.add(
        SyncReadinessIssue(
          'executed-plan-item-without-event',
          row['id'].toString(),
        ),
      );
    }
    for (final row in await db.rawQuery('''SELECT i.id FROM plan_items i
      JOIN events e ON e.source_plan_item_id = i.id
      WHERE i.status IN ('draft','next','dropped')''')) {
      issues.add(
        SyncReadinessIssue(
          'unexecuted-plan-item-with-event',
          row['id'].toString(),
        ),
      );
    }
    for (final row in await db.rawQuery('''SELECT i.id FROM plan_items i
      JOIN events e ON e.source_plan_item_id = i.id
      WHERE (i.status = 'done' AND e.status != 'completed')
         OR (i.status = 'dispatched' AND e.status = 'completed')''')) {
      issues.add(
        SyncReadinessIssue(
          'plan-item-event-status-mismatch',
          row['id'].toString(),
        ),
      );
    }

    final running = SqfliteCount.value(
      await db.rawQuery(
        '''
      SELECT (SELECT count(*) FROM events WHERE status = 'running') +
        (SELECT count(*) FROM routine_executions WHERE status = 'running') AS count''',
      ),
    );
    if (running > 1) {
      issues.add(SyncReadinessIssue('multiple-running', '$running entities'));
    }

    final openSegments = SqfliteCount.value(
      await db.rawQuery(
        '''
      SELECT (SELECT count(*) FROM run_segments WHERE ended_at_utc IS NULL) +
        (SELECT count(*) FROM routine_run_segments WHERE ended_at_utc IS NULL) AS count''',
      ),
    );
    if (openSegments > 1) {
      issues.add(
        SyncReadinessIssue('multiple-open-segments', '$openSegments segments'),
      );
    }

    final inconsistentEvents = await db.rawQuery('''SELECT e.id FROM events e
      WHERE (e.status = 'running') != EXISTS(
        SELECT 1 FROM run_segments s
        WHERE s.event_id = e.id AND s.ended_at_utc IS NULL)''');
    for (final row in inconsistentEvents) {
      issues.add(
        SyncReadinessIssue('event-running-segment', row['id'].toString()),
      );
    }
    final inconsistentExecutions = await db.rawQuery('''
      SELECT e.id FROM routine_executions e
      WHERE (e.status = 'running') != EXISTS(
        SELECT 1 FROM routine_run_segments s
        WHERE s.routine_execution_id = e.id AND s.ended_at_utc IS NULL)''');
    for (final row in inconsistentExecutions) {
      issues.add(
        SyncReadinessIssue('routine-running-segment', row['id'].toString()),
      );
    }

    for (final table in ['run_segments', 'routine_run_segments']) {
      final invalid = await db.rawQuery(
        'SELECT id FROM $table WHERE ended_at_utc IS NOT NULL AND started_at_utc >= ended_at_utc',
      );
      for (final row in invalid) {
        issues.add(
          SyncReadinessIssue('invalid-segment-range', '$table ${row['id']}'),
        );
      }
    }

    final unfinishedOnDemand = await db.rawQuery(
      '''SELECT routine_id, count(*) count
      FROM routine_executions e JOIN routines r ON r.id = e.routine_id
      WHERE r.routine_type = 'onDemand' AND e.status != 'completed'
      GROUP BY routine_id HAVING count(*) > 1''',
    );
    for (final row in unfinishedOnDemand) {
      issues.add(
        SyncReadinessIssue(
          'multiple-unfinished-on-demand',
          '${row['routine_id']}: ${row['count']}',
        ),
      );
    }

    for (final row in await db.rawQuery('''SELECT id FROM routines WHERE
      time_recommendation_enabled NOT IN (0,1) OR
      (time_recommendation_enabled = 0 AND
        (time_recommendation_start_minute IS NOT NULL OR
         time_recommendation_end_minute IS NOT NULL OR
         time_recommendation_latest_end_minute IS NOT NULL OR
         time_recommendation_reason IS NOT NULL)) OR
      (time_recommendation_enabled = 1 AND
        (routine_type != 'scheduled' OR
         time_recommendation_start_minute NOT BETWEEN 0 AND 1439 OR
         time_recommendation_end_minute NOT BETWEEN 0 AND 1439 OR
         time_recommendation_latest_end_minute IS NULL OR
         time_recommendation_latest_end_minute NOT BETWEEN 0 AND 1439 OR
         ((time_recommendation_end_minute - time_recommendation_start_minute + 1440) % 1440) > ((time_recommendation_latest_end_minute - time_recommendation_start_minute + 1440) % 1440) OR
         time_recommendation_start_minute = time_recommendation_end_minute OR
         (time_recommendation_reason IS NOT NULL AND
          length(trim(time_recommendation_reason)) = 0)))''')) {
      issues.add(
        SyncReadinessIssue('routine-time-configuration', row['id'].toString()),
      );
    }

    for (final row in await db.rawQuery('''SELECT id FROM routines WHERE
      show_in_home_quick_actions IS NULL OR
      show_in_home_quick_actions NOT IN (0,1) OR
      (show_in_home_quick_actions = 1 AND routine_type != 'onDemand')''')) {
      issues.add(
        SyncReadinessIssue('routine-home-quick-action', row['id'].toString()),
      );
    }

    final overlaps = await db.rawQuery('''WITH all_segments AS (
      SELECT 'event:' || id identity, started_at_utc started,
        COALESCE(ended_at_utc, 9223372036854775807) ended FROM run_segments
      UNION ALL
      SELECT 'routine:' || id identity, started_at_utc started,
        COALESCE(ended_at_utc, 9223372036854775807) ended
      FROM routine_run_segments
    ) SELECT a.identity first_id, b.identity second_id
      FROM all_segments a JOIN all_segments b ON a.identity < b.identity
      WHERE a.started < b.ended AND b.started < a.ended''');
    for (final row in overlaps) {
      issues.add(SyncReadinessIssue('segment-overlap', row.toString()));
    }

    await _validateOrders(issues);
    return issues;
  }

  Future<void> _validateOrders(List<SyncReadinessIssue> issues) async {
    final db = database.database;
    final checks = <String, String>{
      'category-order': '''SELECT sort_order value FROM categories
        GROUP BY sort_order HAVING count(*) > 1''',
      'routine-category-order':
          '''SELECT sort_order value FROM routine_categories
        GROUP BY sort_order HAVING count(*) > 1''',
      'routine-order':
          '''SELECT routine_category_id, sort_order value FROM routines
        GROUP BY routine_category_id, sort_order HAVING count(*) > 1''',
      'today-order': '''SELECT day_date, order_index value FROM event_day_plans
        GROUP BY day_date, order_index HAVING count(*) > 1''',
    };
    for (final entry in checks.entries) {
      for (final row in await db.rawQuery(entry.value)) {
        issues.add(
          SyncReadinessIssue(entry.key, row.toString(), isBlocking: false),
        );
      }
    }
    final worldOrderDuplicates = await db.rawQuery('''SELECT
      parent_world_node_id, category_id, sort_order, count(*) count
      FROM world_nodes
      GROUP BY parent_world_node_id, category_id, sort_order
      HAVING count(*) > 1''');
    for (final row in worldOrderDuplicates) {
      issues.add(SyncReadinessIssue('world-node-scoped-order', row.toString()));
    }
    for (final row in await db.rawQuery(
      '''SELECT plan_id, sort_order, count(*) count
      FROM plan_items GROUP BY plan_id, sort_order HAVING count(*) > 1''',
    )) {
      issues.add(SyncReadinessIssue('plan-item-scoped-order', row.toString()));
    }
    for (final row in await db.rawQuery(
      'SELECT id FROM plan_items WHERE sort_order < 0',
    )) {
      issues.add(
        SyncReadinessIssue('plan-item-negative-order', row['id'].toString()),
      );
    }
  }
}

class SqfliteCount {
  static int value(List<Map<String, Object?>> rows) =>
      (rows.single['count'] as num).toInt();
}
