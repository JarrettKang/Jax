import '../entities/category.dart';
import '../entities/category_palette.dart';
import '../entities/routine_category.dart';
import '../repositories/routine_repository.dart';
import '../errors/domain_failure.dart';
import '../repositories/event_repository.dart';
import '../use_cases/create_event.dart';

class CategoryService {
  const CategoryService({
    required this.repository,
    required this.newId,
    required this.now,
  });
  final EventRepository repository;
  final IdGenerator newId;
  final Clock now;

  Future<Category> create(String rawName, {int? colorKey}) async {
    final name = _validate(rawName);
    final categories = await repository.getCategories();
    if (categories.any((category) => category.name == name)) {
      throw const DomainFailure('分类名称已存在');
    }
    final timestamp = now().toUtc();
    final selectedColor = colorKey ?? await _recommendedColor(categories);
    _validateColor(selectedColor);
    final category = Category(
      id: newId(),
      name: name,
      sortOrder: categories.length,
      createdAt: timestamp,
      updatedAt: timestamp,
      colorKey: selectedColor,
    );
    await repository.insertCategory(category);
    return category;
  }

  Future<Category> update(String id, String rawName, {int? colorKey}) async {
    final name = _validate(rawName);
    final current = (await repository.getCategories())
        .where((item) => item.id == id)
        .firstOrNull;
    if (current == null) throw const DomainFailure('分类不存在');
    final duplicate = (await repository.getCategories()).any(
      (item) => item.id != id && item.name == name,
    );
    if (duplicate) throw const DomainFailure('分类名称已存在');
    final selectedColor = colorKey ?? current.colorKey;
    _validateColor(selectedColor);
    final updated = current.copyWith(
      name: name,
      colorKey: selectedColor,
      updatedAt: now().toUtc(),
    );
    await repository.updateCategory(updated);
    return updated;
  }

  Future<Category> rename(String id, String rawName) => update(id, rawName);

  Future<void> delete(String id) => repository.deleteCategory(id);
  Future<void> reorder(String id, int index) =>
      repository.reorderCategory(id, index);
  Future<void> assign(String eventId, String? categoryId) =>
      repository.setStandaloneCategory(eventId, categoryId);

  String _validate(String rawName) {
    final name = rawName.trim();
    if (name.isEmpty) throw const DomainFailure('分类名称不能为空');
    if (name == '未分类') throw const DomainFailure('未分类是系统分组，不能创建或重命名');
    return name;
  }

  Future<int> _recommendedColor(List<Category> eventCategories) async {
    final List<RoutineCategory> routineCategories =
        repository is RoutineRepository
        ? await (repository as RoutineRepository).getRoutineCategories()
        : const <RoutineCategory>[];
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
