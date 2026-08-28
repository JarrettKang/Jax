import 'package:flutter/material.dart';

import '../../core/entities/time_summary.dart';
import '../controllers/event_controller.dart';
import '../widgets/execution_time_editor.dart';

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
    builder: (context, _) => FutureBuilder<TimeSummary>(
      future: _week
          ? widget.controller.weeklySummary(_anchor)
          : widget.controller.dailySummary(_anchor),
      builder: (context, snapshot) {
        final summary = snapshot.data;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: const ValueKey('execution-time-correction'),
                onPressed: () => showExecutionTimeOwnerPicker(
                  context,
                  controller: widget.controller,
                ),
                icon: const Icon(Icons.edit_calendar_outlined),
                label: const Text('执行时间纠错'),
              ),
            ),
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
            ],
          ],
        );
      },
    ),
  );

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
  static String _duration(Duration value) =>
      '${value.inHours}h ${(value.inMinutes % 60).toString().padLeft(2, '0')}m';
  static Color _color(BuildContext context, CategoryDuration item) {
    if (item.source == SummaryCategorySource.unclassified) {
      return Theme.of(context).colorScheme.outline;
    }
    const colors = [
      Colors.teal,
      Colors.indigo,
      Colors.orange,
      Colors.purple,
      Colors.pink,
    ];
    return colors[item.bucketKey.hashCode.abs() % colors.length];
  }
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
    if (item.source == SummaryCategorySource.unclassified) {
      return Theme.of(context).colorScheme.outline;
    }
    const colors = [
      Colors.teal,
      Colors.indigo,
      Colors.orange,
      Colors.purple,
      Colors.pink,
    ];
    return colors[item.bucketKey.hashCode.abs() % colors.length];
  }
}
