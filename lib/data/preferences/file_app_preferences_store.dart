import 'dart:convert';
import 'dart:io';

import '../../core/preferences/app_preferences.dart';

/// Device-local configuration, beside jax.db. Never included in business Sync.
/// Reading a missing file/field does not create or migrate any data.
class FileAppPreferencesStore implements AppPreferencesStore {
  FileAppPreferencesStore(this.file);
  final File file;

  Future<Map<String, dynamic>> _read() async {
    if (!await file.exists()) return {};
    final data = jsonDecode(await file.readAsString(encoding: utf8));
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Invalid preferences');
    }
    return data;
  }

  @override
  Future<AppPreferences> load() async {
    final data = await _read();
    final name = data['assistantName'];
    if (name == null) return const AppPreferences();
    if (name is! String) throw const FormatException('Invalid assistant name');
    return AppPreferences.named(name);
  }

  @override
  Future<void> save(AppPreferences preferences) async {
    final value = AppPreferences.named(preferences.assistantName);
    final data = await _read(); // Preserve unrelated/future preference keys.
    data['assistantName'] = value.assistantName;
    await file.parent.create(recursive: true);
    final staged = File('${file.path}.pending');
    await staged.writeAsString(jsonEncode(data), encoding: utf8, flush: true);
    // Replace only after a full flushed write; failure preserves the old file.
    await staged.rename(file.path);
  }
}
