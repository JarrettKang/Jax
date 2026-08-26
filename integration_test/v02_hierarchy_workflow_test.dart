import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:jax/app.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/entities/run_segment.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/repositories/sqlite_event_repository.dart';
import 'package:jax/data/services/sqlite_save_service.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('v0.2 hierarchy workflow uses shared SQLite facts', (
    tester,
  ) async {
    final databasePath = Platform.isAndroid
        ? path.join(
            await getDatabasesPath(),
            'jax-v02-${DateTime.now().microsecondsSinceEpoch}.db',
          )
        : path.join(
            (await Directory.systemTemp.createTemp('jax-v02-')).path,
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
    final repository = SqliteEventRepository(database);
    final time = DateTime.utc(2026, 8, 25, 8);
    JaxEvent event(
      String id,
      String name,
      EventStatus status, {
      String? parent,
    }) => JaxEvent(
      id: id,
      name: name,
      status: status,
      parentEventId: parent,
      firstStartedAt: status == EventStatus.pending ? null : time,
      completedAt: status == EventStatus.completed
          ? time.add(const Duration(minutes: 10))
          : null,
      createdAt: time,
      updatedAt: time,
    );
    for (final value in [
      event('parent', '开发项目', EventStatus.paused),
      event('running', '实现层级功能', EventStatus.running, parent: 'parent'),
      event('sibling', '编写说明', EventStatus.pending, parent: 'parent'),
      event('history-root', '已完成项目', EventStatus.completed),
      event(
        'history-child',
        '已完成步骤',
        EventStatus.completed,
        parent: 'history-root',
      ),
    ]) {
      await repository.insertEvent(value);
    }
    await database.database.insert('run_segments', {
      'id': 'running-open',
      'event_id': 'running',
      'started_at_utc': time.millisecondsSinceEpoch,
      'ended_at_utc': null,
      'created_at_utc': time.millisecondsSinceEpoch,
    });
    for (final segment in [
      RunSegment(
        id: 'history-root-segment',
        eventId: 'history-root',
        startedAt: time,
        endedAt: time.add(const Duration(minutes: 2)),
        createdAt: time,
      ),
      RunSegment(
        id: 'history-child-segment',
        eventId: 'history-child',
        startedAt: time,
        endedAt: time.add(const Duration(minutes: 8)),
        createdAt: time,
      ),
    ]) {
      await database.database.insert('run_segments', {
        'id': segment.id,
        'event_id': segment.eventId,
        'started_at_utc': segment.startedAt.millisecondsSinceEpoch,
        'ended_at_utc': segment.endedAt!.millisecondsSinceEpoch,
        'created_at_utc': segment.createdAt.millisecondsSinceEpoch,
      });
    }

    await tester.pumpWidget(
      JaxApp(
        repository: repository,
        saveService: SqliteSaveService(database),
        now: () => time.add(const Duration(minutes: 5)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('上层：开发项目'), findsOneWidget);
    expect(find.text('同级事件：编写说明'), findsOneWidget);

    await tester.tap(find.text('事件'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('more-running')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('hierarchy-running')));
    await tester.pumpAndSettle();
    expect(find.text('开发项目'), findsWidgets);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('记录'));
    await tester.pumpAndSettle();
    expect(find.text('已完成项目'), findsOneWidget);
    expect(find.text('已完成步骤'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('history-detail-history-root')));
    await tester.pumpAndSettle();
    expect(find.text('总投入：10 分钟'), findsOneWidget);
    expect(find.text('直接执行：2 分钟'), findsOneWidget);
    expect(find.text('已完成步骤'), findsOneWidget);
  });
}
