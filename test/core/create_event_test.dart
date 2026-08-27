import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/category.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/errors/domain_failure.dart';
import 'package:jax/core/use_cases/create_event.dart';

import '../support/memory_repository.dart';

void main() {
  late MemoryRepository repository;
  late CreateEvent createEvent;
  setUp(() {
    repository = MemoryRepository();
    createEvent = CreateEvent(
      repository: repository,
      newId: () => 'fixed-id',
      now: () => DateTime.utc(2026, 8, 24, 12),
    );
  });
  test('creates a pending event with a generated id', () async {
    final event = await createEvent('  阅读  ');
    expect(event.id, 'fixed-id');
    expect(event.name, '阅读');
    expect(event.status, EventStatus.pending);
    expect(repository.events, [event]);
  });
  test('rejects an empty or whitespace-only name', () async {
    await expectLater(createEvent('   '), throwsA(isA<DomainFailure>()));
    expect(repository.events, isEmpty);
  });
  test('allows duplicate names because ids identify events', () async {
    var nextId = 0;
    final useCase = CreateEvent(
      repository: repository,
      newId: () => 'id-${nextId++}',
      now: () => DateTime.utc(2026, 8, 24, 12),
    );
    final first = await useCase('散步');
    final second = await useCase('散步');
    expect(first.name, second.name);
    expect(first.id, isNot(second.id));
  });

  test(
    'creates a root Event with its selected Category in one insert',
    () async {
      repository.categories.add(
        Category(
          id: 'research',
          name: '科研',
          sortOrder: 0,
          createdAt: DateTime.utc(2026, 8, 24),
          updatedAt: DateTime.utc(2026, 8, 24),
        ),
      );

      final event = await createEvent('测试 Yukawa', categoryId: 'research');

      expect(event.parentEventId, isNull);
      expect(event.categoryId, 'research');
      expect(repository.events.single.categoryId, 'research');
    },
  );

  test('creates a child without a direct Category', () async {
    final parent = JaxEvent(
      id: 'parent',
      name: '测试 Yukawa',
      status: EventStatus.pending,
      createdAt: DateTime.utc(2026, 8, 24),
      updatedAt: DateTime.utc(2026, 8, 24),
      categoryId: 'research',
    );
    repository.events.add(parent);

    final child = await createEvent(
      '测试截断距离',
      parentEventId: parent.id,
      categoryId: 'other-category',
    );

    expect(child.parentEventId, parent.id);
    expect(child.categoryId, isNull);
  });
}
