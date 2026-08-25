import '../repositories/event_repository.dart';
import '../use_cases/create_event.dart';

class HierarchyDurationService {
  const HierarchyDurationService(this.repository, {required this.now});

  final EventRepository repository;
  final Clock now;

  Future<Duration> directDuration(String eventId) async {
    final timestamp = now().toUtc();
    final segments = await repository.getRunSegments(eventId);
    return segments.fold<Duration>(
      Duration.zero,
      (total, segment) => total + segment.durationAt(timestamp),
    );
  }

  Future<Duration> totalDuration(String eventId) async {
    final timestamp = now().toUtc();
    final visited = <String>{};

    Future<Duration> sum(String id) async {
      if (!visited.add(id)) return Duration.zero;
      final segments = await repository.getRunSegments(id);
      var total = segments.fold<Duration>(
        Duration.zero,
        (value, segment) => value + segment.durationAt(timestamp),
      );
      for (final child in await repository.getDirectChildren(id)) {
        total += await sum(child.id);
      }
      return total;
    }

    return sum(eventId);
  }
}
