import '../theme/operational_theme.dart';
import '../theme/planning_theme.dart';
import '../theme/desktop_polish.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/preferences/app_preferences.dart';
import '../controllers/app_preferences_controller.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({required this.controller, super.key});
  final AppPreferencesController controller;

  @override
  Widget build(BuildContext context) => OperationalVisualScope(
    builder: (context) => CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(title: const Text('设置')),
          body: AnimatedBuilder(
            animation: controller,
            builder: (context, _) => Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: ListView(
                  padding: OperationalTheme.pagePadding(context),
                  children: [
                    if (controller.loading) const LinearProgressIndicator(),
                    if (controller.error != null) ...[
                      Text(controller.error!),
                      TextButton(
                        onPressed: controller.load,
                        child: const Text('重试'),
                      ),
                    ],
                    PlanningRowSurface(
                      onTap: !controller.loading && controller.error == null
                          ? () => showDialog<void>(
                              context: context,
                              barrierDismissible: false,
                              builder: (_) =>
                                  _AssistantNameDialog(controller: controller),
                            )
                          : null,
                      child: ListTile(
                        key: const ValueKey('assistant-name-setting'),
                        title: const Text('管家的名字'),
                        subtitle: Text(controller.value.assistantName),
                        trailing: const Icon(Icons.chevron_right),
                        enabled:
                            !controller.loading && controller.error == null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _AssistantNameDialog extends StatefulWidget {
  const _AssistantNameDialog({required this.controller});
  final AppPreferencesController controller;
  @override
  State<_AssistantNameDialog> createState() => _AssistantNameDialogState();
}

class _AssistantNameDialogState extends State<_AssistantNameDialog> {
  late final TextEditingController _text;
  bool _saving = false;
  String? _saveError;
  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.controller.value.assistantName);
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || assistantNameError(_text.text) != null) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    final error = await widget.controller.setAssistantName(_text.text);
    if (!mounted) return;
    if (error == null) {
      Navigator.pop(context);
    } else {
      setState(() {
        _saving = false;
        _saveError = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final validation = assistantNameError(_text.text);
    return CallbackShortcuts(
      bindings: Theme.of(context).platform == TargetPlatform.windows
          ? {
              const SingleActivator(LogicalKeyboardKey.escape): () {
                if (!_saving) Navigator.of(context).pop();
              },
            }
          : const {},
      child: PopScope(
        canPop: !_saving,
        child: AlertDialog(
          constraints: DesktopPolish.dialog(context, DesktopDialogSize.form),
          scrollable: true,
          title: const Text('管家的名字'),
          content: SizedBox(
            width: 360,
            child: TextField(
              key: const ValueKey('assistant-name-input'),
              controller: _text,
              autofocus: true,
              enabled: !_saving,
              maxLength: maxAssistantNameLength,
              maxLengthEnforcement: MaxLengthEnforcement.none,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
              onChanged: (_) => setState(() => _saveError = null),
              decoration: InputDecoration(
                labelText: '名称',
                errorText: validation ?? _saveError,
              ),
            ),
          ),
          actions: [
            TextButton(
              key: const ValueKey('cancel-assistant-name'),
              onPressed: _saving ? null : () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              key: const ValueKey('save-assistant-name'),
              onPressed: _saving || validation != null ? null : _save,
              child: Text(_saving ? '保存中…' : '保存'),
            ),
          ],
        ),
      ),
    );
  }
}
