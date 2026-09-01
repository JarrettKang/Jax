import 'package:flutter_test/flutter_test.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/sync/sqlite_sync_readiness.dart';

void main() {
  late AppDatabase app;
  setUp(() async => app = await AppDatabase.inMemory());
  tearDown(() => app.close());

  test('readiness blocks invalid UUID and duplicate scoped order', () async {
    await _insertNode(app, 'not-a-uuid', 0);
    await _insertNode(app, '11111111-1111-4111-8111-111111111111', 0);
    final issues = await SqliteSyncReadiness(app).validate();
    expect(
      issues.map((issue) => issue.code),
      contains('world-node-invalid-uuid'),
    );
    expect(
      issues.map((issue) => issue.code),
      contains('world-node-scoped-order'),
    );
    expect(
      issues
          .where((issue) => issue.code == 'world-node-scoped-order')
          .single
          .isBlocking,
      isTrue,
    );
  });

  test(
    'readiness blocks WorldNode cycles',
    () async {
      const first = '11111111-1111-4111-8111-111111111111';
      const second = '22222222-2222-4222-8222-222222222222';
      await _insertNode(app, first, 0);
      await _insertNode(app, second, 1, parent: first);
      await app.database.update(
        'world_nodes',
        {'parent_world_node_id': second},
        where: 'id = ?',
        whereArgs: [first],
      );
      final issues = await SqliteSyncReadiness(app).validate();
      expect(issues.map((issue) => issue.code), contains('world-node-cycle'));
    },
  );
}

Future<void> _insertNode(
  AppDatabase app,
  String id,
  int order, {
  String? parent,
}) => app.database.insert('world_nodes', {
  'id': id,
  'name': id,
  'status': 'inProgress',
  'parent_world_node_id': parent,
  'sort_order': order,
  'created_at_utc': 1,
  'updated_at_utc': 1,
});
