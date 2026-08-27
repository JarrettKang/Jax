class EventDayPlan {
  const EventDayPlan({
    required this.eventId,
    required this.dayKey,
    required this.order,
    required this.createdAt,
  });

  final String eventId;
  final String dayKey;
  final int order;
  final DateTime createdAt;

  EventDayPlan copyWith({int? order}) => EventDayPlan(
    eventId: eventId,
    dayKey: dayKey,
    order: order ?? this.order,
    createdAt: createdAt,
  );
}
