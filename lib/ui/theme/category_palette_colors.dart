import 'package:flutter/material.dart';

import '../../core/entities/category_palette.dart';

class CategoryPaletteColors {
  const CategoryPaletteColors._();

  static const light = <Color>[
    Color(0xFF6AD1A3),
    Color(0xFF7FBDDA),
    Color(0xFFBBC7BE),
    Color(0xFFFFD47D),
    Color(0xFFFFA288),
    Color(0xFFC49892),
    Color(0xFF929EAB),
    Color(0xFF84ADDC),
  ];

  static Color resolve(BuildContext context, int colorKey) {
    assert(CategoryPalette.isValid(colorKey));
    // Kept behind a theme-aware resolver so dark variants can be added later.
    return light[colorKey];
  }

  static Color neutral(BuildContext context) =>
      Theme.of(context).colorScheme.outline;

  static String hex(int colorKey) =>
      '#${light[colorKey].toARGB32().toRadixString(16).substring(2).toUpperCase()}';
}
