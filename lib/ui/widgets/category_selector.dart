import 'package:flutter/material.dart';

import '../../core/entities/category.dart';

/// Shared nullable Category picker. `null` deliberately represents the
/// virtual, non-persisted "未分类" section.
class CategorySelector extends StatelessWidget {
  const CategorySelector({
    required this.categories,
    required this.value,
    required this.onChanged,
    super.key,
    this.selectorKey,
    this.enabled = true,
    this.helperText,
  });

  final List<Category> categories;
  final String? value;
  final ValueChanged<String?>? onChanged;
  final Key? selectorKey;
  final bool enabled;
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    final validValue = categories.any((category) => category.id == value)
        ? value
        : null;
    return KeyedSubtree(
      key: selectorKey,
      child: DropdownButtonFormField<String?>(
        key: ValueKey('category-value-${validValue ?? 'unclassified'}'),
        initialValue: validValue,
        isExpanded: true,
        decoration: InputDecoration(labelText: '分类', helperText: helperText),
        items: [
          const DropdownMenuItem(value: null, child: Text('未分类')),
          ...categories.map(
            (category) => DropdownMenuItem(
              value: category.id,
              child: Text(category.name, overflow: TextOverflow.ellipsis),
            ),
          ),
        ],
        onChanged: enabled ? onChanged : null,
      ),
    );
  }
}
