import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:jax/app.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/execution_time_segment.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/entities/routine.dart';
import 'package:jax/core/services/execution_time_service.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/repositories/sqlite_event_repository.dart';
import 'package:jax/data/services/sqlite_save_service.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shared Event and Routine time correction works on device', (
    tester,
  ) async {
    final databasePath = Platform.isAndroid
        ? path.join(
            await getDatabasesPath(),
            'jax-time-correction-${DateTime.now().microsecondsSinceEpoch}.db',
          )
        : path.join(
            (await Directory.systemTemp.createTemp('jax-time-correction-'))
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
    await repository.insertEvent(
      JaxEvent(
        id: 'event',
        name: '已暂停事件',
        status: EventStatus.paused,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await repository.insertRoutine(
      Routine(
        id: 'routine',
        name: '已完成日常',
        recurrence: RoutineRecurrence.daily,
        weekdayMask: 0,
        isActive: true,
        sortOrder: 0,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await database.database.insert('routine_executions', {
      'id': 'routine-execution',
      'routine_id': 'routine',
      'occurrence_date': '2026-08-28',
      'status': 'completed',
      'created_at_utc': now.millisecondsSinceEpoch,
      'updated_at_utc': now.millisecondsSinceEpoch,
    });
    final service = ExecutionTimeService(
      repository: repository,
      newId: () => 'manual-segment',
      now: () => now,
    );
    await service.add(
      type: ExecutionOwnerType.event,
      ownerId: 'event',
      ownerName: '已暂停事件',
      start: DateTime.utc(2026, 8, 28, 9),
      end: DateTime.utc(2026, 8, 28, 10),
    );

    await tester.pumpWidget(
      JaxApp(
        repository: repository,
        saveService: SqliteSaveService(database),
        now: () => now,
        newId: () => 'ui-segment',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('记录'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('execution-time-correction')), findsOne);
    await tester.tap(find.byKey(const ValueKey('execution-time-correction')));
    await tester.pumpAndSettle();
    expect(find.text('已暂停事件'), findsOne);
    expect(find.text('已完成日常'), findsOne);
    await tester.tap(find.text('已暂停事件'));
    await tester.pumpAndSettle();
    expect(find.text('编辑执行时间'), findsOne);
    expect(find.text('已暂停事件'), findsOne);
    expect(find.text('添加一段'), findsOne);
    expect(find.byIcon(Icons.edit_outlined), findsOne);
    expect(find.byIcon(Icons.delete_outline), findsOne);
  });
}
