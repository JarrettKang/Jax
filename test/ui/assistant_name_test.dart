import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/app.dart';
import 'package:jax/core/preferences/app_preferences.dart';
import 'package:jax/core/entities/routine.dart';
import 'package:jax/data/preferences/file_app_preferences_store.dart';

import '../support/memory_repository.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    testWidgets(
      'Name edits update Home and temporal, survive restart, keep a single butler identity and technical identifiers $platform',
      (tester) async {
        await tester.runAsync(() async {
          debugDefaultTargetPlatformOverride = platform;
          addTearDown(() => debugDefaultTargetPlatformOverride = null);
          await tester.binding.setSurfaceSize(
            Size(platform == TargetPlatform.android ? 360 : 1400, 900),
          );
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final dir = await Directory.systemTemp.createTemp('jax-name-ui-');
          addTearDown(() => dir.delete(recursive: true));
          final file = File('${dir.path}/app_preferences.json');
          var now = DateTime(2026, 9, 15, 10);
          final repo = MemoryRepository()
            ..routines.add(
              Routine(
                id: 'lunch',
                name: '吃午饭',
                recurrence: RoutineRecurrence.daily,
                weekdayMask: 0,
                isActive: true,
                sortOrder: 0,
                createdAt: now,
                updatedAt: now,
                timeRecommendation: const RoutineTimeRecommendation(
                  startMinute: 660,
                  endMinute: 780,
                ),
              ),
            );
          Widget app() => JaxApp(
            repository: repo,
            preferencesStore: FileAppPreferencesStore(file),
            now: () => now,
          );
          Future<void> settle() async {
            await Future<void>.delayed(const Duration(milliseconds: 100));
            await tester.pumpAndSettle();
          }

          Future<void> edit() async {
            await tester.tap(find.byKey(const ValueKey('open-settings')));
            await settle();
            expect(find.text('管家的名字'), findsOneWidget);
            await tester.tap(
              find.byKey(const ValueKey('assistant-name-setting')),
            );
            await settle();
            expect(
              find.descendant(
                of: find.byType(AlertDialog),
                matching: find.text('管家的名字'),
              ),
              findsOneWidget,
            );
          }

          Future<void> save(String name) async {
            await tester.enterText(
              find.byKey(const ValueKey('assistant-name-input')),
              name,
            );
            await settle();
            await tester.tap(find.byKey(const ValueKey('save-assistant-name')));
            await settle();
            expect(find.byType(AlertDialog), findsNothing);
            await tester.pageBack();
            await settle();
          }

          await tester.pumpWidget(app());
          await settle();
          expect(find.text(defaultAssistantName), findsOneWidget);
          expect(await file.exists(), isFalse);
          expect(find.text('Jax'), findsNothing);
          expect(
            tester
                .widget<Text>(
                  find.byKey(const ValueKey('current-module-title')),
                )
                .data,
            '首页',
          );
          expect(
            tester.widget<MaterialApp>(find.byType(MaterialApp)).title,
            'Jax',
          );
          await edit();
          expect(
            tester
                .widget<TextField>(
                  find.byKey(const ValueKey('assistant-name-input')),
                )
                .controller!
                .text,
            defaultAssistantName,
          );
          for (final invalid in [
            '',
            '   ',
            List.filled(maxAssistantNameLength + 1, '名').join(),
          ]) {
            await tester.enterText(
              find.byKey(const ValueKey('assistant-name-input')),
              invalid,
            );
            await settle();
            expect(
              tester
                  .widget<FilledButton>(
                    find.byKey(const ValueKey('save-assistant-name')),
                  )
                  .onPressed,
              isNull,
            );
            expect(await file.exists(), isFalse);
          }
          await tester.tap(find.byKey(const ValueKey('cancel-assistant-name')));
          await settle();
          await tester.pageBack();
          await settle();
          expect(find.text(defaultAssistantName), findsOneWidget);
          await edit();
          await save('  Alfred  ');
          expect(find.text('Alfred'), findsOneWidget);
          expect(find.text('Jax'), findsNothing);
          expect(
            (await FileAppPreferencesStore(file).load()).assistantName,
            'Alfred',
          );
          for (final module in ['首页', '今日', '世界', '规划', '日常', '记录']) {
            expect(
              find.text(module),
              module == '首页' ? findsNWidgets(2) : findsOneWidget,
            );
          }
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpWidget(app());
          await settle();
          expect(find.text('Alfred'), findsOneWidget);
          expect(find.text('Jax'), findsNothing);
          now = DateTime(2026, 9, 15, 12);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpWidget(app());
          await settle();
          expect(find.text('Alfred 建议您接下来：'), findsOneWidget);
          expect(find.text('吃午饭'), findsOneWidget);
          expect(find.text('Jax'), findsNothing);
          await edit();
          await save('Jax');
          expect(find.text('Jax 建议您接下来：'), findsOneWidget);
          expect(find.text(defaultAssistantName), findsNothing);
          now = DateTime(2026, 9, 15, 10);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpWidget(app());
          await settle();
          expect(find.text('Jax'), findsOneWidget);
          now = DateTime(2026, 9, 15, 12);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpWidget(app());
          await settle();
          await edit();
          await save('小贾');
          expect(find.text('小贾 建议您接下来：'), findsOneWidget);
          expect(find.text('Jax'), findsNothing);
          for (final long in [
            List.filled(maxAssistantNameLength, '名').join(),
            List.filled(maxAssistantNameLength, 'W').join(),
          ]) {
            await edit();
            await save(long);
            expect(find.text('$long 建议您接下来：'), findsOneWidget);
            expect(
              find.byKey(const ValueKey('home-primary-start')),
              findsOneWidget,
            );
            expect(tester.takeException(), isNull);
            now = DateTime(2026, 9, 15, 10);
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpWidget(app());
            await settle();
            expect(find.text(long), findsOneWidget);
            expect(tester.takeException(), isNull);
            now = DateTime(2026, 9, 15, 12);
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpWidget(app());
            await settle();
          }
          expect(
            tester.widget<MaterialApp>(find.byType(MaterialApp)).title,
            'Jax',
          );
          expect(repo.events, isEmpty);
          expect(repo.routineExecutions, isEmpty);
          await tester.pumpWidget(const SizedBox.shrink());
          debugDefaultTargetPlatformOverride = null;
        });
      },
    );
  }
}
