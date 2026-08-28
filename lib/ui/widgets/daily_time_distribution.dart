import 'package:flutter/material.dart';

import '../../core/entities/daily_execution_segment.dart';
import '../../core/entities/daily_timeline_block.dart';
import '../../core/entities/jax_day.dart';

class DailyTimeDistribution extends StatelessWidget {
  const DailyTimeDistribution({
    required this.date,
    required this.segments,
    required this.now,
    required this.colorForBucket,
    required this.onSegmentTap,
    super.key,
  });

  final DateTime date;
  final List<DailyExecutionSegment> segments;
  final DateTime now;
  final Color Function(String bucketKey) colorForBucket;
  final ValueChanged<DailyExecutionSegment> onSegmentTap;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 600;
      final timelineHeight = wide ? 960.0 : 720.0;
      final tickHours = wide ? 1 : 2;
      final day = JaxDay.forDisplayDate(date);
      final blocks = DailyTimelineBlock.forJaxDay(
        date: date,
        segments: segments,
        now: now,
      );
      return Semantics(
        label: '今日时间分布，完整 24 小时',
        child: SizedBox(
          height: timelineHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: wide ? 62 : 50,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (var hour = 0; hour <= 24; hour += tickHours)
                      Positioned(
                        top: _tickTop(hour, timelineHeight),
                        right: 8,
                        child: Text(
                          _tickLabel(day.start.add(Duration(hours: hour))),
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (var hour = 0; hour <= 24; hour += tickHours)
                      Positioned(
                        top: hour / 24 * timelineHeight,
                        left: 0,
                        right: 0,
                        child: Divider(
                          height: 1,
                          thickness: hour == 0 || hour == 24 ? 1 : 0.5,
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                    for (final block in blocks)
                      ..._block(context, block, timelineHeight, wide),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  List<Widget> _block(
    BuildContext context,
    DailyTimelineBlock block,
    double timelineHeight,
    bool wide,
  ) {
    final top = block.startFraction * timelineHeight;
    final height = block.durationFraction * timelineHeight;
    final color = colorForBucket(block.segment.categoryBucketKey);
    final tooltip = _tooltip(block);
    final showLabel = height >= 26;
    final visual = Positioned(
      key: ValueKey('timeline-visual-${block.segment.id}'),
      top: top,
      left: 4,
      right: 4,
      height: height,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color.withValues(alpha: block.segment.isOpen ? 0.72 : 0.86),
            borderRadius: BorderRadius.circular(height < 8 ? 2 : 5),
          ),
          child: showLabel
              ? Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Text(
                    block.segment.name,
                    maxLines: height >= 46 ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color:
                          ThemeData.estimateBrightnessForColor(color) ==
                              Brightness.dark
                          ? Colors.white
                          : Colors.black87,
                    ),
                  ),
                )
              : null,
        ),
      ),
    );
    final hitHeight = height < 40 ? 40.0 : height;
    final hitTop = (top - (hitHeight - height) / 2).clamp(
      0.0,
      timelineHeight - hitHeight,
    );
    final hit = Positioned(
      key: ValueKey('timeline-hit-${block.segment.id}'),
      top: hitTop,
      left: 0,
      right: 0,
      height: hitHeight,
      child: Tooltip(
        message: tooltip,
        waitDuration: wide ? const Duration(milliseconds: 350) : Duration.zero,
        child: Semantics(
          button: true,
          label: tooltip,
          child: InkWell(onTap: () => onSegmentTap(block.segment)),
        ),
      ),
    );
    return [visual, hit];
  }

  String _tooltip(DailyTimelineBlock block) =>
      '${block.segment.name}\n${_clock(block.displayStart)}–${block.segment.isOpen ? '现在' : _clock(block.displayEnd)}\n${_duration(block.displayDuration)}\n${block.segment.categoryName}${block.segment.isOpen ? '\n正在执行' : ''}';

  static double _tickTop(int hour, double height) {
    final raw = hour / 24 * height - 7;
    return raw.clamp(0.0, height - 14);
  }

  static String _tickLabel(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:00';
  static String _clock(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  static String _duration(Duration value) =>
      '${value.inHours}h ${(value.inMinutes % 60).toString().padLeft(2, '0')}m';
}
