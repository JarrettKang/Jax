# Planning Phase P2.5: Flat execution and clean generation

P2.5 completes the product boundary established by P1/P2 without implementing
P3 dispatch.

## Delivered model

- Schema v16 removes Event parent/order columns and adds nullable unique
  `source_plan_item_id` with an FK to PlanItem.
- Event source is derived: a source relation means planned; null means
  standalone. Planned Category is dynamic through WorldNode; standalone
  Category is nullable and direct.
- Event lifecycle, Today order, one-running switching, RunSegment and Record
  remain intact. Event hierarchical completion and descendant behavior are
  removed from Core, Repository, SQLite, UI, Sync and tests.
- World is now a WorldNode management tree. WorldNode More offers create Plan,
  open current Plan, create next round and historical Plan navigation according
  to node/plan state.
- Planning selection is grouped by ordered World Category (plus virtual
  unclassified), with session-local category and branch collapse. Completed
  nodes and nodes with a current Plan remain visible but disabled with reasons.
- A never-executed Plan can be deleted with its unexecuted items and Sync
  tombstones. Linked/dispatched/done history makes physical deletion illegal.
- Today provides a low-friction `+ 临时事项` flow: name, optional Category,
  pending standalone Event, and current-JaxDay placement.

## Reset and Sync strategy

Protocol 4 snapshots carry `datasetGeneration`. Schema v16 stores it in
`dataset_metadata`. Compare rejects different generations and stale compiled
plans retain fingerprint protection. Current protocol export/apply contains no
Event hierarchy lists or legacy link entities; protocol 1–3 baseline parsing is
kept only as an explicit one-way compatibility adapter.

The explicit development reset clears World/Planning/Event/Today/Record facts,
Routine definitions/history, Sync tombstones and entity-bound collapse state.
It preserves device-local external storage and appearance settings. Windows and
Android must be backed up, reset independently with the same generation,
validated as equivalent, then receive a new protocol 4 Last Successful Sync
Baseline. Reset is never propagated as a normal Sync delete wave.

## P3 contract (not implemented here)

P3 may add one atomic operation that validates `PlanItem(next)`, creates an
Event linked by `sourcePlanItemId`, marks the item dispatched, and inserts the
current EventDayPlan. P2.5 does not recommend, dispatch, mark done, restore an
item, review, replan, or run AI planning.
