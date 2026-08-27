import 'package:flutter/material.dart';

import '../../core/entities/event_status.dart';
import '../../core/entities/jax_event.dart';
import '../../core/entities/routine.dart';
import '../controllers/event_controller.dart';
import '../widgets/execution_action_buttons.dart';

class EventsPage extends StatelessWidget {
  const EventsPage({required this.controller, super.key});
  final EventController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      if (controller.loading) {
        return const Center(child: CircularProgressIndicator());
      }
      final events = controller.todayEvents;
      final routines = controller.todayRoutines;
      final day = controller.currentJaxDay;
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          Text('今日', style: Theme.of(context).textTheme.headlineMedium),
          Text('${day.displayDate.month}月${day.displayDate.day}日 · 23:00 结束'),
          if (controller.runningEvent != null ||
              controller.runningRoutine != null) ...[
            const SizedBox(height: 24),
            Text('当前正在执行', style: Theme.of(context).textTheme.titleMedium),
            Text(
              controller.runningEvent?.name ?? controller.runningRoutine!.name,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ],
          const SizedBox(height: 24),
          Text('今日事项', style: Theme.of(context).textTheme.titleLarge),
          if (events.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('今天还没有安排 Event，请到世界加入。'),
            ),
          for (var i = 0; i < events.length; i++)
            _EventRow(
              controller: controller,
              event: events[i],
              index: i,
              count: events.length,
            ),
          const SizedBox(height: 24),
          Text('今日日常', style: Theme.of(context).textTheme.titleLarge),
          if (routines.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('今天没有 recurrence 命中的日常。'),
            ),
          for (final routine in routines)
            _RoutineRow(controller: controller, routine: routine),
          if (events.isEmpty && routines.isEmpty) ...[
            const SizedBox(height: 24),
            const Center(child: Text('今天还没有安排事项')),
          ],
        ],
      );
    },
  );
}

class _EventRow extends StatelessWidget {
  const _EventRow({
    required this.controller,
    required this.event,
    required this.index,
    required this.count,
  });
  final EventController controller;
  final JaxEvent event;
  final int index;
  final int count;

  @override
  Widget build(BuildContext context) {
    final breadcrumb = controller.eventBreadcrumb(event);
    return Card(
      key: ValueKey('today-event-${event.id}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) => Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: constraints.maxWidth > 620
                    ? constraints.maxWidth - 390
                    : constraints.maxWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (breadcrumb.isNotEmpty)
                      Text(
                        breadcrumb,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    Text(_status(event)),
                  ],
                ),
              ),
              if (index > 0)
                IconButton(
                  key: ValueKey('today-up-${event.id}'),
                  tooltip: '今日上移',
                  onPressed: () => controller.moveToday(event.id, index - 1),
                  icon: const Icon(Icons.arrow_upward),
                ),
              if (index < count - 1)
                IconButton(
                  key: ValueKey('today-down-${event.id}'),
                  tooltip: '今日下移',
                  onPressed: () => controller.moveToday(event.id, index + 1),
                  icon: const Icon(Icons.arrow_downward),
                ),
              ..._actions(context),
              if (event.status != EventStatus.running &&
                  event.status != EventStatus.completed)
                IconButton(
                  key: ValueKey('today-remove-${event.id}'),
                  tooltip: '移出今日',
                  onPressed: () => controller.removeFromToday(event.id),
                  icon: const Icon(Icons.today_outlined),
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _actions(BuildContext context) => switch (event.status) {
    EventStatus.pending => [
      _button(
        context,
        'start',
        ExecutionAction.start,
        () => controller.start(event.id),
      ),
    ],
    EventStatus.paused => [
      _button(
        context,
        'resume',
        ExecutionAction.resume,
        () => controller.resume(event.id),
      ),
    ],
    EventStatus.running => [
      _button(
        context,
        'pause',
        ExecutionAction.pause,
        () => controller.pause(event.id),
      ),
      _button(
        context,
        'complete',
        ExecutionAction.complete,
        () => controller.complete(event.id),
      ),
    ],
    EventStatus.waiting => [
      _button(
        context,
        'resume',
        ExecutionAction.resume,
        () => controller.resume(event.id),
      ),
      _button(
        context,
        'complete',
        ExecutionAction.complete,
        () => controller.complete(event.id),
      ),
    ],
    EventStatus.completed => const [],
  };

  Widget _button(
    BuildContext context,
    String keyName,
    ExecutionAction executionAction,
    Future<String?> Function() action,
  ) => ExecutionActionButton(
    key: ValueKey('$keyName-${event.id}'),
    action: executionAction,
    onPressed: () async {
      final error = await action();
      if (error != null && context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error)));
      }
    },
  );

  String _status(JaxEvent event) => switch (event.status) {
    EventStatus.pending => '未开始',
    EventStatus.running => '正在执行',
    EventStatus.paused => '已暂停',
    EventStatus.waiting => '等待中',
    EventStatus.completed => '已完成',
  };
}

class _RoutineRow extends StatelessWidget {
  const _RoutineRow({required this.controller, required this.routine});
  final EventController controller;
  final Routine routine;

  @override
  Widget build(BuildContext context) {
    final execution = controller.executionFor(routine);
    final category = controller.categories
        .where((c) => c.id == routine.categoryId)
        .firstOrNull;
    return Card(
      key: ValueKey('today-routine-${routine.id}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) => Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: constraints.maxWidth > 500
                    ? constraints.maxWidth - 220
                    : constraints.maxWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(routine.name),
                    Text(category?.name ?? '未分类'),
                    Text(_status(execution)),
                  ],
                ),
              ),
              ExecutionActionRow(
                children: switch (execution?.status) {
                  null => [
                    _button(
                      'start',
                      ExecutionAction.start,
                      () => controller.startRoutine(routine),
                    ),
                  ],
                  RoutineExecutionStatus.running => [
                    _button(
                      'pause',
                      ExecutionAction.pause,
                      () => controller.pauseRoutine(routine),
                    ),
                    _button(
                      'complete',
                      ExecutionAction.complete,
                      () => controller.completeRoutine(routine),
                    ),
                  ],
                  RoutineExecutionStatus.paused => [
                    _button(
                      'resume',
                      ExecutionAction.resume,
                      () => controller.startRoutine(routine),
                    ),
                    _button(
                      'complete',
                      ExecutionAction.complete,
                      () => controller.completeRoutine(routine),
                    ),
                  ],
                  RoutineExecutionStatus.completed => const [],
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _button(
    String keyName,
    ExecutionAction executionAction,
    VoidCallback callback,
  ) => ExecutionActionButton(
    key: ValueKey('today-routine-$keyName-${routine.id}'),
    action: executionAction,
    onPressed: callback,
  );

  String _status(RoutineExecution? execution) => switch (execution?.status) {
    null => '未开始',
    RoutineExecutionStatus.running => '正在执行',
    RoutineExecutionStatus.paused => '已暂停',
    RoutineExecutionStatus.completed => '已完成',
  };
}
