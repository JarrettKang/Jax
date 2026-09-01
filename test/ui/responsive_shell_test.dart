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
    expect(_navigationLabels(tester), ['首页', '今日', '世界', '规划', '日常', '记录']);
    expect(find.text('现在没有正在执行的事项'), findsOneWidget);
    expect(find.text('接下来可以做'), findsOneWidget);
    expect(find.text('已加载本地数据'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('记录'));
    await tester.pumpAndSettle();
    expect(find.text('这一天没有记录到执行时间'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps desktop navigation on a wide window', (tester) async {
    await _setViewport(tester, const Size(1200, 800));
    await tester.pumpWidget(JaxApp(repository: MemoryRepository()));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(_navigationLabels(tester), ['首页', '今日', '世界', '规划', '日常', '记录']);
    expect(find.text('现在没有正在执行的事项'), findsOneWidget);
    expect(find.text('接下来可以做'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

List<String> _navigationLabels(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(
        of: find.byWidgetPredicate(
          (widget) => widget is NavigationBar || widget is NavigationRail,
        ),
        matching: find.byType(Text),
      ),
    )
    .map((text) => text.data)
    .whereType<String>()
    .toList();

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
