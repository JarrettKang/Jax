import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/errors/domain_failure.dart';
import 'package:jax/core/repositories/event_repository.dart';
import 'package:jax/core/use_cases/edit_event.dart';

void main() {
  final timestamp = DateTime.utc(2026, 8, 24, 12);

  test('edits a pending event by id', () async {
    final original = JaxEvent(
      id: 'one',
      name: '旧名称',
      status: EventStatus.pending,
      createdAt: timestamp,
      updatedAt: timestamp,
    );
    final repository = _Repository([original]);
    final edited = await EditEvent(
      repository: repository,
      now: () => timestamp.add(const Duration(minutes: 1)),
    )('one', ' 新名称 ');

    expect(edited.name, '新名称');
    expect(repository.events.single.name, '新名称');
  });

  test('rejects empty names and non-pending events', () async {
    final running = JaxEvent(
      id: 'running',
      name: '执行中',
      status: EventStatus.running,
      createdAt: timestamp,
      updatedAt: timestamp,
    );
    final repository = _Repository([running]);
    final edit = EditEvent(repository: repository, now: () => timestamp);

    await expectLater(edit('running', '新名称'), throwsA(isA<DomainFailure>()));
    await expectLater(edit('running', '  '), throwsA(isA<DomainFailure>()));
  });
}

class _Repository implements EventRepository {
  _Repository(this.events);
  final List<JaxEvent> events;

  @override
  Future<JaxEvent?> getEvent(String id) async =>
      events.where((event) => event.id == id).firstOrNull;
  @override
  Future<List<JaxEvent>> getIncompleteEvents() async => List.of(events);
  @override
  Future<void> insertEvent(JaxEvent event) async => events.add(event);
  @override
  @override
  Future<void> deleteEvent(String id) async =>
      events.removeWhere((event) => event.id == id);

  @override
  Future<void> updateEvent(JaxEvent event) async {
    events[events.indexWhere((item) => item.id == event.id)] = event;
  }
}
