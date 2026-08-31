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
        type: RoutineType.onDemand,
        recurrence: RoutineRecurrence.daily,
        weekdayMask: 0,
        isActive: true,
        sortOrder: 0,
        createdAt: now,
        updatedAt: now,
      ),
    );
    repo.routineExecutions.addAll([
      for (final id in ['meal-first', 'meal-second'])
        RoutineExecution(
          id: id,
          routineId: 'meal',
          occurrenceDate: '2026-08-28',
          status: RoutineExecutionStatus.completed,
          createdAt: now,
          updatedAt: now,
        ),
    ]);
    repo.routineSegments.addAll([
      RoutineRunSegment(
        id: 'lunch',
        executionId: 'meal-first',
        startedAt: DateTime(2026, 8, 28, 12),
        endedAt: DateTime(2026, 8, 28, 13),
        createdAt: now,
      ),
      RoutineRunSegment(
        id: 'review-again',
        executionId: 'meal-second',
        startedAt: DateTime(2026, 8, 28, 15),
        endedAt: DateTime(2026, 8, 28, 16),
        createdAt: now,
      ),
    ]);
    final result = await ExecutionSegmentService(
      repository: repo,
      now: () => now,
    ).forJaxDay(now);
    expect(result.map((item) => item.id), [
      'first',
      'lunch',
      'second',
      'review-again',
    ]);
  });

  test('keeps a legitimate sub-second segment as one real record', () async {
    final start = DateTime(2026, 8, 28, 12, 34, 56, 100);
    final end = DateTime(2026, 8, 28, 12, 34, 56, 800);
    final repo = MemoryRepository([event('work')])
      ..segments.add(
        RunSegment(
          id: 'short',
          eventId: 'work',
          startedAt: start,
          endedAt: end,
          createdAt: start,
        ),
      );

    final result = await ExecutionSegmentService(
      repository: repo,
      now: () => now,
    ).forJaxDay(now);

    expect(result, hasLength(1));
    expect(result.single.id, 'short');
    expect(result.single.startedAt, start);
    expect(result.single.endedAt, end);
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
          colorKey: 2,
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
          colorKey: 6,
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
    expect(result.map((item) => item.categoryColorKey), [2, 6]);
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

  test(
    'completion correction reports the conflicting record and time',
    () async {
      final repo = MemoryRepository([event('running'), event('午饭')])
        ..segments.addAll([
          RunSegment(
            id: 'open',
            eventId: 'running',
            startedAt: DateTime(2026, 8, 28, 10),
            createdAt: now,
          ),
          segment('lunch', '午饭', 12, 13),
        ]);
      final service = ExecutionSegmentService(repository: repo, now: () => now);
      await expectLater(
        service.validateCompletionEnd(
          'open',
          DateTime(2026, 8, 28, 10),
          DateTime(2026, 8, 28, 12, 30),
        ),
        throwsA(
          isA<DomainFailure>().having(
            (failure) => failure.message,
            'message',
            allOf(contains('午饭'), contains('12:00–13:00')),
          ),
        ),
      );
    },
  );

  test(
    'on-demand history reuses paused execution or creates completed one',
    () async {
      final repo = MemoryRepository()
        ..routines.addAll([
          for (final id in ['paused', 'fresh'])
            Routine(
              id: id,
              name: id,
              type: RoutineType.onDemand,
              recurrence: RoutineRecurrence.daily,
              weekdayMask: 0,
              isActive: true,
              sortOrder: 0,
              createdAt: now,
              updatedAt: now,
            ),
        ])
        ..routineExecutions.add(
          RoutineExecution(
            id: 'existing',
            routineId: 'paused',
            occurrenceDate: '2026-08-28',
            status: RoutineExecutionStatus.paused,
            createdAt: now,
            updatedAt: now,
          ),
        );
      final service = ExecutionSegmentService(repository: repo, now: () => now);
      await service.addRoutine(
        'paused',
        'unused',
        'paused-segment',
        '2026-08-28',
        DateTime(2026, 8, 28, 8),
        DateTime(2026, 8, 28, 9),
      );
      await service.addRoutine(
        'fresh',
        'independent',
        'fresh-segment',
        '2026-08-28',
        DateTime(2026, 8, 28, 9),
        DateTime(2026, 8, 28, 10),
      );
      expect(
        repo.routineSegments
            .firstWhere((segment) => segment.id == 'paused-segment')
            .executionId,
        'existing',
      );
      expect(
        repo.routineExecutions.firstWhere((e) => e.id == 'existing').status,
        RoutineExecutionStatus.paused,
      );
      expect(
        repo.routineExecutions.firstWhere((e) => e.id == 'independent').status,
        RoutineExecutionStatus.completed,
      );
    },
  );

  test(
    'derives complete JaxDay gaps with clipping and adjacent occupancy',
    () async {
      final afterDay = DateTime(2026, 8, 29);
      final repo = MemoryRepository([event('work')])
        ..segments.addAll([
          RunSegment(
            id: 'late-night',
            eventId: 'work',
            startedAt: DateTime(2026, 8, 27, 23),
            endedAt: DateTime(2026, 8, 27, 23, 30),
            createdAt: now,
          ),
          RunSegment(
            id: 'after-midnight',
            eventId: 'work',
            startedAt: DateTime(2026, 8, 28, 0, 10),
            endedAt: DateTime(2026, 8, 28, 1),
            createdAt: now,
          ),
          segment(
            'morning',
            'work',
            10,
            11,
          ).copyWith(endedAt: DateTime(2026, 8, 28, 11, 20)),
          segment('afternoon', 'work', 13, 14),
        ]);
      final gaps = await ExecutionSegmentService(
        repository: repo,
        now: () => afterDay,
      ).availableGapsForJaxDay(DateTime(2026, 8, 28));

      expect(gaps.map((gap) => (gap.start, gap.end)), [
        (DateTime(2026, 8, 27, 23, 30), DateTime(2026, 8, 28, 0, 10)),
        (DateTime(2026, 8, 28, 1), DateTime(2026, 8, 28, 10)),
        (DateTime(2026, 8, 28, 11, 20), DateTime(2026, 8, 28, 13)),
        (DateTime(2026, 8, 28, 14), DateTime(2026, 8, 28, 23)),
      ]);

      repo.segments.add(
        RunSegment(
          id: 'adjacent',
          eventId: 'work',
          startedAt: DateTime(2026, 8, 28, 11, 20),
          endedAt: DateTime(2026, 8, 28, 13),
          createdAt: now,
        ),
      );
      final adjacent = await ExecutionSegmentService(
        repository: repo,
        now: () => afterDay,
      ).availableGapsForJaxDay(DateTime(2026, 8, 28));
      expect(
        adjacent.any(
          (gap) =>
              gap.start == DateTime(2026, 8, 28, 11, 20) &&
              gap.end == DateTime(2026, 8, 28, 13),
        ),
        isFalse,
      );
    },
  );

  test(
    'open segments occupy through now and a new record splits its gap',
    () async {
      final current = DateTime(2026, 8, 28, 17, 30);
      final repo = MemoryRepository([event('work')])
        ..segments.add(
          RunSegment(
            id: 'open-now',
            eventId: 'work',
            startedAt: DateTime(2026, 8, 28, 16),
            createdAt: current,
          ),
        );
      final service = ExecutionSegmentService(
        repository: repo,
        now: () => current,
      );
      final openGaps = await service.availableGapsForJaxDay(current);
      expect(openGaps.last.end, DateTime(2026, 8, 28, 16));

      repo.segments
        ..clear()
        ..addAll([
          RunSegment(
            id: 'before',
            eventId: 'work',
            startedAt: DateTime(2026, 8, 28, 14),
            endedAt: DateTime(2026, 8, 28, 15, 10),
            createdAt: current,
          ),
          RunSegment(
            id: 'after',
            eventId: 'work',
            startedAt: DateTime(2026, 8, 28, 17, 30),
            endedAt: DateTime(2026, 8, 28, 18),
            createdAt: current,
          ),
        ]);
      final pastService = ExecutionSegmentService(
        repository: repo,
        now: () => DateTime(2026, 8, 29),
      );
      await pastService.addEvent(
        'work',
        'manual',
        DateTime(2026, 8, 28, 15, 30),
        DateTime(2026, 8, 28, 16, 20),
      );
      final updated = await pastService.availableGapsForJaxDay(
        DateTime(2026, 8, 28),
      );
      expect(
        updated.map((gap) => (gap.start, gap.end)),
        containsAll([
          (DateTime(2026, 8, 28, 15, 10), DateTime(2026, 8, 28, 15, 30)),
          (DateTime(2026, 8, 28, 16, 20), DateTime(2026, 8, 28, 17, 30)),
        ]),
      );
    },
  );
}
