import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/entities/run_segment.dart';
import 'package:jax/core/entities/category.dart';
import 'package:jax/core/services/time_summary_service.dart';
import 'package:jax/core/entities/routine.dart';

import '../support/memory_repository.dart';

void main() {
  test(
    'combines Event and Routine segments and splits Routine at 23:00',
    () async {
      final repo = MemoryRepository();
      final start = DateTime(2026, 8, 27, 22, 50);
      repo.routines.add(
        Routine(
          id: 'routine',
          name: '洗澡',
          recurrence: RoutineRecurrence.daily,
          weekdayMask: 0,
          isActive: true,
          sortOrder: 0,
          createdAt: start,
          updatedAt: start,
        ),
      );
      repo.routineExecutions.add(
        RoutineExecution(
          id: 'execution',
          routineId: 'routine',
          occurrenceDate: '2026-08-27',
          status: RoutineExecutionStatus.completed,
          createdAt: start,
          updatedAt: start,
          completedAt: DateTime(2026, 8, 27, 23, 20),
        ),
      );
      repo.routineSegments.add(
        RoutineRunSegment(
          id: 'segment',
          executionId: 'execution',
          startedAt: start,
          endedAt: DateTime(2026, 8, 27, 23, 20),
          createdAt: start,
        ),
      );
      final service = TimeSummaryService(repo, () => DateTime(2026, 8, 29));
      expect(
        (await service.day(DateTime(2026, 8, 27))).total,
        const Duration(minutes: 10),
      );
      expect(
        (await service.day(DateTime(2026, 8, 28))).total,
        const Duration(minutes: 20),
      );
    },
  );
  final base = DateTime(2026, 8, 27);
  JaxEvent event(String id, {String? parent, String? category}) => JaxEvent(
    id: id,
    name: id,
    status: EventStatus.paused,
    parentEventId: parent,
    categoryId: category,
    createdAt: base,
    updatedAt: base,
  );
  RunSegment segment(String id, String eventId, DateTime start, DateTime end) =>
      RunSegment(
        id: id,
        eventId: eventId,
        startedAt: start,
        endedAt: end,
        createdAt: start,
      );

  test(
    'splits segments at the local 23:00 boundary and includes open time once',
    () async {
      final repo =
          MemoryRepository([event('root'), event('child', parent: 'root')])
            ..segments.add(
              segment(
                's',
                'child',
                DateTime(2026, 8, 27, 22, 30),
                DateTime(2026, 8, 27, 23, 30),
              ),
            );
      final service = TimeSummaryService(repo, () => DateTime(2026, 8, 28, 12));
      expect(
        (await service.day(DateTime(2026, 8, 27))).total,
        const Duration(minutes: 30),
      );
      expect(
        (await service.day(DateTime(2026, 8, 28))).total,
        const Duration(minutes: 30),
      );
    },
  );

  test(
    'aggregates direct segments by current root category without duplication',
    () async {
      final repo =
          MemoryRepository([
              event('jax', category: 'dev'),
              event('a', parent: 'jax'),
              event('b', parent: 'jax'),
              event('research', category: 'science'),
              event('uncategorized'),
            ])
            ..categories.addAll([
              Category(
                id: 'dev',
                name: '开发项目',
                sortOrder: 0,
                createdAt: base,
                updatedAt: base,
              ),
              Category(
                id: 'science',
                name: '科研',
                sortOrder: 1,
                createdAt: base,
                updatedAt: base,
              ),
            ])
            ..segments.addAll([
              segment(
                'a1',
                'a',
                DateTime(2026, 8, 27, 8),
                DateTime(2026, 8, 27, 9),
              ),
              segment(
                'b1',
                'b',
                DateTime(2026, 8, 27, 9),
                DateTime(2026, 8, 27, 11),
              ),
              segment(
                'r1',
                'research',
                DateTime(2026, 8, 27, 12),
                DateTime(2026, 8, 27, 15),
              ),
              segment(
                'u1',
                'uncategorized',
                DateTime(2026, 8, 27, 16),
                DateTime(2026, 8, 27, 16, 30),
              ),
            ]);
      final result = await TimeSummaryService(
        repo,
        () => DateTime(2026, 8, 28),
      ).day(base);
      expect(result.total, const Duration(hours: 6, minutes: 30));
      expect(
        {for (final item in result.categories) item.name: item.duration},
        {
          '开发项目': const Duration(hours: 3),
          '科研': const Duration(hours: 3),
          '未分类': const Duration(minutes: 30),
        },
      );
    },
  );

  test(
    'open segment is split across 23:00 and empty windows remain empty',
    () async {
      final repo = MemoryRepository([event('open')])
        ..segments.add(
          RunSegment(
            id: 'open-s',
            eventId: 'open',
            startedAt: DateTime(2026, 8, 27, 22, 30),
            createdAt: base,
          ),
        );
      final service = TimeSummaryService(
        repo,
        () => DateTime(2026, 8, 27, 23, 15),
      );
      expect(
        (await service.day(DateTime(2026, 8, 27))).total,
        const Duration(minutes: 30),
      );
      expect(
        (await service.day(DateTime(2026, 8, 28))).total,
        const Duration(minutes: 15),
      );
      expect((await service.day(DateTime(2026, 8, 26))).categories, isEmpty);
    },
  );

  test(
    'week days sum to weekly total and split Sunday 23:00 boundary',
    () async {
      final repo = MemoryRepository([event('work')])
        ..segments.add(
          segment(
            'week-edge',
            'work',
            DateTime(2026, 8, 30, 22, 30),
            DateTime(2026, 8, 30, 23, 30),
          ),
        );
      final service = TimeSummaryService(repo, () => DateTime(2026, 9, 7));
      final first = await service.week(DateTime(2026, 8, 24));
      final next = await service.week(DateTime(2026, 8, 31));
      expect(first.total, const Duration(minutes: 30));
      expect(next.total, const Duration(minutes: 30));
      expect(
        first.days.fold(Duration.zero, (sum, day) => sum + day.total),
        first.total,
      );
    },
  );

  test('historical category follows current root assignment', () async {
    final root = event('root');
    final repo = MemoryRepository([root])
      ..categories.add(
        Category(
          id: 'dev',
          name: '开发',
          sortOrder: 0,
          createdAt: base,
          updatedAt: base,
        ),
      )
      ..segments.add(
        segment(
          'past',
          'root',
          DateTime(2026, 8, 27, 8),
          DateTime(2026, 8, 27, 9),
        ),
      );
    final service = TimeSummaryService(repo, () => DateTime(2026, 8, 28));
    expect((await service.day(base)).categories.single.name, '未分类');
    repo.events[0] = root.copyWith(categoryId: 'dev');
    expect((await service.day(base)).categories.single.name, '开发');
  });
}
