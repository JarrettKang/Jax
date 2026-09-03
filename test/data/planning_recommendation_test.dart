import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/category.dart';
import 'package:jax/core/entities/plan.dart';
import 'package:jax/core/entities/plan_item.dart';
import 'package:jax/core/entities/world_node.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/repositories/sqlite_event_repository.dart';
import 'package:jax/data/repositories/sqlite_planning_repository.dart';
import 'package:jax/data/repositories/sqlite_world_node_repository.dart';
import 'package:jax/ui/controllers/planning_controller.dart';

void main() {
  test(
    'recommendations derive only focused next items in display order',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'jax-p3-recommend-',
      );
      final app = await AppDatabase.open('${directory.path}/jax.db');
      addTearDown(() async {
        await app.close();
        await directory.delete(recursive: true);
      });
      final events = SqliteEventRepository(app);
      final plans = SqlitePlanningRepository(app);
      final worlds = SqliteWorldNodeRepository(app);
      final now = DateTime.utc(2026, 9, 2, 8);
      await events.insertCategory(
        Category(
          id: 'a',
          name: 'Category A',
          sortOrder: 0,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await events.insertCategory(
        Category(
          id: 'b',
          name: 'Category B',
          sortOrder: 1,
          createdAt: now,
          updatedAt: now,
        ),
      );
      Future<void> node(String id, String name, int order, String category) =>
          worlds.insertWorldNode(
            WorldNode(
              id: id,
              name: name,
              status: WorldNodeStatus.inProgress,
              isFocused: id != '00000000-0000-4000-8000-000000000004',
              categoryId: category,
              sortOrder: order,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await node('00000000-0000-4000-8000-000000000003', 'A2', 1, 'a');
      await node('00000000-0000-4000-8000-000000000004', 'B1', 0, 'b');
      await node('00000000-0000-4000-8000-000000000005', 'A1', 0, 'a');

      Future<Plan> createPlan(String id, String nodeId) =>
          plans.createPlan(id: id, worldNodeId: nodeId, now: now);
      Future<void> createItem(
        Plan plan,
        String id,
        PlanItemStatus status,
      ) async {
        await plans.createPlanItem(
          id: id,
          planId: plan.id,
          title: id,
          now: now,
        );
        if (status != PlanItemStatus.draft) {
          await plans.setPlanItemStatus(id, status, now);
        }
      }

      final a2 = await createPlan(
        'a2-plan',
        '00000000-0000-4000-8000-000000000003',
      );
      await createItem(a2, 'a2-next-1', PlanItemStatus.next);
      await createItem(a2, 'a2-draft', PlanItemStatus.draft);
      await createItem(a2, 'a2-next-2', PlanItemStatus.next);
      final b1 = await createPlan(
        'b1-plan',
        '00000000-0000-4000-8000-000000000004',
      );
      await createItem(b1, 'waiting-next', PlanItemStatus.next);
      final a1 = await createPlan(
        'a1-plan',
        '00000000-0000-4000-8000-000000000005',
      );
      await createItem(a1, 'a1-next', PlanItemStatus.next);

      final controller = PlanningController(
        planningRepository: plans,
        worldNodeRepository: worlds,
        eventRepository: events,
        newId: () => 'unused',
        now: () => now,
      );
      await controller.load();

      expect(controller.recommendationGroups.map((value) => value.node.name), [
        'A1',
        'A2',
      ]);
      expect(
        controller.recommendationGroups
            .expand((value) => value.items)
            .map((value) => value.id),
        ['a1-next', 'a2-next-1', 'a2-next-2'],
      );
    },
  );
}
