import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class AppDatabase {
  AppDatabase._(this.database);

  final Database database;

  static const schemaVersion = 1;

  static Future<AppDatabase> inMemory() async {
    sqfliteFfiInit();
    final database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onCreate: _createSchema,
      ),
    );
    return AppDatabase._(database);
  }

  static Future<AppDatabase> open(String path) async {
    sqfliteFfiInit();
    final database = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (database) => database.execute('PRAGMA foreign_keys = ON'),
        onCreate: _createSchema,
      ),
    );
    return AppDatabase._(database);
  }

  static Future<void> _createSchema(Database database, int version) async {
    await database.execute('''
      CREATE TABLE events (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL CHECK(length(trim(name)) > 0),
        status TEXT NOT NULL CHECK(status IN ('pending', 'running', 'paused', 'completed')),
        first_started_at_utc INTEGER,
        completed_at_utc INTEGER,
        created_at_utc INTEGER NOT NULL,
        updated_at_utc INTEGER NOT NULL
      )
    ''');
  }

  Future<void> close() => database.close();
}
