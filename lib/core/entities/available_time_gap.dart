class AvailableTimeGap {
  const AvailableTimeGap({required this.start, required this.end});

  final DateTime start;
  final DateTime end;

  bool contains(DateTime candidateStart, DateTime candidateEnd) =>
      !candidateStart.isBefore(start) && !candidateEnd.isAfter(end);
}
