# Planning Phase P2: Planning Core

> **Historical design note / superseded:** P2 originally modeled Plan as
> `focused/waiting/ended`. The later **Planning Phase P3.5: WorldNode attention**
> superseded that attention model: focus now belongs to `WorldNode.isFocused`,
> while Plan status is only `current/ended`. This document preserves the P2
> implementation and migration history; use `PRD.md`, `Development_plan.md`, and
> `docs/planning_phase_p3_5.md` for the current model.

P2 adds the editable intention layer above `WorldNode`. It does not create or
modify execution facts. `WorldNode` is long-lived structure, `Plan` is one
round of approach for one node, and `PlanItem` is an editable step inside that
round.

## Storage and identity

Schema v15 adds `plans` and `plan_items`. Both use independent global UUID
identities at the product boundary; they never reuse Event identity.

`plans` stores `id`, `world_node_id`, nullable `title`, `status`, positive
per-node `round_number`, nullable `ended_at_utc`, and created/updated UTC epoch
milliseconds. `(world_node_id, round_number)` is unique. A partial unique index
over focused/waiting rows guarantees at most one current round per WorldNode.
An ended row must have `ended_at_utc`; a current row must not.

`plan_items` stores `id`, `plan_id`, non-empty `title`, nullable `note`,
`status`, `sort_order`, and created/updated UTC epoch milliseconds. Items are a
flat list. P2 deliberately has no parent item, Category, priority, duration,
deadline, calendar placement, or linked Event column.

The v14→v15 migration creates empty Planning tables transactionally and never
derives Planning data from legacy Events. Zero Plans after upgrade is the
expected state.

## State machines and invariants

A Plan is `focused`, `waiting`, or `ended`. Creation is focused; focused and
waiting may toggle without changing items. Either current state may end, which
sets `ended_at_utc`. Normal API/UI cannot reopen an ended round; the user makes
a new empty round whose number is `MAX(round_number)+1` within that WorldNode.
Different WorldNodes may each have a focused Plan.

A PlanItem is `draft`, `next`, `dispatched`, `done`, or `dropped`. P2 user
actions permit draft↔next, draft/next→dropped, and dropped→draft. `dispatched`
and `done` are storage/Sync-compatible P3 states but are not user-settable in
P2. Draft/next may be physically deleted as typo-level draft changes; dropped
is retained history and may be restored. Dispatched/done are neither freely
edited nor deleted.

Ending a Plan leaves every item exactly as it was, including unfinished next
or draft states. Eligibility for future recommendation begins with
`Plan.status == focused`, so historical next rows do not leak into P3.

Planning repository operations validate WorldNode existence/status and Plan
editability in transactions. The partial index enforces current-round
uniqueness below UI. `SqliteWorldNodeRepository` rejects completion while a
focused/waiting Plan exists; ending a Plan never completes the WorldNode.

## Ordering and UI

PlanItem order is one serialized list scoped by Plan. New rows append; UI shows
only valid up/down actions and never groups or reorders by status.

The new `规划` navigation destination opens a compact overview split into
`已关注` and `等待中`, with ended rounds behind a low-noise history expander.
Rows show WorldNode, Plan title/round, next count, and total item count. Adding
a Plan opens a hierarchy-preserving WorldNode selector ordered by effective
Category and sibling order. Completed nodes and nodes already owning a current
Plan are disabled with an explanation.

Plan detail shows WorldNode context, title, status, and the ordered item list.
The leading item action toggles draft/next directly. Edit, dropped, delete, and
restore remain in More; focus/wait is a light header action; ending a round is
in More and always confirms. Input content scrolls under narrow-screen keyboard
constraints.

## Sync protocol 3

Plan and PlanItem are normal business Sync entities with tombstones.
`planItems:<plan UUID>` is the canonical full logical list, so order conflicts
are list conflicts rather than updated-time LWW. Plan fields, item fields and
statuses use the existing three-way manual conflict behavior. Protocol 1
baselines still receive deterministic WorldNode normalization, then protocol 2
baselines are explicitly normalized to protocol 3 with no invented Planning
records.

Snapshot validation/readiness checks owners, statuses, ended timestamp
consistency, round uniqueness, one current Plan per WorldNode, completed-node
exclusion, item title/order/list scope, dangling relations, and foreign keys.
P2-only databases report dispatched/done rows as a non-blocking diagnostic so
the model remains forward-compatible with P3. Mutation apply respects FK
ordering, transactions, rollback, tombstones, stale fingerprints, backup and
final snapshot verification.

## Rollout boundary

P2 does not dispatch PlanItems, create Events, add anything to Today/Home,
write RunSegments, affect Record, copy unfinished legacy Events, implement
Review/Replan, or switch the legacy World UI. P3 will collect next items from
focused Plans, let the user accept a recommendation, create an Event, and drive
dispatched/done from that execution relationship.
