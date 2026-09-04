import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/event_day_plan.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/sync/sync_contract.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/repositories/sqlite_event_repository.dart';
import 'package:jax/data/sync/sqlite_sync_snapshot_adapter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late AppDatabase app;
  late SqliteEventRepository repository;
  final now = DateTime.utc(2026, 9, 3, 15, 1);

  setUp(() async {
    app = await AppDatabase.inMemory();
    repository = SqliteEventRepository(app);
  });

  tearDown(() => app.close());

  test('carries only unfinished Events in previous Today order', () async {
    for (final entry in <String, EventStatus>{
      'completed-a': EventStatus.completed,
      'waiting': EventStatus.waiting,
      'paused': EventStatus.paused,
      'completed-b': EventStatus.completed,
      'pending': EventStatus.pending,
      'running': EventStatus.running,
    }.entries) {
      await repository.insertEvent(
        JaxEvent(
          id: entry.key,
          name: entry.key,
          status: entry.value,
          firstStartedAt: entry.value == EventStatus.running ? now : null,
          completedAt: entry.value == EventStatus.completed ? now : null,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
    await app.database.insert('run_segments', {
      'id': 'open-running',
      'event_id': 'running',
      'started_at_utc': now.millisecondsSinceEpoch,
      'ended_at_utc': null,
      'created_at_utc': now.millisecondsSinceEpoch,
      'updated_at_utc': now.millisecondsSinceEpoch,
    });
    await app.database.insert('routine_categories', {
      'id': 'routine-category',
      'name': 'Routine Category',
      'sort_order': 0,
      'color_key': 0,
      'created_at_utc': now.millisecondsSinceEpoch,
      'updated_at_utc': now.millisecondsSinceEpoch,
    });
    await app.database.insert('routines', {
      'id': 'routine',
      'name': 'Routine',
      'routine_category_id': 'routine-category',
      'routine_type': 'scheduled',
      'recurrence_type': 'daily',
      'weekday_mask': 0,
      'is_active': 1,
      'sort_order': 0,
      'created_at_utc': now.millisecondsSinceEpoch,
      'updated_at_utc': now.millisecondsSinceEpoch,
    });
    await app.database.insert('routine_executions', {
      'id': 'routine-execution',
      'routine_id': 'routine',
      'occurrence_date': '2026-09-03',
      'status': 'paused',
      'completed_at_utc': null,
      'created_at_utc': now.millisecondsSinceEpoch,
      'updated_at_utc': now.millisecondsSinceEpoch,
    });
    await app.database.insert('routine_run_segments', {
      'id': 'routine-segment',
      'routine_execution_id': 'routine-execution',
      'started_at_utc': now.millisecondsSinceEpoch - 60000,
      'ended_at_utc': now.millisecondsSinceEpoch,
      'created_at_utc': now.millisecondsSinceEpoch - 60000,
      'updated_at_utc': now.millisecondsSinceEpoch,
    });
    final routineBefore = await app.database.query('routines');
    final executionBefore = await app.database.query('routine_executions');
    final routineSegmentsBefore = await app.database.query(
      'routine_run_segments',
    );
    var order = 0;
    for (final id in [
      'completed-a',
      'waiting',
      'paused',
      'completed-b',
      'pending',
      'running',
    ]) {
      await repository.addEventDayPlan(
        EventDayPlan(
          eventId: id,
          dayKey: '2026-09-03',
          order: order++,
          createdAt: now,
        ),
      );
    }

    await repository.initializeDayFromPrevious(
      previousDayKey: '2026-09-03',
      currentDayKey: '2026-09-04',
      initializedAt: now,
    );
    await repository.initializeDayFromPrevious(
      previousDayKey: '2026-09-03',
      currentDayKey: '2026-09-04',
      initializedAt: now.add(const Duration(minutes: 1)),
    );

    expect(
      (await repository.getEventDayPlans('2026-09-04')).map((p) => p.eventId),
      ['waiting', 'paused', 'pending', 'running'],
    );
    expect((await app.database.query('events')).length, 6);
    final segments = await app.database.query('run_segments');
    expect(segments, hasLength(1));
    expect(segments.single['ended_at_utc'], isNull);
    expect((await repository.getEvent('running'))!.status, EventStatus.running);
    expect(await app.database.query('routines'), routineBefore);
    expect(await app.database.query('routine_executions'), executionBefore);
    expect(
      await app.database.query('routine_run_segments'),
      routineSegmentsBefore,
    );
  });

  test(
    'appends behind existing Today and later additions append after it',
    () async {
      for (final id in ['old-a', 'old-b', 'today-a', 'today-b', 'later']) {
        await repository.insertEvent(
          JaxEvent(
            id: id,
            name: id,
            status: EventStatus.paused,
            createdAt: now,
            updatedAt: now,
          ),
        );
      }
      await _plans(repository, '2026-09-03', ['old-b', 'old-a'], now);
      await _plans(repository, '2026-09-04', ['today-a', 'today-b'], now);

      await repository.initializeDayFromPrevious(
        previousDayKey: '2026-09-03',
        currentDayKey: '2026-09-04',
        initializedAt: now,
      );
      await repository.addEventDayPlan(
        EventDayPlan(
          eventId: 'later',
          dayKey: '2026-09-04',
          order: 4,
          createdAt: now,
        ),
      );

      expect(
        (await repository.getEventDayPlans('2026-09-04')).map((p) => p.eventId),
        ['today-a', 'today-b', 'old-b', 'old-a', 'later'],
      );
    },
  );

  test(
    'same-day removal and completed restoration never re-trigger carry-over',
    () async {
      for (final entry in {
        'paused': EventStatus.paused,
        'completed': EventStatus.completed,
      }.entries) {
        await repository.insertEvent(
          JaxEvent(
            id: entry.key,
            name: entry.key,
            status: entry.value,
            completedAt: entry.value == EventStatus.completed ? now : null,
            createdAt: now,
            updatedAt: now,
          ),
        );
      }
      await _plans(repository, '2026-09-03', ['paused', 'completed'], now);
      await repository.initializeDayFromPrevious(
        previousDayKey: '2026-09-03',
        currentDayKey: '2026-09-04',
        initializedAt: now,
      );
      await repository.removeEventDayPlan('paused', '2026-09-04');
      await repository.restoreCompletedEvents([
        (await repository.getEvent('completed'))!.copyWith(
          status: EventStatus.paused,
          completedAt: null,
          updatedAt: now.add(const Duration(minutes: 1)),
        ),
      ]);
      await repository.initializeDayFromPrevious(
        previousDayKey: '2026-09-03',
        currentDayKey: '2026-09-04',
        initializedAt: now.add(const Duration(minutes: 1)),
      );

      expect(await repository.getEventDayPlans('2026-09-04'), isEmpty);
    },
  );

  test(
    'failure rolls back both carry-over rows and initialization marker',
    () async {
      for (final id in ['good', 'bad']) {
        await repository.insertEvent(
          JaxEvent(
            id: id,
            name: id,
            status: EventStatus.pending,
            createdAt: now,
            updatedAt: now,
          ),
        );
      }
      await _plans(repository, '2026-09-03', ['good', 'bad'], now);
      await app.database.execute('''CREATE TRIGGER fail_test_carry_over
      BEFORE INSERT ON event_day_plans
      WHEN NEW.day_date = '2026-09-04' AND NEW.event_id = 'bad'
      BEGIN SELECT RAISE(ABORT, 'injected failure'); END''');

      await expectLater(
        repository.initializeDayFromPrevious(
          previousDayKey: '2026-09-03',
          currentDayKey: '2026-09-04',
          initializedAt: now,
        ),
        throwsA(anything),
      );
      expect(await repository.getEventDayPlans('2026-09-04'), isEmpty);
      expect(
        await app.database.query('jax_day_carry_over_initializations'),
        isEmpty,
      );
    },
  );

  test(
    'planned Event eligibility ignores focus and ended Plan state',
    () async {
      final timestamp = now.millisecondsSinceEpoch;
      await app.database.insert('world_nodes', {
        'id': 'world',
        'name': 'World',
        'status': 'inProgress',
        'is_focused': 0,
        'parent_world_node_id': null,
        'sort_order': 0,
        'category_id': null,
        'created_at_utc': timestamp,
        'updated_at_utc': timestamp,
      });
      await app.database.insert('plans', {
        'id': 'ended-plan',
        'world_node_id': 'world',
        'title': 'Ended',
        'status': 'ended',
        'round_number': 1,
        'ended_at_utc': timestamp,
        'created_at_utc': timestamp,
        'updated_at_utc': timestamp,
      });
      await app.database.insert('plan_items', {
        'id': 'dispatched-item',
        'plan_id': 'ended-plan',
        'title': 'Planned',
        'note': null,
        'status': 'dispatched',
        'sort_order': 0,
        'created_at_utc': timestamp,
        'updated_at_utc': timestamp,
      });
      await repository.insertEvent(
        JaxEvent(
          id: 'planned-event',
          name: 'Planned',
          status: EventStatus.paused,
          sourcePlanItemId: 'dispatched-item',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await _plans(repository, '2026-09-03', ['planned-event'], now);

      await repository.initializeDayFromPrevious(
        previousDayKey: '2026-09-03',
        currentDayKey: '2026-09-04',
        initializedAt: now,
      );

      expect(
        (await repository.getEventDayPlans('2026-09-04')).single.eventId,
        'planned-event',
      );
      expect((await app.database.query('plans')).single['status'], 'ended');
      expect(
        (await app.database.query('plan_items')).single['status'],
        'dispatched',
      );
      expect((await app.database.query('world_nodes')).single['is_focused'], 0);
    },
  );

  test(
    'separate devices derive the same sync identity and list order',
    () async {
      final dir = await Directory.systemTemp.createTemp('jax-other-device-');
      addTearDown(() => dir.delete(recursive: true));
      final other = await AppDatabase.open('${dir.path}/jax.db');
      addTearDown(other.close);
      final otherRepository = SqliteEventRepository(other);
      for (final target in [repository, otherRepository]) {
        await target.insertEvent(
          JaxEvent(
            id: 'shared-event',
            name: 'Shared',
            status: EventStatus.waiting,
            createdAt: now,
            updatedAt: now,
          ),
        );
        await _plans(target, '2026-09-03', ['shared-event'], now);
      }
      await repository.initializeDayFromPrevious(
        previousDayKey: '2026-09-03',
        currentDayKey: '2026-09-04',
        initializedAt: now,
      );
      await otherRepository.initializeDayFromPrevious(
        previousDayKey: '2026-09-03',
        currentDayKey: '2026-09-04',
        initializedAt: now.add(const Duration(minutes: 7)),
      );

      final left = await SqliteSyncSnapshotAdapter(app.database).read();
      final right = await SqliteSyncSnapshotAdapter(other.database).read();
      final leftPlan = left.records.singleWhere(
        (record) =>
            record.kind == SyncEntityKind.eventDayPlan &&
            record.payload['jaxDay'] == '2026-09-04',
      );
      final rightPlan = right.records.singleWhere(
        (record) =>
            record.kind == SyncEntityKind.eventDayPlan &&
            record.payload['jaxDay'] == '2026-09-04',
      );
      expect(leftPlan.metadata.id, 'shared-event@2026-09-04');
      expect(rightPlan.metadata.id, leftPlan.metadata.id);
      expect(rightPlan.payload, leftPlan.payload);
      final leftList = left.lists.singleWhere(
        (list) =>
            list.kind == SyncListKind.eventDayPlans &&
            list.scopeId == '2026-09-04',
      );
      final rightList = right.lists.singleWhere(
        (list) =>
            list.kind == SyncListKind.eventDayPlans &&
            list.scopeId == '2026-09-04',
      );
    expect(rightList.itemIds, leftList.itemIds);
    },
  );

  test(
    'v18 migration only adds empty carry-over initialization state',
    () async {
      await app.close();
      sqfliteFfiInit();
      final dir = await Directory.systemTemp.createTemp('jax-v19-migration-');
      final path = '${dir.path}/jax.db';
      var old = await AppDatabase.open(path);
      await old.database.insert('events', {
        'id': 'preserved',
        'name': 'preserved',
        'status': 'paused',
        'source_plan_item_id': null,
        'category_id': null,
        'first_started_at_utc': null,
        'completed_at_utc': null,
        'created_at_utc': 1,
        'updated_at_utc': 1,
      });
      await old.database.execute(
        'DROP TABLE jax_day_carry_over_initializations',
      );
      await old.database.execute('PRAGMA user_version = 18');
      await old.close();

      final migrated = await AppDatabase.open(path);
      expect(
        (await migrated.database.query('events')).single['id'],
        'preserved',
      );
      expect(
        await migrated.database.query('jax_day_carry_over_initializations'),
        isEmpty,
      );
      expect(
        (await migrated.database.rawQuery('PRAGMA user_version'))
            .single['user_version'],
        19,
      );
      await migrated.close();
      await dir.delete(recursive: true);
      app = await AppDatabase.inMemory();
    },
  );
}

Future<void> _plans(
  SqliteEventRepository repository,
  String day,
  List<String> ids,
  DateTime now,
) async {
  for (var i = 0; i < ids.length; i++) {
    await repository.addEventDayPlan(
      EventDayPlan(eventId: ids[i], dayKey: day, order: i, createdAt: now),
    );
  }
}
