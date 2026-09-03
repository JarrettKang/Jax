import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../core/entities/category.dart';
import '../../core/entities/category_palette.dart';
import '../../core/entities/event_status.dart';
import '../../core/entities/jax_event.dart';
import '../../core/entities/plan.dart';
import '../../core/entities/plan_item.dart';
import '../../core/entities/plan_review_note.dart';
import '../../core/entities/run_segment.dart';
import '../../core/entities/world_node.dart';
import '../../core/errors/domain_failure.dart';
import '../../core/repositories/event_repository.dart';
import '../../core/repositories/planning_repository.dart';
import '../../core/repositories/planning_dispatch_repository.dart';
import '../../core/repositories/world_node_repository.dart';
import '../../core/use_cases/create_event.dart' show Clock, IdGenerator;
import '../../core/use_cases/dispatch_plan_items.dart';

class PlanningController extends ChangeNotifier {
  PlanningController({
    required this.planningRepository,
    required this.worldNodeRepository,
    required this.eventRepository,
    required this.newId,
    required this.now,
  }) : _dispatch = planningRepository is PlanningDispatchRepository
           ? DispatchPlanItems(
               repository: planningRepository as PlanningDispatchRepository,
               newId: newId,
               now: now,
             )
           : null;

  final PlanningRepository planningRepository;
  final WorldNodeRepository worldNodeRepository;
  final EventRepository eventRepository;
  final IdGenerator newId;
  final Clock now;
  final DispatchPlanItems? _dispatch;

