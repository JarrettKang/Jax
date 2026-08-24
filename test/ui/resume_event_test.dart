import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/app.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';

import '../support/memory_repository.dart';

void main() {
  testWidgets('resumes a paused event from the UI', (tester) async {
    final time = DateTime.utc(2026);
    final repository = MemoryRepository([
      JaxEvent(
        id: 'one',
        name: '任务',
        status: EventStatus.paused,
        createdAt: time,
        updatedAt: time,
        firstStartedAt: time,
      ),
    ]);
    await tester.pumpWidget(
      JaxApp(repository: repository, newId: () => 'new', now: () => time),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('resume-one')));
    await tester.pump();
    expect(find.textContaining('正在进行'), findsOneWidget);
    expect(repository.segments.single.id, 'new');
  });
}
