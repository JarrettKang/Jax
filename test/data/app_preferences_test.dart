import 'dart:io';
import 'dart:convert';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/preferences/app_preferences.dart';
import 'package:jax/data/preferences/file_app_preferences_store.dart';
import 'package:jax/ui/controllers/app_preferences_controller.dart';

void main() {
  late Directory directory;
  late File file;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('jax-name-test-');
    file = File('${directory.path}/app_preferences.json');
  });
  tearDown(() async => directory.delete(recursive: true));

  test(
    'missing config or field uses central default without writing',
    () async {
      final store = FileAppPreferencesStore(file);
      expect((await store.load()).assistantName, defaultAssistantName);
      expect(await file.exists(), isFalse);
      await file.writeAsString('{"unrelated":7}');
      final before = await file.readAsBytes();
      expect((await store.load()).assistantName, defaultAssistantName);
      expect(await file.readAsBytes(), before);
    },
  );
  test('trim, preserve case and Unicode, persist replacements and unrelated fields', () async {
    await file.writeAsString('{"unrelated":{"enabled":true}}');
    final store = FileAppPreferencesStore(file);
    for (final input in ['  Alfred  ', '小贾', 'aLfReD', '👩🏽‍🔬']) {
      await store.save(AppPreferences.named(input));
      expect(
        (await FileAppPreferencesStore(file).load()).assistantName,
        input.trim(),
      );
      expect(jsonDecode(await file.readAsString())['unrelated'], {
        'enabled': true,
      });
      expect(await File('${file.path}.pending').exists(), isFalse);
    }
  });
  test(
    'empty, whitespace and overlong are rejected without changing saved bytes',
    () async {
      final store = FileAppPreferencesStore(file);
      await store.save(AppPreferences.named('Alfred'));
      final before = await file.readAsBytes();
      for (final input in [
        '',
        '   ',
        '\t\n\u3000',
        List.filled(maxAssistantNameLength + 1, '名').join(),
      ]) {
        expect(
          store.save(AppPreferences(assistantName: input)),
          throwsArgumentError,
        );
      }
      expect(await file.readAsBytes(), before);
    },
  );
  test('limit counts user-visible graphemes rather than UTF16 units', () {
    final emoji = List.filled(maxAssistantNameLength, '👩🏽‍🔬').join();
    final accents = List.filled(maxAssistantNameLength, 'e\u0301').join();
    expect(assistantNameError(emoji), isNull);
    expect(assistantNameError(accents), isNull);
    expect(assistantNameError('$emoji👩🏽‍🔬'), isNotNull);
  });
  test(
    'corrupt preferences are surfaced and never silently overwritten',
    () async {
      await file.writeAsString('{broken');
      final store = FileAppPreferencesStore(file);
      await expectLater(store.load(), throwsFormatException);
      await expectLater(
        store.save(AppPreferences.named('Alfred')),
        throwsFormatException,
      );
      expect(await file.readAsString(), '{broken');
    },
  );
  test(
    'failed file write preserves old bytes and displayed name; retry succeeds',
    () async {
      final store = FileAppPreferencesStore(file);
      await store.save(const AppPreferences());
      final before = await file.readAsBytes();
      final blocked = Directory('${file.path}.pending');
      await blocked.create();
      final controller = AppPreferencesController(store);
      addTearDown(controller.dispose);
      await controller.load();
      expect(await controller.setAssistantName('Alfred'), '保存失败，请重试');
      expect(controller.value.assistantName, defaultAssistantName);
      expect(await file.readAsBytes(), before);
      await blocked.delete();
      expect(await controller.setAssistantName('Alfred'), isNull);
      expect(
        (await FileAppPreferencesStore(file).load()).assistantName,
        'Alfred',
      );
    },
  );
  test(
    'failed load is visible and retries without silently overwriting data',
    () async {
      await file.writeAsString('{broken');
      final controller = AppPreferencesController(
        FileAppPreferencesStore(file),
      );
      addTearDown(controller.dispose);
      await controller.load();
      expect(controller.error, isNotNull);
      expect(await controller.setAssistantName('Alfred'), isNotNull);
      expect(await file.readAsString(), '{broken');
      await file.writeAsString('{}');
      await controller.load();
      expect(controller.error, isNull);
      expect(controller.value.assistantName, defaultAssistantName);
    },
  );
  test('late load cannot race a save and duplicate save is blocked', () async {
    final store = _DelayedStore();
    final controller = AppPreferencesController(store);
    addTearDown(controller.dispose);
    final pending = controller.load();
    expect(await controller.setAssistantName('ignored'), isNotNull);
    store.read.complete(AppPreferences.named('小贾'));
    await pending;
    final saving = controller.setAssistantName('Alfred');
    expect(await controller.setAssistantName('ignored'), isNotNull);
    expect(controller.value.assistantName, '小贾');
    store.write.complete();
    await saving;
    expect(controller.value.assistantName, 'Alfred');
  });
}

class _DelayedStore implements AppPreferencesStore {
  final read = Completer<AppPreferences>();
  final write = Completer<void>();
  @override
  Future<AppPreferences> load() => read.future;
  @override
  Future<void> save(AppPreferences value) => write.future;
}
