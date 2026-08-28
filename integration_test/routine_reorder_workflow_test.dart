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

  testWidgets('Routine reorder serializes rapid definition moves in SQLite', (
    tester,
  ) async {
    final databasePath = Platform.isAndroid
        ? path.join(
            await getDatabasesPath(),
            'jax-routine-reorder-${DateTime.now().microsecondsSinceEpoch}.db',
          )
        : path.join(
            (await Directory.systemTemp.createTemp('jax-routine-reorder-'))
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
    final now = DateTime.utc(2026, 8, 28, 12);
    final repository = SqliteEventRepository(database);
    for (var index = 0; index < 5; index++) {
      final name = 'ABCDE'[index];
      await repository.insertRoutine(
        Routine(
          id: name,
          name: name,
          recurrence: RoutineRecurrence.daily,
          weekdayMask: 0,
          isActive: true,
          sortOrder: index,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
    await tester.pumpWidget(
      JaxApp(
        repository: repository,
        saveService: SqliteSaveService(database),
        now: () => now,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('日常'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('routine-up-C')));
    await tester.tap(find.byKey(const ValueKey('routine-up-C')));
    await tester.pumpAndSettle();
    expect((await repository.getRoutines()).map((routine) => routine.id), [
      'C',
      'A',
      'B',
      'D',
      'E',
    ]);

    for (var i = 0; i < 10; i++) {
      await tester.tap(find.byKey(const ValueKey('routine-down-C')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('routine-up-C')));
      await tester.pumpAndSettle();
    }
    expect((await repository.getRoutines()).map((routine) => routine.id), [
      'C',
      'A',
      'B',
      'D',
      'E',
    ]);
    expect(find.byKey(const ValueKey('routine-up-C')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
