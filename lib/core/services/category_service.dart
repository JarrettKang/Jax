import '../entities/category.dart';
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

  Future<Category> create(String rawName) async {
    final name = _validate(rawName);
    final categories = await repository.getCategories();
    if (categories.any((category) => category.name == name)) {
      throw const DomainFailure('分类名称已存在');
    }
    final timestamp = now().toUtc();
    final category = Category(
      id: newId(),
      name: name,
      sortOrder: categories.length,
      createdAt: timestamp,
      updatedAt: timestamp,
    );
    await repository.insertCategory(category);
    return category;
  }

  Future<Category> rename(String id, String rawName) async {
    final name = _validate(rawName);
    final current = (await repository.getCategories())
        .where((item) => item.id == id)
        .firstOrNull;
    if (current == null) throw const DomainFailure('分类不存在');
    final duplicate = (await repository.getCategories()).any(
      (item) => item.id != id && item.name == name,
    );
    if (duplicate) throw const DomainFailure('分类名称已存在');
    final updated = current.copyWith(name: name, updatedAt: now().toUtc());
    await repository.updateCategory(updated);
    return updated;
  }

  Future<void> delete(String id) => repository.deleteCategory(id);
  Future<void> reorder(String id, int index) =>
      repository.reorderCategory(id, index);
  Future<void> assign(String eventId, String? categoryId) =>
      repository.setRootCategory(eventId, categoryId);

  String _validate(String rawName) {
    final name = rawName.trim();
    if (name.isEmpty) throw const DomainFailure('分类名称不能为空');
    if (name == '未分类') throw const DomainFailure('未分类是系统分组，不能创建或重命名');
    return name;
  }
}
