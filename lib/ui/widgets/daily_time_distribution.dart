import 'package:flutter/material.dart';

import '../../core/entities/daily_execution_segment.dart';
import '../../core/entities/daily_timeline_block.dart';

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
      final rowHeight = wide ? 34.0 : 28.0;
      final rows = DailyTimelineLayout.forJaxDay(
        date: date,
        segments: segments,
        now: now,
      );
      return Semantics(
        label: '今日时间分布，完整 24 小时',
        child: Column(
          children: [
            for (var rowIndex = 0; rowIndex < rows.length; rowIndex++)
              _hourRow(context, rows[rowIndex], rowIndex, rowHeight, wide),
          ],
        ),
      );
    },
  );

  Widget _hourRow(
    BuildContext context,
    DailyTimelineHour hour,
    int rowIndex,
    double rowHeight,
    bool wide,
  ) => SizedBox(
    key: ValueKey('timeline-hour-$rowIndex'),
    height: rowHeight,
    child: Row(
      children: [
        SizedBox(
          width: wide ? 58 : 46,
          child: Text(
            _hourLabel(hour.startedAt),
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: Theme.of(context).colorScheme.outlineVariant,
                          width: 0.5,
                        ),
                      ),
                    ),
                  ),
                ),
                for (final fraction in const [0.25, 0.5, 0.75])
                  Positioned(
                    left: constraints.maxWidth * fraction,
                    top: 3,
                    bottom: 3,
                    child: VerticalDivider(
                      width: 1,
                      thickness: 0.5,
                      color: Theme.of(context).colorScheme.outlineVariant
                          .withValues(alpha: 0.65),
                    ),
                  ),
                for (
                  var fragmentIndex = 0;
                  fragmentIndex < hour.fragments.length;
                  fragmentIndex++
                )
                  ..._fragment(
                    context,
                    hour.fragments[fragmentIndex],
                    constraints.maxWidth,
                    rowHeight,
                    rowIndex,
                    fragmentIndex,
                    wide,
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  List<Widget> _fragment(
    BuildContext context,
    DailyTimelineFragment fragment,
    double trackWidth,
    double rowHeight,
    int rowIndex,
    int fragmentIndex,
    bool wide,
  ) {
    final left = trackWidth * fragment.startFraction;
    final width = trackWidth * fragment.durationFraction;
    final blockHeight = rowHeight - 8;
    final top = 4.0;
    final color = colorForBucket(fragment.segment.categoryBucketKey);
    final tooltip = _tooltip(fragment.segment);
    final identity = '${fragment.segment.id}-$rowIndex-$fragmentIndex';
    final visual = Positioned(
      key: ValueKey('timeline-visual-$identity'),
      left: left,
      top: top,
      width: width,
      height: blockHeight,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color.withValues(
              alpha: fragment.segment.isOpen ? 0.72 : 0.86,
            ),
            borderRadius: BorderRadius.circular(3),
          ),
          child: width >= (wide ? 72 : 58)
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      fragment.segment.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color:
                            ThemeData.estimateBrightnessForColor(color) ==
                                Brightness.dark
                            ? Colors.white
                            : Colors.black87,
                      ),
                    ),
                  ),
                )
              : null,
        ),
      ),
    );
    final hitWidth = width < 32 ? 32.0 : width;
    final hitLeft = (left - (hitWidth - width) / 2).clamp(
      0.0,
      trackWidth - hitWidth,
    );
    final hit = Positioned(
      key: ValueKey('timeline-hit-$identity'),
      left: hitLeft,
      top: 0,
      width: hitWidth,
      height: rowHeight,
      child: Tooltip(
        message: tooltip,
        waitDuration: wide ? const Duration(milliseconds: 350) : Duration.zero,
        child: Semantics(
          button: true,
          label: tooltip,
          child: InkWell(onTap: () => onSegmentTap(fragment.segment)),
        ),
      ),
    );
    return [visual, hit];
  }

  String _tooltip(DailyExecutionSegment segment) {
    final end = segment.endedAt?.toLocal() ?? now;
    return '${segment.name}\n${_clock(segment.startedAt.toLocal())}–${segment.isOpen ? '现在' : _clock(end)}\n${_duration(end.difference(segment.startedAt.toLocal()))}\n${segment.categoryName}${segment.isOpen ? '\n正在执行' : ''}';
  }

  static String _hourLabel(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:00';
  static String _clock(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  static String _duration(Duration value) =>
      '${value.inHours}h ${(value.inMinutes % 60).toString().padLeft(2, '0')}m';
}
