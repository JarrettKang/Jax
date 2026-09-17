import '../theme/desktop_polish.dart';
import '../../core/entities/execution_capabilities.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/entities/category.dart';
import '../../core/entities/event_status.dart';
import '../../core/entities/jax_event.dart';
import '../../core/entities/routine.dart';
import '../../core/entities/world_node.dart';
import '../../core/services/greeting_resolver.dart';
import '../../core/services/temporal_routine.dart';
import '../../core/use_cases/create_event.dart';
import '../controllers/event_controller.dart';
import '../controllers/app_preferences_controller.dart';
import '../../core/preferences/app_preferences.dart';
import '../controllers/planning_controller.dart';
import '../controllers/home_view_state.dart';
import '../controllers/today_temporal_view.dart';
import '../theme/home_pilot_theme.dart';
import '../widgets/execution_action_buttons.dart';
import '../widgets/category_color_picker.dart';
import '../widgets/world_node_ancestry_view.dart';
import '../widgets/waiting_routine_row.dart';
import '../widgets/standalone_event_dialog.dart';
import 'planning_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    required this.controller,
    required this.now,
    required this.onOpenEvents,
    this.planningController,
    this.navigation,
    this.preferences,
    this.onAddPlanStep,
    super.key,
  });
  final EventController controller;
  final PlanningController? planningController;
  final HomeNavigationState? navigation;
  final AppPreferencesController? preferences;
  final Clock now;
  final VoidCallback onOpenEvents;
  final Future<void> Function(BuildContext context, JaxEvent event)?
  onAddPlanStep;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  static const _greeting = GreetingResolver();
  late final HomeNavigationState _navigation;
  final Map<String?, ScrollController> _categoryScrolls = {};

  ScrollController _categoryScroll(String? id) => _categoryScrolls.putIfAbsent(
    id,
    () {
      final scroll = ScrollController(
        initialScrollOffset: _navigation.categoryOffsets[id] ?? 0,
      );
      scroll.addListener(() => _navigation.categoryOffsets[id] = scroll.offset);
      return scroll;
    },
  );

  void _validateCategory() {
    final pc = widget.planningController;
    if (pc != null) _navigation.validateCategories(pc);
  }

  Timer? _timer;
  DateTime? _boundary;
  @override
  void initState() {
    super.initState();
    _navigation = widget.navigation ?? HomeNavigationState();
    widget.planningController?.addListener(_validateCategory);
    widget.controller.addListener(_scheduleBoundary);
    WidgetsBinding.instance.addObserver(this);
    widget.planningController?.load();
    _scheduleBoundary();
  }

  @override
  void didUpdateWidget(HomePage old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_scheduleBoundary);
      widget.controller.addListener(_scheduleBoundary);
    }
    if (old.planningController != widget.planningController) {
      old.planningController?.removeListener(_validateCategory);
      widget.planningController?.addListener(_validateCategory);
      widget.planningController?.load();
    }
    _scheduleBoundary();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // JaxApp owns data reload; avoid duplicate day initialization on resume.
      setState(() {});
      _scheduleBoundary();
    }
  }

  void _scheduleBoundary() {
    final now = widget.now();
    final dates = [
      _greeting.nextChangeAfter(now),
      ?homeTemporalView(widget.controller).nextBoundary,
    ]..sort();
    final next = dates.first;
    if (_boundary == next && _timer?.isActive == true) return;
    _timer?.cancel();
    _boundary = next;
    final delay = next.difference(now);
    _timer = Timer(delay.isNegative ? Duration.zero : delay, () {
      if (!mounted) return;
      _boundary = null;
      setState(() {});
      _scheduleBoundary();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.controller.removeListener(_scheduleBoundary);
    WidgetsBinding.instance.removeObserver(this);
    widget.planningController?.removeListener(_validateCategory);
    for (final scroll in _categoryScrolls.values) {
      scroll.dispose();
    }
    if (widget.navigation == null) _navigation.dispose();
    super.dispose();
  }

  ThemeData get _pilotTheme => HomePilot.theme(Theme.of(context));

  @override
  Widget build(BuildContext context) => Theme(
    data: _pilotTheme,
    child: SizedBox.expand(
      child: Material(
        color: HomePilot.canvas,
        child: AnimatedBuilder(
          animation: Listenable.merge([
            widget.controller,
            widget.planningController,
            _navigation,
            widget.preferences,
          ]),
          builder: (context, _) {
            final ec = widget.controller;
            final primary = homePrimaryRecommendation(ec);
            final running =
                ec.runningEvent != null || ec.runningRoutine != null;
            final categoryView =
                !running &&
                _navigation.categorySelected &&
                !_navigation.viewingRecommendation;
            final canBack = !running && _navigation.canGoBack;
            final waitingCount =
                ec.homeWaitingItems.length + ec.waitingRoutineExecutions.length;
            return PopScope(
              canPop: !canBack,
              onPopInvokedWithResult: (didPop, result) {
                if (!didPop && canBack) _navigation.back();
              },
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.escape): () {
                    if (canBack) _navigation.back();
                  },
                },
                child: Focus(
                  autofocus: true,
                  child: SafeArea(
                    child: SingleChildScrollView(
                      key: PageStorageKey(
                        categoryView
                            ? 'home-category-scroll-${_navigation.categoryId}'
                            : 'home-root-scroll',
                      ),
                      controller: categoryView
                          ? _categoryScroll(_navigation.categoryId)
                          : null,
                      padding: EdgeInsets.fromLTRB(
                        Theme.of(context).platform == TargetPlatform.windows
                            ? 24
                            : 16,
                        24,
                        Theme.of(context).platform == TargetPlatform.windows
                            ? 24
                            : 16,
                        48,
                      ),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: HomePilot.maxWidth,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                _greeting.resolve(widget.now),
                                key: const ValueKey('home-greeting'),
                                style: _pilotTheme.textTheme.bodySmall,
                              ),
                              const SizedBox(height: 24),
                              if (running) ...[
                                if (ec.runningEvent case final JaxEvent event)
                                  _eventHero(event)
                                else
                                  _routineHero(ec.runningRoutine!),
                                if (primary != null)
                                  _temporalBanner(primary, canView: false),
                              ] else if (categoryView) ...[
                                _backButton(),
                                Text(
                                  _categoryTitle,
                                  key: const ValueKey('home-category-view'),
                                  style: _pilotTheme.textTheme.headlineMedium,
                                ),
                                if (primary != null) _temporalBanner(primary),
                                ..._categoryGroups(),
                                if (waitingCount > 0)
                                  _waitingHint(waitingCount),
                              ] else ...[
                                if (_navigation.viewingRecommendation)
                                  _backButton(),
                                if (primary != null)
                                  _primaryCard(primary)
                                else ...[
                                  Text(
                                    _assistantName,
                                    key: const ValueKey('home-assistant-name'),
                                    style: _pilotTheme.textTheme.bodyMedium,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '接下来想做什么？',
                                    key: const ValueKey('home-root-ask'),
                                    style: _pilotTheme.textTheme.headlineMedium,
                                  ),
                                ],
                                const SizedBox(height: 24),
                                if (primary != null)
                                  Text(
                                    '或者做点别的：',
                                    style: _pilotTheme.textTheme.bodySmall,
                                  ),
                                ..._categoryEntries(),
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton(
                                    key: const ValueKey('home-temporary'),
                                    onPressed: _temporary,
                                    child: const Text('临时做一件事'),
                                  ),
                                ),
                              ],
                              if (waitingCount > 0 && !categoryView)
                                _waitingHint(waitingCount),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
  String get _assistantName =>
      widget.preferences?.value.assistantName ?? defaultAssistantName;

  String get _categoryTitle =>
      widget.planningController?.categories
          .where((c) => c.id == _navigation.categoryId)
          .firstOrNull
          ?.name ??
      '其他';

  List<Widget> _categoryEntries() {
    final pc = widget.planningController;
    if (pc == null) return const [];
    if (pc.error != null) {
      return [
        const Text('读取事项失败'),
        TextButton(onPressed: pc.load, child: const Text('重试')),
      ];
    }
    return [
      for (final category in homeCategoryEntries(pc))
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: ValueKey('home-category-entry-${category?.id}'),
              onPressed: () => _navigation.selectCategory(category?.id),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CategoryColorDot(colorKey: category?.colorKey),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      category?.name ?? '其他',
                      style: _pilotTheme.textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
    ];
  }

  Widget _waitingHint(int waitingCount) => Padding(
    padding: const EdgeInsets.only(top: 24),
    child: Row(
      children: [
        Expanded(
          child: Text(
            '等待中的事项 · $waitingCount',
            key: const ValueKey('home-waiting-hint'),
            style: _pilotTheme.textTheme.bodySmall,
          ),
        ),
        TextButton(
          key: const ValueKey('home-waiting-open'),
          onPressed: _openWaiting,
          child: const Text('查看'),
        ),
      ],
    ),
  );

  Widget _backButton() => Align(
    alignment: Alignment.centerLeft,
    child: TextButton.icon(
      key: const ValueKey('home-intent-back'),
      onPressed: _navigation.back,
      icon: const Icon(Icons.arrow_back),
      label: Text(
        _navigation.viewingRecommendation && _navigation.categorySelected
            ? '返回$_categoryTitle'
            : '接下来想做什么',
      ),
    ),
  );

  Widget _temporalBanner(
    TodayTemporalEntry entry, {
    bool canView = true,
  }) => Padding(
    key: const ValueKey('home-temporal-hint'),
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Row(
      children: [
        const Icon(Icons.schedule, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '${entry.routine.name}${entry.state == TemporalRecommendationState.overdue ? '已超过理想时间' : '已进入推荐时间'}',
            style: _pilotTheme.textTheme.bodySmall,
          ),
        ),
        if (canView)
          TextButton(
            key: const ValueKey('home-temporal-view'),
            onPressed: _navigation.recommendation,
            child: const Text('查看'),
          ),
      ],
    ),
  );
  Widget _primaryCard(TodayTemporalEntry entry) => Column(
    key: ValueKey('home-primary-${entry.routine.id}'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        '$_assistantName 建议您接下来：',
        key: const ValueKey('home-assistant-recommendation'),
        style: _pilotTheme.textTheme.bodySmall,
      ),
      const SizedBox(height: 12),
      Text(entry.routine.name, style: _pilotTheme.textTheme.headlineMedium),
      const SizedBox(height: 8),
      Text(
        entry.state == TemporalRecommendationState.overdue
            ? '已超过理想时间 · 最晚 ${_clock(entry.window.latestEndDateTime)}'
            : '已经到了推荐时间 · 理想完成前 ${_clock(entry.window.idealEndDateTime)}',
        style: _pilotTheme.textTheme.bodySmall?.copyWith(
          color: entry.state == TemporalRecommendationState.overdue
              ? HomePilot.warning
              : HomePilot.textSecondary,
        ),
      ),
      const SizedBox(height: 16),
      ExecutionActionButton(
        key: const ValueKey('home-primary-start'),
        primary: true,
        style: HomePilot.buttonStyle(primary: true),
        action: ExecutionAction.start,
        onPressed: () => _act(
          () => widget.controller.startRoutineOccurrence(
            entry.routine,
            entry.window.occurrenceKey,
          ),
        ),
      ),
    ],
  );
  List<Widget> _categoryGroups() {
    final pc = widget.planningController;
    if (pc == null) {
      return [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Text('当前没有关注的事项。'),
        ),
      ];
    }
    if (pc.error != null) {
      return [
        Text('读取事项失败：${pc.error}'),
        TextButton(onPressed: pc.load, child: const Text('重试')),
      ];
    }
    final groups = homeCategoryGroups(
      pc,
      widget.controller,
      categoryId: _navigation.categoryId,
    );
    if (groups.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(pc.loading ? '正在读取事项…' : '当前没有关注的事项。'),
        ),
      ];
    }
    return [
      for (final group in groups)
        Padding(
          key: ValueKey('home-category-group-${group.node.id}'),
          padding: const EdgeInsets.only(top: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final title = Text(
                    group.node.name,
                    style: _pilotTheme.textTheme.titleLarge,
                  );
                  final action = TextButton(
                    key: ValueKey('home-plan-${group.node.id}'),
                    onPressed: () => _plan(group.node),
                    child: const Text('规划一下'),
                  );
                  if (constraints.maxWidth < 360 &&
                      MediaQuery.textScalerOf(context).scale(16) > 20) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [title, action],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: title),
                      const SizedBox(width: 8),
                      action,
                    ],
                  );
                },
              ),
              if (pc
                      .pathFor(group.node)
                      .where((n) => n.id != group.node.id)
                      .toList()
                  case final ancestors when ancestors.isNotEmpty)
                Padding(
                  key: ValueKey('home-ancestry-${group.node.id}'),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: WorldNodeAncestryView(
                    names: ancestors.map((node) => node.name).toList(),
                    compact: true,
                    textStyle: _pilotTheme.textTheme.bodySmall,
                    guideColor: HomePilot.hairlineStrong,
                  ),
                ),
              if (group.items.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('还没有可执行步骤'),
                ),
              for (final item in group.items) _categoryRow(item),
            ],
          ),
        ),
    ];
  }

  Widget _categoryRow(HomeCategoryItem item) {
    final event = item.event;
    final resume = event?.status.canResume == true;
    final status = event?.status == EventStatus.waiting
        ? '等待中'
        : event?.status == EventStatus.paused
        ? '已暂停'
        : null;
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(item.name, style: _pilotTheme.textTheme.titleMedium),
        if (status != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Icon(
                  event?.status == EventStatus.waiting
                      ? Icons.hourglass_empty
                      : Icons.pause,
                  size: 16,
                  color: HomePilot.textMuted,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(status, style: _pilotTheme.textTheme.bodySmall),
                ),
              ],
            ),
          ),
      ],
    );
    final actions = ExecutionActionRow(
      children: [
        if (event != null && event.status.canResume && event.status.canComplete)
          ExecutionActionButton(
            key: ValueKey('home-category-complete-${item.item.id}'),
            action: ExecutionAction.complete,
            primary: false,
            style: HomePilot.buttonStyle(outlined: true),
            onPressed: () => _act(() => widget.controller.complete(event.id)),
          ),
        ExecutionActionButton(
          key: ValueKey('home-category-start-${item.item.id}'),
          primary: false,
          style: HomePilot.buttonStyle(outlined: true),
          action: resume
              ? ExecutionAction.continueWaiting
              : ExecutionAction.start,
          onPressed: widget.planningController?.startingPlanItem == true
              ? null
              : () async {
                  try {
                    if (event != null) {
                      await _startEvent(event);
                    } else {
                      await widget.planningController!.startPlanItem(
                        item.item.id,
                        refreshExecution: widget.controller.load,
                      );
                    }
                  } catch (error) {
                    _showError(error.toString());
                  }
                },
        ),
      ],
    );
    return HomePilotHoverRow(
      key: ValueKey('home-category-${item.identity}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stacked =
                constraints.maxWidth < 320 ||
                (resume && constraints.maxWidth < 480) ||
                MediaQuery.textScalerOf(context).scale(16) > 20;
            return stacked
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [title, const SizedBox(height: 8), actions],
                  )
                : Row(
                    children: [
                      Expanded(child: title),
                      const SizedBox(width: 16),
                      actions,
                    ],
                  );
          },
        ),
      ),
    );
  }

  Future<void> _plan(WorldNode node) async {
    final pc = widget.planningController!;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (routeContext) => CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                Navigator.of(routeContext).maybePop(),
          },
          child: FocusScope(
            autofocus: true,
            child: PlanDetailPage(controller: pc, worldNodeId: node.id),
          ),
        ),
      ),
    );
    if (!mounted) return;
    await pc.load();
    await widget.controller.load();
  }

  Future<void> _temporary() async {
    final result = await showStandaloneEventDialog(
      context,
      widget.controller,
      submitLabel: '开始',
    );
    if (result != null) {
      await _act(
        () => widget.controller.createAndStartStandalone(
          result.$1,
          categoryId: result.$2,
        ),
      );
    }
  }

  Future<void> _startEvent(JaxEvent event) async {
    final ec = widget.controller;
    if (ec.runningEvent case final JaxEvent running) {
      if (running.id != event.id) {
        final error = await ec.pause(running.id);
        if (error != null) {
          _showError(error);
          return;
        }
      }
    }
    if (ec.runningRoutine case final Routine running) {
      final error = await ec.pauseRoutine(running);
      if (error != null) {
        _showError(error);
        return;
      }
    }
    await _act(
      () =>
          event.status == EventStatus.paused ||
              event.status == EventStatus.waiting
          ? ec.resume(event.id)
          : ec.start(event.id),
    );
    await widget.planningController?.load();
  }

  Future<void> _openWaiting() => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (routeContext) => CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              Navigator.of(routeContext).maybePop(),
        },
        child: FocusScope(
          autofocus: true,
          child: Scaffold(
            appBar: AppBar(title: const Text('等待中的事项')),
            body: AnimatedBuilder(
              animation: widget.controller,
              builder: (context, _) {
                final ec = widget.controller;
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 820),
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        if (ec.homeWaitingItems.isEmpty &&
                            ec.waitingRoutineExecutions.isEmpty)
                          const Text('当前没有等待中的事项'),
                        for (final item in ec.homeWaitingItems)
                          Padding(
                            key: ValueKey('home-waiting-${item.event.id}'),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.event.name,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                Text(
                                  '${_eventCategory(ec, item.event)?.name ?? '未分类'} · 等待中',
                                ),
                                const SizedBox(height: 8),
                                ExecutionActionRow(
                                  children: [
                                    ExecutionActionButton(
                                      key: ValueKey(
                                        'home-waiting-resume-${item.event.id}',
                                      ),
                                      action: ExecutionAction.continueWaiting,
                                      onPressed: () => _startEvent(item.event),
                                    ),
                                    ExecutionActionButton(
                                      key: ValueKey(
                                        'home-waiting-complete-${item.event.id}',
                                      ),
                                      action: ExecutionAction.complete,
                                      onPressed: () => _act(
                                        () => ec.complete(item.event.id),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        for (final e in ec.waitingRoutineExecutions)
                          WaitingRoutineRow(
                            controller: ec,
                            execution: e,
                            key: ValueKey('home-waiting-routine-${e.id}'),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    ),
  );

  Widget _eventHero(JaxEvent event) {
    final category = _eventCategory(widget.controller, event);
    return _RunningHero(
      name: event.name,
      contextLabel: category?.name ?? '未分类',
      elapsed: widget.controller.elapsedFor(event),
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
            case _HeroAction.pauseCorrected:
              _showCorrectedEnd(
                pause: true,
                startedAt: widget.controller.runningEventStartedAt(event.id),
                save: widget.controller.correctedEventEndAction(
                  event.id,
                  pause: true,
                ),
              );
            case _HeroAction.completeCorrected:
              _showCorrectedEnd(
                startedAt: widget.controller.runningEventStartedAt(event.id),
                save: widget.controller.correctedEventEndAction(event.id),
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
            value: _HeroAction.pauseCorrected,
            child: Text('暂停并修改暂停时间'),
          ),
          const PopupMenuItem(
            value: _HeroAction.completeCorrected,
            child: Text('完成并修改结束时间…'),
          ),
          const PopupMenuItem(value: _HeroAction.wait, child: Text('等待')),
          const PopupMenuItem(value: _HeroAction.complete, child: Text('完成')),
        ],
      ),
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
            case _HeroAction.pauseCorrected:
              _showCorrectedEnd(
                pause: true,
                startedAt: widget.controller.runningRoutineStartedAt(routine),
                save: widget.controller.correctedRoutineEndAction(
                  routine,
                  pause: true,
                ),
              );
            case _HeroAction.completeCorrected:
              _showCorrectedEnd(
                startedAt: widget.controller.runningRoutineStartedAt(routine),
                save: widget.controller.correctedRoutineEndAction(routine),
              );
            case _HeroAction.wait:
              _act(() => widget.controller.waitRoutine(routine));
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: _HeroAction.wait, child: Text('等待')),
          PopupMenuItem(value: _HeroAction.adjustStart, child: Text('修改开始时间…')),
          PopupMenuItem(
            value: _HeroAction.pauseCorrected,
            child: Text('暂停并修改暂停时间'),
          ),
          PopupMenuItem(
            value: _HeroAction.completeCorrected,
            child: Text('完成并修改结束时间…'),
          ),
          PopupMenuItem(value: _HeroAction.complete, child: Text('完成')),
        ],
      ),
    );
  }

  Future<void> _act(Future<String?> Function() action) async =>
      _showError(await action());

  Future<void> _showCorrectedEnd({
    required DateTime? startedAt,
    required Future<String?> Function(DateTime end) save,
    bool pause = false,
  }) async {
    if (startedAt == null) {
      _showError('执行计时数据不完整');
      return;
    }
    var end = widget.controller.currentTime;
    String? error;
    var submitting = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          constraints: DesktopPolish.dialog(
            dialogContext,
            DesktopDialogSize.form,
          ),
          title: Text(pause ? '实际暂停时间' : '修改结束时间'),
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
                    Text(pause ? '暂停时间：' : '结束时间：'),
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
              onPressed: submitting ? null : () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                if (submitting) return;
                setDialog(() => submitting = true);
                final result = await save(end);
                if (!context.mounted) return;
                if (result == null) {
                  Navigator.pop(dialogContext);
                } else {
                  setDialog(() {
                    error = result;
                    submitting = false;
                  });
                }
              },
              child: Text(pause ? '暂停' : '完成'),
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
          constraints: DesktopPolish.dialog(
            dialogContext,
            DesktopDialogSize.form,
          ),
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
  });
  final String name, contextLabel;
  final Duration elapsed;
  final VoidCallback onPause;
  final Widget menu;
  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('home-running-hero'),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: HomePilot.accentSubtle,
        borderRadius: BorderRadius.circular(HomePilot.heroRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '正在执行',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: HomePilot.textSecondary),
          ),
          const SizedBox(height: 12),
          Text(
            name,
            key: const ValueKey('home-running-name'),
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 4),
          Text(
            contextLabel,
            key: const ValueKey('home-running-context'),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Text(
              _duration(elapsed),
              key: const ValueKey('home-running-duration'),
              maxLines: 1,
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.icon(
                key: const ValueKey('home-running-pause'),
                onPressed: onPause,
                icon: const Icon(Icons.pause),
                label: const Text('暂停'),
              ),
              menu,
            ],
          ),
        ],
      ),
    );
  }
}

enum _HeroAction {
  addPlanStep,
  adjustStart,
  complete,
  completeCorrected,
  pauseCorrected,
  wait,
}

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
