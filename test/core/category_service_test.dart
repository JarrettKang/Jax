import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/category.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/entities/routine_category.dart';
import 'package:jax/core/errors/domain_failure.dart';
import 'package:jax/core/services/category_service.dart';

import '../support/memory_repository.dart';

void main() {
  final now = DateTime.utc(2026);
  test('validates category names and supports CRUD', () async {
    final repo = MemoryRepository();
    final service = CategoryService(
      repository: repo,
      newId: () => 'c1',
      now: () => now,
    );
    final category = await service.create('  工作  ');
    expect(category.name, '工作');
    await expectLater(service.create('工作'), throwsA(isA<DomainFailure>()));
    await expectLater(service.create('未分类'), throwsA(isA<DomainFailure>()));
    expect((await service.rename('c1', '项目')).name, '项目');
    await service.delete('c1');
    expect(repo.categories, isEmpty);
  });

  test(
    'color allocation counts World and Routine and manual repeats are valid',
    () async {
      final repo = MemoryRepository()
        ..routineCategories.add(
          RoutineCategory(
            id: 'r',
            name: '日常',
            sortOrder: 0,
            createdAt: now,
            updatedAt: now,
            colorKey: 0,
          ),
        );
      var id = 0;
      final service = CategoryService(
        repository: repo,
        newId: () => 'c${id++}',
        now: () => now,
      );
      final automatic = await service.create('工作');
      expect(automatic.colorKey, 1);
      final repeated = await service.create('项目', colorKey: 0);
      expect(repeated.colorKey, 0);
      final renamed = await service.rename(automatic.id, '研究');
      expect(renamed.colorKey, 1);
    },
  );

  test('root category follows detach and clears on root to child', () async {
    final root = JaxEvent(
      id: 'a',
      name: 'A',
      status: EventStatus.paused,
      categoryId: 'c',
      createdAt: now,
      updatedAt: now,
    );
    final child = JaxEvent(
      id: 'b',
      name: 'B',
      status: EventStatus.paused,
      parentEventId: 'a',
      createdAt: now,
      updatedAt: now,
    );
    final other = JaxEvent(
      id: 'x',
      name: 'X',
      status: EventStatus.paused,
      createdAt: now,
      updatedAt: now,
    );
    final repo = MemoryRepository([root, child, other])
      ..categories.add(
        Category(
          id: 'c',
          name: '工作',
          sortOrder: 0,
          createdAt: now,
          updatedAt: now,
        ),
      );
    await repo.updateParent('b', null, now);
    expect((await repo.getEvent('b'))!.categoryId, 'c');
    await repo.updateParent('b', 'x', now);
    expect((await repo.getEvent('b'))!.categoryId, isNull);
  });
}
