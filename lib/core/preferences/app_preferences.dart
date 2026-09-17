import 'package:characters/characters.dart';

/// The user-facing butler identity. Jax remains only a technical/project name.
const defaultAssistantName = 'Butler';
const maxAssistantNameLength = 24;

String? assistantNameError(String input) {
  final name = input.trim();
  if (name.isEmpty) return '名称不能为空';
  if (name.characters.length > maxAssistantNameLength) {
    return '名称最多 $maxAssistantNameLength 个字符';
  }
  return null;
}

class AppPreferences {
  const AppPreferences({this.assistantName = defaultAssistantName});
  final String assistantName;

  factory AppPreferences.named(String input) {
    final error = assistantNameError(input);
    if (error != null) throw ArgumentError(error);
    return AppPreferences(assistantName: input.trim());
  }
}

abstract interface class AppPreferencesStore {
  Future<AppPreferences> load();
  Future<void> save(AppPreferences preferences);
}

class InMemoryAppPreferencesStore implements AppPreferencesStore {
  AppPreferences _value = const AppPreferences();
  @override
  Future<AppPreferences> load() async => _value;
  @override
  Future<void> save(AppPreferences preferences) async {
    _value = AppPreferences.named(preferences.assistantName);
  }
}
