import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import '../../core/entities/event_status.dart';
import '../../core/entities/jax_event.dart';
import '../../core/entities/run_segment.dart';
import '../../core/entities/category.dart';
import '../../core/entities/event_day_plan.dart';
import '../../core/entities/routine.dart';
import '../../core/repositories/event_repository.dart';
import '../../core/repositories/event_day_plan_repository.dart';
import '../../core/repositories/routine_repository.dart';
import '../database/app_database.dart';

class SqliteEventRepository
    implements EventRepository, EventDayPlanRepository, RoutineRepository {
  const SqliteEventRepository(this._appDatabase);
  final AppDatabase _appDatabase;

  @override
  Future<void> insertEvent(JaxEvent event) async {
    await _appDatabase.database.transaction((transaction) async {
      final row = _toRow(event);
      row['sort_order'] =
          event.sortOrder ??
          await _nextSortOrder(transaction, event.parentEventId);
      await transaction.insert('events', row);
    });
  }

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
      await _pauseRunningRoutineIn(transaction, event.updatedAt);
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
  Future<void> restoreCompletedEvents(List<JaxEvent> events) async {
    if (events.isEmpty) throw StateError('No events to restore');
    await _appDatabase.database.transaction((transaction) async {
      for (final event in events) {
        final rows = await transaction.query(
          'events',
          columns: ['status'],
          where: 'id = ?',
          whereArgs: [event.id],
          limit: 1,
        );
        if (rows.isEmpty) throw StateError('Event not found: ${event.id}');
        if (rows.single['status'] != EventStatus.completed.name ||
            event.status != EventStatus.paused ||
            event.completedAt != null) {
          throw StateError('Invalid completed Event restoration');
        }
      }
      for (final event in events) {
        final count = await transaction.update(
          'events',
          _toRow(event),
          where: 'id = ? AND status = ?',
          whereArgs: [event.id, EventStatus.completed.name],
        );
        if (count != 1) throw StateError('Event restore conflict: ${event.id}');
      }
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
  Future<void> reorderSibling(String eventId, int targetIndex) async {
    await _appDatabase.database.transaction((transaction) async {
      final eventRows = await transaction.query(
        'events',
        columns: ['parent_event_id'],
        where: 'id = ?',
        whereArgs: [eventId],
        limit: 1,
      );
      if (eventRows.isEmpty) throw StateError('Event not found: $eventId');
      final parent = eventRows.single['parent_event_id'] as String?;
      final siblings = await transaction.query(
        'events',
        columns: ['id'],
        where: parent == null
            ? 'parent_event_id IS NULL'
            : 'parent_event_id = ?',
        whereArgs: parent == null ? null : [parent],
        orderBy: 'sort_order ASC, created_at_utc ASC, id ASC',
      );
      if (targetIndex < 0 || targetIndex >= siblings.length) {
        throw StateError('Invalid target index');
      }
      final ids = siblings.map((row) => row['id']! as String).toList();
      final current = ids.indexOf(eventId);
      final moved = ids.removeAt(current);
      ids.insert(targetIndex, moved);
      for (var index = 0; index < ids.length; index++) {
        final count = await transaction.update(
          'events',
          {'sort_order': index},
          where: 'id = ?',
          whereArgs: [ids[index]],
        );
        if (count != 1) throw StateError('Event not found: ${ids[index]}');
      }
    });
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
        columns: ['status', 'category_id'],
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
      String? categoryId;
      if (parentEventId == null) {
        final root = await transaction.rawQuery(
          '''WITH RECURSIVE ancestors(id, parent_event_id, category_id) AS (
          SELECT id, parent_event_id, category_id FROM events WHERE id = ?
          UNION ALL
          SELECT e.id, e.parent_event_id, e.category_id FROM events e
          JOIN ancestors a ON e.id = a.parent_event_id
        ) SELECT category_id FROM ancestors WHERE parent_event_id IS NULL LIMIT 1''',
          [eventId],
        );
        categoryId = root.isEmpty
            ? null
            : root.single['category_id'] as String?;
      }
      final count = await transaction.update(
        'events',
        {
          'parent_event_id': parentEventId,
          'sort_order': await _nextSortOrder(transaction, parentEventId),
          'updated_at_utc': updatedAt.toUtc().millisecondsSinceEpoch,
          'category_id': categoryId,
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
    'category_id': event.categoryId,
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
      categoryId: row['category_id'] as String?,
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

  @override
  Future<List<Category>> getCategories() async {
    final rows = await _appDatabase.database.query(
      'categories',
      orderBy: 'sort_order ASC, created_at_utc ASC, id ASC',
    );
    return rows.map(_categoryFromRow).toList(growable: false);
  }

  @override
  Future<void> insertCategory(Category category) async {
    await _appDatabase.database.insert('categories', _categoryToRow(category));
  }

  @override
  Future<void> updateCategory(Category category) async {
    final count = await _appDatabase.database.update(
      'categories',
      _categoryToRow(category),
      where: 'id = ?',
      whereArgs: [category.id],
    );
    if (count != 1) throw StateError('Category not found: ${category.id}');
  }

  @override
  Future<void> deleteCategory(String id) async {
    await _appDatabase.database.delete(
      'categories',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> reorderCategory(String id, int targetIndex) async {
    await _appDatabase.database.transaction((transaction) async {
      final rows = await transaction.query(
        'categories',
        orderBy: 'sort_order ASC, created_at_utc ASC, id ASC',
      );
      final ids = rows.map((row) => row['id']! as String).toList();
      final current = ids.indexOf(id);
      if (current < 0 || targetIndex < 0 || targetIndex >= ids.length) {
        throw StateError('Invalid category order');
      }
      final moved = ids.removeAt(current);
      ids.insert(targetIndex, moved);
      for (var i = 0; i < ids.length; i++) {
        await transaction.update(
          'categories',
          {'sort_order': i},
          where: 'id = ?',
          whereArgs: [ids[i]],
        );
      }
    });
  }

  @override
  Future<void> setRootCategory(String eventId, String? categoryId) async {
    await _appDatabase.database.transaction((transaction) async {
      final event = await transaction.query(
        'events',
        columns: ['parent_event_id'],
        where: 'id = ?',
        whereArgs: [eventId],
        limit: 1,
      );
      if (event.isEmpty) {
        throw StateError('Event not found: $eventId');
      }
      if (event.single['parent_event_id'] != null) {
        throw StateError('Only root events can have a category');
      }
      if (categoryId != null) {
        final category = await transaction.query(
          'categories',
          where: 'id = ?',
          whereArgs: [categoryId],
          limit: 1,
        );
        if (category.isEmpty) {
          throw StateError('Category not found: $categoryId');
        }
      }
      await transaction.update(
        'events',
        {'category_id': categoryId},
        where: 'id = ?',
        whereArgs: [eventId],
      );
    });
  }

  Map<String, Object?> _categoryToRow(Category category) => {
    'id': category.id,
    'name': category.name,
    'sort_order': category.sortOrder,
    'created_at_utc': category.createdAt.millisecondsSinceEpoch,
    'updated_at_utc': category.updatedAt.millisecondsSinceEpoch,
  };

  Category _categoryFromRow(Map<String, Object?> row) => Category(
    id: row['id']! as String,
    name: row['name']! as String,
    sortOrder: row['sort_order']! as int,
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      row['created_at_utc']! as int,
      isUtc: true,
    ),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(
      row['updated_at_utc']! as int,
      isUtc: true,
    ),
  );

  @override
  Future<List<EventDayPlan>> getEventDayPlans(String dayKey) async =>
      (await _appDatabase.database.query(
        'event_day_plans',
        where: 'day_date = ?',
        whereArgs: [dayKey],
        orderBy: 'order_index ASC, created_at_utc ASC, event_id ASC',
      )).map(_eventDayPlanFromRow).toList();

  @override
  Future<void> addEventDayPlan(EventDayPlan plan) async =>
      _appDatabase.database.insert(
        'event_day_plans',
        _eventDayPlanToRow(plan),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );

  @override
  Future<void> addEventDayPlans(List<EventDayPlan> plans) async {
    if (plans.isEmpty) return;
    await _appDatabase.database.transaction((tx) async {
      for (final plan in plans) {
        await tx.insert(
          'event_day_plans',
          _eventDayPlanToRow(plan),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });
  }

  @override
  Future<void> removeEventDayPlan(String eventId, String dayKey) async =>
      _appDatabase.database.delete(
        'event_day_plans',
        where: 'event_id = ? AND day_date = ?',
        whereArgs: [eventId, dayKey],
      );

  @override
  Future<void> reorderEventDayPlan(
    String eventId,
    String dayKey,
    int targetIndex,
  ) async => _appDatabase.database.transaction((tx) async {
    final rows = await tx.query(
      'event_day_plans',
      where: 'day_date = ?',
      whereArgs: [dayKey],
      orderBy: 'order_index ASC, created_at_utc ASC, event_id ASC',
    );
    final plans = rows.map(_eventDayPlanFromRow).toList();
    final current = plans.indexWhere((p) => p.eventId == eventId);
    if (current < 0 || targetIndex < 0 || targetIndex >= plans.length) {
      throw StateError('Invalid Today order');
    }
    final moved = plans.removeAt(current);
    plans.insert(targetIndex, moved);
    for (var i = 0; i < plans.length; i++) {
      await tx.update(
        'event_day_plans',
        {'order_index': i},
        where: 'event_id = ? AND day_date = ?',
        whereArgs: [plans[i].eventId, dayKey],
      );
    }
  });

  Map<String, Object?> _eventDayPlanToRow(EventDayPlan plan) => {
    'event_id': plan.eventId,
    'day_date': plan.dayKey,
    'order_index': plan.order,
    'created_at_utc': plan.createdAt.toUtc().millisecondsSinceEpoch,
  };

  EventDayPlan _eventDayPlanFromRow(Map<String, Object?> row) => EventDayPlan(
    eventId: row['event_id']! as String,
    dayKey: row['day_date']! as String,
    order: row['order_index']! as int,
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      row['created_at_utc']! as int,
      isUtc: true,
    ),
  );

  @override
  Future<List<Routine>> getRoutines() async =>
      (await _appDatabase.database.query(
        'routines',
        orderBy: 'sort_order ASC, created_at_utc ASC, id ASC',
      )).map(_routineFromRow).toList();
  @override
  Future<void> insertRoutine(Routine r) async =>
      _appDatabase.database.insert('routines', _routineToRow(r));
  @override
  Future<void> updateRoutine(Routine r) async {
    if (await _appDatabase.database.update(
          'routines',
          _routineToRow(r),
          where: 'id = ?',
          whereArgs: [r.id],
        ) !=
        1) {
      throw StateError('Routine not found');
    }
  }

  @override
  Future<void> reorderRoutine(String id, int targetIndex) async =>
      _appDatabase.database.transaction((tx) async {
        final rows = await tx.query(
          'routines',
          orderBy: 'sort_order ASC, created_at_utc ASC, id ASC',
        );
        final routines = rows.map(_routineFromRow).toList();
        final current = routines.indexWhere((r) => r.id == id);
        if (current < 0 || targetIndex < 0 || targetIndex >= routines.length) {
          throw StateError('Invalid Routine order');
        }
        final moved = routines.removeAt(current);
        routines.insert(targetIndex, moved);
        for (var i = 0; i < routines.length; i++) {
          await tx.update(
            'routines',
            {'sort_order': i},
            where: 'id = ?',
            whereArgs: [routines[i].id],
          );
        }
      });

  @override
  Future<RoutineExecution?> getRoutineExecution(
    String routineId,
    String occurrenceDate,
  ) async {
    final rows = await _appDatabase.database.query(
      'routine_executions',
      where: 'routine_id = ? AND occurrence_date = ?',
      whereArgs: [routineId, occurrenceDate],
      limit: 1,
    );
    return rows.isEmpty ? null : _executionFromRow(rows.single);
  }

  @override
  Future<List<RoutineExecution>> getRoutineExecutions() async =>
      (await _appDatabase.database.query('routine_executions'))
          .map(_executionFromRow)
          .toList();
  @override
  Future<RoutineExecution?> getRunningRoutineExecution() async {
    final rows = await _appDatabase.database.query(
      'routine_executions',
      where: 'status = ?',
      whereArgs: ['running'],
      limit: 1,
    );
    return rows.isEmpty ? null : _executionFromRow(rows.single);
  }

  @override
  Future<List<RoutineRunSegment>> getRoutineRunSegments(String id) async =>
      (await _appDatabase.database.query(
        'routine_run_segments',
        where: 'routine_execution_id = ?',
        whereArgs: [id],
        orderBy: 'started_at_utc ASC',
      )).map(_routineSegmentFromRow).toList();
  @override
  Future<void> startRoutineExecution(
    RoutineExecution e,
    RoutineRunSegment s,
    DateTime now,
  ) async {
    await _appDatabase.database.transaction((tx) async {
      await _pauseRunningEventIn(tx, now);
      final other = await tx.query(
        'routine_executions',
        where: 'status = ? AND id != ?',
        whereArgs: ['running', e.id],
        limit: 1,
      );
      if (other.isNotEmpty) await _pauseRunningRoutineIn(tx, now);
      final exists = await tx.query(
        'routine_executions',
        where: 'id = ?',
        whereArgs: [e.id],
        limit: 1,
      );
      if (exists.isEmpty) {
        await tx.insert('routine_executions', _executionToRow(e));
      } else {
        await tx.update(
          'routine_executions',
          _executionToRow(e),
          where: 'id = ?',
          whereArgs: [e.id],
        );
      }
      await tx.insert('routine_run_segments', _routineSegmentToRow(s));
    });
  }

  @override
  Future<void> pauseRoutineExecution(RoutineExecution e, RoutineRunSegment s) =>
      _finishRoutineSegment(e, s);
  @override
  Future<void> completeRoutineExecution(
    RoutineExecution e,
    RoutineRunSegment s,
  ) => _finishRoutineSegment(e, s);
  Future<void> _finishRoutineSegment(
    RoutineExecution e,
    RoutineRunSegment s,
  ) async => _appDatabase.database.transaction((tx) async {
    await tx.update(
      'routine_executions',
      _executionToRow(e),
      where: 'id = ?',
      whereArgs: [e.id],
    );
    if (await tx.update(
          'routine_run_segments',
          _routineSegmentToRow(s),
          where: 'id = ? AND ended_at_utc IS NULL',
          whereArgs: [s.id],
        ) !=
        1) {
      throw StateError('Open routine segment not found');
    }
  });
  @override
  Future<void> updateRoutineExecutionOnly(RoutineExecution e) async =>
      _appDatabase.database.update(
        'routine_executions',
        _executionToRow(e),
        where: 'id = ?',
        whereArgs: [e.id],
      );
  @override
  Future<void> pauseRunningRoutine(DateTime now) async => _appDatabase.database
      .transaction((tx) => _pauseRunningRoutineIn(tx, now));
  Future<void> _pauseRunningRoutineIn(dynamic tx, DateTime now) async {
    final rows = await tx.query(
      'routine_executions',
      where: 'status = ?',
      whereArgs: ['running'],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final id = rows.single['id'] as String;
    await tx.update(
      'routine_executions',
      {
        'status': 'paused',
        'updated_at_utc': now.toUtc().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await tx.update(
      'routine_run_segments',
      {'ended_at_utc': now.toUtc().millisecondsSinceEpoch},
      where: 'routine_execution_id = ? AND ended_at_utc IS NULL',
      whereArgs: [id],
    );
  }

  Future<void> _pauseRunningEventIn(dynamic tx, DateTime now) async {
    final rows = await tx.query(
      'events',
      where: 'status = ?',
      whereArgs: ['running'],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final id = rows.single['id'] as String;
    await tx.update(
      'events',
      {
        'status': 'paused',
        'updated_at_utc': now.toUtc().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await tx.update(
      'run_segments',
      {'ended_at_utc': now.toUtc().millisecondsSinceEpoch},
      where: 'event_id = ? AND ended_at_utc IS NULL',
      whereArgs: [id],
    );
  }

  Map<String, Object?> _routineToRow(Routine r) => {
    'id': r.id,
    'name': r.name,
    'category_id': r.categoryId,
    'recurrence_type': r.recurrence.name,
    'weekday_mask': r.weekdayMask,
    'is_active': r.isActive ? 1 : 0,
    'sort_order': r.sortOrder,
    'created_at_utc': r.createdAt.toUtc().millisecondsSinceEpoch,
    'updated_at_utc': r.updatedAt.toUtc().millisecondsSinceEpoch,
  };
  Routine _routineFromRow(Map<String, Object?> r) => Routine(
    id: r['id'] as String,
    name: r['name'] as String,
    categoryId: r['category_id'] as String?,
    recurrence: RoutineRecurrence.values.byName(r['recurrence_type'] as String),
    weekdayMask: r['weekday_mask'] as int,
    isActive: (r['is_active'] as int) == 1,
    sortOrder: r['sort_order'] as int,
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      r['created_at_utc'] as int,
      isUtc: true,
    ),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(
      r['updated_at_utc'] as int,
      isUtc: true,
    ),
  );
  Map<String, Object?> _executionToRow(RoutineExecution e) => {
    'id': e.id,
    'routine_id': e.routineId,
    'occurrence_date': e.occurrenceDate,
    'status': e.status.name,
    'completed_at_utc': e.completedAt?.toUtc().millisecondsSinceEpoch,
    'created_at_utc': e.createdAt.toUtc().millisecondsSinceEpoch,
    'updated_at_utc': e.updatedAt.toUtc().millisecondsSinceEpoch,
  };
  RoutineExecution _executionFromRow(Map<String, Object?> r) =>
      RoutineExecution(
        id: r['id'] as String,
        routineId: r['routine_id'] as String,
        occurrenceDate: r['occurrence_date'] as String,
        status: RoutineExecutionStatus.values.byName(r['status'] as String),
        completedAt: r['completed_at_utc'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                r['completed_at_utc'] as int,
                isUtc: true,
              ),
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          r['created_at_utc'] as int,
          isUtc: true,
        ),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          r['updated_at_utc'] as int,
          isUtc: true,
        ),
      );
  Map<String, Object?> _routineSegmentToRow(RoutineRunSegment s) => {
    'id': s.id,
    'routine_execution_id': s.executionId,
    'started_at_utc': s.startedAt.toUtc().millisecondsSinceEpoch,
    'ended_at_utc': s.endedAt?.toUtc().millisecondsSinceEpoch,
    'created_at_utc': s.createdAt.toUtc().millisecondsSinceEpoch,
  };
  RoutineRunSegment _routineSegmentFromRow(Map<String, Object?> r) =>
      RoutineRunSegment(
        id: r['id'] as String,
        executionId: r['routine_execution_id'] as String,
        startedAt: DateTime.fromMillisecondsSinceEpoch(
          r['started_at_utc'] as int,
          isUtc: true,
        ),
        endedAt: r['ended_at_utc'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                r['ended_at_utc'] as int,
                isUtc: true,
              ),
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          r['created_at_utc'] as int,
          isUtc: true,
        ),
      );
}
