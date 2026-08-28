import 'package:flutter/material.dart';

import 'category_color_picker.dart';

class CategoryEditDialog extends StatefulWidget {
  const CategoryEditDialog({
    required this.title,
    required this.initialColorKey,
    required this.onSave,
    this.initialName = '',
    super.key,
  });
  final String title;
  final String initialName;
  final int initialColorKey;
  final Future<String?> Function(String name, int colorKey) onSave;

  @override
  State<CategoryEditDialog> createState() => _CategoryEditDialogState();
}

class _CategoryEditDialogState extends State<CategoryEditDialog> {
  late final TextEditingController name;
  late int colorKey;
  String? error;

  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: widget.initialName);
    colorKey = widget.initialColorKey;
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const ValueKey('category-name'),
            controller: name,
            autofocus: true,
            decoration: InputDecoration(labelText: '名称', errorText: error),
          ),
          const SizedBox(height: 18),
          Text('颜色', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          CategoryColorPicker(
            value: colorKey,
            onChanged: (value) => setState(() => colorKey = value),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () async {
          final result = await widget.onSave(name.text, colorKey);
          if (!mounted) return;
          if (result == null) {
            Navigator.pop(this.context);
          } else {
            setState(() => error = result);
          }
        },
        child: const Text('保存'),
      ),
    ],
  );
}
