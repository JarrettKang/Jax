import 'dart:ui' show AppExitResponse;

import 'package:flutter_test/flutter_test.dart';
import 'package:jax/app.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/entities/run_segment.dart';
import 'package:jax/core/services/save_service.dart';

import '../support/memory_repository.dart';

class CloseSaveService implements SaveService {
  CloseSaveService({this.error});
  final Object? error;
  int calls = 0;
  @override
  Future<void> flush() async {
    calls++;
    if (error != null) throw error!;
  }
}

void main() {
  testWidgets('exit request pauses and saves before allowing close', (
    tester,
  ) async {
    final startedAt = DateTime.utc(2026, 8, 24, 12);
    final repository = MemoryRepository([
      JaxEvent(
        id: 'event',
        name: '运行中',
        status: EventStatus.running,
        firstStartedAt: startedAt,
        createdAt: startedAt,
        updatedAt: startedAt,
      ),
    ]);
    repository.segments.add(
      RunSegment(
        id: 'segment',
        eventId: 'event',
        startedAt: startedAt,
        createdAt: startedAt,
      ),
    );
    final save = CloseSaveService();
    final closedAt = startedAt.add(const Duration(minutes: 5));
    await tester.pumpWidget(
      JaxApp(repository: repository, saveService: save, now: () => closedAt),
    );
    await tester.pumpAndSettle();

    final response = await tester.binding.handleRequestAppExit();

    expect(response, AppExitResponse.exit);
    expect(repository.events.single.status, EventStatus.paused);
    expect(repository.segments.single.endedAt, closedAt);
    expect(save.calls, 1);
  });

  testWidgets('save failure blocks close and asks the user to retry', (
    tester,
  ) async {
    final save = CloseSaveService(error: StateError('flush failed'));
    await tester.pumpWidget(
      JaxApp(repository: MemoryRepository(), saveService: save),
    );
    await tester.pumpAndSettle();

    final response = await tester.binding.handleRequestAppExit();
    await tester.pump();

    expect(response, AppExitResponse.cancel);
    expect(find.text('关闭前保存失败，请重试'), findsOneWidget);
  });
}
