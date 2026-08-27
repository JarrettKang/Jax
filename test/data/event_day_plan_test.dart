import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/event_day_plan.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/repositories/sqlite_event_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test(
    'v8 stores unique day plans and reorders independently of World',
    () async {
      final db = await AppDatabase.inMemory();
      final repository = SqliteEventRepository(db);
      final now = DateTime.utc(2026, 8, 27);
      for (var i = 0; i < 3; i++) {
        await repository.insertEvent(
          JaxEvent(
            id: 'e$i',
            name: 'E$i',
            status: EventStatus.pending,
            sortOrder: i,
            createdAt: now.add(Duration(seconds: i)),
            updatedAt: now,
          ),
        );
      }
      await repository.addEventDayPlan(
        EventDayPlan(
          eventId: 'e2',
          dayKey: '2026-08-27',
          order: 0,
          createdAt: now,
        ),
      );
      await repository.addEventDayPlan(
        EventDayPlan(
          eventId: 'e0',
          dayKey: '2026-08-27',
          order: 1,
          createdAt: now,
        ),
      );
      await repository.addEventDayPlan(
        EventDayPlan(
          eventId: 'e0',
          dayKey: '2026-08-27',
          order: 9,
          createdAt: now,
        ),
      );
      await repository.addEventDayPlans([
        EventDayPlan(
          eventId: 'e1',
          dayKey: '2026-08-27',
          order: 2,
          createdAt: now,
        ),
        EventDayPlan(
          eventId: 'e0',
          dayKey: '2026-08-27',
          order: 3,
          createdAt: now,
        ),
      ]);
      expect(
        (await repository.getEventDayPlans('2026-08-27')).map((p) => p.eventId),
        ['e2', 'e0', 'e1'],
      );
      await repository.reorderEventDayPlan('e0', '2026-08-27', 0);
      expect(
        (await repository.getEventDayPlans('2026-08-27')).map((p) => p.eventId),
        ['e0', 'e2', 'e1'],
      );
      expect((await repository.getOrderedTopLevelEvents()).map((e) => e.id), [
        'e0',
        'e1',
        'e2',
      ]);
      await repository.removeEventDayPlan('e0', '2026-08-27');
      expect(
        (await repository.getEventDayPlans('2026-08-27')).map((p) => p.eventId),
        ['e2', 'e1'],
      );
      await db.close();
    },
  );

  test(
    'v7 migration preserves existing Event and starts with no plans',
    () async {
      sqfliteFfiInit();
      final dir = await Directory.systemTemp.createTemp('jax-today-migration-');
      final path = '${dir.path}/jax.db';
      final old = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 7,
          onCreate: (db, _) async {
            await db.execute(
              'CREATE TABLE events (id TEXT PRIMARY KEY,name TEXT NOT NULL,status TEXT NOT NULL,parent_event_id TEXT,sort_order INTEGER,category_id TEXT,first_started_at_utc INTEGER,completed_at_utc INTEGER,created_at_utc INTEGER NOT NULL,updated_at_utc INTEGER NOT NULL)',
            );
            await db.insert('events', {
              'id': 'old',
              'name': '旧事件',
              'status': 'paused',
              'sort_order': 0,
              'created_at_utc': 1,
              'updated_at_utc': 1,
            });
          },
        ),
      );
      await old.close();
      final app = await AppDatabase.open(path);
      expect((await app.database.query('events')).single['name'], '旧事件');
      expect(await app.database.query('event_day_plans'), isEmpty);
      expect(
        (await app.database.rawQuery('PRAGMA user_version'))
            .single['user_version'],
        AppDatabase.schemaVersion,
      );
      await app.close();
      await dir.delete(recursive: true);
    },
  );
}
