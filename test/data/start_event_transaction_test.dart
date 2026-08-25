import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/entities/run_segment.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/repositories/sqlite_event_repository.dart';

void main() {
  test('atomically stores running state and open segment', () async {
    final db = await AppDatabase.inMemory();
    addTearDown(db.close);
    final repository = SqliteEventRepository(db);
    final time = DateTime.utc(2026);
    final pending = JaxEvent(
      id: 'event',
      name: '任务',
      status: EventStatus.pending,
      createdAt: time,
      updatedAt: time,
    );
    await repository.insertEvent(pending);
    final running = pending.copyWith(
      status: EventStatus.running,
      firstStartedAt: time,
    );
    final segment = RunSegment(
      id: 'segment',
      eventId: 'event',
      startedAt: time,
      createdAt: time,
    );
    await repository.startEvent(running, segment);
    expect((await repository.getEvent('event'))!.status, EventStatus.running);
    expect(await repository.getRunSegments('event'), [segment]);
  });

  test('atomically switches running event to a descendant', () async {
    final db = await AppDatabase.inMemory();
    addTearDown(db.close);
    final repository = SqliteEventRepository(db);
    final start = DateTime.utc(2026, 8, 25, 10);
    final switchedAt = start.add(const Duration(minutes: 4));
    final root = JaxEvent(
      id: 'root',
      name: 'root',
      status: EventStatus.running,
      firstStartedAt: start,
      createdAt: start,
      updatedAt: start,
    );
    final leaf = JaxEvent(
      id: 'leaf',
      name: 'leaf',
      status: EventStatus.pending,
      parentEventId: root.id,
      createdAt: start,
      updatedAt: start,
    );
    final open = RunSegment(
      id: 'root-open',
      eventId: root.id,
      startedAt: start,
      createdAt: start,
    );
    await repository.insertEvent(root);
    await repository.insertEvent(leaf);
    await db.database.insert('run_segments', {
      'id': open.id,
      'event_id': open.eventId,
      'started_at_utc': open.startedAt.millisecondsSinceEpoch,
      'ended_at_utc': null,
      'created_at_utc': open.createdAt.millisecondsSinceEpoch,
    });

    await repository.switchRunningEvent(
      pausedRunning: root.copyWith(
        status: EventStatus.paused,
        updatedAt: switchedAt,
      ),
      closedSegment: open.copyWith(endedAt: switchedAt),
      runningTarget: leaf.copyWith(
        status: EventStatus.running,
        firstStartedAt: switchedAt,
        updatedAt: switchedAt,
      ),
      newSegment: RunSegment(
        id: 'leaf-open',
        eventId: leaf.id,
        startedAt: switchedAt,
        createdAt: switchedAt,
      ),
      pausedAncestors: const [],
    );

    expect((await repository.getEvent(root.id))?.status, EventStatus.paused);
    expect((await repository.getEvent(leaf.id))?.status, EventStatus.running);
    expect(
      (await repository.getRunSegments(root.id)).single.endedAt,
      switchedAt,
    );
    expect((await repository.getRunSegments(leaf.id)).single.endedAt, isNull);
  });
}
