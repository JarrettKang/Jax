import '../theme/desktop_polish.dart';

import 'package:flutter/material.dart';

import '../controllers/event_controller.dart';

Future<(String, String?)?> showStandaloneEventDialog(
  BuildContext context,
  EventController controller, {
  String submitLabel = '添加到今日',
}) async {
  var name = '';
  String? categoryId;
  return showDialog<(String, String?)>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        constraints: DesktopPolish.dialog(
          dialogContext,
          DesktopDialogSize.form,
        ),
        title: const Text('添加临时事项'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('standalone-event-name'),
              autofocus: true,
              onChanged: (value) => name = value,
              decoration: const InputDecoration(labelText: '名称'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              key: const ValueKey('standalone-event-category'),
              initialValue: categoryId,
              decoration: const InputDecoration(labelText: '分类（可选）'),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('未分类'),
                ),
                for (final category in controller.categories)
                  DropdownMenuItem<String?>(
                    value: category.id,
                    child: Text(category.name),
                  ),
              ],
              onChanged: (value) => setState(() => categoryId = value),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey('save-standalone-event'),
            onPressed: () => Navigator.pop(dialogContext, (name, categoryId)),
            child: Text(submitLabel),
          ),
        ],
      ),
    ),
  );
}
