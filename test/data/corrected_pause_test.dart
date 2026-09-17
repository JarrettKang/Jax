import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/entities/run_segment.dart';
import 'package:jax/core/entities/routine.dart';
import 'package:jax/core/errors/domain_failure.dart';
import 'package:jax/core/services/execution_segment_service.dart';
import 'package:jax/core/services/routine_service.dart';
import 'package:jax/core/sync/sync_mutation_plan.dart';
import 'package:jax/core/sync/sync_compare_engine.dart';
import 'package:jax/core/sync/resolved_sync_plan.dart';
import 'package:jax/core/sync/sync_plan_compiler.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/repositories/sqlite_event_repository.dart';
import 'package:jax/data/repositories/sqlite_planning_repository.dart';
import 'package:jax/data/sync/sqlite_sync_snapshot_adapter.dart';
import 'package:jax/data/sync/sqlite_sync_mutation_executor.dart';
import 'package:jax/ui/controllers/event_controller.dart';

import '../support/world_map_fixture.dart';

void main() {
  late AppDatabase db;
  late SqliteEventRepository repo;
  late EventController c;
  late DateTime now;
  var id = 0;
  final start = DateTime(2026, 9, 15, 13);
  final end = DateTime(2026, 9, 15, 14, 5);
  setUp(() async {
    db = await AppDatabase.inMemory();
    repo = SqliteEventRepository(db);
    now = start;
    id = 0;
    c = EventController(
      repository: repo,
      now: () => now,
      newId: () => 'new-${id++}',
    );
  });
  tearDown(() async {
    c.dispose();
    await db.close();
  });

  Future<void> event({bool planned = false}) async {
    if (planned) {
      await seedWorldMapFixture(db);
      await SqlitePlanningRepository(db).dispatchPlanItems(
        eventIdsByPlanItemId: {'fixture-step-0': 'event'},
        dayKey: '2026-09-15',
        now: now,
      );
    } else {
      await repo.insertEvent(
        JaxEvent(
          id: 'event',
          name: 'Event',
          status: EventStatus.pending,
          createdAt: start,
          updatedAt: start,
        ),
      );
    }
    await c.load();
    expect(await c.start('event'), isNull);
    now = DateTime(2026, 9, 15, 14, 20);
  }

  Future<Routine> routine(RoutineType type) async {
    final service = RoutineService(
      repository: repo,
      now: () => now,
      newId: () => 'new-${id++}',
    );
    await service.create(
      'Routine',
      null,
      RoutineRecurrence.daily,
      0,
      type: type,
    );
    final r = (await repo.getRoutines()).single;
    await service.start(r);
    await c.load();
    now = DateTime(2026, 9, 15, 14, 20);
    return r;
  }

  for (final planned in [false, true]) {
    test(
      'Event planned=$planned corrects 65 minutes and resumes a new segment',
      () async {
        await event(planned: planned);
        final first = (await repo.getRunSegments('event')).single;
        expect(await c.pauseAt('event', end), isNull);
        expect((await repo.getEvent('event'))!.status, EventStatus.paused);
        expect(c.runningEvent, isNull);
        final records = await ExecutionSegmentService(
          repository: repo,
          now: () => now,
        ).forJaxDay(now);
        expect(records.single.endedAt, end.toUtc());
        expect(
          (await repo.getRunSegments('event')).single.durationAt(now),
          const Duration(minutes: 65),
        );
        if (planned) {
          expect(
            (await db.database.query(
              'plan_items',
              where: 'id = ?',
              whereArgs: ['fixture-step-0'],
            )).single['status'],
            'dispatched',
          );
        }
        now = DateTime(2026, 9, 15, 15);
        expect(await c.resume('event'), isNull);
        final segments = await repo.getRunSegments('event');
        expect(segments, hasLength(2));
        expect(
          segments.singleWhere((s) => s.id == first.id).endedAt,
          end.toUtc(),
        );
        expect(
          segments.singleWhere((s) => s.endedAt == null).startedAt,
          now.toUtc(),
        );
        expect(c.elapsedFor(c.runningEvent!), const Duration(minutes: 65));
      },
    );
  }

  for (final type in RoutineType.values) {
    test(
      '$type corrects, releases running slot and resumes original occurrence',
      () async {
        final r = await routine(type);
        final original = (await repo.getRoutineExecutions()).single;
        expect(await c.pauseRoutineAt(r, end), isNull);
        expect(
          (await repo.getRoutineExecutions()).single.status,
          RoutineExecutionStatus.paused,
        );
        expect(await repo.getRunningRoutineExecution(), isNull);
        expect(
          (await repo.getRoutineRunSegments(original.id)).single
              .durationAt(now),
          const Duration(minutes: 65),
        );
        now = DateTime(2026, 9, 15, 15);
        final service = RoutineService(
          repository: repo,
          now: () => now,
          newId: () => 'new-${id++}',
        );
        await service.start(
          r,
          execution: (await repo.getRoutineExecutions()).single,
        );
        expect((await repo.getRoutineExecutions()).single.id, original.id);
        final segments = await repo.getRoutineRunSegments(original.id);
        expect(segments, hasLength(2));
        expect(
          segments.singleWhere((s) => s.endedAt != null).endedAt,
          end.toUtc(),
        );
        expect(
          segments.singleWhere((s) => s.endedAt == null).startedAt,
          now.toUtc(),
        );
      },
    );
  }

  test(
    'invalid range and cross-type overlap reject without partial writes',
    () async {
      final r = await routine(RoutineType.scheduled);
      expect(await c.pauseRoutineAt(r, start), isNotNull);
      expect(
        await c.pauseRoutineAt(r, start.subtract(const Duration(minutes: 1))),
        isNotNull,
      );
      expect(
        await c.pauseRoutineAt(r, now.add(const Duration(minutes: 1))),
        isNotNull,
      );
      await repo.insertEvent(
        JaxEvent(
          id: 'other',
          name: 'Other',
          status: EventStatus.paused,
          createdAt: start,
          updatedAt: start,
        ),
      );
      await repo.insertHistoricalRunSegment(
        RunSegment(
          id: 'other-segment',
          eventId: 'other',
          startedAt: DateTime(2026, 9, 15, 14, 10).toUtc(),
          endedAt: now.toUtc(),
          createdAt: start.toUtc(),
        ),
      );
      expect(
        await c.pauseRoutineAt(r, DateTime(2026, 9, 15, 14, 15)),
        contains('重叠'),
      );
      expect(
        (await repo.getRoutineExecutions()).single.status,
        RoutineExecutionStatus.running,
      );
      expect((await repo.getAllRoutineRunSegments()).single.endedAt, isNull);
      // Shortening before the unrelated closed interval is valid.
      expect(await c.pauseRoutineAt(r, end), isNull);
    },
  );

  test('captured action rejects stale Sync revision, missing open and resumed segment', () async {
    await event();
    final action = c.correctedEventEndAction('event', pause: true);
    final e = (await repo.getEvent('event'))!;
    await repo.updateEvent(e.copyWith(updatedAt: now.toUtc(), name: 'Synced'));
    expect(await action(end), contains('发生变化'));
    expect((await repo.getRunSegments('event')).single.endedAt, isNull);
    await c.load();
    final beforeResume = c.correctedEventEndAction('event', pause: true);
    expect(await c.pause('event'), isNull);
    now = DateTime(2026, 9, 15, 15);
    expect(await c.resume('event'), isNull);
    expect(await beforeResume(now), contains('发生变化'));
    await db.database.delete('run_segments', where: 'ended_at_utc IS NULL');
    expect(await c.pauseAt('event', now), isNotNull);
    expect((await repo.getEvent('event'))!.status, EventStatus.running);
  });

  test('transaction rejects raced start, revision, overlap and rolls back a write failure', () async {
    await event();
    final e = (await repo.getEvent('event'))!;
    final s = (await repo.getRunSegments('event')).single;
    Future<void> commit({DateTime? expected, RunSegment? segment}) =>
        repo.pauseEvent(
          e.copyWith(status: EventStatus.paused, updatedAt: now.toUtc()),
          segment ?? s.copyWith(endedAt: end.toUtc()),
          expectedUpdatedAt: expected ?? e.updatedAt,
        );
    await expectLater(commit(expected: now), throwsA(isA<DomainFailure>()));
    await expectLater(
      commit(
        segment: s.copyWith(
          startedAt: start.add(const Duration(minutes: 1)).toUtc(),
          endedAt: end.toUtc(),
        ),
      ),
      throwsA(isA<DomainFailure>()),
    );
    await expectLater(
      commit(
        segment: s.copyWith(
          endedAt: now.add(const Duration(minutes: 1)).toUtc(),
        ),
      ),
      throwsA(isA<DomainFailure>()),
    );
    await db.database.execute(
      "CREATE TRIGGER reject_pause_segment BEFORE UPDATE ON run_segments BEGIN SELECT RAISE(ABORT, 'injected failure'); END",
    );
    await expectLater(commit(), throwsA(anything));
    expect((await repo.getEvent('event'))!.status, EventStatus.running);
    expect((await repo.getRunSegments('event')).single.endedAt, isNull);
    await db.database.execute('DROP TRIGGER reject_pause_segment');
    await commit();
    expect((await repo.getEvent('event'))!.status, EventStatus.paused);
  });

  test('corrected completion uses same closure while retaining completion semantics', () async {
    await event(planned: true);
    expect(await c.completeAt('event', end), isNull);
    expect((await repo.getEvent('event'))!.completedAt, end.toUtc());
    expect((await repo.getEvent('event'))!.status, EventStatus.completed);
    expect(
      (await db.database.query(
        'plan_items',
        where: 'id = ?',
        whereArgs: ['fixture-step-0'],
      )).single['status'],
      'done',
    );
  });

  test('Routine transaction validates overlaps and rolls back both writes on failure', () async {
    await routine(RoutineType.onDemand);
    final e = (await repo.getRoutineExecutions()).single;
    final s = (await repo.getRoutineRunSegments(e.id)).single;
    Future<void> commit() => repo.pauseRoutineExecution(
      e.copyWith(status: RoutineExecutionStatus.paused, updatedAt: now.toUtc()),
      s.copyWith(endedAt: end.toUtc()),
      expectedUpdatedAt: e.updatedAt,
    );
    await repo.insertEvent(
      JaxEvent(
        id: 'other',
        name: 'Other',
        status: EventStatus.paused,
        createdAt: start,
        updatedAt: start,
      ),
    );
    await repo.insertHistoricalRunSegment(
      RunSegment(
        id: 'overlap',
        eventId: 'other',
        startedAt: start.add(const Duration(minutes: 10)).toUtc(),
        endedAt: end.toUtc(),
        createdAt: start.toUtc(),
      ),
    );
    await expectLater(commit(), throwsA(isA<DomainFailure>()));
    expect(
      (await repo.getRoutineExecutions()).single.status,
      RoutineExecutionStatus.running,
    );
    expect((await repo.getRoutineRunSegments(e.id)).single.endedAt, isNull);
    await db.database.delete(
      'run_segments',
      where: 'id = ?',
      whereArgs: ['overlap'],
    );
    await db.database.execute(
      "CREATE TRIGGER reject_routine_pause BEFORE UPDATE ON routine_run_segments BEGIN SELECT RAISE(ABORT, 'injected failure'); END",
    );
    await expectLater(commit(), throwsA(anything));
    expect(
      (await repo.getRoutineExecutions()).single.status,
      RoutineExecutionStatus.running,
    );
    expect((await repo.getRoutineRunSegments(e.id)).single.endedAt, isNull);
  });

  test(
    'Event rejects equal, earlier, future and conflicting closed segment',
    () async {
      await event();
      for (final invalid in [
        start,
        start.subtract(const Duration(milliseconds: 1)),
        now.add(const Duration(milliseconds: 1)),
      ]) {
        expect(await c.pauseAt('event', invalid), isNotNull);
      }
      await repo.insertEvent(
        JaxEvent(
          id: 'other',
          name: 'Other',
          status: EventStatus.paused,
          createdAt: start,
          updatedAt: start,
        ),
      );
      await repo.insertHistoricalRunSegment(
        RunSegment(
          id: 'overlap',
          eventId: 'other',
          startedAt: start.toUtc(),
          endedAt: end.toUtc(),
          createdAt: start.toUtc(),
        ),
      );
      expect(await c.pauseAt('event', end), contains('重叠'));
      final e = (await repo.getEvent('event'))!;
      final s = (await repo.getRunSegments('event')).single;
      await expectLater(
        repo.pauseEvent(
          e.copyWith(status: EventStatus.paused, updatedAt: now.toUtc()),
          s.copyWith(endedAt: end.toUtc()),
          expectedUpdatedAt: e.updatedAt,
        ),
        throwsA(isA<DomainFailure>()),
      );
      expect((await repo.getEvent('event'))!.status, EventStatus.running);
      expect((await repo.getRunSegments('event')).single.endedAt, isNull);
    },
  );

  test('Routine corrected completion retains real completion time', () async {
    final r = await routine(RoutineType.onDemand);
    expect(await c.completeRoutineAt(r, end), isNull);
    final execution = (await repo.getRoutineExecutions()).single;
    expect(execution.status, RoutineExecutionStatus.completed);
    expect(execution.completedAt, end.toUtc());
    expect(
      (await repo.getRoutineRunSegments(execution.id)).single.durationAt(now),
      const Duration(minutes: 65),
    );
  });

  test(
    'captured Routine occurrence remains original across JaxDay boundary',
    () async {
      now = DateTime(2026, 9, 15, 22, 30);
      final r = await routine(RoutineType.scheduled);
      final original = (await repo.getRoutineExecutions()).single;
      final action = c.correctedRoutineEndAction(r, pause: true);
      now = DateTime(2026, 9, 16, 0, 45);
      await c.load();
      final corrected = DateTime(2026, 9, 16, 0, 30);
      expect(await action(corrected), isNull);
      final execution = (await repo.getRoutineExecutions()).single;
      expect(execution.id, original.id);
      expect(execution.occurrenceDate, original.occurrenceDate);
      expect(execution.status, RoutineExecutionStatus.paused);
      expect(
        (await repo.getRoutineRunSegments(original.id)).single.endedAt,
        corrected.toUtc(),
      );
    },
  );

  for (final reverse in [false, true]) {
    for (final isRoutine in [false, true]) {
      test(
        'Sync ${reverse ? 'Android to Windows' : 'Windows to Android'} routine=$isRoutine preserves corrected facts',
        () async {
          Routine? r;
          if (isRoutine) {
            r = await routine(RoutineType.scheduled);
          } else {
            await event();
          }
          final baseline = await SqliteSyncSnapshotAdapter(db.database).read();
          final other = await AppDatabase.inMemory();
          addTearDown(other.close);
          await other.database.update('dataset_metadata', {
            'generation': baseline.datasetGeneration,
          });
          const executor = SqliteSyncMutationExecutor();
          await executor.applyDatabase(other, [
            for (final record in baseline.records)
              SyncMutation.upsertRecord(record),
            for (final list in baseline.lists) SyncMutation.applyList(list),
          ]);
          expect(
            isRoutine
                ? await c.pauseRoutineAt(r!, end)
                : await c.pauseAt('event', end),
            isNull,
          );
          final source = await SqliteSyncSnapshotAdapter(db.database).read();
          final target = await SqliteSyncSnapshotAdapter(other.database).read();
          final w = reverse ? target : source, a = reverse ? source : target;
          final preview = const SyncCompareEngine().compare(
            windows: w,
            android: a,
            baseline: baseline,
          );
          final plan = const SyncPlanCompiler().compile(
            resolved: ResolvedSyncPlan(preview: preview),
            windows: w,
            android: a,
            baseline: baseline,
          );
          await executor.applyDatabase(
            other,
            reverse ? plan.windowsOperations : plan.androidOperations,
          );
          final synced = await SqliteSyncSnapshotAdapter(other.database).read();
          expect(
            synced.businessFingerprintSha256,
            source.businessFingerprintSha256,
          );
          expect(synced.protocolVersion, 11);
          final otherRepo = SqliteEventRepository(other);
          if (isRoutine) {
            expect(
              (await otherRepo.getRoutineExecutions()).single.status,
              RoutineExecutionStatus.paused,
            );
            expect(
              (await otherRepo.getAllRoutineRunSegments()).single.durationAt(
                now,
              ),
              const Duration(minutes: 65),
            );
          } else {
            expect(
              (await otherRepo.getEvent('event'))!.status,
              EventStatus.paused,
            );
            expect(
              (await otherRepo.getRunSegments('event')).single.durationAt(now),
              const Duration(minutes: 65),
            );
          }
        },
      );
    }
  }
}
