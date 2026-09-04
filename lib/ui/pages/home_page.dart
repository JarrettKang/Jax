import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/entities/category.dart';
import '../../core/entities/event_status.dart';
import '../../core/entities/jax_event.dart';
import '../../core/entities/routine.dart';
import '../../core/recommendation/recommendation_engine.dart';
import '../../core/services/greeting_resolver.dart';
import '../../core/use_cases/create_event.dart';
import '../controllers/event_controller.dart';
import '../theme/category_palette_colors.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    required this.controller,
    required this.now,
    required this.onOpenEvents,
    this.onAddPlanStep,
    super.key,
  });
  final EventController controller;
  final Clock now;
  final VoidCallback onOpenEvents;
  final Future<void> Function(BuildContext context, JaxEvent event)?
  onAddPlanStep;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _greeting = GreetingResolver();
  static const _waitingPreviewLimit = 4;
  Timer? _timer;
  var _showAllWaiting = false;
  @override
  void initState() {
    super.initState();
    _scheduleGreeting();
  }

  @override
  void didUpdateWidget(HomePage old) {
    super.didUpdateWidget(old);
    if (old.now != widget.now) _scheduleGreeting();
  }

  void _scheduleGreeting() {
    _timer?.cancel();
    final now = widget.now();
    final local = now.toLocal();
    final greetingDelay = _greeting.nextChangeAfter(now).difference(local);
    final minuteDelay = Duration(
      seconds: 60 - local.second,
      milliseconds: -local.millisecond,
    );
    final delay = greetingDelay < minuteDelay ? greetingDelay : minuteDelay;
    _timer = Timer(delay.isNegative ? Duration.zero : delay, () {
      if (!mounted) return;
      setState(() {});
      _scheduleGreeting();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      if (widget.controller.loading) {
        return const Center(child: CircularProgressIndicator());
      }
      final event = widget.controller.runningEvent;
      final routine = widget.controller.runningRoutine;
      final waiting = widget.controller.homeWaitingItems;
      final visibleWaiting = _showAllWaiting
          ? waiting
          : waiting.take(_waitingPreviewLimit).toList(growable: false);
      final recommendations = widget.controller.homeRecommendations
          .take(3)
          .toList(growable: false);
      final next = recommendations.map(_nextItem).toList(growable: false);
      final hasPrimary =
          recommendations.firstOrNull?.strength ==
          RecommendationStrength.promoted;
      final quickActions = _quickActions(routine);
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 72),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 880),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _greeting.resolve(widget.now).replaceFirst('，我是 Jax', ''),
                    key: const ValueKey('home-greeting'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (event != null)
                    _eventHero(event)
                  else if (routine != null)
                    _routineHero(routine)
                  else
                    const _IdleHero(),
                  if (waiting.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    _Title('等待中 · ${waiting.length}'),
                    for (final item in visibleWaiting)
                      _WaitingRow(
                        key: ValueKey('home-waiting-${item.event.id}'),
                        item: item,
                        contextLabel: _waitingContext(item),
                        onResume: () => _resumeWaiting(item),
                      ),
                    if (waiting.length > _waitingPreviewLimit)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          key: const ValueKey('home-waiting-show-all'),
                          onPressed: () => setState(
                            () => _showAllWaiting = !_showAllWaiting,
                          ),
                          child: Text(_showAllWaiting ? '收起' : '查看全部'),
                        ),
                      ),
                    const Divider(height: 40),
                  ] else
                    const SizedBox(height: 28),
                  _Title(event == null && routine == null ? '接下来可以做' : '接下来'),
                  if (next.isEmpty)
                    _EmptyNext(onOpenEvents: widget.onOpenEvents)
                  else if (hasPrimary) ...[
                    const _RecommendationLabel('首选'),
                    _NextRow(
                      key: ValueKey('home-next-${next.first.id}'),
                      item: next.first,
                      onStart: () => _start(next.first),
                    ),
                    if (next.length > 1) ...[
                      const _RecommendationLabel('其他可做'),
                      for (final item in next.skip(1))
                        _NextRow(
                          key: ValueKey('home-next-${item.id}'),
                          item: item,
                          onStart: () => _start(item),
                        ),
                    ],
                  ] else
                    for (final item in next)
                      _NextRow(
                        key: ValueKey('home-next-${item.id}'),
                        item: item,
                        onStart: () => _start(item),
                      ),
                  if (quickActions.isNotEmpty) ...[
                    const Divider(height: 40),
                    const _Title('快捷动作'),
                    for (final item in quickActions)
                      _NextRow(
                        key: ValueKey('home-on-demand-${item.id}'),
                        item: item,
                        actionLabel:
                            widget.controller
                                    .executionFor(item.routine!)
                                    ?.status ==
                                RoutineExecutionStatus.paused
                            ? '恢复'
                            : '开始',
                        onStart: () => _start(item),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _eventHero(JaxEvent event) {
    final category = _eventCategory(widget.controller, event);
    return _RunningHero(
      name: event.name,
      contextLabel: category?.name ?? '未分类',
      elapsed: widget.controller.elapsedFor(event),
      colorKey: category?.colorKey,
      onPause: () => _act(() => widget.controller.pause(event.id)),
      menu: PopupMenuButton<_HeroAction>(
        key: const ValueKey('home-running-more'),
        tooltip: '更多操作',
        onSelected: (value) {
          switch (value) {
            case _HeroAction.adjustStart:
              _showCorrectedStart(
                startedAt: widget.controller.runningEventStartedAt(event.id),
                save: (expected, value) => widget.controller
                    .adjustRunningEventStart(event.id, expected, value),
              );
            case _HeroAction.addPlanStep:
              widget.onAddPlanStep?.call(context, event);
            case _HeroAction.complete:
              _act(() => widget.controller.complete(event.id));
            case _HeroAction.completeCorrected:
              _showCorrectedCompletion(
                startedAt: widget.controller.runningEventStartedAt(event.id),
                complete: (end) => widget.controller.completeAt(event.id, end),
              );
            case _HeroAction.wait:
              _act(() => widget.controller.wait(event.id));
          }
        },
        itemBuilder: (_) => [
          if (event.isPlanned && widget.onAddPlanStep != null)
            const PopupMenuItem(
              value: _HeroAction.addPlanStep,
              child: Text('补充计划步骤…'),
            ),
          const PopupMenuItem(
            value: _HeroAction.adjustStart,
            child: Text('修改开始时间…'),
          ),
          const PopupMenuItem(
            value: _HeroAction.completeCorrected,
            child: Text('完成并修改结束时间…'),
          ),
          const PopupMenuItem(value: _HeroAction.wait, child: Text('等待')),
          const PopupMenuItem(value: _HeroAction.complete, child: Text('完成')),
        ],
      ),
      progress: _ContextProgress(controller: widget.controller),
    );
  }

  Widget _routineHero(Routine routine) {
    final category = widget.controller.routineCategories
        .where((c) => c.id == routine.routineCategoryId)
        .firstOrNull;
    return _RunningHero(
      name: routine.name,
      contextLabel:
          '${category?.name ?? '未分类'} · ${routine.isScheduled ? _recurrence(routine.recurrence) : '按需'}',
      elapsed: widget.controller.routineElapsed(routine),
      colorKey: category?.colorKey,
      onPause: () => _act(() => widget.controller.pauseRoutine(routine)),
      menu: PopupMenuButton<_HeroAction>(
        key: const ValueKey('home-running-more'),
        tooltip: '更多操作',
        onSelected: (value) {
          switch (value) {
            case _HeroAction.adjustStart:
              _showCorrectedStart(
                startedAt: widget.controller.runningRoutineStartedAt(routine),
                save: (expected, value) => widget.controller
                    .adjustRunningRoutineStart(routine, expected, value),
              );
            case _HeroAction.addPlanStep:
              break;
            case _HeroAction.complete:
              _act(() => widget.controller.completeRoutine(routine));
            case _HeroAction.completeCorrected:
              _showCorrectedCompletion(
                startedAt: widget.controller.runningRoutineStartedAt(routine),
                complete: (end) =>
                    widget.controller.completeRoutineAt(routine, end),
              );
            case _HeroAction.wait:
              break;
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: _HeroAction.adjustStart, child: Text('修改开始时间…')),
          PopupMenuItem(
            value: _HeroAction.completeCorrected,
            child: Text('完成并修改结束时间…'),
          ),
          PopupMenuItem(value: _HeroAction.complete, child: Text('完成')),
        ],
      ),
    );
  }

  _NextItem _nextItem(Recommendation recommendation) {
    final candidate = recommendation.candidate;
    final event = candidate.event;
    if (event != null) {
      final category = _eventCategory(widget.controller, event);
      return _NextItem.event(
        event,
        category?.name ?? '未分类',
        category?.colorKey,
        reason: recommendation.reason,
      );
    }
    final routine = candidate.routine!;
    final category = widget.controller.routineCategories
        .where((c) => c.id == routine.routineCategoryId)
        .firstOrNull;
    return _NextItem.routine(
      routine,
      '${category?.name ?? '未分类'} · ${_recurrence(routine.recurrence)}',
      category?.colorKey,
      reason: recommendation.reason,
    );
  }

  List<_NextItem> _quickActions(Routine? runningRoutine) => widget
      .controller
      .activeOnDemandRoutines
      .where((routine) => routine.id != runningRoutine?.id)
      .take(4)
      .map((routine) {
        final category = widget.controller.routineCategories
            .where((item) => item.id == routine.routineCategoryId)
            .firstOrNull;
        return _NextItem.routine(
          routine,
          '${category?.name ?? '未分类'} · 按需',
          category?.colorKey,
        );
      })
      .toList(growable: false);

  String _waitingContext(HomeWaitingItem item) {
    final category = _eventCategory(widget.controller, item.event);
    final hierarchy = item.ancestors.map((event) => event.name).join(' › ');
    return [
      category?.name ?? '未分类',
      if (hierarchy.isNotEmpty) hierarchy,
    ].join(' · ');
  }

  Future<void> _resumeWaiting(HomeWaitingItem item) => _start(
    _NextItem.event(
      item.event,
      _waitingContext(item),
      _eventCategory(widget.controller, item.event)?.colorKey,
    ),
  );

  Future<void> _start(_NextItem item) async {
    final runningEvent = widget.controller.runningEvent;
    final runningRoutine = widget.controller.runningRoutine;
    if (runningEvent != null && runningEvent.id != item.id) {
      final pauseError = await widget.controller.pause(runningEvent.id);
      if (pauseError != null) {
        _showError(pauseError);
        return;
      }
    } else if (runningRoutine != null && runningRoutine.id != item.id) {
      final pauseError = await widget.controller.pauseRoutine(runningRoutine);
      if (pauseError != null) {
        _showError(pauseError);
        return;
      }
    }
    final error = item.event != null
        ? item.event!.status == EventStatus.paused ||
                  item.event!.status == EventStatus.waiting
              ? await widget.controller.resume(item.id)
              : await widget.controller.start(item.id)
        : await widget.controller.startRoutine(item.routine!);
    _showError(error);
  }

  Future<void> _act(Future<String?> Function() action) async =>
      _showError(await action());

  Future<void> _showCorrectedCompletion({
    required DateTime? startedAt,
    required Future<String?> Function(DateTime end) complete,
  }) async {
    if (startedAt == null) {
      _showError('执行计时数据不完整');
      return;
    }
    var end = widget.controller.currentTime;
    String? error;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('修改结束时间'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('开始时间：${_dateTime(startedAt)}'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text('结束时间：'),
                    OutlinedButton(
                      onPressed: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: end,
                          firstDate: DateTime(
                            startedAt.year,
                            startedAt.month,
                            startedAt.day,
                          ),
                          lastDate: widget.controller.currentTime,
                        );
                        if (date != null) {
                          setDialog(() {
                            end = DateTime(
                              date.year,
                              date.month,
                              date.day,
                              end.hour,
                              end.minute,
                            );
                            error = null;
                          });
                        }
                      },
                      child: Text(_date(end)),
                    ),
                    OutlinedButton(
                      onPressed: () async {
                        final time = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.fromDateTime(end),
                        );
                        if (time != null) {
                          setDialog(() {
                            end = DateTime(
                              end.year,
                              end.month,
                              end.day,
                              time.hour,
                              time.minute,
                            );
                            error = null;
                          });
                        }
                      },
                      child: Text(_clock(end)),
                    ),
                  ],
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                final result = await complete(end);
                if (!context.mounted) return;
                if (result == null) {
                  Navigator.pop(dialogContext);
                } else {
                  setDialog(() => error = result);
                }
              },
              child: const Text('完成'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCorrectedStart({
    required DateTime? startedAt,
    required Future<String?> Function(DateTime expected, DateTime value) save,
  }) async {
    if (startedAt == null) {
      _showError('执行计时数据不完整');
      return;
    }
    final expected = startedAt;
    var value = startedAt;
    String? error;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('修改开始时间'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('当前记录开始于：${_dateTime(expected)}'),
                const SizedBox(height: 12),
                const Text('实际开始时间：'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      key: const ValueKey('running-start-date'),
                      onPressed: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: value,
                          firstDate: DateTime(2000),
                          lastDate: widget.controller.currentTime,
                        );
                        if (date != null) {
                          setDialog(() {
                            value = DateTime(
                              date.year,
                              date.month,
                              date.day,
                              value.hour,
                              value.minute,
                            );
                            error = null;
                          });
                        }
                      },
                      child: Text(_date(value)),
                    ),
                    OutlinedButton(
                      key: const ValueKey('running-start-time'),
                      onPressed: () async {
                        final time = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.fromDateTime(value),
                        );
                        if (time != null) {
                          setDialog(() {
                            value = DateTime(
                              value.year,
                              value.month,
                              value.day,
                              time.hour,
                              time.minute,
                            );
                            error = null;
                          });
                        }
                      },
                      child: Text(_clock(value)),
                    ),
                  ],
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              key: const ValueKey('save-running-start'),
              onPressed: () async {
                final result = await save(expected, value);
                if (!context.mounted) return;
                if (result == null) {
                  Navigator.pop(dialogContext);
                } else {
                  setDialog(() => error = result);
                }
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  String _date(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  String _clock(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  String _dateTime(DateTime value) => '${_date(value)} ${_clock(value)}';
  void _showError(String? error) {
    if (error != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
  }
}

class _RunningHero extends StatelessWidget {
  const _RunningHero({
    required this.name,
    required this.contextLabel,
    required this.elapsed,
    required this.onPause,
    required this.menu,
    this.colorKey,
    this.progress,
  });
  final String name, contextLabel;
  final Duration elapsed;
  final int? colorKey;
  final VoidCallback onPause;
  final Widget menu;
  final Widget? progress;
  @override
  Widget build(BuildContext context) {
    final accent = colorKey == null
        ? CategoryPaletteColors.neutral(context)
        : CategoryPaletteColors.resolve(context, colorKey!);
    return Container(
      key: const ValueKey('home-running-hero'),
      padding: const EdgeInsets.fromLTRB(22, 20, 16, 18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(color: accent, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text('正在执行', style: Theme.of(context).textTheme.labelLarge),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            name,
            key: const ValueKey('home-running-name'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 5),
          Text(
            contextLabel,
            key: const ValueKey('home-running-context'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            _duration(elapsed),
            key: const ValueKey('home-running-duration'),
            style: Theme.of(context).textTheme.displaySmall
                ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  key: const ValueKey('home-running-pause'),
                  onPressed: onPause,
                  icon: const Icon(Icons.pause),
                  label: const Text('暂停'),
                ),
              ),
              const SizedBox(width: 8),
              menu,
            ],
          ),
          if (progress != null) ...[const Divider(height: 28), progress!],
        ],
      ),
    );
  }
}

class _ContextProgress extends StatelessWidget {
  const _ContextProgress({required this.controller});
  final EventController controller;
  @override
  Widget build(BuildContext context) {
    final work = controller.homeRunningContext;
    if (work == null || work.visibleSteps.length <= 1) {
      return const SizedBox.shrink();
    }
    final completed = work.visibleSteps
        .where((e) => e.status == EventStatus.completed)
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${work.subject.name} · $completed / ${work.visibleSteps.length} 已完成',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 6),
        for (final step in work.visibleSteps)
          Padding(
            key: ValueKey('home-step-${step.id}'),
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Icon(
                  step.status == EventStatus.completed
                      ? Icons.check
                      : step.status == EventStatus.running
                      ? Icons.arrow_right
                      : Icons.remove,
                  key: ValueKey('home-step-${step.status.name}-${step.id}'),
                  size: 17,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    step.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _IdleHero extends StatelessWidget {
  const _IdleHero();
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Text(
      '现在没有正在执行的事项',
      key: const ValueKey('home-idle-title'),
      style: Theme.of(context).textTheme.headlineSmall,
    ),
  );
}

class _Title extends StatelessWidget {
  const _Title(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );
}

class _RecommendationLabel extends StatelessWidget {
  const _RecommendationLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 5, bottom: 1),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelSmall
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );
}

class _NextRow extends StatelessWidget {
  const _NextRow({
    required this.item,
    required this.onStart,
    this.actionLabel = '开始',
    super.key,
  });
  final _NextItem item;
  final VoidCallback onStart;
  final String actionLabel;
  @override
  Widget build(BuildContext context) {
    final color = item.colorKey == null
        ? CategoryPaletteColors.neutral(context)
        : CategoryPaletteColors.resolve(context, item.colorKey!);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 32,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  item.secondary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                if (item.reason != null)
                  Text(
                    item.reason!,
                    key: ValueKey('home-next-reason-${item.id}'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
              ],
            ),
          ),
          TextButton.icon(
            key: ValueKey('home-next-start-${item.id}'),
            onPressed: onStart,
            icon: const Icon(Icons.play_arrow, size: 20),
            label: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}

class _EmptyNext extends StatelessWidget {
  const _EmptyNext({required this.onOpenEvents});
  final VoidCallback onOpenEvents;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          '今天还没有可开始的事项',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      TextButton(
        key: const ValueKey('home-open-events'),
        onPressed: onOpenEvents,
        child: const Text('查看今日'),
      ),
    ],
  );
}

class _WaitingRow extends StatelessWidget {
  const _WaitingRow({
    required this.item,
    required this.contextLabel,
    required this.onResume,
    super.key,
  });
  final HomeWaitingItem item;
  final String contextLabel;
  final VoidCallback onResume;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.hourglass_empty,
          size: 18,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.event.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                contextLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                '等待中',
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: Theme.of(context).colorScheme.outline),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        TextButton.icon(
          key: ValueKey('home-waiting-resume-${item.event.id}'),
          onPressed: onResume,
          icon: const Icon(Icons.play_arrow, size: 20),
          label: const Text('恢复'),
        ),
      ],
    ),
  );
}

