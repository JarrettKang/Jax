import '../../core/entities/event_status.dart';
import '../../core/entities/jax_event.dart';
import '../../core/repositories/event_repository.dart';
import '../database/app_database.dart';

class SqliteEventRepository implements EventRepository {
  const SqliteEventRepository(this._appDatabase);
  final AppDatabase _appDatabase;

  @override
  Future<void> insertEvent(JaxEvent event) =>
      _appDatabase.database.insert('events', _toRow(event));

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

  @override
  Future<JaxEvent?> getEvent(String id) async {
    final rows = await _appDatabase.database.query(
      'events',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : _fromRow(rows.single);
  }

  @override
  Future<void> updateEvent(JaxEvent event) async {
    final count = await _appDatabase.database.update(
      'events',
      _toRow(event),
      where: 'id = ?',
      whereArgs: [event.id],
    );
    if (count != 1) throw StateError('Event not found: ${event.id}');
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
    DateTime? optional(String key) {
      final value = row[key] as int?;
      return value == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
    }

    return JaxEvent(
      id: row['id']! as String,
      name: row['name']! as String,
      status: EventStatus.fromStorage(row['status']! as String),
      firstStartedAt: optional('first_started_at_utc'),
      completedAt: optional('completed_at_utc'),
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
