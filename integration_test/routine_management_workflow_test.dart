import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:jax/app.dart';
import 'package:jax/core/entities/routine.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/repositories/sqlite_event_repository.dart';
import 'package:jax/data/services/sqlite_save_service.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Routine management delegates daily execution to Today', (
    tester,
  ) async {
    final databasePath = Platform.isAndroid
        ? path.join(
            await getDatabasesPath(),
            'jax-routine-management-${DateTime.now().microsecondsSinceEpoch}.db',
          )
        : path.join(
            (await Directory.systemTemp.createTemp('jax-routine-management-'))
                .path,
            'jax.db',
          );
    final database = Platform.isAndroid
        ? await AppDatabase.openWithFactory(databasePath, databaseFactory)
        : await AppDatabase.open(databasePath);
    addTearDown(() async {
      await database.close();
      if (Platform.isAndroid) {
        await deleteDatabase(databasePath);
      } else {
        await File(databasePath).parent.delete(recursive: true);
      }
    });
    final now = DateTime.utc(2026, 8, 28, 8);
    final repository = SqliteEventRepository(database);
    Routine routine(String id, String name, int order, {bool active = true}) =>
        Routine(
          id: id,
          name: name,
          recurrence: RoutineRecurrence.daily,
          weekdayMask: 0,
          isActive: active,
          sortOrder: order,
          createdAt: now,
          updatedAt: now,
        );
    for (final item in [
      routine('wash', '晚上洗漱', 0),
      routine('sleep', '睡觉', 1),
      routine('inactive', '已停用日常', 2, active: false),
    ]) {
      await repository.insertRoutine(item);
    }
    var id = 0;
    await tester.pumpWidget(
      JaxApp(
        repository: repository,
        saveService: SqliteSaveService(database),
        newId: () => 'new-${id++}',
        now: () => now,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('日常'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('create-routine-category')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('category-name')), '日常起居');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('日常起居'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('routine-category-toggle-unclassified')),
    );
    await tester.pumpAndSettle();
    expect(find.text('晚上洗漱'), findsNothing);
    await tester.tap(find.text('今日'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('日常'));
    await tester.pumpAndSettle();
    expect(find.text('晚上洗漱'), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey('routine-category-toggle-unclassified')),
    );
    await tester.pumpAndSettle();

    expect(find.text('今日备用执行'), findsNothing);
    expect(find.text('管理日常'), findsNothing);
    expect(find.text('未分类'), findsOneWidget);
    expect(find.text('每日'), findsNWidgets(2));
    expect(find.text('开始'), findsNothing);
    expect(find.text('暂停'), findsNothing);
    expect(find.text('完成'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('routine-more-sleep')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('routine-up-sleep')));
    await tester.pumpAndSettle();
    expect((await repository.getRoutines()).first.id, 'sleep');
    await tester.tap(find.byKey(const ValueKey('routine-more-wash')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('停用'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('已停用'));
    await tester.pumpAndSettle();
    final reactivate = find.text('重新启用').first;
    await tester.ensureVisible(reactivate);
    await tester.pumpAndSettle();
    expect(reactivate.hitTestable(), findsOneWidget);
    await tester.tap(reactivate);
    await tester.pumpAndSettle();
    expect(
      (await repository.getRoutines())
          .firstWhere((r) => r.id == 'wash')
          .isActive,
      isTrue,
    );

    final createRoutine = find.byKey(const ValueKey('create-routine'));
    await tester.scrollUntilVisible(
      createRoutine,
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(createRoutine.hitTestable(), findsOneWidget);
    await tester.tap(createRoutine);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '新增日常');
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();
    expect(
      (await repository.getRoutines()).any((r) => r.name == '新增日常'),
      isTrue,
    );

    await tester.tap(find.text('今日'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('today-routine-start-wash')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('today-routine-pause-wash')), findsOne);
    await tester.tap(find.text('日常'));
    await tester.pumpAndSettle();
    expect(find.text('正在执行'), findsOne);
    expect(find.text('暂停'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
