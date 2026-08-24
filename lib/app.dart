import 'package:flutter/material.dart';

import 'ui/pages/events_page.dart';
import 'ui/pages/history_page.dart';

class JaxApp extends StatelessWidget {
  const JaxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Jax',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF315C4C)),
        useMaterial3: true,
      ),
      home: const _JaxShell(),
    );
  }
}

class _JaxShell extends StatefulWidget {
  const _JaxShell();

  @override
  State<_JaxShell> createState() => _JaxShellState();
}

class _JaxShellState extends State<_JaxShell> {
  var _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      const EventsPage(),
      const HistoryPage(),
    ];

    return Scaffold(
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
    );
  }
}
