import 'package:jax/core/entities/category.dart';
import 'package:jax/core/entities/world_node.dart';
import 'package:jax/core/entities/plan_item.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/repositories/sqlite_event_repository.dart';
import 'package:jax/data/repositories/sqlite_world_node_repository.dart';
import 'package:jax/data/repositories/sqlite_planning_repository.dart';

String mapNodeId(int index) =>
    '40000000-0000-4000-8000-${index.toString().padLeft(12, '0')}';

Future<void> seedWorldMapFixture(AppDatabase app) async {
  final now = DateTime.utc(2026, 9, 8, 4);
  final events = SqliteEventRepository(app);
  final nodes = SqliteWorldNodeRepository(app);
  final plans = SqlitePlanningRepository(app);
  for (final (id, name, order) in [('research', '科研', 0), ('life', '生活', 1)]) {
    await events.insertCategory(
      Category(
        id: id,
        name: name,
        sortOrder: order,
        colorKey: order,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }
  // Requested example plus a sibling branch that continues across descendants.
  final rows = <(int, String, int?, int)>[
    (0, 'snowman粒子', null, 0),
    (1, '粗圆柱', null, 1),
    (2, 'Yukawa粒子', 1, 0),
    (3, 'WCA粒子', 1, 1),
    (4, '看分层倾斜角', 3, 0),
    (5, '胶体团簇拉伸', null, 2),
    (6, 'A：多层结构', null, 3),
    (7, 'B：父级', 6, 0),
    (8, 'C：中间分支', 6, 1),
    (9, 'C1', 8, 0),
    (10, 'C2', 8, 1),
    (11, 'D：下一分支', 6, 2),
    (12, 'E：第三层', 11, 0),
    (13, 'F：第四层', 12, 0),
    (17, 'G：第五层', 13, 0),
    (14, '第六层：这是一个很长的研究节点名称，用于验证深层缩进和多行截断', 17, 0),
    (15, '日常生活', null, 0),
    (16, '居住环境', 15, 0),
  ];
  for (final (index, name, parent, order) in rows) {
    await nodes.insertWorldNode(
      WorldNode(
        id: mapNodeId(index),
        name: name,
        status: index == 9
            ? WorldNodeStatus.completed
            : WorldNodeStatus.inProgress,
        isFocused: index == 3,
        parentWorldNodeId: parent == null ? null : mapNodeId(parent),
        categoryId: parent == null ? (index >= 15 ? 'life' : 'research') : null,
        sortOrder: order,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }
  await plans.createPlan(
    id: 'fixture-plan',
    worldNodeId: mapNodeId(3),
    now: now,
  );
  for (var i = 0; i < 2; i++) {
    await plans.createPlanItem(
      id: 'fixture-step-$i',
      planId: 'fixture-plan',
      title: '下一步 $i',
      initialStatus: PlanItemStatus.next,
      now: now,
    );
  }
}
