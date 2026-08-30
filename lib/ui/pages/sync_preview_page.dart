import 'package:flutter/material.dart';

import '../../core/sync/sync_compare_engine.dart';

/// Debug-facing Phase 2A renderer. Choices update only this widget's in-memory
/// proposal state; there is intentionally no repository or apply dependency.
class SyncPreviewPage extends StatefulWidget {
  const SyncPreviewPage({required this.plan, super.key});
  final SyncPlan plan;

  @override
  State<SyncPreviewPage> createState() => _SyncPreviewPageState();
}

class _SyncPreviewPageState extends State<SyncPreviewPage> {
  final Map<String, SyncSide> _choices = {};

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Jax Sync · 仅预览')),
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
            if (widget.plan.count(SyncComparisonKind.deletedWindows) > 0)
              _metric(
                '电脑删除',
                widget.plan.count(SyncComparisonKind.deletedWindows),
              ),
            if (widget.plan.count(SyncComparisonKind.deletedAndroid) > 0)
              _metric(
                '手机删除',
                widget.plan.count(SyncComparisonKind.deletedAndroid),
              ),
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
        const Padding(
          padding: EdgeInsets.only(top: 20),
          child: Text('Phase 2A 不会写入任一数据库。以上选择只保存在当前页面内存中。'),
        ),
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
      _choice(item.key),
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
      _choice(item.key),
    ],
  );
  Widget _invariantTile(SyncInvariantConflict item) => ExpansionTile(
    title: Text(item.title),
    subtitle: Text(item.detail),
    children: [_choice('invariant:${item.type.name}:${item.title}')],
  );
  Widget _choice(String key) => SegmentedButton<SyncSide>(
    segments: const [
      ButtonSegment(value: SyncSide.windows, label: Text('使用电脑')),
      ButtonSegment(value: SyncSide.android, label: Text('使用手机')),
      ButtonSegment(value: SyncSide.unresolved, label: Text('暂不处理')),
    ],
    selected: {_choices[key] ?? SyncSide.unresolved},
    onSelectionChanged: (value) => setState(() => _choices[key] = value.single),
  );
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
