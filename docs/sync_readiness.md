# Sync Readiness (Phase 1)

## Decision

Jax uses persisted UUID v4 strings as every standalone business entity's
SQLite `TEXT PRIMARY KEY`. These IDs are already global identities; adding a
second `sync_id` would duplicate identity and create mapping risk. Local and
sync identity are therefore the same immutable UUID. Existing Windows and
Android databases came from the same snapshot, so their historical UUIDs are
already equal.

Phase 1 uses snapshot comparison. It adds no device ID, revision counter,
change log, transport, merge policy, or sync UI.

## Schema audit (v13)

All instants are UTC Unix epoch milliseconds (`INTEGER`). JaxDay keys are
local calendar strings (`YYYY-MM-DD`) calculated by Core with the 23:00 local
boundary; they are values, not instants.

| Table / sync entity | Identity and relations | Mutable business fields | Metadata |
| --- | --- | --- | --- |
| `categories` / EventCategory | UUID `id` | name, sort_order, color_key | created/updated |
| `events` / Event | UUID `id`; parent/category UUID FKs | name, status, parent, category, sibling order, first-started/completed | created/updated |
| `run_segments` / EventRunSegment | UUID `id`; event UUID FK | started/ended (null means open) | created/updated |
| `routine_categories` | UUID `id` | name, sort_order, color_key | created/updated |
| `routines` | UUID `id`; RoutineCategory UUID FK | name, scheduled/onDemand type, recurrence, weekday mask, active, order | created/updated |
| `routine_executions` | UUID `id`; Routine UUID FK | JaxDay occurrence key, status, completed | created/updated |
| `routine_run_segments` | UUID `id`; execution UUID FK | started/ended (null means open) | created/updated |
| `event_day_plans` / EventDayPlan | deterministic `eventUUID@JaxDay`; event UUID FK | JaxDay and per-day order | created/updated |
| `sync_tombstones` | `(entity_type, entity_id)` | deleted_at_utc | deletion metadata |

`sync_tombstones` records physical deletion without changing existing UI or
repository semantics. SQLite triggers cover explicit and cascading deletes.
Re-inserting the same identity removes its tombstone. Tombstone retention and
garbage collection require peer acknowledgement and are deferred to Phase 2.

SQLite update triggers are a safety net: if any mutation path changes a row
without advancing `updated_at_utc`, the database advances it. Segment and Today
plan metadata added by v12→v13 is initialized from `created_at_utc`, preserving
deterministic historical facts.

## Device-independent sync contract

`SyncRecord` contains `kind`, immutable global `id`, UTC created/updated/deleted
metadata, and a complete payload. Relations must be serialized as global IDs:

- Event: `parentSyncId`, `categorySyncId`.
- EventRunSegment: `eventSyncId`.
- Routine: `routineCategorySyncId`.
- RoutineExecution: `routineSyncId` (never inferred from routine + day).
- RoutineRunSegment: `routineExecutionSyncId`.
- EventDayPlan: `eventSyncId`, JaxDay key, and order.

The adapter may use local SQL column names internally, but the Sync Model must
never expose a row number or assume equal local database positions.

## Ordering

Current integer ordering is adequate for a preview-first Phase 2. A sibling
collection (Event siblings, categories, routines in a category, or one day's
plans) is the conflict unit. Apply must normalize it to unique contiguous
integers. Concurrent reorder is reported as a list conflict; Phase 1 does not
introduce fractional order or a CRDT.

## Validation before/after apply

`SqliteSyncReadiness.validate()` is read-only and reports broken foreign keys,
missing identities, Event cycles, child direct categories, duplicate scoped
orders, multiple running/open segments, running/open-segment disagreement,
invalid/overlapping segment ranges, and multiple unfinished On-demand
executions. Duplicate/gapped integer orders are non-blocking warnings because
all reads have a deterministic secondary order and Phase 2 treats the complete
sibling list as the conflict unit.

Phase 2 must additionally apply through Core rules and validate:

- Event has at most one parent, no cycle, only roots have direct Category,
  completed ancestors/unfinished descendants remain legal, and sibling order
  is normalized.
- Routine enums/recurrence are valid; On-demand has at most one unfinished
  execution.
- Every execution/segment/plan owner exists; closed ranges have start < end;
  global segment overlap rules hold.
- Event + RoutineExecution has at most one running entity and exactly one
  matching open segment; non-running entities have no open segment.
- Today relations point to Events, have unique order per JaxDay, and preserve
  current running/Today rules.

Conflict resolution (including two locally valid running entities) must happen
before commit. The validator identifies invalid candidates; it does not pick a
winner or silently repair data.

## Sync scope

Synced business data: Event/EventCategory, hierarchy, status, category/color,
all business orders, Today plans, Routine/RoutineCategory including type,
recurrence and active state, RoutineExecution, and both segment types.

Device-local data: window geometry, navigation/hover/temporary selections,
World and Routine Category collapse preferences, debug settings, logs, backups,
and save-status presentation. Summary charts are derived from synced segments
and are not synced as records.

## Deliberately deferred

- ADB/LAN/cloud transport and device authorization/discovery.
- Snapshot adapter implementation, compare engine, safe apply, and backup UI.
- Entity-vs-field conflict policy, last-write-wins policy, and manual conflict UI.
- Running conflict winner, order conflict winner, and tombstone garbage collection.
- Optional device ID for diagnostics/conflict explanations.
- Any operation log, server, account, CRDT, or event sourcing.

Phase 2 must first implement a complete adapter and prove that no business field
is omitted, then add read/compare/conflict preview before any apply path.
