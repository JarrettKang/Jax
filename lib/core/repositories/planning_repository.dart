import '../entities/plan.dart';
import '../entities/plan_item.dart';
import '../entities/plan_review_note.dart';

/// Compose existing Plan and PlanItem creation in one transaction.
abstract interface class FirstPlanningStepRepository {
  Future<Plan> createFirstPlanningStep({
    required String planId,
    required String itemId,
    required String worldNodeId,
    required String title,
    String? note,
    PlanItemStatus initialStatus = PlanItemStatus.next,
    required DateTime now,
  });
}

abstract interface class PlanningRepository {
  Future<List<Plan>> getPlans();
  Future<Plan?> getPlan(String id);
  Future<List<PlanItem>> getPlanItems(String planId);
  Future<List<PlanReviewNote>> getPlanReviewNotes(String planId);

  Future<Plan> createPlan({
    required String id,
    required String worldNodeId,
    String? title,
    required DateTime now,
  });
  Future<void> renamePlan(String id, String? title, DateTime now);
  Future<void> setPlanStatus(String id, PlanStatus status, DateTime now);
  Future<void> deletePlan(String id);

  Future<PlanItem> createPlanItem({
    required String id,
    required String planId,
    required String title,
    String? note,
    PlanItemStatus initialStatus = PlanItemStatus.next,
    required DateTime now,
  });
  Future<void> editPlanItem(
    String id, {
    required String title,
    String? note,
    required DateTime now,
  });
  Future<void> setPlanItemStatus(
    String id,
    PlanItemStatus status,
    DateTime now,
  );
  Future<void> deletePlanItem(String id);
  Future<void> reorderPlanItem(String id, int targetIndex, DateTime now);

  Future<PlanReviewNote> createPlanReviewNote({
    required String id,
    required String planId,
    required String content,
    required DateTime now,
  });
  Future<void> editPlanReviewNote(
    String id, {
    required String content,
    required DateTime now,
  });
  Future<void> deletePlanReviewNote(String id);
}
