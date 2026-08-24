import 'package:flutter_test/flutter_test.dart';
import 'package:jax/app.dart';

void main() {
  testWidgets('shows the empty events and history sections', (tester) async {
    await tester.pumpWidget(const JaxApp());

    expect(find.text('Jax'), findsOneWidget);
    expect(find.text('事件'), findsOneWidget);
    expect(find.text('暂无未完成事件'), findsOneWidget);

    await tester.tap(find.text('记录'));
    await tester.pumpAndSettle();

    expect(find.text('暂无历史记录'), findsOneWidget);
  });
}
