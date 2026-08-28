import 'package:flutter/material.dart';

import '../../core/entities/category_palette.dart';
import '../theme/category_palette_colors.dart';

class CategoryColorPicker extends StatelessWidget {
  const CategoryColorPicker({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    key: const ValueKey('category-color-picker'),
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final key in CategoryPalette.keys)
        Tooltip(
          message: CategoryPaletteColors.hex(key),
          child: InkWell(
            key: ValueKey('category-color-$key'),
            customBorder: const CircleBorder(),
            onTap: () => onChanged(key),
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: CategoryPaletteColors.resolve(context, key),
                border: Border.all(
                  color: value == key
                      ? Theme.of(context).colorScheme.onSurface
                      : Colors.transparent,
                  width: 3,
                ),
              ),
              child: value == key
                  ? const Icon(Icons.check, size: 19, color: Colors.black87)
                  : null,
            ),
          ),
        ),
    ],
  );
}

class CategoryColorDot extends StatelessWidget {
  const CategoryColorDot({this.colorKey, super.key});
  final int? colorKey;

  @override
  Widget build(BuildContext context) => Container(
    key: ValueKey('category-color-dot-${colorKey ?? 'neutral'}'),
    width: 10,
    height: 10,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: colorKey == null
          ? CategoryPaletteColors.neutral(context)
          : CategoryPaletteColors.resolve(context, colorKey!),
    ),
  );
}
