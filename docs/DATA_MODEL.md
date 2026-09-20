# Current data model

**SQLite schema 24 · Sync protocol 11.** This is the current conceptual model,
not a migration listing. Implementation: `lib/data/database/app_database.dart`,
repository adapters and the core entities. Old schema-21/protocol-8 notes are superseded.

## Relationships

```text
Category → WorldNode (parent/child hierarchy)
WorldNode → Plan (rounds) → PlanItem → Event → RunSegment
Plan → PlanReviewNote
Standalone Event → EventDayPlan
RoutineCategory → Routine → RoutineExecution → RoutineRunSegment
```

The review note belongs directly to a Plan, not to a PlanItem. Day assignments
also apply to planned Events. Hierarchy, intentions, steps and executions are
separate records; Events themselves have no parent-event tree.

| Entity | Current role / invariants |
|---|---|
| Category | Named ordered group and color key; used by World roots and standalone events |
| WorldNode | Parent reference, order, category, inProgress/completed lifecycle and independent focus flag |
| Plan | Round number per WorldNode; at most one current round; ended rounds retain end time |
| PlanItem | Ordered title/note; draft, next, dispatched, done or dropped; promotion reference described below |
| PlanReviewNote | Explicit review text associated with a plan and creation/update times |
| Event | Flat pending/running/paused/waiting/completed execution; optional unique source PlanItem |
| EventDayPlan | Event/day assignment and order, separate from execution status |
| RunSegment | Event active interval, start and optional end; elapsed active time comes from segments |
| Routine | Scheduled or onDemand definition, recurrence, active flag and optional temporal recommendation |
| RoutineExecution | Occurrence date and running/paused/waiting/completed domain status |
| RoutineRunSegment | Active interval of one routine occurrence |

A planned Event has a unique `source_plan_item_id` and no direct category. Its
category is resolved through the source plan's WorldNode. A standalone Event may
have a category directly. Dispatch preserves one execution per PlanItem.

## Schema 22–24 additions

**Promotion (22):** a PlanItem may reference its promoted WorldNode. The reference
is unique and only valid for stored draft/next rows. Repository/domain adapters
expose the promoted state; no fictitious `promoted` value is added to the old SQL
status CHECK constraint. Promoted steps do not remain ordinary executable next steps.

**Temporal lifecycle (23):** scheduled routines can define start, preferred end
and latest end minutes, including windows crossing midnight. Enabled windows must
be valid and ordered; disabled recommendations cannot retain a latest-end value.
The temporal rule layer determines recommended, late and expired behavior.

**Routine waiting (24):** storage preserves the older routine-execution status
constraint: a paused row plus `is_waiting=1` encodes waiting. Domain and Sync expose
one waiting status. It does not accumulate active time while waiting.

## Time, Today and Record

Persistent timestamps use UTC; local display and the Jax-day boundary are handled
by the domain. Day assignments are independent of completion. Carry-over
initializations prevent repeating a device-local day transition. Record uses
actual segments, including corrections, rather than inferring work from an
intention's lifetime or time spent paused/waiting.

## Sync and local metadata

`dataset_metadata` identifies a dataset generation. Sync tombstones record deleted
entities; update metadata/triggers support snapshot comparison and confirmed apply.
Protocol 11 carries current business semantics, including promotion and temporal
routine waiting. Generation-aware baselines distinguish a reset from ordinary edits.

Device-local carry-over initialization, assistant preferences and collapse state
are not interchangeable with business Sync entities. Developer backup ownership
markers and rollback metadata belong to tooling, not the planning model.

Migrations and repository operations enforce constraints with SQLite foreign keys
and transactions. Migration tests remain required for future schema changes. This
phase changes documentation/demo tools only; schema and Sync protocol stay frozen.
