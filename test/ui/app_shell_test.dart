import 'package:flutter_test/flutter_test.dart';
import 'package:jax/app.dart';

import '../support/memory_repository.dart';
import '../support/ui_navigation.dart';

void main() {
  testWidgets('shows the empty World and summary sections', (tester) async {
    await tester.pumpWidget(JaxApp(repository: MemoryRepository()));
    await tester.pumpAndSettle();
    expect(find.text('Jax'), findsOneWidget);
    await openWorldOverview(tester);
    expect(find.text('世界数据库不可用'), findsOneWidget);
    await tester.tap(find.text('记录'));
    await tester.pumpAndSettle();
    expect(find.text('这一天没有记录到执行时间'), findsOneWidget);
  });
}
