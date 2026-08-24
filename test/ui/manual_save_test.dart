import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/app.dart';
import 'package:jax/core/services/save_service.dart';

import '../support/memory_repository.dart';

class FakeSaveService implements SaveService {
  FakeSaveService({this.error, this.wait});

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
  testWidgets('manual save shows success and changes no business state', (
    tester,
  ) async {
    final repository = MemoryRepository();
    final service = FakeSaveService();
    await tester.pumpWidget(
      JaxApp(repository: repository, saveService: service),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('manual-save')));
    await tester.pumpAndSettle();

    expect(find.text('保存成功'), findsOneWidget);
    expect(service.calls, 1);
    expect(repository.events, isEmpty);
  });

  testWidgets('manual save shows failure', (tester) async {
    final service = FakeSaveService(error: StateError('disk is full'));
    await tester.pumpWidget(
      JaxApp(repository: MemoryRepository(), saveService: service),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('manual-save')));
    await tester.pumpAndSettle();

    expect(find.text('保存失败，请重试'), findsOneWidget);
    expect(service.calls, 1);
  });

  testWidgets('manual save cannot be triggered twice while saving', (
    tester,
  ) async {
    final completer = Completer<void>();
    final service = FakeSaveService(wait: completer.future);
    await tester.pumpWidget(
      JaxApp(repository: MemoryRepository(), saveService: service),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('manual-save')));
    await tester.pump();
    final button = tester.widget<IconButton>(
      find.byKey(const ValueKey('manual-save')),
    );
    expect(button.onPressed, isNull);
    expect(service.calls, 1);
    completer.complete();
    await tester.pumpAndSettle();
  });
}