class _NextItem {
  const _NextItem._(
    this.id,
    this.name,
    this.secondary,
    this.colorKey, {
    this.event,
    this.routine,
    this.reason,
  });
  factory _NextItem.event(
    JaxEvent e,
    String secondary,
    int? colorKey, {
    String? reason,
  }) =>
      _NextItem._(e.id, e.name, secondary, colorKey, event: e, reason: reason);
  factory _NextItem.routine(
    Routine r,
    String secondary,
    int? colorKey, {
    String? reason,
  }) => _NextItem._(
    r.id,
    r.name,
    secondary,
    colorKey,
    routine: r,
    reason: reason,
  );
  final String id, name, secondary;
  final int? colorKey;
  final JaxEvent? event;
  final Routine? routine;
  final String? reason;
}

enum _HeroAction { addPlanStep, adjustStart, complete, completeCorrected, wait }

Category? _eventCategory(EventController controller, JaxEvent event) {
  return controller.categories
      .where((c) => c.id == controller.effectiveCategoryIdFor(event.id))
      .firstOrNull;
}

String _recurrence(RoutineRecurrence value) => switch (value) {
  RoutineRecurrence.daily => '每日',
  RoutineRecurrence.weekdays => '工作日',
  RoutineRecurrence.weekends => '周末',
  RoutineRecurrence.selectedWeekdays => '指定星期',
};
String _duration(Duration value) =>
    '${value.inHours.toString().padLeft(2, '0')}:${(value.inMinutes % 60).toString().padLeft(2, '0')}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';
