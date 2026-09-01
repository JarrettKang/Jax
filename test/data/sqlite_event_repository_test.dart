import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/category.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/entities/routine_category.dart';
import 'package:jax/core/entities/routine.dart';
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

  test(
    'persists direct Category for standalone Events',
    () async {
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
    },
  );
}
