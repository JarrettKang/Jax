import 'event_status.dart';
import 'routine.dart';

extension EventExecutionCapabilities on EventStatus {
  bool get canComplete =>
      this == EventStatus.running ||
      this == EventStatus.paused ||
      this == EventStatus.waiting;
  bool get canResume =>
      this == EventStatus.paused || this == EventStatus.waiting;
}

extension RoutineExecutionCapabilities on RoutineExecutionStatus {
  bool get canComplete => this != RoutineExecutionStatus.completed;
  bool get canResume =>
      this == RoutineExecutionStatus.paused ||
      this == RoutineExecutionStatus.waiting;
}
