import 'package:flutter/material.dart';

import '../../core/entities/time_summary.dart';
import '../../core/entities/daily_execution_segment.dart';
import '../../core/entities/available_time_gap.dart';
import '../controllers/event_controller.dart';
import '../theme/category_palette_colors.dart';
import '../widgets/daily_time_distribution.dart';

class SummaryPage extends StatefulWidget {
  const SummaryPage({required this.controller, super.key});
  final EventController controller;
  @override
  State<SummaryPage> createState() => _SummaryPageState();
}

class _SummaryPageState extends State<SummaryPage> {
  var _week = false;
  late DateTime _anchor;

  @override
  void initState() {
    super.initState();
    // Summary navigation must use the app's injected clock.  Besides keeping
    // the page aligned with the 23:00 Jax-day boundary, this avoids a brief
    // mismatch between the visible "today" and the data service after reload.
    _anchor = widget.controller.currentJaxDay.displayDate;
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) => FutureBuilder<List<Object>>(
      key: ValueKey(
        'record-summary-${_week ? 'week' : 'day'}-${_anchor.year}-${_anchor.month}-${_anchor.day}',
      ),
      future: Future.wait([
        _week
            ? widget.controller.weeklySummary(_anchor)
            : widget.controller.dailySummary(_anchor),
        if (!_week) widget.controller.dailyExecutionSegments(_anchor),
      ]),
      builder: (context, snapshot) {
        final summary = snapshot.data?.firstOrNull as TimeSummary?;
        final segments = !_week && snapshot.data != null
            ? snapshot.data![1] as List<DailyExecutionSegment>
            : const <DailyExecutionSegment>[];
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  label: Text('日总结'),
                  icon: Icon(Icons.today_outlined),
                ),
                ButtonSegment(
                  value: true,
                  label: Text('周总结'),
                  icon: Icon(Icons.date_range_outlined),
                ),
              ],
              selected: {_week},
              onSelectionChanged: (value) =>
                  setState(() => _week = value.single),
            ),
            const SizedBox(height: 20),
            _navigator(),
            if (summary == null)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              Text(
                summary.isCurrent ? (_week ? '本周 · 进行中' : '今天 · 进行中') : '已结束',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 4),
              Text(
                '${_time(summary.start)} – ${_time(summary.end)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 20),
              Text('已记录时间', style: Theme.of(context).textTheme.titleMedium),
              Text(
                _duration(summary.total),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              if (summary.categories.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: Text(_week ? '这一周没有记录到执行时间' : '这一天没有记录到执行时间'),
                  ),
                )
              else ...[
                if (_week && summary is WeeklyTimeSummary) ...[
                  const SizedBox(height: 28),
                  Text(
                    '每日时间分配',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  _WeeklyBars(summary: summary),
                ],
                const SizedBox(height: 28),
                Text(
                  _week ? '本周分类汇总' : '各分类时间',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                for (var i = 0; i < summary.categories.length; i++)
                  _CategoryBar(
                    item: summary.categories[i],
                    total: summary.total,
                    color: _color(context, summary.categories[i]),
                  ),
              ],
              if (!_week) ...[
                const SizedBox(height: 32),
                Text('今日时间分布', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                DailyTimeDistribution(
                  date: _anchor,
                  segments: segments,
                  now: widget.controller.currentTime,
                  colorForSegment: (segment) => segment.categoryColorKey == null
                      ? CategoryPaletteColors.neutral(context)
                      : CategoryPaletteColors.resolve(
                          context,
                          segment.categoryColorKey!,
                        ),
                  onSegmentTap: (segment) =>
                      _editSegment(context, segment, segments),
                ),
                const SizedBox(height: 32),
                Row(
                  children: [
                    Text(
                      '执行记录',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () => _addSegment(context),
                      icon: const Icon(Icons.add),
                      label: const Text('添加执行记录'),
                    ),
                  ],
                ),
                if (segments.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('这一天没有执行片段'),
                  ),
                for (final segment in segments)
                  _SegmentRow(
                    segment: segment,
                    day: _anchor,
                    onTap: () => _editSegment(context, segment, segments),
                  ),
              ],
            ],
          ],
        );
      },
    ),
  );

  DateTime _onDay(TimeOfDay value) {
    final date = value.hour >= 23
        ? _anchor.subtract(const Duration(days: 1))
        : _anchor;
    return DateTime(date.year, date.month, date.day, value.hour, value.minute);
  }

  Future<void> _editSegment(
    BuildContext context,
    DailyExecutionSegment segment,
    List<DailyExecutionSegment> list,
  ) async {
    if (segment.isOpen) {
      await _showOpenSegment(context, segment);
      return;
    }
    var start = segment.startedAt.toLocal();
    var end = segment.endedAt!.toLocal();
    final index = list.indexOf(segment);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => StatefulBuilder(
        builder: (context, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            24,
            24,
            24 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(segment.name, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              _timeButton(context, '开始', start, () async {
                final t = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay.fromDateTime(start),
                );
                if (t != null) setSheet(() => start = _onDay(t));
              }),
              _timeButton(context, '结束', end, () async {
                final t = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay.fromDateTime(end),
                );
                if (t != null) setSheet(() => end = _onDay(t));
              }),
              if (index > 0) _contextLine('上一项', list[index - 1]),
              if (index >= 0 && index < list.length - 1)
                _contextLine('下一项', list[index + 1]),
              const SizedBox(height: 16),
              Row(
                children: [
                  TextButton(
                    onPressed: () async {
                      final error = await widget.controller
                          .deleteClosedExecutionSegment(segment);
                      if (context.mounted) {
                        Navigator.pop(context);
                        if (error != null) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(SnackBar(content: Text(error)));
                        }
                      }
                    },
                    child: const Text('删除'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () async {
                      final error = await widget.controller
                          .updateClosedExecutionSegment(segment, start, end);
                      if (context.mounted && error == null) {
                        Navigator.pop(context);
                      }
                      if (context.mounted && error != null) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text(error)));
                      }
                    },
                    child: const Text('保存'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showOpenSegment(
    BuildContext context,
    DailyExecutionSegment segment,
  ) => showModalBottomSheet<void>(
    context: context,
    builder: (context) {
      final elapsed = widget.controller.currentTime.difference(
        segment.startedAt.toLocal(),
      );
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(segment.name, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Text('${_clock(segment.startedAt)} → 现在'),
            const SizedBox(height: 4),
            Text(_duration(elapsed)),
            const SizedBox(height: 4),
            Text(segment.categoryName),
            const SizedBox(height: 12),
            Text(
              '正在执行 · 请在 Today 中暂停或完成',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
    },
  );

  Widget _contextLine(String label, DailyExecutionSegment segment) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Text(
      '$label  ${segment.name}  ${_clock(segment.startedAt)}–${segment.endedAt == null ? '现在' : _clock(segment.endedAt!)}',
    ),
  );
  Widget _timeButton(
    BuildContext context,
    String label,
    DateTime value,
    VoidCallback tap,
  ) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    trailing: TextButton(onPressed: tap, child: Text(_clock(value))),
  );
  Future<void> _addSegment(BuildContext context) async {
    final eventCandidates = [
      for (final event in widget.controller.historicalEventCandidates)
        _Candidate.event(
          event.id,
          event.name,
          widget.controller.historicalEventContext(event),
        ),
    ];
    final scheduledCandidates = [
      for (final routine
          in widget.controller.historicalScheduledRoutineCandidates)
        _Candidate.routine(
          routine.id,
          routine.name,
          widget.controller.historicalRoutineContext(routine),
        ),
    ];
    final onDemandCandidates = [
      for (final routine
          in widget.controller.historicalOnDemandRoutineCandidates)
        _Candidate.routine(
          routine.id,
          routine.name,
          widget.controller.historicalRoutineContext(routine),
        ),
    ];
    final candidates = [
      ...eventCandidates,
      ...scheduledCandidates,
      ...onDemandCandidates,
    ];
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('当天没有可补记的事项或日常')));
      return;
    }
    final picked = await showModalBottomSheet<_Candidate>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.78,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(title: Text('选择要补记的对象')),
              if (eventCandidates.isNotEmpty) ...[
                const _CandidateGroupTitle('今日事项'),
                for (final candidate in eventCandidates)
                  _CandidateTile(candidate),
              ],
              if (scheduledCandidates.isNotEmpty) ...[
                const _CandidateGroupTitle('今日日常'),
                for (final candidate in scheduledCandidates)
                  _CandidateTile(candidate),
              ],
              if (onDemandCandidates.isNotEmpty) ...[
                const _CandidateGroupTitle('快捷动作'),
                for (final candidate in onDemandCandidates)
                  _CandidateTile(candidate),
              ],
            ],
          ),
        ),
      ),
    );
    if (picked == null || !context.mounted) return;
    final gaps = await widget.controller.availableTimeGaps(_anchor);
    if (!context.mounted) return;
    var start = _onDay(const TimeOfDay(hour: 12, minute: 0));
    var end = _onDay(const TimeOfDay(hour: 12, minute: 30));
    var showAllGaps = false;
    String? rangeError;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => StatefulBuilder(
        builder: (context, setSheet) {
          Future<void> setAndValidate({
            TimeOfDay? newStart,
            TimeOfDay? newEnd,
          }) async {
            setSheet(() {
              if (newStart != null) start = _onDay(newStart);
              if (newEnd != null) end = _onDay(newEnd);
              rangeError = null;
            });
            final error = await widget.controller
                .validateHistoricalSegmentRange(start, end);
            if (context.mounted) setSheet(() => rangeError = error);
          }

          final containingGap = gaps
              .where((gap) => gap.contains(start, end))
              .firstOrNull;
          final visibleGaps = showAllGaps ? gaps : gaps.take(5).toList();
          return SafeArea(
            child: FractionallySizedBox(
              heightFactor: 0.84,
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  24,
                  20,
                  24,
                  20 + MediaQuery.viewInsetsOf(context).bottom,
                ),
                children: [
                  Text('添加执行记录', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  Text(
                    picked.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    picked.context,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 20),
                  Text('可用空白时间', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  if (visibleGaps.isEmpty)
                    Text(
                      '当前没有可用空白时间',
                      style: Theme.of(context).textTheme.bodySmall,
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (var index = 0; index < visibleGaps.length; index++)
                          OutlinedButton(
                            key: ValueKey('available-gap-$index'),
                            onPressed: () => setSheet(() {
                              start = visibleGaps[index].start;
                              end = visibleGaps[index].end;
                              rangeError = null;
                            }),
                            child: Text(_gapRange(visibleGaps[index])),
                          ),
                      ],
                    ),
                  if (gaps.length > 5)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () =>
                            setSheet(() => showAllGaps = !showAllGaps),
                        child: Text(showAllGaps ? '收起' : '查看全部'),
                      ),
                    ),
                  const SizedBox(height: 12),
                  _timeButton(context, '开始时间', start, () async {
                    final value = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(start),
                    );
                    if (value != null) await setAndValidate(newStart: value);
                  }),
                  _timeButton(context, '结束时间', end, () async {
                    final value = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(end),
                    );
                    if (value != null) await setAndValidate(newEnd: value);
                  }),
                  if (containingGap != null)
                    Text(
                      '位于可用空白 ${_gapRange(containingGap)} 内',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  if (rangeError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      rangeError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('取消'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () async {
                          final error = picked.routine
                              ? await widget.controller
                                    .addHistoricalRoutineSegment(
                                      picked.id,
                                      _anchor,
                                      start,
                                      end,
                                    )
                              : await widget.controller
                                    .addHistoricalEventSegment(
                                      picked.id,
                                      start,
                                      end,
                                    );
                          if (context.mounted && error == null) {
                            Navigator.pop(context);
                          }
                          if (context.mounted && error != null) {
                            setSheet(() => rangeError = error);
                          }
                        },
                        child: const Text('添加记录'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  static String _gapRange(AvailableTimeGap gap) =>
      '${_clock(gap.start)}–${_clock(gap.end)}';

  Widget _navigator() => Row(
    children: [
      IconButton(
        tooltip: _week ? '上一周' : '前一天',
        icon: const Icon(Icons.chevron_left),
        onPressed: () => setState(
          () => _anchor = _anchor.subtract(Duration(days: _week ? 7 : 1)),
        ),
      ),
      Expanded(
        child: Center(
          child: Text(
            _week
                ? '${_date(_anchor.subtract(Duration(days: _anchor.weekday - 1)))} – ${_date(_anchor.add(Duration(days: 7 - _anchor.weekday)))}'
                : _date(_anchor),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      ),
      IconButton(
        tooltip: _week ? '下一周' : '后一天',
        icon: const Icon(Icons.chevron_right),
        onPressed: () => setState(
          () => _anchor = _anchor.add(Duration(days: _week ? 7 : 1)),
        ),
      ),
    ],
  );

  static String _date(DateTime value) => '${value.month} 月 ${value.day} 日';
  static String _time(DateTime value) =>
      '${_date(value)} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  static String _clock(DateTime value) =>
      '${value.toLocal().hour.toString().padLeft(2, '0')}:${value.toLocal().minute.toString().padLeft(2, '0')}';
  static String _duration(Duration value) =>
      '${value.inHours}h ${(value.inMinutes % 60).toString().padLeft(2, '0')}m';
  static Color _color(BuildContext context, CategoryDuration item) {
    return item.colorKey == null
        ? CategoryPaletteColors.neutral(context)
        : CategoryPaletteColors.resolve(context, item.colorKey!);
  }
}

class _SegmentRow extends StatelessWidget {
  const _SegmentRow({
    required this.segment,
    required this.day,
    required this.onTap,
  });
  final DailyExecutionSegment segment;
  final DateTime day;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
            child: Text(
              '${_clock(segment.startedAt)} → ${segment.endedAt == null ? '现在' : _clock(segment.endedAt!)}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(segment.name),
                if (segment.detail != null || segment.isOpen)
                  Text(
                    segment.isOpen ? '正在执行' : segment.detail!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

String _clock(DateTime value) =>
    '${value.toLocal().hour.toString().padLeft(2, '0')}:${value.toLocal().minute.toString().padLeft(2, '0')}';

class _Candidate {
  const _Candidate(this.id, this.name, this.context, this.routine);
  final String id, name;
  final String context;
  final bool routine;
  const _Candidate.event(String id, String name, String context)
    : this(id, name, context, false);
  const _Candidate.routine(String id, String name, String context)
    : this(id, name, context, true);
}

class _CandidateGroupTitle extends StatelessWidget {
  const _CandidateGroupTitle(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Text(label, style: Theme.of(context).textTheme.labelLarge),
  );
}

class _CandidateTile extends StatelessWidget {
  const _CandidateTile(this.candidate);
  final _Candidate candidate;
  @override
  Widget build(BuildContext context) => ListTile(
    key: ValueKey('segment-candidate-${candidate.id}'),
    dense: true,
    title: Text(candidate.name),
    subtitle: Text(
      candidate.context,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    ),
    onTap: () => Navigator.pop(context, candidate),
  );
}

class _CategoryBar extends StatelessWidget {
  const _CategoryBar({
    required this.item,
    required this.total,
    required this.color,
  });
  final CategoryDuration item;
  final Duration total;
  final Color color;
  @override
  Widget build(BuildContext context) {
    final percent = total == Duration.zero
        ? 0.0
        : item.duration.inMicroseconds / total.inMicroseconds;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(item.name, overflow: TextOverflow.ellipsis)),
              Text(
                '${SummaryPageState.duration(item.duration)} · ${(percent * 100).round()}%',
              ),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: percent,
            color: color,
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
          ),
        ],
      ),
    );
  }
}

class _WeeklyBars extends StatelessWidget {
  const _WeeklyBars({required this.summary});
  final WeeklyTimeSummary summary;
  @override
  Widget build(BuildContext context) {
    final peak = summary.days.fold<Duration>(
      Duration.zero,
      (value, day) => value > day.total ? value : day.total,
    );
    return SizedBox(
      height: 150,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var day = 0; day < 7; day++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Tooltip(
                          triggerMode: TooltipTriggerMode.tap,
                          message: SummaryPageState.duration(
                            summary.days[day].total,
                          ),
                          child: SizedBox(
                            height: peak == Duration.zero
                                ? 0
                                : 110 *
                                      summary.days[day].total.inMicroseconds /
                                      peak.inMicroseconds,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                for (final category in summary.categories)
                                  Builder(
                                    builder: (context) {
                                      final match = summary.days[day].categories
                                          .where(
                                            (item) =>
                                                item.bucketKey ==
                                                category.bucketKey,
                                          )
                                          .firstOrNull;
                                      if (match == null) {
                                        return const SizedBox.shrink();
                                      }
                                      return Expanded(
                                        flex: match.duration.inSeconds < 1
                                            ? 1
                                            : match.duration.inSeconds,
                                        child: Container(
                                          color: SummaryPageState.color(
                                            context,
                                            category,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Text(
                      '周${['一', '二', '三', '四', '五', '六', '日'][day]}',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class SummaryPageState {
  static String duration(Duration value) =>
      '${value.inHours}h ${(value.inMinutes % 60).toString().padLeft(2, '0')}m';
  static Color color(BuildContext context, CategoryDuration item) {
    return item.colorKey == null
        ? CategoryPaletteColors.neutral(context)
        : CategoryPaletteColors.resolve(context, item.colorKey!);
  }
}
