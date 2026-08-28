import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/category.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/entities/run_segment.dart';
import 'package:jax/core/entities/routine.dart';
import 'package:jax/core/entities/routine_category.dart';
import 'package:jax/core/errors/domain_failure.dart';
import 'package:jax/core/services/execution_segment_service.dart';

import '../support/memory_repository.dart';

void main() {
  final now = DateTime(2026, 8, 28, 20);
  JaxEvent event(String id, {String? categoryId}) => JaxEvent(
    id: id,
    name: id,
    status: EventStatus.completed,
    createdAt: now,
    updatedAt: now,
    categoryId: categoryId,
  );
  RunSegment segment(String id, String event, int start, int end) => RunSegment(
    id: id,
    eventId: event,
    startedAt: DateTime(2026, 8, 28, start),
    endedAt: DateTime(2026, 8, 28, end),
    createdAt: now,
  );

  test('lists repeated Event and Routine segments in one chronological JaxDay list', () async {
    final repo = MemoryRepository([event('work')])
      ..segments.addAll([
        segment('first', 'work', 8, 9),
        segment('second', 'work', 13, 14),
      ]);
    repo.routines.add(
      Routine(
        id: 'meal',
        name: '午饭',
        recurrence: RoutineRecurrence.daily,
        weekdayMask: 0,
        isActive: true,
        sortOrder: 0,
        createdAt: now,
        updatedAt: now,
      ),
    );
    repo.routineExecutions.add(
      RoutineExecution(
        id: 'meal-day',
        routineId: 'meal',
        occurrenceDate: '2026-08-28',
        status: RoutineExecutionStatus.completed,
        createdAt: now,
        updatedAt: now,
      ),
    );
    repo.routineSegments.add(
      RoutineRunSegment(
        id: 'lunch',
        executionId: 'meal-day',
        startedAt: DateTime(2026, 8, 28, 12),
        endedAt: DateTime(2026, 8, 28, 13),
        createdAt: now,
      ),
    );
    final result = await ExecutionSegmentService(
      repository: repo,
      now: () => now,
    ).forJaxDay(now);
    expect(result.map((item) => item.id), ['first', 'lunch', 'second']);
  });

  test('keeps Event and Routine category identities distinct', () async {
    final repo = MemoryRepository([event('work', categoryId: 'same')])
      ..categories.add(
        Category(
          id: 'same',
          name: '生活',
          sortOrder: 0,
          createdAt: now,
          updatedAt: now,
        ),
      )
      ..segments.add(segment('event-segment', 'work', 8, 9))
      ..routineCategories.add(
        RoutineCategory(
          id: 'same',
          name: '生活',
          sortOrder: 0,
          createdAt: now,
          updatedAt: now,
        ),
      )
      ..routines.add(
        Routine(
          id: 'routine',
          name: '早餐',
          routineCategoryId: 'same',
          recurrence: RoutineRecurrence.daily,
          weekdayMask: 0,
          isActive: true,
          sortOrder: 0,
          createdAt: now,
          updatedAt: now,
        ),
      )
      ..routineExecutions.add(
        RoutineExecution(
          id: 'execution',
          routineId: 'routine',
          occurrenceDate: '2026-08-28',
          status: RoutineExecutionStatus.completed,
          createdAt: now,
          updatedAt: now,
        ),
      )
      ..routineSegments.add(
        RoutineRunSegment(
          id: 'routine-segment',
          executionId: 'execution',
          startedAt: DateTime(2026, 8, 28, 9),
          endedAt: DateTime(2026, 8, 28, 10),
          createdAt: now,
        ),
      );
    final result = await ExecutionSegmentService(
      repository: repo,
      now: () => now,
    ).forJaxDay(now);
    expect(result.map((item) => item.categoryBucketKey), [
      'event:same',
      'routine:same',
    ]);
  });

  test('updates, adds and deletes closed segments while preserving adjacent boundaries', () async {
    final repo = MemoryRepository([event('one'), event('two')])
      ..segments.addAll([
        segment('one', 'one', 8, 9),
        segment('two', 'two', 9, 10),
      ]);
    final service = ExecutionSegmentService(repository: repo, now: () => now);
    final item = (await service.forJaxDay(now)).first;
    await service.updateClosed(
      item,
      DateTime(2026, 8, 28, 8),
      DateTime(2026, 8, 28, 9),
    );
    await service.addEvent(
      'one',
      'three',
      DateTime(2026, 8, 28, 10),
      DateTime(2026, 8, 28, 11),
    );
    await service.deleteClosed(item);
    expect(repo.segments.map((item) => item.id), ['two', 'three']);
  });

  test('rejects overlap, future, invalid range, and closed editor use for open segment', () async {
    final repo = MemoryRepository([event('one'), event('two')])
      ..segments.addAll([
        segment('one', 'one', 8, 9),
        RunSegment(
          id: 'open',
          eventId: 'two',
          startedAt: DateTime(2026, 8, 28, 13),
          createdAt: now,
        ),
      ]);
    final service = ExecutionSegmentService(repository: repo, now: () => now);
    await expectLater(
      service.addEvent(
        'two',
        'bad',
        DateTime(2026, 8, 28, 8, 30),
        DateTime(2026, 8, 28, 9, 30),
      ),
      throwsA(isA<DomainFailure>()),
    );
    await expectLater(
      service.addEvent(
        'two',
        'future',
        DateTime(2026, 8, 28, 19),
        DateTime(2026, 8, 28, 21),
      ),
      throwsA(isA<DomainFailure>()),
    );
    await expectLater(
      service.addEvent(
        'two',
        'range',
        DateTime(2026, 8, 28, 12),
        DateTime(2026, 8, 28, 12),
      ),
      throwsA(isA<DomainFailure>()),
    );
    final open = (await service.forJaxDay(now)).last;
    await expectLater(
      service.updateClosed(
        open,
        DateTime(2026, 8, 28, 13),
        DateTime(2026, 8, 28, 14),
      ),
      throwsA(isA<DomainFailure>()),
    );
  });

  test(
    'clips a segment crossing the 23:00 JaxDay boundary without splitting data',
    () async {
      final repo = MemoryRepository([event('night')])
        ..segments.add(
          RunSegment(
            id: 'night',
            eventId: 'night',
            startedAt: DateTime(2026, 8, 27, 22, 40),
            endedAt: DateTime(2026, 8, 27, 23, 20),
            createdAt: now,
          ),
        );
      final service = ExecutionSegmentService(repository: repo, now: () => now);
      expect(
        (await service.forJaxDay(DateTime(2026, 8, 27))).single.id,
        'night',
      );
      expect(
        (await service.forJaxDay(DateTime(2026, 8, 28))).single.id,
        'night',
      );
      expect(repo.segments, hasLength(1));
    },
  );
}
