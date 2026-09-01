import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jax/core/entities/event_day_plan.dart';
import 'package:jax/core/entities/event_status.dart';
import 'package:jax/core/entities/jax_event.dart';
import 'package:jax/core/entities/plan.dart';
import 'package:jax/core/entities/plan_item.dart';
import 'package:jax/core/entities/world_node.dart';
import 'package:jax/core/errors/domain_failure.dart';
import 'package:jax/core/use_cases/complete_event.dart';
import 'package:jax/core/use_cases/dispatch_plan_items.dart';
import 'package:jax/core/use_cases/restore_event.dart';
import 'package:jax/data/database/app_database.dart';
import 'package:jax/data/repositories/sqlite_event_repository.dart';
import 'package:jax/data/repositories/sqlite_planning_repository.dart';
import 'package:jax/data/repositories/sqlite_world_node_repository.dart';

void main() {
  late Directory directory;
  late AppDatabase app;
  late SqlitePlanningRepository planning;
  late SqliteEventRepository events;
  late _Ids ids;
  var now = DateTime(2026, 9, 2, 10);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('jax-p3-dispatch-');
    app = await AppDatabase.open('${directory.path}/jax.db');
    planning = SqlitePlanningRepository(app);
    events = SqliteEventRepository(app);
    ids = _Ids();
    await SqliteWorldNodeRepository(app).insertWorldNode(
      WorldNode(
        id: '00000000-0000-4000-8000-000000000001',
        name: 'Jax',
        status: WorldNodeStatus.inProgress,
        sortOrder: 0,
        createdAt: now.toUtc(),
        updatedAt: now.toUtc(),
      ),
    );
  });

  tearDown(() async {
    await app.close();
    await directory.delete(recursive: true);
  });

  Future<Plan> plan({String id = 'plan'}) => planning.createPlan(
    id: id,
    worldNodeId: '00000000-0000-4000-8000-000000000001',
    now: now,
  );

  Future<PlanItem> item(Plan plan, String id, {bool next = true}) async {
    final created = await planning.createPlanItem(
      id: id,
      planId: plan.id,
      title: 'Title $id',
      now: now,
    );
    if (next) {
      await planning.setPlanItemStatus(id, PlanItemStatus.next, now);
    }
    return created;
  }

  DispatchPlanItems dispatcher() =>
      DispatchPlanItems(repository: planning, newId: ids.call, now: () => now);

  test(
    'single dispatch atomically creates pending Event and Today row',
    () async {
      final focused = await plan();
      await item(focused, 'item');

      final dispatched = await dispatcher()(['item']);

      expect(dispatched, hasLength(1));
      final event = dispatched.single;
      expect(event.name, 'Title item');
      expect(event.status, EventStatus.pending);
      expect(event.sourcePlanItemId, 'item');
      expect(event.categoryId, isNull);
      expect(
        (await planning.getPlanItems(focused.id)).single.status,
        PlanItemStatus.dispatched,
      );
      expect(
        (await events.getEventDayPlans('2026-09-02')).single.eventId,
        event.id,
      );
      expect(await events.getRunSegments(event.id), isEmpty);
    },
  );

  test('batch is all-or-nothing when one selected item is stale', () async {
    final focused = await plan();
    await item(focused, 'a');
    await item(focused, 'b');
    await item(focused, 'draft', next: false);

    await expectLater(
      dispatcher()(['a', 'b', 'draft']),
      throwsA(isA<DomainFailure>()),
    );

    expect(await events.getIncompleteEvents(), isEmpty);
    expect(await events.getEventDayPlans('2026-09-02'), isEmpty);
    expect(
      (await planning.getPlanItems(focused.id)).map((value) => value.status),
      [PlanItemStatus.next, PlanItemStatus.next, PlanItemStatus.draft],
    );
  });

  test('draft, waiting, ended, and duplicate dispatch are rejected', () async {
    final focused = await plan();
    await item(focused, 'draft', next: false);
    await expectLater(dispatcher()(['draft']), throwsA(isA<DomainFailure>()));

    await item(focused, 'next');
    await planning.setPlanStatus(focused.id, PlanStatus.waiting, now);
    await expectLater(dispatcher()(['next']), throwsA(isA<DomainFailure>()));
    await planning.setPlanStatus(focused.id, PlanStatus.focused, now);
    await dispatcher()(['next']);
    await expectLater(dispatcher()(['next']), throwsA(isA<DomainFailure>()));
    expect(await events.getIncompleteEvents(), hasLength(1));

    final secondDirectory = await Directory.systemTemp.createTemp(
      'jax-p3-ended-',
    );
    final second = await AppDatabase.open('${secondDirectory.path}/jax.db');
    addTearDown(() async {
      await second.close();
      await secondDirectory.delete(recursive: true);
    });
    final world = SqliteWorldNodeRepository(second);
    final repo = SqlitePlanningRepository(second);
    await world.insertWorldNode(
      WorldNode(
        id: '00000000-0000-4000-8000-000000000002',
        name: 'Ended',
        status: WorldNodeStatus.inProgress,
        sortOrder: 0,
        createdAt: now.toUtc(),
        updatedAt: now.toUtc(),
      ),
    );
    final ended = await repo.createPlan(
      id: 'ended',
      worldNodeId: '00000000-0000-4000-8000-000000000002',
      now: now,
    );
    await repo.createPlanItem(
      id: 'ended-item',
      planId: ended.id,
      title: 'x',
      now: now,
    );
    await repo.setPlanItemStatus('ended-item', PlanItemStatus.next, now);
    await repo.setPlanStatus(ended.id, PlanStatus.ended, now);
    await expectLater(
      DispatchPlanItems(repository: repo, newId: ids.call, now: () => now)([
        'ended-item',
      ]),
      throwsA(isA<DomainFailure>()),
    );
  });

  test(
    'dispatch appends after existing Today order in selected order',
    () async {
      final existing = JaxEvent(
        id: 'existing',
        name: 'Existing',
        status: EventStatus.pending,
        createdAt: now.toUtc(),
        updatedAt: now.toUtc(),
      );
      await events.insertEvent(existing);
      await events.addEventDayPlan(
        EventDayPlan(
          eventId: existing.id,
          dayKey: '2026-09-02',
          order: 0,
          createdAt: now.toUtc(),
        ),
      );
      final focused = await plan();
      await item(focused, 'c');
      await item(focused, 'd');

      final created = await dispatcher()(['c', 'd']);
      expect(
        (await events.getEventDayPlans('2026-09-02'))
            .map((value) => value.eventId),
        ['existing', created[0].id, created[1].id],
      );
    },
  );

  test('planned completion and restore update PlanItem atomically', () async {
    final focused = await plan();
    await item(focused, 'item');
    final event = (await dispatcher()(['item'])).single;
    await events.updateEvent(
      event.copyWith(status: EventStatus.waiting, updatedAt: now.toUtc()),
    );

    await CompleteEvent(repository: events, now: () => now)(event.id);
    expect(
      (await planning.getPlanItems(focused.id)).single.status,
      PlanItemStatus.done,
    );
    expect((await events.getEvent(event.id))!.status, EventStatus.completed);

    await RestoreEvent(repository: events, now: () => now)(event.id);
    expect(
      (await planning.getPlanItems(focused.id)).single.status,
      PlanItemStatus.dispatched,
    );
    expect((await events.getEvent(event.id))!.status, EventStatus.paused);
  });

  test(
    'completion and restore roll back on linked PlanItem mismatch',
    () async {
      final focused = await plan();
      await item(focused, 'item');
      final event = (await dispatcher()(['item'])).single;
      await events.updateEvent(
        event.copyWith(status: EventStatus.waiting, updatedAt: now.toUtc()),
      );
      await app.database.update(
        'plan_items',
        {'status': 'next'},
        where: 'id = ?',
        whereArgs: ['item'],
      );

      await expectLater(
        CompleteEvent(repository: events, now: () => now)(event.id),
        throwsStateError,
      );
      expect((await events.getEvent(event.id))!.status, EventStatus.waiting);

      await app.database.update(
        'plan_items',
        {'status': 'dispatched'},
        where: 'id = ?',
        whereArgs: ['item'],
      );
      await CompleteEvent(repository: events, now: () => now)(event.id);
      await app.database.update(
        'plan_items',
        {'status': 'dispatched'},
        where: 'id = ?',
        whereArgs: ['item'],
      );
      await expectLater(
        RestoreEvent(repository: events, now: () => now)(event.id),
        throwsStateError,
      );
      expect((await events.getEvent(event.id))!.status, EventStatus.completed);
    },
  );

  test(
    'dispatched Event name is decoupled from immutable PlanItem title',
    () async {
      final focused = await plan();
      await item(focused, 'item');
      final event = (await dispatcher()(['item'])).single;

      await events.updateEvent(
        event.copyWith(name: 'Renamed Event', updatedAt: now.toUtc()),
      );
      expect((await events.getEvent(event.id))!.name, 'Renamed Event');
      expect(
        (await planning.getPlanItems(focused.id)).single.title,
        'Title item',
      );
      await expectLater(
        planning.editPlanItem(
          'item',
          title: 'Forbidden',
          now: now.toUtc(),
        ),
        throwsA(isA<DomainFailure>()),
      );
    },
  );

  test(
    'Today remove does not withdraw dispatch and planned delete rejects',
    () async {
      final focused = await plan();
      await item(focused, 'item');
      final event = (await dispatcher()(['item'])).single;

      await events.removeEventDayPlan(event.id, '2026-09-02');
      expect(await events.getEvent(event.id), isNotNull);
      expect(
        (await planning.getPlanItems(focused.id)).single.status,
        PlanItemStatus.dispatched,
      );
      await events.addEventDayPlan(
        EventDayPlan(
          eventId: event.id,
          dayKey: '2026-09-02',
          order: 0,
          createdAt: now.toUtc(),
        ),
      );
      expect(await events.getEventDayPlans('2026-09-02'), hasLength(1));
      await expectLater(
        events.deleteEvent(event.id),
        throwsA(isA<DomainFailure>()),
      );
    },
  );

  test('waiting or ended Plan preserves already dispatched Event facts', () async {
    final focused = await plan();
    await item(focused, 'item');
    final event = (await dispatcher()(['item'])).single;

    await planning.setPlanStatus(focused.id, PlanStatus.waiting, now);
    expect(await events.getEvent(event.id), isNotNull);
    expect(await events.getEventDayPlans('2026-09-02'), hasLength(1));
    expect(
      (await planning.getPlanItems(focused.id)).single.status,
      PlanItemStatus.dispatched,
    );
    await planning.setPlanStatus(focused.id, PlanStatus.ended, now);
    expect(await events.getEvent(event.id), isNotNull);
    expect(await events.getEventDayPlans('2026-09-02'), hasLength(1));
    await expectLater(
      planning.deletePlan(focused.id),
      throwsA(isA<DomainFailure>()),
    );
  });

  test(
    'dispatch resolves JaxDay at submission across 23:00 boundary',
    () async {
      final focused = await plan();
      await item(focused, 'early');
      await item(focused, 'late');
      now = DateTime(2026, 9, 2, 22, 59);
      await dispatcher()(['early']);
      now = DateTime(2026, 9, 2, 23, 1);
      await dispatcher()(['late']);

      expect(await events.getEventDayPlans('2026-09-02'), hasLength(1));
      expect(await events.getEventDayPlans('2026-09-03'), hasLength(1));
    },
  );
}

class _Ids {
  var value = 0;
  String call() => 'event-${value++}';
}
