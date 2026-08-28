import '../entities/routine_category.dart';
import '../entities/category_palette.dart';
import '../entities/category.dart';
import '../repositories/event_repository.dart';
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

  Future<void> create(String rawName, {int? colorKey}) async {
    final name = await _validated(rawName);
    final categories = await repository.getRoutineCategories();
    final timestamp = now().toUtc();
    final selectedColor = colorKey ?? await _recommendedColor(categories);
    _validateColor(selectedColor);
    await repository.insertRoutineCategory(
      RoutineCategory(
        id: newId(),
        name: name,
        sortOrder: categories.length,
        createdAt: timestamp,
        updatedAt: timestamp,
        colorKey: selectedColor,
      ),
    );
  }

  Future<void> update(
    RoutineCategory category,
    String rawName, {
    int? colorKey,
  }) async {
    final name = await _validated(rawName, exceptId: category.id);
    final selectedColor = colorKey ?? category.colorKey;
    _validateColor(selectedColor);
    await repository.updateRoutineCategory(
      category.copyWith(
        name: name,
        colorKey: selectedColor,
        updatedAt: now().toUtc(),
      ),
    );
  }

  Future<void> rename(RoutineCategory category, String rawName) =>
      update(category, rawName);

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

  Future<int> _recommendedColor(List<RoutineCategory> routineCategories) async {
    final List<Category> eventCategories = repository is EventRepository
        ? await (repository as EventRepository).getCategories()
        : const <Category>[];
    return CategoryPalette.leastUsed([
      ...eventCategories.map((category) => category.colorKey),
      ...routineCategories.map((category) => category.colorKey),
    ]);
  }

  void _validateColor(int colorKey) {
    if (!CategoryPalette.isValid(colorKey)) {
      throw const DomainFailure('分类颜色无效');
    }
  }
}
