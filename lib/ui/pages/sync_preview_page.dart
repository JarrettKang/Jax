import 'package:flutter/material.dart';

import '../../core/sync/resolved_sync_plan.dart';
import '../../core/sync/sync_compare_engine.dart';
import '../../core/sync/sync_contract.dart';
import '../../core/sync/sync_mutation_plan.dart';
import '../../core/sync/sync_plan_compiler.dart';

typedef ConfirmedSyncApply = Future<void> Function(ResolvedSyncPlan resolved);

class SyncPreviewPage extends StatefulWidget {
  const SyncPreviewPage({
    required this.plan,
    this.windowsSnapshot,
    this.androidSnapshot,
    this.baseline,
    this.onConfirmedApply,
    super.key,
  });

  final SyncPlan plan;
  final SyncSnapshot? windowsSnapshot;
  final SyncSnapshot? androidSnapshot;
  final SyncSnapshot? baseline;
  final ConfirmedSyncApply? onConfirmedApply;

  @override
  State<SyncPreviewPage> createState() => _SyncPreviewPageState();
}

class _SyncPreviewPageState extends State<SyncPreviewPage> {
  final Map<String, SyncSide> _recordChoices = {};
  final Map<String, SyncSide> _listChoices = {};
  SyncMutationPlan? _mutationPlan;
  String? _validationError;
  var _submitting = false;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Jax Sync · Debug')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Sync Analysis', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _metric('相同', widget.plan.same.length),
            _metric('仅电脑', widget.plan.count(SyncComparisonKind.onlyWindows)),
            _metric('仅手机', widget.plan.count(SyncComparisonKind.onlyAndroid)),
            _metric('可自动合并', widget.plan.autoMergeable.length),
            _metric('实体/字段冲突', widget.plan.manualConflicts.length),
            _metric('排序冲突', widget.plan.listConflicts.length),
            _metric('业务规则冲突', widget.plan.invariantConflicts.length),
          ],
        ),
        if (widget.plan.warnings.isNotEmpty) ...[
          const SizedBox(height: 20),
          _section(
            '本地数据提示',
            widget.plan.warnings.map(
              (text) => ListTile(
                leading: const Icon(Icons.warning_amber),
                title: Text(text),
              ),
            ),
          ),
        ],
        _section('需要处理', widget.plan.manualConflicts.map(_conflictTile)),
        _section('排序冲突', widget.plan.listConflicts.map(_listTile)),
        _section('业务规则冲突', widget.plan.invariantConflicts.map(_invariantTile)),
        _section(
          '自动合并',
          widget.plan.autoMergeable.map(
            (item) => ListTile(
              title: Text(item.title),
              subtitle: Text(_sideDescription(item)),
            ),
          ),
        ),
        const SizedBox(height: 20),
        _planValidation(),
      ],
    ),
  );

  Widget _metric(String label, int count) => SizedBox(
    width: 150,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$count', style: Theme.of(context).textTheme.headlineMedium),
            Text(label),
          ],
        ),
      ),
    ),
  );

  Widget _section(String title, Iterable<Widget> children) {
    final values = children.toList();
    if (values.isEmpty) return const SizedBox.shrink();
    return ExpansionTile(
      title: Text('$title · ${values.length}'),
      initiallyExpanded: title == '需要处理',
      children: values,
    );
  }

  Widget _conflictTile(SyncPlanItem item) => ExpansionTile(
    title: Text(item.title),
    subtitle: Text(item.detail ?? item.conflictType?.name ?? ''),
    children: [
      for (final field in item.changedFields)
        ListTile(
          title: Text(field.field),
          subtitle: Text(
            '电脑：${field.windowsDisplay ?? field.windowsValue}\n'
            '手机：${field.androidDisplay ?? field.androidValue}',
          ),
        ),
      _choice(
        selected: _recordChoices[item.key],
        onChanged: (side) => _choose(_recordChoices, item.key, side),
      ),
    ],
  );

  Widget _listTile(SyncListConflict item) => ExpansionTile(
    title: Text(item.title),
    subtitle: const Text('完整列表顺序不同'),
    children: [
      ListTile(
        title: const Text('电脑顺序'),
        subtitle: Text(
          _numbered(
            item.windowsLabels.isEmpty ? item.windowsIds : item.windowsLabels,
          ),
        ),
      ),
      ListTile(
        title: const Text('手机顺序'),
        subtitle: Text(
          _numbered(
            item.androidLabels.isEmpty ? item.androidIds : item.androidLabels,
          ),
        ),
      ),
      _choice(
        selected: _listChoices[item.key],
        onChanged: (side) => _choose(_listChoices, item.key, side),
      ),
    ],
  );

  Widget _invariantTile(SyncInvariantConflict item) => ListTile(
    leading: const Icon(Icons.block),
    title: Text(item.title),
    subtitle: Text('${item.detail}\n需要显式的合法最终状态，当前不能直接 Apply。'),
  );

  Widget _choice({
    required SyncSide? selected,
    required ValueChanged<SyncSide> onChanged,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: SegmentedButton<SyncSide>(
      segments: const [
        ButtonSegment(value: SyncSide.windows, label: Text('使用电脑')),
        ButtonSegment(value: SyncSide.android, label: Text('使用手机')),
        ButtonSegment(value: SyncSide.unresolved, label: Text('暂不处理')),
      ],
      selected: {selected ?? SyncSide.unresolved},
      onSelectionChanged: (value) => onChanged(value.single),
    ),
  );

  Widget _planValidation() {
    if (widget.windowsSnapshot == null || widget.androidSnapshot == null) {
      return const Text(
        '当前仅加载了 Preview；未提供 source snapshots，因此不能 Dry Run 或执行同步。',
      );
    }
    final mutation = _mutationPlan;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('计划检查', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_validationError != null)
              Text(
                _validationError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              )
            else if (mutation == null)
              const Text('解决全部冲突后执行 Dry Run。')
            else ...[
              const Text(
                '✅ PLAN_VALID · hierarchy / running / segments / ordering / Today',
              ),
              const SizedBox(height: 8),
              Text('Windows operations：${mutation.windowsOperations.length}'),
              Text('Android operations：${mutation.androidOperations.length}'),
              Text(
                '排序变更：${_listOperationCount(mutation)} · '
                '冲突已解决：${_resolvedCount()}',
              ),
              Text(
                'Expected fingerprint：'
                '${mutation.expectedFinalSnapshot.businessFingerprintSha256}',
              ),
              const SizedBox(height: 8),
              const Text('备份：Windows 待创建 · Android 待创建'),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  key: const ValueKey('sync-dry-run'),
                  onPressed: _submitting ? null : _dryRun,
                  icon: const Icon(Icons.rule),
                  label: const Text('Dry Run'),
                ),
                if (widget.onConfirmedApply != null)
                  FilledButton.icon(
                    key: const ValueKey('sync-apply'),
                    onPressed: mutation == null || _submitting
                        ? null
                        : _confirmApply,
                    icon: const Icon(Icons.sync),
                    label: Text(_submitting ? '正在启动同步…' : '执行同步'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _choose(Map<String, SyncSide> target, String key, SyncSide side) {
    setState(() {
      target[key] = side;
      _mutationPlan = null;
      _validationError = null;
    });
  }

  ResolvedSyncPlan _resolved() => ResolvedSyncPlan(
    preview: widget.plan,
    recordChoices: _recordChoices,
    listChoices: _listChoices,
  );

  void _dryRun() {
    try {
      final mutation = const SyncPlanCompiler().compile(
        resolved: _resolved(),
        windows: widget.windowsSnapshot!,
        android: widget.androidSnapshot!,
        baseline: widget.baseline,
      );
      setState(() {
        _mutationPlan = mutation;
        _validationError = null;
      });
    } catch (error) {
      setState(() {
        _mutationPlan = null;
        _validationError = '$error';
      });
    }
  }

  Future<void> _confirmApply() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('执行真实双端同步？'),
        content: const Text(
          '这将同时修改电脑和手机上的 Jax 数据。\n\n'
          '同步前会自动创建两端备份；任何验证失败都会尝试恢复两端数据。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey('confirm-real-sync'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('执行同步'),
          ),
        ],
      ),
    );
    if (confirmed != true || _submitting) return;
    setState(() => _submitting = true);
    try {
      await widget.onConfirmedApply!(_resolved());
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _validationError = '$error';
      });
    }
  }

  int _listOperationCount(SyncMutationPlan plan) => [
    ...plan.windowsOperations,
    ...plan.androidOperations,
  ].where((operation) => operation.type == SyncMutationType.applyList).length;

  int _resolvedCount() => _recordChoices.values
      .followedBy(_listChoices.values)
      .where((side) => side != SyncSide.unresolved)
      .length;

  String _numbered(List<String> values) =>
      [for (var i = 0; i < values.length; i++) '${i + 1}. ${values[i]}']
          .join('\n');

  String _sideDescription(SyncPlanItem item) => switch (item.comparison) {
    SyncComparisonKind.onlyWindows => '电脑新增',
    SyncComparisonKind.onlyAndroid => '手机新增',
    SyncComparisonKind.deletedWindows => '电脑删除',
    SyncComparisonKind.deletedAndroid => '手机删除',
    _ => item.detail ?? item.comparison.name,
  };
}
