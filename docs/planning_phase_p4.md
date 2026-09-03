# Planning Phase P4: Review and WorldNode Detail

P4 adds reflection without turning Planning into a mandatory workflow, and adds a
read-only second layer to World without making World an execution surface.

## Data and lifecycle

SQLite schema v17 adds `plan_review_notes(id, plan_id, content,
created_at_utc, updated_at_utc)`. Migration from v16 creates an empty table and
sync triggers only. A note may be created, edited, or deleted while its Plan is
focused, waiting, or ended. Editing preserves `created_at_utc`; blank content is
rejected. Notes never enter Record or change Plan, PlanItem, Event, or WorldNode.

An unexecuted Plan remains physically deletable even if it has review notes.
Deletion writes note and item tombstones before the Plan tombstone. A Plan with
dispatched/done items or a linked Event remains non-deletable and retains notes
when ended.

## Sync contract

Sync protocol 5 adds `planReviewNote` with `planSyncId` and `content`. Notes are
part of snapshots, business fingerprints, three-way comparison, mutation plans,
apply, tombstones, and readiness. Concurrent content edits are field conflicts,
not last-writer-wins. Protocol 4 baselines normalize to protocol 5 without
inventing notes. Dataset generation is unchanged.

Readiness rejects missing/invalid identities, blank content, invalid timestamp
order, dangling Plan references, and normal FK failures. Apply upserts Plan before
its notes and deletes notes before Plan.

## UI contract

Plan Detail shows a lightweight review section newest first, with timestamps and
edit/delete actions. The multiline dialog scrolls on narrow Android layouts.
Review remains optional and ending a Plan never prompts for one.

Clicking a WorldNode opens a read-only detail with overview, current Plan summary,
ended Plan history, and execution history. Waiting counts as current. Historical
Plans use deterministic round/created order and open the canonical Plan Detail.
Execution history is derived only through
`Event.sourcePlanItem → PlanItem → Plan → exact WorldNode`; standalone Events,
other nodes, and descendants are excluded. Direct RunSegment duration is shown,
but no execution controls are added.

## Explicit exclusions

P4 does not add PDCA stages, AI summaries, replanning, reminders, daily-review
workflows, descendant duration aggregation, withdraw, or a second Plan editor.
