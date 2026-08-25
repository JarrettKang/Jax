import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/services/greeting_resolver.dart';
import '../../core/use_cases/create_event.dart';
import '../controllers/event_controller.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    required this.controller,
    required this.now,
    required this.onOpenEvents,
    super.key,
  });

  final EventController controller;
  final Clock now;
  final VoidCallback onOpenEvents;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _greetingResolver = GreetingResolver();
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _scheduleGreetingRefresh();
  }

  @override
  void didUpdateWidget(HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.now != widget.now) _scheduleGreetingRefresh();
  }

  void _scheduleGreetingRefresh() {
    _refreshTimer?.cancel();
    final current = widget.now();
    final delay = _greetingResolver
        .nextChangeAfter(current)
        .difference(current.toLocal());
    _refreshTimer = Timer(delay.isNegative ? Duration.zero : delay, () {
      if (!mounted) return;
      setState(() {});
      _scheduleGreetingRefresh();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final running = widget.controller.runningEvent;
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _greetingResolver.resolve(widget.now),
                    key: const ValueKey('home-greeting'),
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 32),
                  if (widget.controller.loading)
                    const Center(child: CircularProgressIndicator())
                  else if (running == null)
                    Card(
                      child: InkWell(
                        key: const ValueKey('home-open-events'),
                        borderRadius: BorderRadius.circular(12),
                        onTap: widget.onOpenEvents,
                        child: const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('我们来做点什么？'),
                        ),
                      ),
                    )
                  else
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '当前正在执行：',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              running.name,
                              key: const ValueKey('home-running-event'),
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            if (widget.controller.runningParent != null) ...[
                              const Divider(height: 32),
                              Text(
                                '上层：${widget.controller.runningParent!.name}',
                                key: const ValueKey('home-running-parent'),
                              ),
                              if (widget
                                  .controller
                                  .runningSiblings
                                  .isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  '同级事件：${widget.controller.runningSiblings.map((event) => event.name).join('、')}',
                                  key: const ValueKey('home-running-siblings'),
                                ),
                              ],
                            ],
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
