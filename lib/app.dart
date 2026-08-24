import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'core/repositories/event_repository.dart';
import 'core/services/save_service.dart';
import 'core/use_cases/create_event.dart';
import 'ui/controllers/event_controller.dart';
import 'ui/pages/events_page.dart';
import 'ui/pages/history_page.dart';

class JaxApp extends StatefulWidget {
  JaxApp({
    required this.repository,
    SaveService? saveService,
    IdGenerator? newId,
    Clock? now,
    super.key,
  }) : saveService = saveService ?? const _ImmediateSaveService(),
       newId = newId ?? const Uuid().v4,
       now = now ?? DateTime.now;

  final EventRepository repository;
  final SaveService saveService;
  final IdGenerator newId;
  final Clock now;

  @override
  State<JaxApp> createState() => _JaxAppState();
}

class _JaxAppState extends State<JaxApp> {
  late final EventController _controller;
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  var _selectedIndex = 0;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = EventController(
      repository: widget.repository,
      newId: widget.newId,
      now: widget.now,
    );
    _controller.load();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.saveService.flush();
      _messengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('保存成功')),
      );
    } catch (_) {
      _messengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('保存失败，请重试')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      EventsPage(controller: _controller),
      HistoryPage(controller: _controller),
    ];

    return MaterialApp(
      scaffoldMessengerKey: _messengerKey,
      title: 'Jax',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF315C4C)),
        useMaterial3: true,
      ),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Jax'),
          actions: [
            IconButton(
              key: const ValueKey('manual-save'),
              tooltip: _saving ? '正在保存' : '保存',
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
            ),
          ],
        ),
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _selectedIndex,
              labelType: NavigationRailLabelType.all,
              onDestinationSelected: (index) {
                setState(() => _selectedIndex = index);
              },
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.checklist_outlined),
                  selectedIcon: Icon(Icons.checklist),
                  label: Text('事件'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.history_outlined),
                  selectedIcon: Icon(Icons.history),
                  label: Text('记录'),
                ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: pages[_selectedIndex]),
          ],
        ),
      ),
    );
  }
}

class _ImmediateSaveService implements SaveService {
  const _ImmediateSaveService();

  @override
  Future<void> flush() async {}
}
