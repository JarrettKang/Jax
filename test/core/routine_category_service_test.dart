import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/routine.dart';
import 'package:jax/core/services/routine_category_service.dart';

import '../support/memory_repository.dart';

void main() {
  test('Routine Category CRUD is independent and delete moves routines to unclassified', () async {
    final now = DateTime.utc(2026, 8, 28);
    var id = 0;
    final repo = MemoryRepository();
    final service = RoutineCategoryService(
      repository: repo,
      newId: () => 'c${id++}',
      now: () => now,
    );
    await service.create('日常起居');
    await service.create('饮食');
    expect((await repo.getRoutineCategories()).map((c) => c.name), [
      '日常起居',
      '饮食',
    ]);
    final first = (await repo.getRoutineCategories()).first;
    await service.rename(first, '生活');
    await service.reorder(first.id, 1);
    expect((await repo.getRoutineCategories()).map((c) => c.name), [
      '饮食',
      '生活',
    ]);
    repo.routines.add(
      Routine(
        id: 'r',
        name: '洗漱',
        routineCategoryId: first.id,
        recurrence: RoutineRecurrence.daily,
        weekdayMask: 0,
        isActive: false,
        sortOrder: 0,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await service.delete(first.id);
    expect(repo.routines.single.routineCategoryId, isNull);
    expect(repo.routines.single.isActive, isFalse);
  });

  test('Routine reorder is scoped to its category', () async {
    final now = DateTime.utc(2026, 8, 28);
    final repo = MemoryRepository();
    Routine r(String id, String? category, int order) => Routine(
      id: id,
      name: id,
      routineCategoryId: category,
      recurrence: RoutineRecurrence.daily,
      weekdayMask: 0,
      isActive: true,
      sortOrder: order,
      createdAt: now,
      updatedAt: now,
    );
    repo.routines.addAll([r('a', 'x', 0), r('b', 'x', 1), r('other', 'y', 0)]);
    await repo.reorderRoutine('b', 0);
    expect(
      (await repo.getRoutines())
          .where((r) => r.routineCategoryId == 'x')
          .map((r) => r.id),
      ['b', 'a'],
    );
    expect(repo.routines.singleWhere((r) => r.id == 'other').sortOrder, 0);
  });
}
