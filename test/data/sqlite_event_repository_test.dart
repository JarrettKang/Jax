import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/category.dart';
import 'package:jax/core/entities/jax_event.dart';
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

  test(
    'persists root Category and child relationship at Event creation',
    () async {
      final createdAt = DateTime.utc(2026, 8, 24, 12);
      await repository.insertCategory(
        Category(
          id: 'research',
          name: '科研',
          sortOrder: 0,
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
      );
      var nextId = 0;
      final create = CreateEvent(
        repository: repository,
        newId: () => 'event-${nextId++}',
        now: () => createdAt,
      );

      final root = await create('测试 Yukawa', categoryId: 'research');
      final child = await create(
        '测试截断距离',
        parentEventId: root.id,
        categoryId: 'research',
      );

      expect((await repository.getEvent(root.id))!.categoryId, 'research');
      final storedChild = (await repository.getEvent(child.id))!;
      expect(storedChild.parentEventId, root.id);
      expect(storedChild.categoryId, isNull);
    },
  );
}
