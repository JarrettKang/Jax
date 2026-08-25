import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/entities/run_segment.dart';
import 'package:jax/core/use_cases/start_event.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/repositories/sqlite_event_repository.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android sqflite migrates v2 hierarchy data to v3', (
    tester,
  ) async {
    expect(Platform.isAndroid, isTrue);
    final databasePath = path.join(
      await getDatabasesPath(),
      'jax-v2-v3-${DateTime.now().microsecondsSinceEpoch}.db',
    );
    addTearDown(() => deleteDatabase(databasePath));
    final time = DateTime.utc(2026, 8, 25, 8);
    final old = await databaseFactory.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (database, _) async {
          await database.execute('''CREATE TABLE events (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL CHECK(length(trim(name)) > 0),
            status TEXT NOT NULL CHECK(status IN ('pending','running','paused','completed')),
            first_started_at_utc INTEGER,
            completed_at_utc INTEGER,
            created_at_utc INTEGER NOT NULL,
            updated_at_utc INTEGER NOT NULL
          )''');
          await database.execute('''CREATE TABLE run_segments (
            id TEXT PRIMARY KEY,
            event_id TEXT NOT NULL REFERENCES events(id) ON DELETE CASCADE,
            started_at_utc INTEGER NOT NULL,
            ended_at_utc INTEGER,
            created_at_utc INTEGER NOT NULL
          )''');
        },
      ),
    );
    await old.insert('events', {
      'id': 'phone-existing',
      'name': '真机旧数据模型',
      'status': 'pending',
      'created_at_utc': time.millisecondsSinceEpoch,
      'updated_at_utc': time.millisecondsSinceEpoch,
    });
    await old.close();

    final upgraded = await AppDatabase.openWithFactory(
      databasePath,
      databaseFactory,
    );
    addTearDown(upgraded.close);
    final event = await SqliteEventRepository(upgraded)
        .getEvent('phone-existing');
    final version = await upgraded.database.rawQuery('PRAGMA user_version');

    expect(version.single['user_version'], 3);
    expect(event?.name, '真机旧数据模型');
    expect(event?.parentEventId, isNull);

    JaxEvent pending(String id, {String? parent}) => JaxEvent(
      id: id,
      name: id,
      status: EventStatus.pending,
      parentEventId: parent,
      createdAt: time,
      updatedAt: time,
    );
    final repository = SqliteEventRepository(upgraded);
    await repository.insertEvent(pending('parent'));
    await repository.insertEvent(pending('child', parent: 'parent'));
    await expectLater(
      repository.updateParent('parent', 'child', time),
      throwsA(anything),
    );
    expect((await repository.getEvent('parent'))?.parentEventId, isNull);

    await repository.startEvent(
      pending('parent')
          .copyWith(status: EventStatus.running, firstStartedAt: time),
      RunSegment(
        id: 'parent-open',
        eventId: 'parent',
        startedAt: time,
        createdAt: time,
      ),
    );
    final switchedAt = time.add(const Duration(minutes: 2));
    await StartEvent(
      repository: repository,
      newId: () => 'child-open',
      now: () => switchedAt,
    )('child');
    expect((await repository.getEvent('parent'))?.status, EventStatus.paused);
    expect((await repository.getEvent('child'))?.status, EventStatus.running);
    expect(
      (await repository.getRunSegments('parent')).single.endedAt,
      switchedAt,
    );
    expect((await repository.getRunSegments('child')).single.endedAt, isNull);
  });
}
