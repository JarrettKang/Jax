import 'package:flutter/material.dart';

import '../../core/entities/daily_execution_segment.dart';

String recordClock(DateTime value) {
  final t = value.toLocal();
  return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

String recordDate(DateTime value) {
  final t = value.toLocal();
  return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
}

String recordRange(DailyExecutionSegment segment, DateTime day, DateTime now) {
  final start = segment.startedAt.toLocal();
  final end = segment.endedAt?.toLocal() ?? now.toLocal();
  final dated =
      !DateUtils.isSameDay(start, end) || !DateUtils.isSameDay(start, day);
  String time(DateTime t) =>
      '${dated ? '${recordDate(t)} ' : ''}${recordClock(t)}';
  return '${time(start)} → ${segment.isOpen ? '现在' : time(end)}';
}

String recordDuration(Duration value) =>
    '${value.inHours}h ${(value.inMinutes % 60).toString().padLeft(2, '0')}m';
