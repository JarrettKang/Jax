import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'dart:ui' show AppExitResponse;

import 'package:uuid/uuid.dart';

import 'core/repositories/event_repository.dart';
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
import 'ui/pages/sync_preview_page.dart';

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

  @override
  State<JaxApp> createState() => _JaxAppState();
}

class _JaxAppState extends State<JaxApp> {
  late final EventController _controller;
  late final PrepareForShutdown _prepareForShutdown;
  AppLifecycleListener? _lifecycleListener;
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
    _prepareForShutdown = PrepareForShutdown(
      repository: widget.repository,
      saveService: widget.saveService,
      now: widget.now,
    );
    if (Platform.isWindows) {
      _lifecycleListener = AppLifecycleListener(
        onExitRequested: _handleExitRequest,
      );
    }
    _controller.load();
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

  @override
  void dispose() {
    _lifecycleListener?.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      HomePage(
        controller: _controller,
        now: widget.now,
        onOpenEvents: () => setState(() => _selectedIndex = 1),
      ),
      EventsPage(
        controller: _controller,
        onOpenWorld: () => setState(() => _selectedIndex = 2),
      ),
      WorldPage(
        controller: _controller,
        worldCategoryCollapseStore: widget.worldCategoryCollapseStore,
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
                if (kDebugMode && widget.debugSyncPlan != null)
                  IconButton(
                    key: const ValueKey('sync-preview'),
                    tooltip: '同步分析（仅预览）',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            SyncPreviewPage(plan: widget.debugSyncPlan!),
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

class _ImmediateSaveService implements SaveService {
  const _ImmediateSaveService();

  @override
  Future<void> flush() async {}
}
