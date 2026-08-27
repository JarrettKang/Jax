import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/app.dart';
import 'package:jax/core/entities/category.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/preferences/world_category_collapse_store.dart';

import '../support/memory_repository.dart';

void main() {
  final now = DateTime(2026, 8, 28, 12);
  JaxEvent event(
    String id,
    EventStatus status, {
    String? name,
    String? parent,
    String? categoryId,
    int? order,
  }) => JaxEvent(
    id: id,
    name: name ?? id,
    status: status,
    parentEventId: parent,
    categoryId: categoryId,
    sortOrder: order,
    createdAt: now,
    updatedAt: now,
  );
  Category category(String id, String name, int order) => Category(
    id: id,
    name: name,
    sortOrder: order,
    createdAt: now,
    updatedAt: now,
  );
  Future<void> openWorld(WidgetTester tester) async {
    await tester.tap(find.text('世界'));
    await tester.pumpAndSettle();
  }

  Future<void> openDetail(WidgetTester tester, String? id) async {
    await tester.tap(find.byKey(ValueKey('world-category-open-$id')));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'overview shows ordered real and virtual Categories with structural counts',
    (tester) async {
      final repository =
          MemoryRepository([
              event(
                'dev-root',
                EventStatus.pending,
                categoryId: 'dev',
                order: 0,
              ),
              event(
                'dev-child',
                EventStatus.completed,
                parent: 'dev-root',
                order: 0,
              ),
              event(
                'research-root',
                EventStatus.running,
                categoryId: 'research',
                order: 1,
              ),
              event('loose-root', EventStatus.waiting, order: 2),
            ])
            ..categories.addAll([
              category('dev', '开发项目', 0),
              category('research', '科研', 1),
              category('empty', '生活起居', 2),
            ]);
      await tester.pumpWidget(JaxApp(repository: repository, now: () => now));
      await tester.pumpAndSettle();
      await openWorld(tester);

      expect(find.byKey(const ValueKey('world-overview')), findsOneWidget);
      expect(find.byKey(const ValueKey('world-tree')), findsNothing);
      for (final id in ['dev', 'research', 'empty', null]) {
        expect(find.byKey(ValueKey('world-category-$id')), findsOneWidget);
      }
      expect(find.text('2 个事件'), findsOneWidget);
      expect(find.text('1 个顶级事件'), findsNWidgets(3));
      expect(find.text('0 个事件'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('world-category-active-research')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('world-category-active-dev')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('world-category-more-null')),
        findsNothing,
      );
    },
  );

  testWidgets('unclassified is hidden when empty and empty World is natural', (
    tester,
  ) async {
    final repository = MemoryRepository()
      ..categories.add(category('empty', '空分类', 0));
    await tester.pumpWidget(JaxApp(repository: repository, now: () => now));
    await tester.pumpAndSettle();
    await openWorld(tester);
    expect(find.byKey(const ValueKey('world-category-empty')), findsOneWidget);
    expect(find.byKey(const ValueKey('world-category-null')), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(JaxApp(repository: MemoryRepository()));
    await tester.pumpAndSettle();
    await openWorld(tester);
    expect(find.text('你的世界还没有分类'), findsOneWidget);
    expect(find.byKey(const ValueKey('world-new-category')), findsOneWidget);
  });

  testWidgets('Category card opens only its full hierarchy and back returns', (
    tester,
  ) async {
    final repository =
        MemoryRepository([
            event('A', EventStatus.pending, categoryId: 'dev', order: 0),
            event('B', EventStatus.completed, parent: 'A', order: 0),
            event('C', EventStatus.paused, parent: 'A', order: 1),
            event('R', EventStatus.pending, categoryId: 'research', order: 1),
          ])
          ..categories.addAll([
            category('dev', '开发项目', 0),
            category('research', '科研', 1),
          ]);
    await tester.pumpWidget(JaxApp(repository: repository, now: () => now));
    await tester.pumpAndSettle();
    await openWorld(tester);
    await openDetail(tester, 'dev');

    expect(find.byKey(const ValueKey('world-tree')), findsOneWidget);
    for (final id in ['A', 'B', 'C']) {
      expect(find.byKey(ValueKey('world-node-$id')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('world-node-R')), findsNothing);
    expect(find.text('已完成'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('world-back-overview')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('world-overview')), findsOneWidget);
  });

  testWidgets(
    'Event collapse remains session state and legacy preferences are harmless',
    (tester) async {
      final preferences = InMemoryWorldCategoryCollapseStore();
      await preferences.setCollapsed(
        WorldCategoryCollapseStore.sectionKey('dev'),
        true,
      );
      final repository = MemoryRepository([
        event('A', EventStatus.pending, categoryId: 'dev'),
        event('B', EventStatus.paused, parent: 'A'),
        event('C', EventStatus.completed, parent: 'B'),
      ])..categories.add(category('dev', '开发项目', 0));
      await tester.pumpWidget(
        JaxApp(
          repository: repository,
          now: () => now,
          worldCategoryCollapseStore: preferences,
        ),
      );
      await tester.pumpAndSettle();
      await openWorld(tester);
      expect(find.byKey(const ValueKey('world-category-dev')), findsOneWidget);
      await openDetail(tester, 'dev');
      expect(find.byKey(const ValueKey('world-node-B')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('world-toggle-A')));
      await tester.pump();
      expect(find.byKey(const ValueKey('world-node-B')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('world-back-overview')));
      await tester.pumpAndSettle();
      await openDetail(tester, 'dev');
      expect(find.byKey(const ValueKey('world-node-B')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('world-toggle-A')));
      await tester.pump();
      expect(find.byKey(const ValueKey('world-node-C')), findsOneWidget);
    },
  );

  testWidgets('detail creates categorized and unclassified root Events', (
    tester,
  ) async {
    var id = 0;
    final repository = MemoryRepository([event('loose', EventStatus.pending)])
      ..categories.add(category('research', '科研', 0));
    await tester.pumpWidget(
      JaxApp(repository: repository, newId: () => 'new-${id++}'),
    );
    await tester.pumpAndSettle();
    await openWorld(tester);
    await openDetail(tester, 'research');
    expect(find.text('这个分类还没有事件'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('world-new-event')));
    await tester.pumpAndSettle();
    expect(find.text('由当前分类确定'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '测试 Yukawa');
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();
    final categorized = repository.events.singleWhere(
      (item) => item.name == '测试 Yukawa',
    );
    expect(categorized.parentEventId, isNull);
    expect(categorized.categoryId, 'research');
    expect(
      find.byKey(ValueKey('world-node-${categorized.id}')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('world-back-overview')));
    await tester.pumpAndSettle();
    expect(find.text('1 个事件'), findsNWidgets(2));
    await openDetail(tester, null);
    await tester.tap(find.byKey(const ValueKey('world-new-event')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '无分类新事件');
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();
    expect(
      repository.events.singleWhere((item) => item.name == '无分类新事件').categoryId,
      isNull,
    );
  });

  testWidgets('Category menu renames reorders and deletes without Event loss', (
    tester,
  ) async {
    final repository =
        MemoryRepository([event('A', EventStatus.pending, categoryId: 'dev')])
          ..categories.addAll([
            category('dev', '开发项目', 0),
            category('research', '科研', 1),
          ]);
    await tester.pumpWidget(JaxApp(repository: repository, now: () => now));
    await tester.pumpAndSettle();
    await openWorld(tester);

    await tester.tap(
      find.byKey(const ValueKey('world-category-more-research')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('上移'));
    await tester.pumpAndSettle();
    expect((await repository.getCategories()).first.id, 'research');

    await tester.tap(find.byKey(const ValueKey('world-category-more-dev')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重命名'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '工程');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('工程'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('world-category-more-dev')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除分类'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('world-category-dev')), findsNothing);
    expect(find.byKey(const ValueKey('world-category-null')), findsOneWidget);
    expect(repository.events.single.categoryId, isNull);
    await openDetail(tester, null);
    expect(find.byKey(const ValueKey('world-node-A')), findsOneWidget);
  });

  testWidgets('narrow overview uses two columns and detail does not overflow', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    const longCategory = '这是一个很长的开发项目分类名称用于验证小屏';
    const longEvent = '这是一个很长的深层事件名称用于验证世界页不会溢出';
    final repository =
        MemoryRepository([
            event(
              'root',
              EventStatus.pending,
              name: longEvent,
              categoryId: 'dev',
            ),
            event(
              'child',
              EventStatus.running,
              name: longEvent,
              parent: 'root',
            ),
          ])
          ..categories.addAll([
            category('dev', longCategory, 0),
            category('research', '科研', 1),
          ]);
    await tester.pumpWidget(JaxApp(repository: repository, now: () => now));
    await tester.pumpAndSettle();
    await openWorld(tester);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('world-category-dev'))).dy,
      tester
          .getTopLeft(find.byKey(const ValueKey('world-category-research')))
          .dy,
    );
    expect(tester.takeException(), isNull);
    await openDetail(tester, 'dev');
    expect(find.text(longEvent), findsNWidgets(2));
    expect(find.text('正在执行'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
