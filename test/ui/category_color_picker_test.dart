import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jax/ui/widgets/category_color_picker.dart';

void main() {
  testWidgets(
    'shows eight selectable swatches with a clear current selection',
    (tester) async {
      var selected = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) => Scaffold(
              body: CategoryColorPicker(
                value: selected,
                onChanged: (value) => setState(() => selected = value),
              ),
            ),
          ),
        ),
      );

      for (var key = 0; key < 8; key++) {
        expect(find.byKey(ValueKey('category-color-$key')), findsOneWidget);
      }
      expect(find.byIcon(Icons.check), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('category-color-6')));
      await tester.pump();
      expect(selected, 6);
      expect(find.byIcon(Icons.check), findsOneWidget);
    },
  );
}
