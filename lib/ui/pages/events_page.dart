import 'package:flutter/material.dart';

import '../controllers/event_controller.dart';

class EventsPage extends StatelessWidget {
  const EventsPage({required this.controller, super.key});

  final EventController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Scaffold(
          body: controller.loading
              ? const Center(child: CircularProgressIndicator())
              : controller.events.isEmpty
              ? const Center(child: Text('暂无未完成事件'))
              : ListView.builder(
                  padding: const EdgeInsets.all(24),
                  itemCount: controller.events.length,
                  itemBuilder: (context, index) {
                    final event = controller.events[index];
                    return Card(
                      child: ListTile(
                        title: Text(event.name),
                        subtitle: const Text('未开始'),
                      ),
                    );
                  },
                ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => _CreateEventDialog(controller: controller),
            ),
            icon: const Icon(Icons.add),
            label: const Text('新建事件'),
          ),
        );
      },
    );
  }
}

class _CreateEventDialog extends StatefulWidget {
  const _CreateEventDialog({required this.controller});

  final EventController controller;

  @override
  State<_CreateEventDialog> createState() => _CreateEventDialogState();
}

class _CreateEventDialogState extends State<_CreateEventDialog> {
  final _textController = TextEditingController();
  String? _error;
  bool _submitting = false;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('新建事件'),
      content: TextField(
        controller: _textController,
        autofocus: true,
        decoration: InputDecoration(labelText: '事件名称', errorText: _error),
        onSubmitted: _submitting ? null : (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: const Text('创建'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    final message = await widget.controller.create(_textController.text);
    if (!mounted) return;
    if (message == null) {
      Navigator.pop(context);
    } else {
      setState(() {
        _submitting = false;
        _error = message;
      });
    }
  }
}
