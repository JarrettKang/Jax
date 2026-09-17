import '../services/temporal_routine.dart';
import '../entities/event_status.dart';
import '../entities/jax_day.dart';
import '../entities/jax_event.dart';
import '../entities/routine.dart';

enum RecommendationCandidateKind { event, scheduledRoutine }

enum RecommendationStrength { normal, promoted }

class RecommendationContext {
  const RecommendationContext({
    required this.currentLocalDateTime,
    required this.currentJaxDay,
    required this.todayEvents,
    required this.todayScheduledRoutines,
    required this.routineExecutions,
    this.runningEventId,
    this.runningRoutineId,
  });

  final DateTime currentLocalDateTime;
  final JaxDay currentJaxDay;
  final List<JaxEvent> todayEvents;
  final List<Routine> todayScheduledRoutines;
  final Map<String, RoutineExecution?> routineExecutions;
  final String? runningEventId;
  final String? runningRoutineId;
}

class RecommendationCandidate {
  const RecommendationCandidate._({
    required this.id,
    required this.kind,
    required this.stableOrder,
    this.event,
    this.routine,
    this.execution,
  });

  factory RecommendationCandidate.event(JaxEvent event, int stableOrder) =>
      RecommendationCandidate._(
        id: event.id,
        kind: RecommendationCandidateKind.event,
        stableOrder: stableOrder,
        event: event,
      );

  factory RecommendationCandidate.scheduledRoutine(
    Routine routine,
    RoutineExecution? execution,
    int stableOrder,
  ) => RecommendationCandidate._(
    id: routine.id,
    kind: RecommendationCandidateKind.scheduledRoutine,
    stableOrder: stableOrder,
    routine: routine,
    execution: execution,
  );

  final String id;
  final RecommendationCandidateKind kind;
  final int stableOrder;
  final JaxEvent? event;
  final Routine? routine;
  final RoutineExecution? execution;
}

class RecommendationSignal {
  const RecommendationSignal({
    required this.candidateId,
    required this.ruleId,
    required this.strength,
    required this.reason,
  });

  final String candidateId;
  final String ruleId;
  final RecommendationStrength strength;
  final String reason;
}

abstract interface class RecommendationRule {
  RecommendationSignal? evaluate(
    RecommendationContext context,
    RecommendationCandidate candidate,
  );
}

class TimeRecommendationRule implements RecommendationRule {
  const TimeRecommendationRule();
  static const ruleId = 'scheduled-routine-time';

  @override
  RecommendationSignal? evaluate(
    RecommendationContext context,
    RecommendationCandidate candidate,
  ) {
    if (candidate.kind != RecommendationCandidateKind.scheduledRoutine) {
      return null;
    }
    final routine = candidate.routine!;
    final execution = candidate.execution;
    final configuration = routine.timeRecommendation;
    if (!routine.isScheduled ||
        !routine.isActive ||
        configuration == null ||
        context.runningRoutineId == routine.id ||
        execution?.status == RoutineExecutionStatus.paused ||
        execution?.status == RoutineExecutionStatus.waiting ||
        execution?.status == RoutineExecutionStatus.running ||
        execution?.status == RoutineExecutionStatus.completed) {
      return null;
    }
    ResolvedTemporalWindow? window;
    try {
      window = TemporalRoutine.actionable(
        routine,
        context.currentJaxDay,
        context.currentLocalDateTime,
      );
    } on Object {
      return null;
    }
    if (window == null) return null;
    final start = configuration.startMinute;
    final end = configuration.latestEndMinute;
    return RecommendationSignal(
      candidateId: candidate.id,
      ruleId: ruleId,
      strength: RecommendationStrength.promoted,
      reason:
          configuration.reason ??
          '当前处于推荐时间 ${formatMinute(start)}–${formatMinute(end)}',
    );
  }

  static String formatMinute(int minute) =>
      '${(minute ~/ 60).toString().padLeft(2, '0')}:'
      '${(minute % 60).toString().padLeft(2, '0')}';
}

class HomeCandidateProvider {
  const HomeCandidateProvider();

  List<RecommendationCandidate> provide(RecommendationContext context) {
    final result = <RecommendationCandidate>[];
    for (final event in context.todayEvents) {
      if (event.id == context.runningEventId ||
          event.status == EventStatus.completed ||
          event.status == EventStatus.waiting) {
        continue;
      }
      result.add(RecommendationCandidate.event(event, result.length));
    }
    for (final routine in context.todayScheduledRoutines) {
      final execution = context.routineExecutions[routine.id];
      if (!routine.isScheduled || !routine.isActive) continue;
      if (routine.timeRecommendation != null) {
        try {
          if (TemporalRoutine.actionable(
                routine,
                context.currentJaxDay,
                context.currentLocalDateTime,
              ) ==
              null) {
            continue;
          }
        } on Object {
          continue;
        }
      } else if (!routine.appliesTo(context.currentJaxDay.displayDate)) {
        continue;
      }
      if (routine.id == context.runningRoutineId ||
          execution?.status == RoutineExecutionStatus.paused ||
          execution?.status == RoutineExecutionStatus.waiting ||
          execution?.status == RoutineExecutionStatus.running ||
          execution?.status == RoutineExecutionStatus.completed) {
        continue;
      }
      result.add(
        RecommendationCandidate.scheduledRoutine(
          routine,
          execution,
          result.length,
        ),
      );
    }
    return result;
  }
}

class Recommendation {
  const Recommendation({
    required this.candidate,
    required this.strength,
    required this.signals,
    this.reason,
  });

  final RecommendationCandidate candidate;
  final RecommendationStrength strength;
  final List<RecommendationSignal> signals;
  final String? reason;
}

class RecommendationEngine {
  const RecommendationEngine({required this.rules});
  final List<RecommendationRule> rules;

  List<Recommendation> recommend(
    RecommendationContext context,
    List<RecommendationCandidate> candidates,
  ) {
    final result = candidates.map((candidate) {
      final signals = rules
          .map((rule) => rule.evaluate(context, candidate))
          .nonNulls
          .toList(growable: false);
      final promoted = signals.where(
        (signal) => signal.strength == RecommendationStrength.promoted,
      );
      return Recommendation(
        candidate: candidate,
        strength: promoted.isEmpty
            ? RecommendationStrength.normal
            : RecommendationStrength.promoted,
        signals: signals,
        reason: promoted.firstOrNull?.reason,
      );
    }).toList();
    result.sort((a, b) {
      final tier = b.strength.index.compareTo(a.strength.index);
      return tier != 0
          ? tier
          : a.candidate.stableOrder.compareTo(b.candidate.stableOrder);
    });
    return result;
  }
}
