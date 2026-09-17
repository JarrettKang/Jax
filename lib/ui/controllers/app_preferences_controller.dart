import 'package:flutter/foundation.dart';

import '../../core/preferences/app_preferences.dart';

class AppPreferencesController extends ChangeNotifier {
  AppPreferencesController(this.store);
  final AppPreferencesStore store;
  AppPreferences value = const AppPreferences();
  bool loading = true;
  bool saving = false;
  String? error;
  bool _disposed = false;

  void _publish() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    loading = true;
    error = null;
    _publish();
    try {
      value = await store.load();
    } catch (_) {
      error = '读取设置失败，请重试';
    } finally {
      loading = false;
      _publish();
    }
  }

  Future<String?> setAssistantName(String input) async {
    final validation = assistantNameError(input);
    if (validation != null) return validation;
    if (loading || saving || error != null) return '设置尚未就绪，请重试';
    saving = true;
    _publish();
    try {
      final next = AppPreferences.named(input);
      await store.save(next);
      value = next;
      return null;
    } catch (_) {
      return '保存失败，请重试';
    } finally {
      saving = false;
      _publish();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
