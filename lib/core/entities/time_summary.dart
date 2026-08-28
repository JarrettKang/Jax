class CategoryDuration {
  const CategoryDuration({
    required this.categoryId,
    required this.name,
    required this.duration,
    required this.order,
    this.bucketKey = '',
    this.source = SummaryCategorySource.event,
  });

  final String? categoryId;
  final String name;
  final Duration duration;
  final int order;
  final String bucketKey;
  final SummaryCategorySource source;
}

enum SummaryCategorySource { event, routine, unclassified }

class TimeSummary {
  const TimeSummary({
    required this.start,
    required this.end,
    required this.isCurrent,
    required this.categories,
  });

  final DateTime start;
  final DateTime end;
  final bool isCurrent;
  final List<CategoryDuration> categories;

  Duration get total =>
      categories.fold(Duration.zero, (sum, item) => sum + item.duration);
}

class WeeklyTimeSummary extends TimeSummary {
  const WeeklyTimeSummary({
    required super.start,
    required super.end,
    required super.isCurrent,
    required super.categories,
    required this.days,
  });

  final List<TimeSummary> days;
}
