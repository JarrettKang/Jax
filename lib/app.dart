import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'dart:ui' show AppExitResponse;

import 'package:uuid/uuid.dart';

import 'core/repositories/event_repository.dart';
import 'core/entities/jax_event.dart';
import 'core/repositories/planning_repository.dart';
import 'core/repositories/world_node_repository.dart';
import 'core/preferences/world_category_collapse_store.dart';
import 'core/preferences/routine_category_collapse_store.dart';
import 'core/services/save_service.dart';
import 'core/use_cases/create_event.dart';
import 'core/use_cases/prepare_for_shutdown.dart';
import 'ui/controllers/event_controller.dart';
import 'ui/pages/events_page.dart';
import 'ui/pages/summary_page.dart';
import 'ui/pages/home_page.dart';
import 'ui/pages/world_page.dart';
import 'ui/pages/routine_page.dart';
import 'core/repositories/routine_repository.dart';
import 'core/sync/sync_compare_engine.dart';
import 'core/sync/sync_contract.dart';
import 'ui/pages/sync_preview_page.dart';
import 'ui/controllers/planning_controller.dart';
import 'ui/pages/planning_page.dart';

ThemeData buildJaxTheme(TargetPlatform platform) => ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF315C4C)),
  fontFamily: platform == TargetPlatform.windows ? 'Microsoft YaHei UI' : null,
  platform: platform,
  useMaterial3: true,
);

class JaxApp extends StatefulWidget {
  JaxApp({
    required this.repository,
    SaveService? saveService,
    WorldCategoryCollapseStore? worldCategoryCollapseStore,
    RoutineCategoryCollapseStore? routineCategoryCollapseStore,
    IdGenerator? newId,
    Clock? now,
    this.debugSyncPlan,
    this.debugSyncWindowsSnapshot,
    this.debugSyncAndroidSnapshot,
    this.debugSyncBaseline,
    this.onConfirmedSyncApply,
    this.onOpenDebugSync,
    this.planningRepository,
    this.worldNodeRepository,
    super.key,
  }) : saveService = saveService ?? const _ImmediateSaveService(),
       worldCategoryCollapseStore =
           worldCategoryCollapseStore ?? InMemoryWorldCategoryCollapseStore(),
       routineCategoryCollapseStore =
           routineCategoryCollapseStore ??
           InMemoryRoutineCategoryCollapseStore(),
       newId = newId ?? const Uuid().v4,
       now = now ?? DateTime.now;

  final EventRepository repository;
  final SaveService saveService;
  final WorldCategoryCollapseStore worldCategoryCollapseStore;
  final RoutineCategoryCollapseStore routineCategoryCollapseStore;
  final IdGenerator newId;
  final Clock now;
  final SyncPlan? debugSyncPlan;
  final SyncSnapshot? debugSyncWindowsSnapshot;
  final SyncSnapshot? debugSyncAndroidSnapshot;
  final SyncSnapshot? debugSyncBaseline;
  final ConfirmedSyncApply? onConfirmedSyncApply;
  final Future<void> Function()? onOpenDebugSync;
  final PlanningRepository? planningRepository;
  final WorldNodeRepository? worldNodeRepository;

  @override
  State<JaxApp> createState() => _JaxAppState();
}

