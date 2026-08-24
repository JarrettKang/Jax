import '../../core/entities/event_status.dart';
import '../../core/entities/jax_event.dart';
import '../../core/repositories/event_repository.dart';
import '../database/app_database.dart';

class SqliteEventRepository implements EventRepository {
  const SqliteEventRepository(this._appDatabase);

  final AppDatabase _appDatabase;

  @override
  Future<void> insertEvent(JaxEvent event) async {
    await _appDatabase.database.insert('events', _toRow(event));
  }

  @override
  Future<List<JaxEvent>> getIncompleteEvents() async {
    final rows = await _appDatabase.database.query(
      'events',
      where: 'status != ?',
      whereArgs: [EventStatus.completed.name],
      orderBy: 'created_at_utc ASC, id ASC',
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  Map<String, Object?> _toRow(JaxEvent event) => {
    'id': event.id,
    'name': event.name,
    'status': event.status.name,
    'first_started_at_utc': event.firstStartedAt?.millisecondsSinceEpoch,
    'completed_at_utc': event.completedAt?.millisecondsSinceEpoch,
    'created_at_utc': event.createdAt.millisecondsSinceEpoch,
    'updated_at_utc': event.updatedAt.millisecondsSinceEpoch,
  };

  JaxEvent _fromRow(Map<String, Object?> row) {
    DateTime? optionalTime(String column) {
      final value = row[column] as int?;
      return value == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
    }

    return JaxEvent(
      id: row['id']! as String,
      name: row['name']! as String,
      status: EventStatus.fromStorage(row['status']! as String),
      firstStartedAt: optionalTime('first_started_at_utc'),
      completedAt: optionalTime('completed_at_utc'),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        row['created_at_utc']! as int,
        isUtc: true,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        row['updated_at_utc']! as int,
        isUtc: true,
      ),
    );
  }
}
