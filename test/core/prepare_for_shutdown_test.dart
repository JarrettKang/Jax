import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/entities/run_segment.dart';
import 'package:jax/core/services/save_service.dart';
import 'package:jax/core/use_cases/prepare_for_shutdown.dart';

import '../support/memory_repository.dart';

class RecordingSaveService implements SaveService {
  RecordingSaveService({this.error, this.wait});
  final Object? error;
  final Future<void>? wait;
  int calls = 0;
  @override
  Future<void> flush() async {
    calls++;
    if (wait != null) await wait!;
    if (error != null) throw error!;
  }
}

void main() {
  final startedAt = DateTime.utc(2026, 8, 24, 12);
  JaxEvent runningEvent() => JaxEvent(
    id: 'event',
    name: '进行中',
    status: EventStatus.running,
    firstStartedAt: startedAt,
    createdAt: startedAt,
    updatedAt: startedAt,
  );

  test(
    'normal shutdown pauses running event, ends segment, then saves',
    () async {
      final repository = MemoryRepository([runningEvent()]);
      repository.segments.add(
        RunSegment(
          id: 'segment',
          eventId: 'event',
          startedAt: startedAt,
          createdAt: startedAt,
        ),
      );
      final save = RecordingSaveService();
      final closedAt = startedAt.add(const Duration(minutes: 15));

      await PrepareForShutdown(
        repository: repository,
        saveService: save,
        now: () => closedAt,
      )();

      expect(repository.events.single.status, EventStatus.paused);
      expect(repository.segments.single.endedAt, closedAt);
      expect(save.calls, 1);
    },
  );

  test('shutdown with no running event only saves', () async {
    final time = DateTime.utc(2026);
    final paused = JaxEvent(
      id: 'paused',
      name: '暂停',
      status: EventStatus.paused,
      createdAt: time,
      updatedAt: time,
    );
    final repository = MemoryRepository([paused]);
    final save = RecordingSaveService();

    await PrepareForShutdown(
      repository: repository,
      saveService: save,
      now: () => time,
    )();

    expect(repository.events.single, paused);
    expect(save.calls, 1);
  });

  test('save failure is reported to the close caller', () async {
    final repository = MemoryRepository();
    final save = RecordingSaveService(error: StateError('flush failed'));
    final shutdown = PrepareForShutdown(
      repository: repository,
      saveService: save,
      now: () => DateTime.utc(2026),
    );

    await expectLater(shutdown(), throwsA(isA<StateError>()));
  });

  test('duplicate close callbacks share one operation', () async {
    final completer = Completer<void>();
    final save = RecordingSaveService(wait: completer.future);
    final shutdown = PrepareForShutdown(
      repository: MemoryRepository(),
      saveService: save,
      now: () => DateTime.utc(2026),
    );

    final first = shutdown();
    final second = shutdown();
    await Future<void>.delayed(Duration.zero);
    expect(save.calls, 1);
    completer.complete();
    await Future.wait([first, second]);
    expect(save.calls, 1);
  });
}
