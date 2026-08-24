enum EventStatus {
  pending,
  running,
  paused,
  completed;

  static EventStatus fromStorage(String value) {
    return EventStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => throw FormatException('Unknown event status: $value'),
    );
  }
}
