import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/category.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/entities/run_segment.dart';
import 'package:jax/core/entities/routine_category.dart';
import 'package:jax/core/entities/routine.dart';
import 'package:jax/core/errors/domain_failure.dart';
import 'package:jax/core/use_cases/create_event.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/repositories/sqlite_event_repository.dart';

void main() {
  late AppDatabase database;
  late SqliteEventRepository repository;

  setUp(() async {
    database = await AppDatabase.inMemory();
    repository = SqliteEventRepository(database);
  });

  tearDown(() => database.close());

  test('persists and reloads pending events by id', () async {
    final createdAt = DateTime.utc(2026, 8, 24, 12);
    final event = JaxEvent(
      id: 'event-1',
      name: '读书',
      status: EventStatus.pending,
      createdAt: createdAt,
      updatedAt: createdAt,
    );

    await repository.insertEvent(event);
    final loaded = await repository.getIncompleteEvents();

    expect(loaded, [event]);
  });

  test('repeated Routine start cannot create a second open segment', () async {
    final time = DateTime.utc(2026, 8, 30, 10);
    final routine = Routine(
      id: 'routine',
      name: '日常',
      recurrence: RoutineRecurrence.daily,
      weekdayMask: 0,
      isActive: true,
      sortOrder: 0,
      createdAt: time,
      updatedAt: time,
    );
    final execution = RoutineExecution(
      id: 'execution',
      routineId: routine.id,
      occurrenceDate: '2026-08-30',
      status: RoutineExecutionStatus.running,
      createdAt: time,
      updatedAt: time,
    );
    await repository.insertRoutine(routine);
    await repository.startRoutineExecution(
      execution,
      RoutineRunSegment(
        id: 'segment-1',
        executionId: execution.id,
        startedAt: time,
        createdAt: time,
      ),
      time,
    );

    await expectLater(
      repository.startRoutineExecution(
        execution,
        RoutineRunSegment(
          id: 'segment-2',
          executionId: execution.id,
          startedAt: time,
          createdAt: time,
        ),
        time,
      ),
      throwsA(isA<StateError>()),
    );
    final segments = await repository.getRoutineRunSegments(execution.id);
    expect(segments, hasLength(1));
    expect(segments.single.endedAt, isNull);
  });

  test('persists Routine Category colorKey', () async {
    final timestamp = DateTime.utc(2026, 8, 24, 12);
    await repository.insertRoutineCategory(
      RoutineCategory(
        id: 'daily',
        name: '日常',
        sortOrder: 0,
        createdAt: timestamp,
        updatedAt: timestamp,
        colorKey: 7,
      ),
    );
    expect((await repository.getRoutineCategories()).single.colorKey, 7);
  });

  test('persists direct Category for standalone Events', () async {
    final createdAt = DateTime.utc(2026, 8, 24, 12);
    await repository.insertCategory(
      Category(
        id: 'research',
        name: '科研',
        sortOrder: 0,
        createdAt: createdAt,
        updatedAt: createdAt,
        colorKey: 5,
      ),
    );
    var nextId = 0;
    final create = CreateEvent(
      repository: repository,
      newId: () => 'event-${nextId++}',
      now: () => createdAt,
    );

    final root = await create('测试 Yukawa', categoryId: 'research');
    final second = await create('测试截断距离', categoryId: 'research');

    expect((await repository.getEvent(root.id))!.categoryId, 'research');
    expect((await repository.getCategories()).single.colorKey, 5);
    final storedSecond = (await repository.getEvent(second.id))!;
    expect(storedSecond.sourcePlanItemId, isNull);
    expect(storedSecond.categoryId, 'research');
  });

  test(
    'atomically corrects one Event open segment and advances sync metadata',
    () async {
      final previousStart = DateTime.utc(2026, 9, 1, 9, 50);
      final boundary = DateTime.utc(2026, 9, 1, 10, 10);
      final original = DateTime.utc(2026, 9, 1, 10, 20);
      final now = DateTime.utc(2026, 9, 1, 11);
      final previous = JaxEvent(
        id: 'previous',
        name: '检查超算',
        status: EventStatus.completed,
        createdAt: previousStart,
        updatedAt: boundary,
        completedAt: boundary,
      );
      final pending = JaxEvent(
        id: 'current',
        name: '开发',
        status: EventStatus.pending,
        createdAt: original,
        updatedAt: original,
      );
      await repository.insertEvent(previous);
      await repository.insertHistoricalRunSegment(
        RunSegment(
          id: 'previous-segment',
          eventId: previous.id,
          startedAt: previousStart,
          endedAt: boundary,
          createdAt: previousStart,
        ),
      );
      await repository.insertEvent(pending);
      await repository.startEvent(
        pending.copyWith(
          status: EventStatus.running,
          updatedAt: original,
          firstStartedAt: original,
        ),
        RunSegment(
          id: 'open-segment',
          eventId: pending.id,
          startedAt: original,
          createdAt: original,
        ),
      );

      await expectLater(
        repository.adjustRunningEventStart(
          eventId: pending.id,
          segmentId: 'open-segment',
          expectedStartedAt: original,
          newStartedAt: DateTime.utc(2026, 9, 1, 10),
          updatedAt: now,
        ),
        throwsA(
          isA<DomainFailure>().having(
            (failure) => failure.message,
            'message',
            contains('检查超算'),
          ),
        ),
      );
      expect(
        (await repository.getRunSegments(pending.id)).single.startedAt,
        original,
      );

      await repository.adjustRunningEventStart(
        eventId: pending.id,
        segmentId: 'open-segment',
        expectedStartedAt: original,
        newStartedAt: boundary,
        updatedAt: now,
      );

      final segments = await repository.getAllRunSegments();
      final adjusted = segments.singleWhere(
        (item) => item.id == 'open-segment',
      );
      expect(segments, hasLength(2));
      expect(adjusted.startedAt, boundary);
      expect(adjusted.endedAt, isNull);
      final row = (await database.database.query(
        'run_segments',
        where: 'id = ?',
        whereArgs: ['open-segment'],
      )).single;
      expect(row['updated_at_utc'], now.millisecondsSinceEpoch);
    },
  );

  test(
    'atomically corrects one Routine open segment without changing owner',
    () async {
      final original = DateTime.utc(2026, 9, 1, 10, 20);
      final corrected = DateTime.utc(2026, 9, 1, 10, 5);
      final now = DateTime.utc(2026, 9, 1, 11);
      final routine = Routine(
        id: 'routine-correction',
        name: '拉伸',
        type: RoutineType.onDemand,
        recurrence: RoutineRecurrence.daily,
        weekdayMask: 0,
        isActive: true,
        sortOrder: 0,
        createdAt: original,
        updatedAt: original,
      );
      final execution = RoutineExecution(
        id: 'routine-execution',
        routineId: routine.id,
        occurrenceDate: '2026-09-01',
        status: RoutineExecutionStatus.running,
        createdAt: original,
        updatedAt: original,
      );
      await repository.insertRoutine(routine);
      await repository.startRoutineExecution(
        execution,
        RoutineRunSegment(
          id: 'routine-open',
          executionId: execution.id,
          startedAt: original,
          createdAt: original,
        ),
        original,
      );

      await repository.adjustRunningRoutineStart(
        executionId: execution.id,
        segmentId: 'routine-open',
        expectedStartedAt: original,
        newStartedAt: corrected,
        updatedAt: now,
      );

      final segments = await repository.getRoutineRunSegments(execution.id);
      expect(segments, hasLength(1));
      expect(segments.single.id, 'routine-open');
      expect(segments.single.startedAt, corrected);
      expect(segments.single.endedAt, isNull);
      expect((await repository.getRunningRoutineExecution())?.id, execution.id);
    },
  );
}
