import 'package:flutter/material.dart';

import '../../core/entities/jax_event.dart';
import '../controllers/event_controller.dart';

class EventsPage extends StatelessWidget {
  const EventsPage({required this.controller, super.key});
  final EventController controller;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => Scaffold(
      body: controller.loading
          ? const Center(child: CircularProgressIndicator())
          : controller.events.isEmpty
          ? const Center(child: Text('暂无未完成事件'))
          : ListView(
              padding: const EdgeInsets.all(24),
              children: controller.events
                  .map(
                    (event) => Card(
                      child: ListTile(
                        title: Text(event.name),
                        subtitle: const Text('未开始'),
                        trailing: IconButton(
                          key: ValueKey('edit-${event.id}'),
                          icon: const Icon(Icons.edit),
                          tooltip: '编辑',
                          onPressed: () => _showEditor(context, event),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEditor(context, null),
        icon: const Icon(Icons.add),
        label: const Text('新建事件'),
      ),
    ),
  );

  void _showEditor(BuildContext context, JaxEvent? event) => showDialog<void>(
    context: context,
    builder: (_) => _EventEditor(controller: controller, event: event),
  );
}

class _EventEditor extends StatefulWidget {
  const _EventEditor({required this.controller, this.event});
  final EventController controller;
  final JaxEvent? event;
  @override
  State<_EventEditor> createState() => _EventEditorState();
}

class _EventEditorState extends State<_EventEditor> {
  late final TextEditingController _text = TextEditingController(
    text: widget.event?.name,
  );
  String? _error;
  bool _busy = false;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.event == null ? '新建事件' : '编辑事件'),
    content: TextField(
      controller: _text,
      autofocus: true,
      decoration: InputDecoration(labelText: '事件名称', errorText: _error),
      onSubmitted: _busy ? null : (_) => _submit(),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: _busy ? null : _submit,
        child: Text(widget.event == null ? '创建' : '保存'),
      ),
    ],
  );
  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final message = widget.event == null
        ? await widget.controller.create(_text.text)
        : await widget.controller.edit(widget.event!.id, _text.text);
    if (!mounted) return;
    if (message == null) {
      Navigator.pop(context);
    } else {
      setState(() {
        _busy = false;
        _error = message;
      });
    }
  }
}
