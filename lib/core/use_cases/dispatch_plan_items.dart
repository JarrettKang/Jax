import '../entities/jax_day.dart';
import '../entities/jax_event.dart';
import '../errors/domain_failure.dart';
import '../repositories/planning_dispatch_repository.dart';
import 'create_event.dart';

class DispatchPlanItems {
  const DispatchPlanItems({
    required this.repository,
    required this.newId,
    required this.now,
  });

  final PlanningDispatchRepository repository;
  final IdGenerator newId;
  final Clock now;

  Future<List<JaxEvent>> call(Iterable<String> planItemIds) async {
    final ids = planItemIds.toSet().toList(growable: false);
    if (ids.isEmpty) throw const DomainFailure('请至少选择一个今日建议');
    final instant = now();
    return repository.dispatchPlanItems(
      eventIdsByPlanItemId: {for (final id in ids) id: newId()},
      dayKey: JaxDay.containing(instant).key,
      now: instant.toUtc(),
    );
  }
}
