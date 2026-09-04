class JaxDay {
  const JaxDay({
    required this.displayDate,
    required this.start,
    required this.end,
  });

  final DateTime displayDate;
  final DateTime start;
  final DateTime end;

  String get key =>
      '${displayDate.year.toString().padLeft(4, '0')}-${displayDate.month.toString().padLeft(2, '0')}-${displayDate.day.toString().padLeft(2, '0')}';

  JaxDay get previous => JaxDay.forDisplayDate(
    DateTime(displayDate.year, displayDate.month, displayDate.day - 1),
  );

  static JaxDay containing(DateTime instant) {
    final local = instant.toLocal();
    final calendarDate = DateTime(local.year, local.month, local.day);
    final displayDate = local.hour >= 23
        ? calendarDate.add(const Duration(days: 1))
        : calendarDate;
    final start = displayDate
        .subtract(const Duration(days: 1))
        .add(const Duration(hours: 23));
    return JaxDay(
      displayDate: displayDate,
      start: start,
      end: displayDate.add(const Duration(hours: 23)),
    );
  }

  static JaxDay forDisplayDate(DateTime date) {
    final displayDate = DateTime(date.year, date.month, date.day);
    return JaxDay(
      displayDate: displayDate,
      start: displayDate
          .subtract(const Duration(days: 1))
          .add(const Duration(hours: 23)),
      end: displayDate.add(const Duration(hours: 23)),
    );
  }
}
