import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/repositories/sqlite_event_repository.dart';

void main() {
  late AppDatabase database;
  late SqliteEventRepository repository;
  final time = DateTime.utc(2026, 8, 25, 10);

  JaxEvent event(String id, {String? parentId}) => JaxEvent(
    id: id,
    name: id,
    status: EventStatus.pending,
    parentEventId: parentId,
    createdAt: time,
    updatedAt: time,
  );

  setUp(() async {
    database = await AppDatabase.inMemory();
    repository = SqliteEventRepository(database);
  });
  tearDown(() => database.close());

  test(
    'stores nullable parent and queries direct parent and children',
    () async {
      final parent = event('parent');
      final first = event('first', parentId: parent.id);
      final second = event('second', parentId: parent.id);
      await repository.insertEvent(parent);
      await repository.insertEvent(first);
      await repository.insertEvent(second);

      expect(await repository.getParent(first.id), parent);
      expect(await repository.getDirectChildren(parent.id), [first, second]);
      expect(await repository.getParent(parent.id), isNull);
    },
  );

  test('updates and clears a parent relationship', () async {
    final parent = event('parent');
    final child = event('child');
    await repository.insertEvent(parent);
    await repository.insertEvent(child);

    await repository.updateParent(child.id, parent.id, time);
    expect((await repository.getEvent(child.id))!.parentEventId, parent.id);
    await repository.updateParent(child.id, null, time);
    expect((await repository.getEvent(child.id))!.parentEventId, isNull);
  });

  test('foreign key rejects a missing parent', () async {
    await expectLater(
      repository.insertEvent(event('child', parentId: 'missing')),
      throwsA(anything),
    );
  });

  test(
    'repository transaction rejects cycles and invalid status nesting',
    () async {
      final parent = event('parent');
      final child = event('child', parentId: parent.id);
      final completed = JaxEvent(
        id: 'completed',
        name: 'completed',
        status: EventStatus.completed,
        createdAt: time,
        updatedAt: time,
      );
      await repository.insertEvent(parent);
      await repository.insertEvent(child);
      await repository.insertEvent(completed);

      await expectLater(
        repository.updateParent(parent.id, child.id, time),
        throwsA(anything),
      );
      await expectLater(
        repository.updateParent(parent.id, completed.id, time),
        throwsA(anything),
      );
      expect((await repository.getEvent(parent.id))?.parentEventId, isNull);
    },
  );
}
