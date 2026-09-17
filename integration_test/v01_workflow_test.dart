import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/execution_workflow.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Native Today execution and Record survive database restart', (
    tester,
  ) async {
    await verifyExecutionWorkflow(tester);
  });
}