class _JaxAppState extends State<JaxApp> {
  late final EventController _controller;
  late final PrepareForShutdown _prepareForShutdown;
  PlanningController? _planningController;
  AppLifecycleListener? _lifecycleListener;
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  var _selectedIndex = 0;
  PlanningOpenRequest? _planningOpenRequest;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = EventController(
      repository: widget.repository,
      newId: widget.newId,
      now: widget.now,
    );
    _prepareForShutdown = PrepareForShutdown(
      repository: widget.repository,
      saveService: widget.saveService,
      now: widget.now,
    );
    if (widget.planningRepository != null &&
        widget.worldNodeRepository != null) {
      _planningController = PlanningController(
        planningRepository: widget.planningRepository!,
        worldNodeRepository: widget.worldNodeRepository!,
        eventRepository: widget.repository,
        newId: widget.newId,
        now: widget.now,
      );
    }
    _lifecycleListener = AppLifecycleListener(
      onResume: _handleResume,
      onExitRequested: Platform.isWindows ? _handleExitRequest : null,
    );
    _controller.load();
  }

  void _handleResume() {
    _controller.load();
    _planningController?.load();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.saveService.flush();
      _controller.recordSaveSuccess();
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

  Future<AppExitResponse> _handleExitRequest() async {
    try {
      if (widget.repository case final RoutineRepository routines) {
        await routines.pauseRunningRoutine(widget.now().toUtc());
      }
      await _prepareForShutdown();
      return AppExitResponse.exit;
    } catch (_) {
      _messengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('关闭前保存失败，请重试')),
      );
      return AppExitResponse.cancel;
    }
  }

  Future<void> _openDebugSync() async {
    try {
      if (widget.repository case final RoutineRepository routines) {
        await routines.pauseRunningRoutine(widget.now().toUtc());
      }
      await _prepareForShutdown();
      await widget.onOpenDebugSync!();
    } catch (error) {
      _messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('无法打开 Debug Sync：$error')),
      );
    }
  }

  String _formatSaveStatus(DateTime? savedAt) {
    if (savedAt == null) return '已加载本地数据';
    final local = savedAt.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '最后保存：${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }

  Widget _saveStatus() => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) => Text(
      _saving ? '正在保存…' : _formatSaveStatus(_controller.lastSavedAt),
      key: const ValueKey('save-status'),
      maxLines: 1,
    ),
  );

  Widget _saveButton() => IconButton(
    key: const ValueKey('manual-save'),
    tooltip: _saving ? '正在保存' : '保存',
    onPressed: _saving ? null : _save,
    icon: _saving
        ? const SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.save_outlined),
  );

  void _openPlanningPlan(String planId, {bool addItem = false}) {
    setState(() {
      _planningOpenRequest = PlanningOpenRequest(
        planId: planId,
        openAddItem: addItem,
      );
      _selectedIndex = 3;
    });
  }

  Future<void> _addPlanStepFromRunningEvent(
    BuildContext dialogContext,
    JaxEvent event,
  ) async {
    final planning = _planningController;
    final sourceId = event.sourcePlanItemId;
    if (planning == null || sourceId == null) return;
    try {
      final target = await planning.resolvePlanStepRefinement(sourceId);
      if (!mounted || !dialogContext.mounted) return;
      switch (target.kind) {
        case PlanStepRefinementKind.currentSourcePlan:
          _openPlanningPlan(target.sourcePlan.id, addItem: true);
          return;
        case PlanStepRefinementKind.endedSourceWithCurrentPlan:
          final choice = await _endedPlanChoice(
            target,
            dialogContext: dialogContext,
            hasCurrentPlan: true,
          );
          if (!mounted || choice == null) return;
          if (choice == _PlanStepChoice.currentPlan) {
            _openPlanningPlan(target.currentPlan!.id, addItem: true);
          } else if (choice == _PlanStepChoice.sourcePlan) {
            _openPlanningPlan(target.sourcePlan.id);
          }
          return;
        case PlanStepRefinementKind.endedSourceWithoutCurrentPlan:
          final choice = await _endedPlanChoice(
            target,
            dialogContext: dialogContext,
            hasCurrentPlan: false,
          );
          if (!mounted || choice == null) return;
          if (choice == _PlanStepChoice.sourcePlan) {
            _openPlanningPlan(target.sourcePlan.id);
          } else if (choice == _PlanStepChoice.newRound) {
            final plan = await planning.createPlan(target.node);
            if (mounted) _openPlanningPlan(plan.id, addItem: true);
          }
          return;
        case PlanStepRefinementKind.completedWorldNode:
          final choice = await _completedNodeChoice(target, dialogContext);
          if (mounted && choice == _PlanStepChoice.sourcePlan) {
            _openPlanningPlan(target.sourcePlan.id);
          }
          return;
      }
    } catch (error) {
      _messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Future<_PlanStepChoice?> _endedPlanChoice(
    PlanStepRefinementTarget target, {
    required BuildContext dialogContext,
    required bool hasCurrentPlan,
  }) {
    return showDialog<_PlanStepChoice>(
      context: dialogContext,
      builder: (context) => AlertDialog(
        title: const Text('来源计划已经结束'),
        content: Text(
          hasCurrentPlan
              ? '“${target.node.name}”已有新的当前计划。要把步骤补充到当前计划，还是查看原来的来源计划？'
              : '“${target.node.name}”目前没有当前计划。可以添加新一轮后继续补充，或查看原来的来源计划。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            key: const ValueKey('view-source-plan'),
            onPressed: () => Navigator.pop(context, _PlanStepChoice.sourcePlan),
            child: const Text('查看来源计划'),
          ),
          FilledButton(
            key: ValueKey(
              hasCurrentPlan ? 'add-to-current-plan' : 'create-new-plan-round',
            ),
            onPressed: () => Navigator.pop(
              context,
              hasCurrentPlan
                  ? _PlanStepChoice.currentPlan
                  : _PlanStepChoice.newRound,
            ),
            child: Text(hasCurrentPlan ? '补充到当前计划' : '添加新一轮'),
          ),
        ],
      ),
    );
  }

  Future<_PlanStepChoice?> _completedNodeChoice(
    PlanStepRefinementTarget target,
    BuildContext dialogContext,
  ) {
    return showDialog<_PlanStepChoice>(
      context: dialogContext,
      builder: (context) => AlertDialog(
        title: const Text('世界节点已经完成'),
        content: Text(
          '“${target.node.name}”需要先在“世界”中恢复，才能创建新一轮或补充计划步骤。Jax 不会自动恢复节点。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            key: const ValueKey('view-source-plan'),
            onPressed: () => Navigator.pop(context, _PlanStepChoice.sourcePlan),
            child: const Text('查看来源计划'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _lifecycleListener?.dispose();
    _controller.dispose();
    _planningController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      HomePage(
        controller: _controller,
        now: widget.now,
        onOpenEvents: () => setState(() => _selectedIndex = 1),
        onAddPlanStep: _planningController == null
            ? null
            : _addPlanStepFromRunningEvent,
      ),
      EventsPage(
        controller: _controller,
        planningController: _planningController,
      ),
      _planningController == null
          ? const Center(child: Text('世界数据库不可用'))
          : WorldPage(
              controller: _planningController!,
              worldCategoryCollapseStore: widget.worldCategoryCollapseStore,
            ),
      _planningController == null
          ? const Center(child: Text('规划数据库不可用'))
          : PlanningPage(
              controller: _planningController!,
              onAddEventToToday: _controller.addToToday,
              isEventToday: _controller.isPlannedToday,
              openRequest: _planningOpenRequest,
              onOpenRequestConsumed: () {
                if (mounted) setState(() => _planningOpenRequest = null);
              },
            ),
      RoutinePage(
        controller: _controller,
        collapseStore: widget.routineCategoryCollapseStore,
      ),
      SummaryPage(controller: _controller),
    ];

    return MaterialApp(
      scaffoldMessengerKey: _messengerKey,
      title: 'Jax',
      debugShowCheckedModeBanner: false,
      theme: buildJaxTheme(defaultTargetPlatform),
      home: Builder(
        builder: (context) {
          final compact = MediaQuery.sizeOf(context).width < 600;
          return Scaffold(
            appBar: AppBar(
              title: const Text('Jax'),
              actions: [
                if (kDebugMode &&
                    Platform.isWindows &&
                    widget.onOpenDebugSync != null)
                  IconButton(
                    key: const ValueKey('open-debug-sync'),
                    tooltip: '开发工具 · 双端同步',
                    onPressed: _openDebugSync,
                    icon: const Icon(Icons.developer_mode),
                  ),
                if (kDebugMode && widget.debugSyncPlan != null)
                  IconButton(
                    key: const ValueKey('sync-preview'),
                    tooltip: '同步分析（仅预览）',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => SyncPreviewPage(
                          plan: widget.debugSyncPlan!,
                          windowsSnapshot: widget.debugSyncWindowsSnapshot,
                          androidSnapshot: widget.debugSyncAndroidSnapshot,
                          baseline: widget.debugSyncBaseline,
                          onConfirmedApply: widget.onConfirmedSyncApply,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.sync_alt),
                  ),
                if (!compact)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Center(child: _saveStatus()),
                  ),
                _saveButton(),
              ],
              bottom: compact
                  ? PreferredSize(
                      preferredSize: const Size.fromHeight(40),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: SizedBox(
                          height: 32,
                          width: double.infinity,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: _saveStatus(),
                          ),
                        ),
                      ),
                    )
                  : null,
            ),
            body: compact
                ? pages[_selectedIndex]
                : Row(
                    children: [
                      NavigationRail(
                        selectedIndex: _selectedIndex,
                        labelType: NavigationRailLabelType.all,
                        onDestinationSelected: (index) {
                          setState(() => _selectedIndex = index);
                          _controller.load();
                          _planningController?.load();
                        },
                        destinations: const [
                          NavigationRailDestination(
                            icon: Icon(Icons.home_outlined),
                            selectedIcon: Icon(Icons.home),
                            label: Text('首页'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.checklist_outlined),
                            selectedIcon: Icon(Icons.checklist),
                            label: Text('今日'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.account_tree_outlined),
                            selectedIcon: Icon(Icons.account_tree),
                            label: Text('世界'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.route_outlined),
                            selectedIcon: Icon(Icons.route),
                            label: Text('规划'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.repeat),
                            selectedIcon: Icon(Icons.repeat_on),
                            label: Text('日常'),
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
            bottomNavigationBar: compact
                ? NavigationBar(
                    selectedIndex: _selectedIndex,
                    onDestinationSelected: (index) {
                      setState(() => _selectedIndex = index);
                      _controller.load();
                      _planningController?.load();
                    },
                    destinations: const [
                      NavigationDestination(
                        icon: Icon(Icons.home_outlined),
                        selectedIcon: Icon(Icons.home),
                        label: '首页',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.checklist_outlined),
                        selectedIcon: Icon(Icons.checklist),
                        label: '今日',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.account_tree_outlined),
                        selectedIcon: Icon(Icons.account_tree),
                        label: '世界',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.route_outlined),
                        selectedIcon: Icon(Icons.route),
                        label: '规划',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.repeat),
                        selectedIcon: Icon(Icons.repeat_on),
                        label: '日常',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.history_outlined),
                        selectedIcon: Icon(Icons.history),
                        label: '记录',
                      ),
                    ],
                  )
                : null,
          );
        },
      ),
    );
  }
}

enum _PlanStepChoice { currentPlan, newRound, sourcePlan }

class _ImmediateSaveService implements SaveService {
  const _ImmediateSaveService();

  @override
  Future<void> flush() async {}
}
