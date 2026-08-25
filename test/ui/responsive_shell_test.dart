import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/app.dart';

import '../support/memory_repository.dart';

void main() {
  testWidgets('uses bottom navigation without overflow on a narrow phone', (
    tester,
  ) async {
    await _setViewport(tester, const Size(360, 800), textScaleFactor: 2);
    await tester.pumpWidget(JaxApp(repository: MemoryRepository()));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.text('已加载本地数据'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('记录'));
    await tester.pumpAndSettle();
    expect(find.text('暂无历史记录'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps desktop navigation on a wide window', (tester) async {
    await _setViewport(tester, const Size(1200, 800));
    await tester.pumpWidget(JaxApp(repository: MemoryRepository()));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _setViewport(
  WidgetTester tester,
  Size size, {
  double textScaleFactor = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.platformDispatcher.textScaleFactorTestValue = textScaleFactor;
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
}
