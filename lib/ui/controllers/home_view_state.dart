import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../core/entities/category.dart';

import '../../core/entities/event_status.dart';
import '../../core/entities/jax_event.dart';
import '../../core/entities/plan_item.dart';
import '../../core/entities/world_node.dart';
import 'event_controller.dart';
import 'planning_controller.dart';
import 'today_temporal_view.dart';

/// Session-only navigation; deliberately excluded from persistence and Sync.
/// A null categoryId with categorySelected means the derived “其他” group.
class HomeNavigationState extends ChangeNotifier {
  bool categorySelected = false;
  String? categoryId;
  bool viewingRecommendation = false;
  final Map<String?, double> categoryOffsets = {};
  bool get canGoBack => viewingRecommendation || categorySelected;

  void selectCategory(String? id) {
    categorySelected = true;
    categoryId = id;
    viewingRecommendation = false;
    notifyListeners();
  }

  void recommendation() {
    viewingRecommendation = true;
    notifyListeners();
  }

  void validateCategories(PlanningController planning) {
    if (planning.loading || planning.error != null || !categorySelected) return;
    if (homeCategoryEntries(planning).any((c) => c?.id == categoryId)) return;
    categorySelected = false;
    viewingRecommendation = false;
    notifyListeners();
  }

  void back() {
    if (viewingRecommendation) {
      viewingRecommendation = false;
    } else {
      categorySelected = false;
    }
    notifyListeners();
  }
}

/// World order and effective (ancestor-root) category; no candidate requirement.
/// Null is a UI-only group and never inserts a Category.
List<Category?> homeCategoryEntries(PlanningController planning) {
  final ids = {
    for (final group in planning.focusedWorldNodePlanning) group.category?.id,
  };
  return [
    for (final category in planning.categories)
      if (ids.contains(category.id)) category,
    if (ids.contains(null)) null,
  ];
}

TodayTemporalView homeTemporalView(EventController controller) =>
    TodayTemporalView.derive(
      routines: controller.routines,
      day: controller.currentJaxDay,
      time: controller.currentTime,
      executionFor: controller.executionForOccurrence,
      runningRoutineId: controller.runningRoutine?.id,
      waitingRoutineIds: {
        ...controller.waitingRoutines.map((r) => r.id),
        ...controller.pausedRoutineExecutions.map((e) => e.routineId),
      },
    );

TodayTemporalEntry? homePrimaryRecommendation(EventController controller) =>
    homeTemporalView(controller).now
        .where((e) => e.execution == null)
        .firstOrNull;

class HomeCategoryItem {
  const HomeCategoryItem(this.item, this.event);
  final PlanItem item;
  final JaxEvent? event;
  String get identity => 'plan-${item.id}';
  String get name => event?.name ?? item.title;
}

class HomeCategoryGroup {
  const HomeCategoryGroup(this.node, this.items);
  final WorldNode node;
  final List<HomeCategoryItem> items;
}

/// Reuses Planning's focused/current query and Today's source identity rule.
/// Includes linked executions regardless of EventDayPlan membership.
List<HomeCategoryGroup> homeCategoryGroups(
  PlanningController planning,
  EventController execution, {
  required String? categoryId,
}) {
  final live = {
    for (final e in [...execution.events, ...execution.history])
      if (e.sourcePlanItemId != null) e.sourcePlanItemId!: e,
  };
  final groups = <HomeCategoryGroup>[];
  // One pass over already-loaded plans; no per-category database reads.
  final itemsByNode = <String, List<PlanItem>>{};
  for (final plan in planning.plans) {
    itemsByNode
        .putIfAbsent(plan.worldNodeId, () => [])
        .addAll(planning.itemsFor(plan.id));
  }
  for (final group in planning.focusedWorldNodePlanning) {
    if (group.category?.id != categoryId) continue;
    final sorted = List<PlanItem>.of(itemsByNode[group.node.id] ?? const [])
      ..sort((a, b) {
        final order = a.sortOrder.compareTo(b.sortOrder);
        return order != 0 ? order : a.id.compareTo(b.id);
      });
    final items = <HomeCategoryItem>[];
    for (final item in sorted) {
      if (item.isPromoted) continue;
      final event = live[item.id] ?? planning.linkedEventFor(item.id);
      if (event != null) {
        if (event.status != EventStatus.completed) {
          items.add(HomeCategoryItem(item, event));
        }
      } else if (item.planId == group.currentPlan?.id && item.isExecutable) {
        items.add(HomeCategoryItem(item, null));
      }
    }
    groups.add(HomeCategoryGroup(group.node, items));
  }
  return groups;
}
