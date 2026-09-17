import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/routine.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/ui/controllers/event_controller.dart';
import 'package:jax/ui/controllers/home_view_state.dart';
import 'package:jax/ui/pages/home_page.dart';

import '../support/memory_repository.dart';
import '../support/home_category_fixture.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    testWidgets(
      'Category survives temporal boundaries, banners and session navigation $platform',
      (tester) async {
        await tester.binding.setSurfaceSize(
          Size(platform == TargetPlatform.android ? 360 : 1200, 900),
        );
        addTearDown(() => tester.binding.setSurfaceSize(null));
        var now = DateTime(2026, 9, 15, 10, 59);
        final repo = MemoryRepository()
          ..routines.add(
            Routine(
              id: 'lunch',
              name: '午饭',
              recurrence: RoutineRecurrence.daily,
              weekdayMask: 0,
              isActive: true,
              sortOrder: 0,
              createdAt: now,
              updatedAt: now,
              timeRecommendation: const RoutineTimeRecommendation(
                startMinute: 660,
                endMinute: 661,
                latestEndMinute: 662,
              ),
            ),
          );
        final c = EventController(
          repository: repo,
          newId: () => 'unused',
          now: () => now,
        );
        await c.load();
        final navigation = HomeNavigationState();
        final planning = homeCategoryFixture(
          repo,
          now,
          includeDevelopment: true,
        );
        addTearDown(planning.dispose);
        Widget page() => MaterialApp(
          theme: ThemeData(platform: platform),
          home: Scaffold(
            body: HomePage(
              controller: c,
              navigation: navigation,
              planningController: planning,
              now: () => now,
              onOpenEvents: () {},
            ),
          ),
        );
        await tester.pumpWidget(page());
        await tester.pumpAndSettle();
        expect(find.text('接下来想做什么？'), findsOneWidget);
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.text('科研'), findsOneWidget);
        expect(find.text('开发项目'), findsOneWidget);
        expect(find.text('工作'), findsNothing);
        await tester.tap(
          find.byKey(const ValueKey('home-category-entry-research')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('home-category-view')),
          findsOneWidget,
        );
        expect(repo.events, isEmpty);
        expect(repo.routineExecutions, isEmpty);
        now = DateTime(2026, 9, 15, 11);
        await tester.pump(const Duration(minutes: 1));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('home-temporal-hint')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('home-category-view')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('home-primary-lunch')), findsNothing);
        await tester.tap(find.byKey(const ValueKey('home-temporal-view')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('home-primary-lunch')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('home-category-view')), findsNothing);
        expect(find.text('科研'), findsOneWidget);
        expect(find.text('开发项目'), findsOneWidget);
        expect(find.text('工作'), findsNothing);
        await tester.tap(find.byKey(const ValueKey('home-intent-back')));
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(page());
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('home-category-view')),
          findsOneWidget,
        );
        if (platform == TargetPlatform.android) {
          await tester.binding.handlePopRoute();
        } else {
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        }
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('home-primary-lunch')),
          findsOneWidget,
        );
        now = DateTime(2026, 9, 15, 11, 1, 0, 1);
        await tester.pump(const Duration(minutes: 1, milliseconds: 1));
        await tester.pumpAndSettle();
        expect(find.text('已超过理想时间 · 最晚 11:02'), findsOneWidget);
        now = DateTime(2026, 9, 15, 11, 2, 0, 1);
        await tester.pump(const Duration(minutes: 1));
        await tester.pumpAndSettle();
        expect(find.text('接下来想做什么？'), findsOneWidget);
        expect(repo.routineExecutions, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        c.dispose();
        navigation.dispose();
      },
    );
  }
  testWidgets(
    'temporary action uses standalone creation and starts only on submit',
    (tester) async {
      final repo = MemoryRepository([], false);
      var id = 0;
      final now = DateTime(2026, 9, 15, 10);
      final c = EventController(
        repository: repo,
        newId: () => 'id-${id++}',
        now: () => now,
      );
      await c.load();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomePage(controller: c, now: () => now, onOpenEvents: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('home-temporary')));
      await tester.pumpAndSettle();
      expect(repo.events, isEmpty);
      await tester.enterText(
        find.byKey(const ValueKey('standalone-event-name')),
        '临时处理',
      );
      await tester.tap(find.byKey(const ValueKey('save-standalone-event')));
      await tester.pumpAndSettle();
      expect(repo.events.single.isStandalone, isTrue);
      expect(repo.events.single.status, EventStatus.running);
      expect(repo.segments, hasLength(1));
      expect(repo.eventDayPlans, hasLength(1));
      expect(find.byKey(const ValueKey('home-running-hero')), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
    },
  );
  testWidgets(
    'waiting is a lightweight entrance and management can complete Event',
    (tester) async {
      final now = DateTime(2026, 9, 15, 10);
      final repo = MemoryRepository([
        JaxEvent(
          id: 'waiting',
          name: '等结果',
          status: EventStatus.waiting,
          createdAt: now,
          updatedAt: now,
        ),
      ]);
      final c = EventController(
        repository: repo,
        newId: () => 'unused',
        now: () => now,
      );
      await c.load();
      final planning = homeCategoryFixture(repo, now, includeDevelopment: true);
      addTearDown(planning.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomePage(
              controller: c,
              planningController: planning,
              now: () => now,
              onOpenEvents: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('接下来想做什么？'), findsOneWidget);
      expect(find.text('等结果'), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('home-category-entry-research')),
      );
      await tester.pumpAndSettle();
      expect(find.text('等待中的事项 · 1'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('home-waiting-open')));
      await tester.pumpAndSettle();
      expect(find.text('等结果'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('home-waiting-complete-waiting')),
      );
      await tester.pumpAndSettle();
      expect(repo.events.single.status, EventStatus.completed);
      expect(find.text('当前没有等待中的事项'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('home-category-view')), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
    },
  );
  testWidgets('running always wins while temporal boundary only adds a hint', (
    tester,
  ) async {
    var now = DateTime(2026, 9, 15, 10, 59);
    final repo = MemoryRepository();
    var id = 0;
    repo.routines.add(
      Routine(
        id: 'lunch',
        name: '午饭',
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
    final c = EventController(
      repository: repo,
      newId: () => 'id-${id++}',
      now: () => now,
    );
    await c.load();
    await c.createAndStartStandalone('研究');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomePage(controller: c, now: () => now, onOpenEvents: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final event = c.runningEvent!;
    now = DateTime(2026, 9, 15, 11);
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-running-hero')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-temporal-hint')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-primary-lunch')), findsNothing);
    expect(find.byKey(const ValueKey('home-root-ask')), findsNothing);
    expect(c.runningEvent!.id, event.id);
    expect(repo.routineExecutions, isEmpty);
    await c.complete(event.id);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-primary-lunch')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });
}
