import '../theme/desktop_polish.dart';

import 'package:flutter/material.dart';

import '../../core/entities/jax_event.dart';
import '../controllers/event_controller.dart';

Future<void> showHistoryDetailDialog(
  BuildContext context, {
  required EventController controller,
  required JaxEvent event,
}) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    constraints: DesktopPolish.dialog(context, DesktopDialogSize.form),
    title: Text(event.name, maxLines: 2, overflow: TextOverflow.ellipsis),
    content: FutureBuilder<Duration>(
      future: controller.directDuration(event.id),
      builder: (context, snapshot) => snapshot.hasData
          ? Text(
              '执行投入：${snapshot.requireData.inMinutes} 分钟',
              key: const ValueKey('history-direct-duration'),
            )
          : const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(),
            ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('关闭'),
      ),
    ],
  ),
);
