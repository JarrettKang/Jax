import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/repositories/sqlite_event_repository.dart';
import 'package:jax/data/services/sqlite_save_service.dart';

void main() {
  test('flush creates no backup and changes no business state', () async {
    final directory = await Directory.systemTemp.createTemp('jax-save-');
    addTearDown(() => directory.delete(recursive: true));
    final database = await AppDatabase.open(
      '${directory.path}${Platform.pathSeparator}jax.db',
    );
    addTearDown(database.close);
    final repository = SqliteEventRepository(database);
    final time = DateTime.utc(2026, 8, 24, 12);
    final event = JaxEvent(
      id: 'event',
      name: '保持不变',
      status: EventStatus.pending,
      createdAt: time,
      updatedAt: time,
    );
    await repository.insertEvent(event);
    final filesBefore = directory.listSync().map((file) => file.path).toSet();

    await SqliteSaveService(database).flush();

    expect(await repository.getEvent(event.id), event);
    expect(directory.listSync().map((file) => file.path).toSet(), filesBefore);
  });
}
