import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../core/entities/category.dart';
import '../../core/entities/category_palette.dart';
import '../../core/entities/plan.dart';
import '../../core/entities/plan_item.dart';
import '../../core/entities/world_node.dart';
import '../../core/errors/domain_failure.dart';
import '../../core/repositories/event_repository.dart';
import '../../core/repositories/planning_repository.dart';
import '../../core/repositories/world_node_repository.dart';
import '../../core/use_cases/create_event.dart' show Clock, IdGenerator;

class PlanningController extends ChangeNotifier {
  PlanningController({
    required this.planningRepository,
    required this.worldNodeRepository,
    required this.eventRepository,
    required this.newId,
    required this.now,
  });

  final PlanningRepository planningRepository;
  final WorldNodeRepository worldNodeRepository;
  final EventRepository eventRepository;
  final IdGenerator newId;
  final Clock now;

  List<Plan> plans = const [];
  List<WorldNode> worldNodes = const [];
  List<Category> categories = const [];
  final Map<String, List<PlanItem>> _items = {};
  bool loading = false;
  Object? error;

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final values = await Future.wait([
        planningRepository.getPlans(),
        worldNodeRepository.getWorldNodes(),
        eventRepository.getCategories(),
      ]);
      plans = values[0] as List<Plan>;
      worldNodes = values[1] as List<WorldNode>;
      categories = values[2] as List<Category>;
      for (final plan in plans) {
        _items[plan.id] = await planningRepository.getPlanItems(plan.id);
      }
    } catch (value) {
      error = value;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  List<PlanItem> itemsFor(String planId) => _items[planId] ?? const [];
  WorldNode? nodeFor(String id) =>
      worldNodes.where((node) => node.id == id).firstOrNull;
  Category? categoryForNode(WorldNode node) {
    var current = node;
    while (current.parentWorldNodeId != null) {
      final parent = nodeFor(current.parentWorldNodeId!);
      if (parent == null) return null;
      current = parent;
    }
    return categories.where((c) => c.id == current.categoryId).firstOrNull;
  }

  bool hasCurrentPlan(String worldNodeId) =>
      plans.any((plan) => plan.worldNodeId == worldNodeId && plan.isCurrent);

  Plan? currentPlanFor(String worldNodeId) => plans
      .where((plan) => plan.worldNodeId == worldNodeId && plan.isCurrent)
      .firstOrNull;

  bool hasEndedPlan(String worldNodeId) => plans.any(
    (plan) => plan.worldNodeId == worldNodeId && plan.status == PlanStatus.ended,
  );

  Future<void> createCategory(String rawName) async {
    final name = rawName.trim();
    if (name.isEmpty) throw const DomainFailure('分类名称不能为空');
    if (categories.any((category) => category.name == name)) {
      throw const DomainFailure('分类名称已存在');
    }
    final timestamp = now().toUtc();
    await eventRepository.insertCategory(
      Category(
        id: newId(),
        name: name,
        sortOrder: categories.length,
        colorKey: CategoryPalette.leastUsed(
          categories.map((category) => category.colorKey),
        ),
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
    );
    await load();
  }

  Future<void> renameCategory(Category category, String rawName) async {
    final name = rawName.trim();
    if (name.isEmpty) throw const DomainFailure('分类名称不能为空');
    if (categories.any(
      (value) => value.id != category.id && value.name == name,
    )) {
      throw const DomainFailure('分类名称已存在');
    }
    await eventRepository.updateCategory(
      Category(
        id: category.id,
        name: name,
        sortOrder: category.sortOrder,
        colorKey: category.colorKey,
        createdAt: category.createdAt,
        updatedAt: now().toUtc(),
      ),
    );
    await load();
  }

  Future<void> deleteCategory(Category category) async {
    await eventRepository.deleteCategory(category.id);
    await load();
  }

  Future<void> moveCategory(Category category, int targetIndex) async {
    await eventRepository.reorderCategory(category.id, targetIndex);
    await load();
  }

  Future<void> createWorldNode(
    String rawName, {
    String? parentWorldNodeId,
    String? categoryId,
  }) async {
    final name = rawName.trim();
    if (name.isEmpty) throw const DomainFailure('世界节点名称不能为空');
    final siblings = worldNodes.where(
      (node) => parentWorldNodeId != null
          ? node.parentWorldNodeId == parentWorldNodeId
          : node.parentWorldNodeId == null && node.categoryId == categoryId,
    );
    final timestamp = now().toUtc();
    await worldNodeRepository.insertWorldNode(
      WorldNode(
        id: newId(),
        name: name,
        status: WorldNodeStatus.inProgress,
        parentWorldNodeId: parentWorldNodeId,
        categoryId: parentWorldNodeId == null ? categoryId : null,
        sortOrder: siblings.length,
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
    );
    await load();
  }

  Future<void> renameWorldNode(WorldNode node, String rawName) async {
    final name = rawName.trim();
    if (name.isEmpty) throw const DomainFailure('世界节点名称不能为空');
    await worldNodeRepository.updateWorldNode(
      node.copyWith(name: name, updatedAt: now().toUtc()),
    );
    await load();
  }

  Future<void> setWorldNodeStatus(
    WorldNode node,
    WorldNodeStatus status,
  ) async {
    await worldNodeRepository.updateWorldNode(
      node.copyWith(status: status, updatedAt: now().toUtc()),
    );
    await load();
  }

  Future<void> moveWorldNodeOrder(WorldNode node, int targetIndex) async {
    await worldNodeRepository.reorderWorldNode(node.id, targetIndex);
    await load();
  }

  Future<void> moveWorldNode(
    WorldNode node, {
    String? parentWorldNodeId,
    String? categoryId,
  }) async {
    final siblings = worldNodes.where(
      (value) => parentWorldNodeId != null
          ? value.parentWorldNodeId == parentWorldNodeId
          : value.parentWorldNodeId == null && value.categoryId == categoryId,
    );
    await worldNodeRepository.reparentWorldNode(
      node.id,
      parentWorldNodeId,
      parentWorldNodeId == null ? categoryId : null,
      siblings.length,
      now().toUtc(),
    );
    await load();
  }

  Future<Plan> createPlan(WorldNode node) async {
    final plan = await planningRepository.createPlan(
      id: newId(),
      worldNodeId: node.id,
      now: now(),
    );
    await load();
    return plan;
  }

  Future<void> renamePlan(Plan plan, String? title) async {
    await planningRepository.renamePlan(plan.id, title, now());
    await load();
  }

  Future<void> setPlanStatus(Plan plan, PlanStatus status) async {
    await planningRepository.setPlanStatus(plan.id, status, now());
    await load();
  }

  bool canDeletePlan(Plan plan) => itemsFor(plan.id).every(
    (item) =>
        item.status != PlanItemStatus.dispatched &&
        item.status != PlanItemStatus.done,
  );

  Future<void> deletePlan(Plan plan) async {
    await planningRepository.deletePlan(plan.id);
    await load();
  }

  Future<void> addItem(Plan plan, String title, String? note) async {
    await planningRepository.createPlanItem(
      id: newId(),
      planId: plan.id,
      title: title,
      note: note,
      now: now(),
    );
    await load();
  }

  Future<void> editItem(PlanItem item, String title, String? note) async {
    await planningRepository.editPlanItem(
      item.id,
      title: title,
      note: note,
      now: now(),
    );
    await load();
  }

  Future<void> setItemStatus(PlanItem item, PlanItemStatus status) async {
    await planningRepository.setPlanItemStatus(item.id, status, now());
    await load();
  }

  Future<void> deleteItem(PlanItem item) async {
    await planningRepository.deletePlanItem(item.id);
    await load();
  }

  Future<void> moveItem(PlanItem item, int targetIndex) async {
    await planningRepository.reorderPlanItem(item.id, targetIndex, now());
    await load();
  }
}
