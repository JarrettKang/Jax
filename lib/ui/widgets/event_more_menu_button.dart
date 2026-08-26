import 'package:flutter/material.dart';

/// Shared entry point for secondary actions on an Event.
///
/// The pages intentionally provide different menu items, but the trigger is
/// one Jax control so its icon, hit target, hover/focus behavior and tooltip
/// do not drift between list and World views.
class EventMoreMenuButton<T> extends StatelessWidget {
  const EventMoreMenuButton({
    required this.itemBuilder,
    required this.onSelected,
    super.key,
  });

  final PopupMenuItemBuilder<T> itemBuilder;
  final PopupMenuItemSelected<T> onSelected;

  @override
  Widget build(BuildContext context) => PopupMenuButton<T>(
    tooltip: '更多操作',
    icon: const Icon(Icons.more_vert),
    onSelected: onSelected,
    itemBuilder: itemBuilder,
  );
}
