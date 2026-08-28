import '../entities/routine_category.dart';
import '../errors/domain_failure.dart';
import '../repositories/routine_repository.dart';
import '../use_cases/create_event.dart';

class RoutineCategoryService {
  const RoutineCategoryService({
    required this.repository,
    required this.newId,
    required this.now,
  });
  final RoutineRepository repository;
  final IdGenerator newId;
  final Clock now;

  Future<void> create(String rawName) async {
    final name = await _validated(rawName);
    final categories = await repository.getRoutineCategories();
    final timestamp = now().toUtc();
    await repository.insertRoutineCategory(
      RoutineCategory(
        id: newId(),
        name: name,
        sortOrder: categories.length,
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
    );
  }

  Future<void> rename(RoutineCategory category, String rawName) async {
    final name = await _validated(rawName, exceptId: category.id);
    await repository.updateRoutineCategory(
      category.copyWith(name: name, updatedAt: now().toUtc()),
    );
  }

  Future<void> delete(String id) => repository.deleteRoutineCategory(id);
  Future<void> reorder(String id, int index) =>
      repository.reorderRoutineCategory(id, index);

  Future<String> _validated(String raw, {String? exceptId}) async {
    final name = raw.trim();
    if (name.isEmpty) throw const DomainFailure('分类名称不能为空');
    if (name == '未分类') throw const DomainFailure('未分类是系统分组，不能创建或重命名');
    if ((await repository.getRoutineCategories()).any(
      (c) => c.id != exceptId && c.name == name,
    )) {
      throw const DomainFailure('分类名称已存在');
    }
    return name;
  }
}
