import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/entities/event_status.dart';
import '../../core/entities/jax_event.dart';
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
      final runningRoutine = widget.controller.runningRoutine;
      final work = widget.controller.homeRunningContext;
      final waiting = widget.controller.homeWaitingItems;
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
                  else if (running == null &&
                      runningRoutine == null &&
                      waiting.isEmpty)
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
                  else ...[
                    if (running == null && runningRoutine == null)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('当前没有正在执行的事项'),
                        ),
                      ),
                    if (work != null)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '当前正在做',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                work.subject.name,
                                key: const ValueKey('home-work-subject'),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall,
                              ),
                              if (work.ancestors.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  work.ancestors
                                      .map((event) => event.name)
                                      .join(' › '),
                                  key: const ValueKey('home-ancestor-path'),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                ),
                              ],
                              const Divider(height: 32),
                              if (work.omittedBefore)
                                const _OmissionRow(
                                  key: ValueKey('home-omitted-before'),
                                ),
                              for (final step in work.visibleSteps)
                                _StepRow(
                                  event: step,
                                  elapsed: widget.controller.elapsedFor(step),
                                ),
                              if (work.omittedAfter)
                                const _OmissionRow(
                                  key: ValueKey('home-omitted-after'),
                                ),
                            ],
                          ),
                        ),
                      ),
                    if (runningRoutine != null)
                      Card(
                        key: const ValueKey('home-running-routine'),
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '当前正在做',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                runningRoutine.name,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall,
                              ),
                              Text(
                                '日常 · ${widget.controller.categories.where((c) => c.id == runningRoutine.categoryId).firstOrNull?.name ?? '未分类'}',
                              ),
                              Text(
                                widget.controller
                                    .routineElapsed(runningRoutine)
                                    .toString()
                                    .split('.')
                                    .first,
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (waiting.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Text(
                        '同时在等待',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Card(
                        child: Column(
                          children: [
                            for (final item in waiting)
                              ListTile(
                                key: ValueKey('home-waiting-${item.event.id}'),
                                leading: const Icon(Icons.hourglass_empty),
                                title: Text(
                                  item.event.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: item.ancestors.isEmpty
                                    ? null
                                    : Text(
                                        item.ancestors
                                            .map((event) => event.name)
                                            .join(' › '),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.event, required this.elapsed});

  final JaxEvent event;
  final Duration elapsed;

  @override
  Widget build(BuildContext context) {
    final (icon, label) = switch (event.status) {
      EventStatus.completed => (Icons.check_circle_outline, '已完成'),
      EventStatus.running => (
        Icons.radio_button_checked,
        '进行中 · ${_duration(elapsed)}',
      ),
      EventStatus.paused => (Icons.pause_circle_outline, '已暂停'),
      EventStatus.waiting => (Icons.hourglass_empty, '等待中'),
      EventStatus.pending => (Icons.radio_button_unchecked, '未开始'),
    };
    return Padding(
      key: ValueKey('home-step-${event.id}'),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              icon,
              key: ValueKey('home-step-${event.status.name}-${event.id}'),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(event.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _duration(Duration value) =>
      '${value.inHours.toString().padLeft(2, '0')}:'
      '${(value.inMinutes % 60).toString().padLeft(2, '0')}:'
      '${(value.inSeconds % 60).toString().padLeft(2, '0')}';
}

class _OmissionRow extends StatelessWidget {
  const _OmissionRow({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Text(
      '⋮',
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.titleMedium
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );
}
