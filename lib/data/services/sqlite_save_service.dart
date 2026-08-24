import '../../core/services/save_service.dart';
import '../database/app_database.dart';

class SqliteSaveService implements SaveService {
  const SqliteSaveService(this._database);

  final AppDatabase _database;

  @override
  Future<void> flush() async {
    await _database.database.rawQuery('PRAGMA wal_checkpoint(FULL)');
  }
}
