import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/sync/resolved_sync_plan.dart';
import '../../data/sync/windows_debug_sync_coordinator.dart';
import '../../data/sync/sync_storage_service.dart';
import 'sync_preview_page.dart';

class DebugSyncPage extends StatefulWidget {
  const DebugSyncPage({
    required this.coordinator,
    this.initialAnalysis,
    this.initialSerial,
    super.key,
  });
  final DebugSyncCoordinator coordinator;
  final DebugSyncAnalysis? initialAnalysis;
  final String? initialSerial;

  @override
  State<DebugSyncPage> createState() => _DebugSyncPageState();
}

class _DebugSyncPageState extends State<DebugSyncPage> {
  DebugSyncConnection? _connection;
  late DebugSyncAnalysis? _analysis;
  DebugSyncRunResult? _result;
  late String? _serial;
  String? _error;
  String _stage = '等待检查连接';
  bool _busy = false;
  SyncStorageSettings? _storage;
  SyncStorageInventory? _inventory;

  @override
  void initState() {
    super.initState();
    _analysis = widget.initialAnalysis;
    _serial = widget.initialSerial;
    if (_analysis != null) _stage = '分析完成';
    _loadStorage();
  }

  Future<void> _loadStorage() async {
    try {
      final storage = await widget.coordinator.loadStorage();
      final inventory = await widget.coordinator.storageInventory(storage);
      if (mounted) {
        setState(() {
          _storage = storage;
          _inventory = inventory;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = '无法读取同步存储配置：$error');
      }
    }
  }

  Future<void> _checkConnection() async {
    setState(() {
      _busy = true;
      _error = null;
      _stage = '正在检查 ADB 和设备…';
    });
    final connection = await widget.coordinator.inspectDevices();
    String? serial = _serial;
    final authorized = connection.devices.where((d) => d.authorized).toList();
    if (authorized.length == 1) serial = authorized.single.serial;
    String? error = connection.message;
    if (serial != null && authorized.any((d) => d.serial == serial)) {
      setState(() => _stage = '正在检查 Jax Debug 和数据库访问…');
      error = await widget.coordinator.verifyDevice(serial);
    }
    if (!mounted) return;
    setState(() {
      _connection = connection;
      _serial = serial;
      _busy = false;
      _error = error;
      _stage = error == null && serial != null ? '连接检查完成' : '连接尚未就绪';
    });
  }

  Future<void> _analyze() async {
    final serial = _serial;
    if (serial == null) return;
    setState(() {
      _busy = true;
      _analysis = null;
      _result = null;
      _error = null;
      _stage = '正在读取电脑数据…';
    });
    try {
      final analysis = await widget.coordinator.analyze(
        serial,
        onStage: (stage) {
          if (mounted) setState(() => _stage = _stageLabel(stage));
        },
      );
      if (!mounted) return;
      setState(() {
        _analysis = analysis;
        _stage = '分析完成';
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply(ResolvedSyncPlan resolved) async {
    setState(() {
      _busy = true;
      _error = null;
      _stage = '正在重新检查数据…';
    });
    final result = await widget.coordinator.apply(
      _serial!,
      _analysis!,
      resolved,
      onStage: (stage) {
        if (mounted) setState(() => _stage = _stageLabel(stage));
      },
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = result;
      if (result.exitCode != 0) {
        _error = _resultMessage(result);
      }
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Jax Sync · Debug Tools'),
      actions: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Center(
            child: Text(
              'REAL DATA',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ),
      ],
    ),
    body: Column(
      children: [
        _statusBar(),
        Expanded(child: _body()),
      ],
    ),
  );

  Widget _statusBar() => Material(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          if (_busy) ...[
            const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(child: Text(_stage)),
          Text(_baselineLabel()),
        ],
      ),
    ),
  );

  Widget _body() {
    if (_result != null) return _resultView(_result!);
    if (_analysis != null) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: _storageCard(),
          ),
          Expanded(
            child: SyncPreviewPage(
              plan: _analysis!.plan,
              windowsSnapshot: _analysis!.windowsSnapshot,
              androidSnapshot: _analysis!.androidSnapshot,
              baseline: _analysis!.baseline,
              onConfirmedApply: _busy ? null : _apply,
              embedded: true,
            ),
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _storageCard(),
        const SizedBox(height: 20),
        Text('连接状态', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        ListTile(
          leading: const Icon(Icons.computer),
          title: const Text('Windows'),
          subtitle: const Text('本机 Jax Debug 数据库'),
          trailing: const Text('REAL DATA'),
        ),
        if (_connection != null)
          RadioGroup<String>(
            groupValue: _serial,
            onChanged: _busy
                ? (_) {}
                : (value) => setState(() => _serial = value),
            child: Column(
              children: [
                for (final device in _connection!.devices)
                  RadioListTile<String>(
                    value: device.serial,
                    enabled: !_busy && device.authorized,
                    title: Text(device.model),
                    subtitle: Text('${device.serial} · ${device.state}'),
                  ),
              ],
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Wrap(
          spacing: 12,
          children: [
            OutlinedButton.icon(
              onPressed: _busy ? null : _checkConnection,
              icon: const Icon(Icons.usb),
              label: const Text('检查连接'),
            ),
            FilledButton.icon(
              onPressed: _busy || _serial == null || _error != null
                  ? null
                  : _analyze,
              icon: const Icon(Icons.manage_search),
              label: const Text('分析同步'),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const Text('需要：Android 开发者模式、USB 调试、ADB，以及手机上的 Jax Debug 安装。'),
      ],
    );
  }

  Widget _storageCard() {
    final storage = _storage;
    if (storage == null) return const LinearProgressIndicator();
    final canChange = !_busy && _analysis == null && _result == null;
    return Card(
      child: ExpansionTile(
        title: const Text('同步数据存储位置'),
        subtitle: Text(storage.root),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('保存同步基线、同步前备份和诊断信息。选择的目录将直接作为 SyncStorageRoot。'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('备份保留：最近 '),
              DropdownButton<int>(
                value: storage.backupRetention,
                items: List.generate(50, (index) => index + 1)
                    .map(
                      (value) =>
                          DropdownMenuItem(value: value, child: Text('$value')),
                    )
                    .toList(),
                onChanged: !canChange
                    ? null
                    : (value) async {
                        if (value == null) return;
                        await widget.coordinator.updateBackupRetention(value);
                        await _loadStorage();
                      },
              ),
              const Text(' 次'),
              const Spacer(),
              if (_inventory != null)
                Text(
                  '${_inventory!.backupSessions} 个备份 · ${_formatBytes(_inventory!.totalBytes)}',
                ),
            ],
          ),
          Wrap(
            spacing: 12,
            children: [
              OutlinedButton.icon(
                onPressed: canChange ? _changeStorage : null,
                icon: const Icon(Icons.drive_file_move_outline),
                label: const Text('更改位置'),
              ),
              TextButton.icon(
                onPressed: _busy ? null : widget.coordinator.openStorageFolder,
                icon: const Icon(Icons.folder_open),
                label: const Text('打开文件夹'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _changeStorage() async {
    final destination = await widget.coordinator.chooseStorageDirectory();
    if (destination == null || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('迁移现有同步数据？'),
        content: Text(
          '旧位置：${_storage!.root}\n\n新位置：$destination\n\n'
          '将复制并验证 Last Successful Sync Baseline、${_inventory?.backupSessions ?? 0} 次备份及诊断数据。'
          '验证成功并切换配置后，才会清理旧副本。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('迁移并使用新位置'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      _busy = true;
      _error = null;
      _stage = '正在复制并验证同步数据…';
    });
    try {
      final result = await widget.coordinator.migrateStorage(destination);
      await _loadStorage();
      if (mounted) {
        setState(() => _stage = '同步存储迁移完成');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.removedOldCopies
                  ? '迁移完成，旧副本已安全清理。'
                  : '迁移完成；部分旧副本未能清理，可稍后手工检查。',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '迁移失败，当前仍使用原同步数据位置。\n$error';
          _stage = '迁移失败';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _formatBytes(int bytes) => bytes < 1024 * 1024
      ? '${(bytes / 1024).toStringAsFixed(1)} KB'
      : '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';

  Widget _resultView(DebugSyncRunResult result) {
    final success = result.status == 'Success';
    final rolledBack = result.status == 'SYNC_FAILED_ROLLED_BACK';
    final critical = result.status == 'CRITICAL_ROLLBACK_FAILURE';
    final baselineFailed =
        result.status == 'SYNC_APPLIED_BASELINE_WRITE_FAILED';
    final report = result.report;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Icon(
          success ? Icons.check_circle : Icons.error,
          size: 56,
          color: success
              ? Colors.green
              : critical
              ? Theme.of(context).colorScheme.error
              : Colors.orange,
        ),
        const SizedBox(height: 12),
        Text(
          success
              ? '同步成功'
              : baselineFailed
              ? '双端数据已同步，但 Baseline 写入失败'
              : rolledBack
              ? '同步失败，已恢复电脑和手机到同步前状态'
              : critical
              ? '数据恢复未完全成功，请不要继续使用同步工具'
              : '同步未完成',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        if (_error != null) SelectableText(_error!),
        const SizedBox(height: 16),
        Text('Windows backup：${report['windowsBackup'] ?? '未创建'}'),
        Text('Android backup：${report['androidBackup'] ?? '未创建'}'),
        Text('Baseline：${report['baselinePath'] ?? '尚未建立'}'),
        Text('Final fingerprint：${report['finalFingerprint'] ?? '未验证'}'),
        if (report['postSyncSummary'] != null)
          Text('最终复核：${report['postSyncSummary']}'),
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          children: [
            OutlinedButton(onPressed: _analyze, child: const Text('重新分析')),
            FilledButton(onPressed: _finish, child: const Text('完成')),
          ],
        ),
      ],
    );
  }

  Future<void> _finish() async {
    await Process.start(
      Platform.resolvedExecutable,
      const [],
      workingDirectory: widget.coordinator.projectRoot,
    );
    exit(0);
  }

  String _baselineLabel() => _analysis == null
      ? 'Baseline：待分析'
      : _analysis!.plan.hasBaseline
      ? 'Baseline：已建立 · Three-way Compare'
      : 'Baseline：尚未建立 · 首次同步';

  String _stageLabel(String stage) => switch (stage) {
    'StoppingApps' => '正在停止业务写入…',
    'Analyzing' => '正在读取手机数据并检查一致性…',
    'DryRun' => '正在检查同步计划…',
    'BackingUpWindows' => '正在备份电脑…',
    'BackingUpAndroid' => '正在备份手机…',
    'BackupsReady' => '电脑和手机备份已验证…',
    'ApplyingWindows' => '正在写入电脑…',
    'ValidatingWindows' => '正在验证电脑…',
    'ApplyingAndroid' => '正在写入手机…',
    'ValidatingAndroid' => '正在验证手机…',
    'FinalVerification' => '正在检查最终状态…',
    'WritingBaseline' => '正在建立同步 Baseline…',
    'PostSyncAnalyze' => '正在执行最终复核…',
    'RollingBack' => '同步失败，正在恢复两端数据…',
    _ => stage,
  };

  String _resultMessage(DebugSyncRunResult result) {
    final error = result.report['error']?.toString() ?? result.stderr;
    if (error.contains('STALE_SYNC_PLAN')) return '数据在分析后发生变化。没有执行同步，请重新分析。';
    if (result.status == 'SYNC_FAILED_ROLLED_BACK') {
      return '同步失败，但两端数据已安全恢复。\n$error';
    }
    if (result.status == 'CRITICAL_ROLLBACK_FAILURE') {
      return '数据恢复未完全成功。请保留备份并停止同步操作。\n$error';
    }
    return error;
  }
}
