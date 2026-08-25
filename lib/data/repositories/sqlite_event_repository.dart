import '../../core/entities/event_status.dart';
import '../../core/entities/jax_event.dart';
import '../../core/entities/run_segment.dart';
import '../../core/repositories/event_repository.dart';
import '../database/app_database.dart';

class SqliteEventRepository implements EventRepository {
  const SqliteEventRepository(this._appDatabase);
  final AppDatabase _appDatabase;

  @override
  Future<void> insertEvent(JaxEvent event) =>
      _appDatabase.database.insert('events', _toRow(event));

  @override
  Future<List<JaxEvent>> getIncompleteEvents() async {
    final rows = await _appDatabase.database.query(
      'events',
      where: 'status != ?',
      whereArgs: [EventStatus.completed.name],
      orderBy: 'created_at_utc ASC, id ASC',
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  @override
  Future<List<JaxEvent>> getCompletedEvents() async {
    final rows = await _appDatabase.database.query(
      'events',
      where: 'status = ?',
      whereArgs: [EventStatus.completed.name],
      orderBy: 'completed_at_utc DESC',
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  @override
  Future<JaxEvent?> getEvent(String id) async {
    final rows = await _appDatabase.database.query(
      'events',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : _fromRow(rows.single);
  }

  @override
  Future<void> updateEvent(JaxEvent event) async {
    final count = await _appDatabase.database.update(
      'events',
      _toRow(event),
      where: 'id = ?',
      whereArgs: [event.id],
    );
    if (count != 1) throw StateError('Event not found: ${event.id}');
  }

  @override
  Future<void> deleteEvent(String id) async {
    await _appDatabase.database.transaction((transaction) async {
      final count = await transaction.delete(
        'events',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (count != 1) throw StateError('Event not found: $id');
    });
  }

  @override
  Future<void> startEvent(JaxEvent event, RunSegment segment) async {
    await _appDatabase.database.transaction((transaction) async {
      final running = await transaction.query(
        'events',
        where: 'status = ? AND id != ?',
        whereArgs: [EventStatus.running.name, event.id],
        limit: 1,
      );
      if (running.isNotEmpty) {
        throw StateError('Another event is already running');
      }
      await transaction.update(
        'events',
        _toRow(event),
        where: 'id = ?',
        whereArgs: [event.id],
      );
      await transaction.insert('run_segments', _segmentToRow(segment));
    });
  }

  @override
  Future<List<RunSegment>> getRunSegments(String eventId) async {
    final rows = await _appDatabase.database.query(
      'run_segments',
      where: 'event_id = ?',
      whereArgs: [eventId],
      orderBy: 'started_at_utc ASC',
    );
    return rows.map(_segmentFromRow).toList(growable: false);
  }

  @override
  Future<void> pauseEvent(JaxEvent event, RunSegment segment) async {
    await _appDatabase.database.transaction((transaction) async {
      await transaction.update(
        'events',
        _toRow(event),
        where: 'id = ?',
        whereArgs: [event.id],
      );
      final count = await transaction.update(
        'run_segments',
        _segmentToRow(segment),
        where: 'id = ? AND ended_at_utc IS NULL',
        whereArgs: [segment.id],
      );
      if (count != 1) throw StateError('Open run segment not found');
    });
  }

  @override
  Future<JaxEvent?> getParent(String eventId) async {
    final rows = await _appDatabase.database.rawQuery(
      '''SELECT parent.* FROM events child
         JOIN events parent ON parent.id = child.parent_event_id
         WHERE child.id = ? LIMIT 1''',
      [eventId],
    );
    return rows.isEmpty ? null : _fromRow(rows.single);
  }

  @override
  Future<List<JaxEvent>> getDirectChildren(String parentEventId) async {
    final rows = await _appDatabase.database.query(
      'events',
      where: 'parent_event_id = ?',
      whereArgs: [parentEventId],
      orderBy: 'sort_order ASC, created_at_utc ASC, id ASC',
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  @override
  Future<List<JaxEvent>> getOrderedSiblings(String eventId) async {
    final event = await getEvent(eventId);
    if (event == null) throw StateError('Event not found: $eventId');
    return _querySiblings(event.parentEventId);
  }

  @override
  Future<List<JaxEvent>> getOrderedTopLevelEvents() => _querySiblings(null);

  Future<List<JaxEvent>> _querySiblings(String? parentEventId) async {
    final rows = await _appDatabase.database.query(
      'events',
      where: parentEventId == null
          ? 'parent_event_id IS NULL'
          : 'parent_event_id = ?',
      whereArgs: parentEventId == null ? null : [parentEventId],
      orderBy: 'sort_order ASC, created_at_utc ASC, id ASC',
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  Future<int> _nextSortOrder(dynamic executor, String? parentEventId) async {
    final rows = await executor.rawQuery(
      parentEventId == null
          ? 'SELECT COALESCE(MAX(sort_order), -1) + 1 AS next_order FROM events WHERE parent_event_id IS NULL'
          : 'SELECT COALESCE(MAX(sort_order), -1) + 1 AS next_order FROM events WHERE parent_event_id = ?',
      parentEventId == null ? null : [parentEventId],
    );
    return rows.single['next_order']! as int;
  }

  @override
  Future<void> updateParent(
    String eventId,
    String? parentEventId,
    DateTime updatedAt,
  ) async {
    await _appDatabase.database.transaction((transaction) async {
      final childRows = await transaction.query(
        'events',
        columns: ['status'],
        where: 'id = ?',
        whereArgs: [eventId],
        limit: 1,
      );
      if (childRows.isEmpty) throw StateError('Event not found: $eventId');
      if (parentEventId != null) {
        final parentRows = await transaction.query(
          'events',
          columns: ['status'],
          where: 'id = ?',
          whereArgs: [parentEventId],
          limit: 1,
        );
        if (parentRows.isEmpty) {
          throw StateError('Parent event not found: $parentEventId');
        }
        if (childRows.single['status'] != EventStatus.completed.name &&
            parentRows.single['status'] == EventStatus.completed.name) {
          throw StateError('Incomplete event cannot have completed parent');
        }
        final cycle = await transaction.rawQuery(
          '''WITH RECURSIVE ancestors(id, parent_event_id) AS (
               SELECT id, parent_event_id FROM events WHERE id = ?
               UNION ALL
               SELECT event.id, event.parent_event_id FROM events event
               JOIN ancestors ON event.id = ancestors.parent_event_id
             ) SELECT 1 FROM ancestors WHERE id = ? LIMIT 1''',
          [parentEventId, eventId],
        );
        if (cycle.isNotEmpty) throw StateError('Hierarchy cycle detected');
      }
      final count = await transaction.update(
        'events',
        {
          'parent_event_id': parentEventId,
          'sort_order': await _nextSortOrder(transaction, parentEventId),
          'updated_at_utc': updatedAt.toUtc().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [eventId],
      );
      if (count != 1) throw StateError('Event not found: $eventId');
    });
  }

  @override
  Future<void> switchRunningEvent({
    required JaxEvent pausedRunning,
    required RunSegment closedSegment,
    required JaxEvent runningTarget,
    required RunSegment newSegment,
    required List<JaxEvent> pausedAncestors,
  }) async {
    await _appDatabase.database.transaction((transaction) async {
      final paused = await transaction.update(
        'events',
        _toRow(pausedRunning),
        where: 'id = ?',
        whereArgs: [pausedRunning.id],
      );
      if (paused != 1) throw StateError('Running event not found');
      final closed = await transaction.update(
        'run_segments',
        _segmentToRow(closedSegment),
        where: 'id = ? AND ended_at_utc IS NULL',
        whereArgs: [closedSegment.id],
      );
      if (closed != 1) throw StateError('Open run segment not found');
      for (final ancestor in pausedAncestors) {
        final updated = await transaction.update(
          'events',
          _toRow(ancestor),
          where: 'id = ?',
          whereArgs: [ancestor.id],
        );
        if (updated != 1) throw StateError('Ancestor event not found');
      }
      final started = await transaction.update(
        'events',
        _toRow(runningTarget),
        where: 'id = ?',
        whereArgs: [runningTarget.id],
      );
      if (started != 1) throw StateError('Target event not found');
      await transaction.insert('run_segments', _segmentToRow(newSegment));
    });
  }

  Map<String, Object?> _segmentToRow(RunSegment segment) => {
    'id': segment.id,
    'event_id': segment.eventId,
    'started_at_utc': segment.startedAt.millisecondsSinceEpoch,
    'ended_at_utc': segment.endedAt?.millisecondsSinceEpoch,
    'created_at_utc': segment.createdAt.millisecondsSinceEpoch,
  };

  RunSegment _segmentFromRow(Map<String, Object?> row) => RunSegment(
    id: row['id']! as String,
    eventId: row['event_id']! as String,
    startedAt: DateTime.fromMillisecondsSinceEpoch(
      row['started_at_utc']! as int,
      isUtc: true,
    ),
    endedAt: row['ended_at_utc'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            row['ended_at_utc']! as int,
            isUtc: true,
          ),
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      row['created_at_utc']! as int,
      isUtc: true,
    ),
  );
  Map<String, Object?> _toRow(JaxEvent event) => {
    'id': event.id,
    'name': event.name,
    'status': event.status.name,
    'parent_event_id': event.parentEventId,
    'sort_order': event.sortOrder,
    'first_started_at_utc': event.firstStartedAt?.millisecondsSinceEpoch,
    'completed_at_utc': event.completedAt?.millisecondsSinceEpoch,
    'created_at_utc': event.createdAt.millisecondsSinceEpoch,
    'updated_at_utc': event.updatedAt.millisecondsSinceEpoch,
  };

  JaxEvent _fromRow(Map<String, Object?> row) {
    DateTime? optional(String key) {
      final value = row[key] as int?;
      return value == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
    }

    return JaxEvent(
      id: row['id']! as String,
      name: row['name']! as String,
      status: EventStatus.fromStorage(row['status']! as String),
      parentEventId: row['parent_event_id'] as String?,
      sortOrder: row['sort_order'] as int?,
      firstStartedAt: optional('first_started_at_utc'),
      completedAt: optional('completed_at_utc'),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        row['created_at_utc']! as int,
        isUtc: true,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        row['updated_at_utc']! as int,
        isUtc: true,
      ),
    );
  }
}
