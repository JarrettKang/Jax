import 'package:flutter_test/flutter_test.dart';
import 'package:jax/app.dart';

import '../support/memory_repository.dart';
import '../support/ui_navigation.dart';

void main() {
  testWidgets('shows the empty events and history sections', (tester) async {
    await tester.pumpWidget(JaxApp(repository: MemoryRepository()));
    await tester.pumpAndSettle();
    expect(find.text('Jax'), findsOneWidget);
    await openEventsPage(tester);
    expect(find.text('暂无未完成事件'), findsOneWidget);
    await tester.tap(find.text('记录'));
    await tester.pumpAndSettle();
    expect(find.text('暂无历史记录'), findsOneWidget);
  });
}
