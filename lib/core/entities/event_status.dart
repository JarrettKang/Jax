enum EventStatus {
  pending,
  running,
  paused,
  waiting,
  completed;

  static EventStatus fromStorage(String value) {
    return EventStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => throw FormatException('Unknown event status: $value'),
    );
  }
}
