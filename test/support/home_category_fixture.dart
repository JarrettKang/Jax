import 'package:jax/core/entities/category.dart';
import 'package:jax/core/entities/world_node.dart';
import 'package:jax/core/repositories/planning_repository.dart';
import 'package:jax/core/repositories/world_node_repository.dart';
import 'package:jax/core/repositories/event_repository.dart';
import 'package:jax/ui/controllers/planning_controller.dart';

// In-memory read snapshot for fake-clock UI tests. Unexpected repository calls
// fail; production queries and writes are covered by SQLite integration tests.
class _UnusedRepositories implements PlanningRepository, WorldNodeRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class HomeSnapshotController extends PlanningController {
  HomeSnapshotController(EventRepository events, DateTime time)
    : super(
        planningRepository: _UnusedRepositories(),
        worldNodeRepository: _UnusedRepositories(),
        eventRepository: events,
        newId: () => 'unused',
        now: () => time,
      );
  @override
  Future<void> load() async => notifyListeners();
}

HomeSnapshotController homeCategoryFixture(
  EventRepository events,
  DateTime now, {
  bool includeDevelopment = false,
}) {
  return HomeSnapshotController(events, now)
    ..categories = [
      if (includeDevelopment)
        Category(
          id: 'dev',
          name: '开发项目',
          sortOrder: -1,
          createdAt: now,
          updatedAt: now,
        ),
      Category(
        id: 'research',
        name: '科研',
        sortOrder: 0,
        createdAt: now,
        updatedAt: now,
      ),
    ]
    ..worldNodes = [
      if (includeDevelopment)
        WorldNode(
          id: 'dev-node',
          name: 'Jax',
          categoryId: 'dev',
          status: WorldNodeStatus.inProgress,
          isFocused: true,
          sortOrder: 0,
          createdAt: now,
          updatedAt: now,
        ),
      WorldNode(
        id: 'research-node',
        name: '新的研究方向',
        categoryId: 'research',
        status: WorldNodeStatus.inProgress,
        isFocused: true,
        sortOrder: 0,
        createdAt: now,
        updatedAt: now,
      ),
    ];
}