  List<Plan> plans = const [];
  List<WorldNode> worldNodes = const [];
  List<Category> categories = const [];
  final Map<String, List<PlanItem>> _items = {};
  final Map<String, List<PlanReviewNote>> _reviewNotes = {};
  final Map<String, JaxEvent> _linkedEvents = {};
  final Map<String, List<RunSegment>> _segments = {};
  bool loading = false;
  bool dispatching = false;
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
        eventRepository.getIncompleteEvents(),
        eventRepository.getCompletedEvents(),
        eventRepository.getAllRunSegments(),
      ]);
      plans = values[0] as List<Plan>;
      worldNodes = values[1] as List<WorldNode>;
      categories = values[2] as List<Category>;
      _items.clear();
      _reviewNotes.clear();
      _linkedEvents.clear();
      _segments.clear();
      for (final event in <JaxEvent>[
        ...(values[3] as List<JaxEvent>),
        ...(values[4] as List<JaxEvent>),
      ]) {
        if (event.sourcePlanItemId case final String itemId) {
          _linkedEvents[itemId] = event;
        }
      }
      for (final segment in values[5] as List<RunSegment>) {
        _segments.putIfAbsent(segment.eventId, () => []).add(segment);
      }
      for (final plan in plans) {
        _items[plan.id] = await planningRepository.getPlanItems(plan.id);
        _reviewNotes[plan.id] = await planningRepository.getPlanReviewNotes(
          plan.id,
        );
      }
    } catch (value) {
      error = value;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  List<PlanItem> itemsFor(String planId) => _items[planId] ?? const [];
  List<PlanReviewNote> reviewNotesFor(String planId) =>
      _reviewNotes[planId] ?? const [];
  JaxEvent? linkedEventFor(String planItemId) => _linkedEvents[planItemId];

  List<PlanningRecommendationGroup> get recommendationGroups {
    final groups = <PlanningRecommendationGroup>[];
    for (final plan in plans.where(
      (value) => value.status == PlanStatus.focused,
    )) {
      final items =
          itemsFor(plan.id)
              .where((item) => item.status == PlanItemStatus.next)
              .toList()
            ..sort(_itemOrder);
      final node = nodeFor(plan.worldNodeId);
      if (items.isEmpty || node == null) continue;
      groups.add(
        PlanningRecommendationGroup(
          plan: plan,
          node: node,
          category: categoryForNode(node),
          items: items,
        ),
      );
    }
    groups.sort((a, b) {
      final category = _categoryIndex(a.category)
          .compareTo(_categoryIndex(b.category));
      if (category != 0) return category;
      final node = _compareNodeDisplayOrder(a.node, b.node);
      if (node != 0) return node;
      final round = a.plan.roundNumber.compareTo(b.plan.roundNumber);
      return round != 0 ? round : a.plan.id.compareTo(b.plan.id);
    });
    return groups;
  }

  Future<void> dispatchRecommendations(Iterable<String> planItemIds) async {
    if (_dispatch == null) throw const DomainFailure('当前数据库不支持计划派发');
    if (dispatching) throw const DomainFailure('正在加入今日，请稍候');
    dispatching = true;
    notifyListeners();
    try {
      await _dispatch(planItemIds);
      await load();
    } finally {
      dispatching = false;
      notifyListeners();
    }
  }

  int _categoryIndex(Category? category) {
    if (category == null) return categories.length;
    final index = categories.indexWhere((value) => value.id == category.id);
    return index < 0 ? categories.length : index;
  }

  int _compareNodeDisplayOrder(WorldNode left, WorldNode right) {
    final a = _nodePath(left);
    final b = _nodePath(right);
    for (var index = 0; index < a.length && index < b.length; index++) {
      final order = a[index].sortOrder.compareTo(b[index].sortOrder);
      if (order != 0) return order;
      final id = a[index].id.compareTo(b[index].id);
      if (id != 0) return id;
    }
    return a.length.compareTo(b.length);
  }

  List<WorldNode> _nodePath(WorldNode node) {
    final path = <WorldNode>[node];
    var current = node;
    while (current.parentWorldNodeId != null) {
      final parentId = current.parentWorldNodeId!;
      final parent = nodeFor(parentId);
      if (parent == null) break;
      path.insert(0, parent);
      current = parent;
    }
    return path;
  }

  static int _itemOrder(PlanItem a, PlanItem b) {
    final order = a.sortOrder.compareTo(b.sortOrder);
    return order != 0 ? order : a.id.compareTo(b.id);
  }

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

  List<Plan> endedPlansFor(String worldNodeId) =>
      plans
          .where(
            (plan) =>
                plan.worldNodeId == worldNodeId &&
                plan.status == PlanStatus.ended,
          )
          .toList()
        ..sort((a, b) {
          final round = a.roundNumber.compareTo(b.roundNumber);
          return round != 0 ? round : a.createdAt.compareTo(b.createdAt);
        });

  List<WorldNode> pathFor(WorldNode node) => _nodePath(node);

  List<WorldNodeExecutionHistoryItem> executionHistoryFor(String worldNodeId) {
    final referenceTime = now();
    final planById = {
      for (final plan in plans.where((p) => p.worldNodeId == worldNodeId))
        plan.id: plan,
    };
    final itemById = <String, PlanItem>{};
    for (final entry in _items.entries) {
      if (!planById.containsKey(entry.key)) continue;
      for (final item in entry.value) {
        itemById[item.id] = item;
      }
    }
    final result = <WorldNodeExecutionHistoryItem>[];
    for (final entry in _linkedEvents.entries) {
      final item = itemById[entry.key];
      if (item == null) continue;
      final event = entry.value;
      final segments = _segments[event.id] ?? const [];
      final directDuration = segments.fold<Duration>(
        Duration.zero,
        (sum, segment) => sum + segment.durationAt(referenceTime),
      );
      DateTime recentAt = event.completedAt ?? event.updatedAt;
      for (final segment in segments) {
        final candidate = segment.endedAt ?? segment.startedAt;
        if (candidate.isAfter(recentAt)) recentAt = candidate;
      }
      result.add(
        WorldNodeExecutionHistoryItem(
          event: event,
          plan: planById[item.planId]!,
          planItem: item,
          directDuration: directDuration,
          recentAt: recentAt,
        ),
      );
    }
    result.sort((a, b) {
      final recent = b.recentAt.compareTo(a.recentAt);
      return recent != 0 ? recent : a.event.id.compareTo(b.event.id);
    });
    return result;
  }

  bool hasEndedPlan(String worldNodeId) => plans.any(
    (plan) =>
        plan.worldNodeId == worldNodeId && plan.status == PlanStatus.ended,
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

  Future<void> addReviewNote(Plan plan, String content) async {
    await planningRepository.createPlanReviewNote(
      id: newId(),
      planId: plan.id,
      content: content,
      now: now(),
    );
    await load();
  }

  Future<void> editReviewNote(PlanReviewNote note, String content) async {
    await planningRepository.editPlanReviewNote(
      note.id,
      content: content,
      now: now(),
    );
    await load();
  }

  Future<void> deleteReviewNote(PlanReviewNote note) async {
    await planningRepository.deletePlanReviewNote(note.id);
    await load();
  }
}

class WorldNodeExecutionHistoryItem {
  const WorldNodeExecutionHistoryItem({
    required this.event,
    required this.plan,
    required this.planItem,
    required this.directDuration,
    required this.recentAt,
  });

  final JaxEvent event;
  final Plan plan;
  final PlanItem planItem;
  final Duration directDuration;
  final DateTime recentAt;
}

class PlanningRecommendationGroup {
  const PlanningRecommendationGroup({
    required this.plan,
    required this.node,
    required this.category,
    required this.items,
  });

  final Plan plan;
  final WorldNode node;
  final Category? category;
  final List<PlanItem> items;
}

String planningEventStatusText(EventStatus status) => switch (status) {
  EventStatus.pending => '待开始',
  EventStatus.running => '进行中',
  EventStatus.paused => '暂停',
  EventStatus.waiting => '等待',
  EventStatus.completed => '已完成',
};
