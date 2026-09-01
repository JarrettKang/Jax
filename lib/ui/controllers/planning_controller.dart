import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../core/entities/category.dart';
import '../../core/entities/plan.dart';
import '../../core/entities/plan_item.dart';
import '../../core/entities/world_node.dart';
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
