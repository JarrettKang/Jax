import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'core/repositories/event_repository.dart';
import 'core/use_cases/create_event.dart';
import 'ui/controllers/event_controller.dart';
import 'ui/pages/events_page.dart';
import 'ui/pages/history_page.dart';

class JaxApp extends StatefulWidget {
  JaxApp({required this.repository, IdGenerator? newId, Clock? now, super.key})
    : newId = newId ?? const Uuid().v4,
      now = now ?? DateTime.now;

  final EventRepository repository;
  final IdGenerator newId;
  final Clock now;

  @override
  State<JaxApp> createState() => _JaxAppState();
}

class _JaxAppState extends State<JaxApp> {
  late final EventController _controller;
  var _selectedIndex = 0;

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
      title: 'Jax',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF315C4C)),
        useMaterial3: true,
      ),
      home: Scaffold(
        appBar: AppBar(title: const Text('Jax')),
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
