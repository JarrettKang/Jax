import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/app.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/repositories/sqlite_event_repository.dart';
import 'package:jax/data/services/sqlite_save_service.dart';
import 'package:jax/ui/pages/home_page.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as android;

/// Current Today/Record workflow; preserves native SQLite and restart assertions.
Future<void> verifyExecutionWorkflow(WidgetTester tester) async {
  final directory = await Directory.systemTemp.createTemp('jax-rc-execution-');
  final filename = p.join(directory.path, 'fixture.db');
  Future<AppDatabase> open() => Platform.isAndroid
      ? AppDatabase.openWithFactory(filename, android.databaseFactory)
      : AppDatabase.open(filename);
  var database = await open();
  var repository = SqliteEventRepository(database);
  var now = DateTime.now();
  var sequence = 0;
  HomePage? home;
  Future<void> settle() async {
    // Native SQLite futures are not represented by scheduled animation frames.
    await tester.pump(const Duration(milliseconds: 200));
    for (var i = 0; i < 200 && home?.controller.loading == true; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(home?.controller.loading, isFalse);
    await tester.pumpAndSettle();
  }

  Future<void> mount() async {
    await tester.pumpWidget(
      JaxApp(
        repository: repository,
        saveService: SqliteSaveService(database),
        newId: () => 'rc-${sequence++}',
        now: () => now,
      ),
    );
    await tester.pump();
    home = tester.widget<HomePage>(find.byType(HomePage));
    await settle();
  }

  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await database.close();
    await directory.delete(recursive: true);
  });
  Future<void> today() async {
    await tester.tap(find.text('今日').last);
    await settle();
  }

  Future<String> create(String name) async {
    await tester.tap(find.byKey(const ValueKey('add-standalone-event')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('standalone-event-name')),
      name,
    );
    await tester.tap(find.byKey(const ValueKey('save-standalone-event')));
    await settle();
    return (await repository.getIncompleteEvents())
        .singleWhere((e) => e.name == name)
        .id;
  }

  Future<void> action(String id, String action, EventStatus expected) async {
    final target = find.byKey(ValueKey('$action-$id'));
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    expect(target.hitTestable(), findsOneWidget);
    await tester.tap(target);
    await settle();
    expect((await repository.getEvent(id))!.status, expected);
  }

  await mount();
  await today();
  final a = await create('RC task A');
  final b = await create('RC task B');
  await action(a, 'start', EventStatus.running);
  await action(b, 'start', EventStatus.running);
  expect((await repository.getEvent(a))!.status, EventStatus.paused);
  expect(
    (await repository.getIncompleteEvents()).where(
      (e) => e.status == EventStatus.running,
    ),
    hasLength(1),
  );
  await action(a, 'resume', EventStatus.running);
  expect((await repository.getEvent(b))!.status, EventStatus.paused);
  expect((await repository.getEvent(a))!.status, EventStatus.running);
  await tester.tap(find.text('首页').last);
  await settle();
  expect(find.text('RC task A'), findsWidgets);
  await today();
  now = now.add(const Duration(minutes: 9));
  await action(a, 'pause', EventStatus.paused);
  now = now.add(const Duration(minutes: 1));
  await action(b, 'resume', EventStatus.running);
  now = now.add(const Duration(minutes: 4));
  await action(b, 'pause', EventStatus.paused);
  now = now.add(const Duration(minutes: 2));
  await action(a, 'resume', EventStatus.running);
  now = now.add(const Duration(minutes: 6));
  await action(a, 'complete', EventStatus.completed);
  final segments = await repository.getRunSegments(a);
  expect(segments, hasLength(3));
  expect(
    segments.fold<Duration>(
      Duration.zero,
      (total, s) => total + s.durationAt(now),
    ),
    const Duration(minutes: 15),
  );
  await tester.tap(find.text('记录').last);
  await settle();
  Future<void> showRecord(String id) async {
    final finder = find.byKey(ValueKey('record-segment-$id'));
    await tester.scrollUntilVisible(
      finder,
      120,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('record-list')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(finder, findsOneWidget);
  }

  for (final segment in segments.where(
    (s) => s.durationAt(now) > Duration.zero,
  )) {
    await showRecord(segment.id);
    expect(
      find.byKey(ValueKey('record-segment-${segment.id}')),
      findsOneWidget,
    );
  }
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  await database.close();
  database = await open();
  repository = SqliteEventRepository(database);
  expect((await repository.getEvent(a))!.status, EventStatus.completed);
  expect((await repository.getEvent(b))!.status, EventStatus.paused);
  expect(await repository.getRunSegments(a), hasLength(3));
  await mount();
  await today();
  expect(find.byKey(ValueKey('resume-$b')), findsOneWidget);
  await tester.tap(find.text('记录').last);
  await settle();
  await showRecord(segments.last.id);
  expect(
    find.byKey(ValueKey('record-segment-${segments.last.id}')),
    findsOneWidget,
  );
  expect(tester.takeException(), isNull);
}
