# Planning Phase P4: Review and WorldNode Detail

**Status: implemented.** This document describes current Review and WorldNode
Detail behavior after the P3.5 WorldNode attention refactor.

P4 adds reflection without turning Planning into a mandatory workflow, and adds a
read-only second layer to World without making World an execution surface.

## Data and lifecycle

SQLite schema v17 adds `plan_review_notes(id, plan_id, content,
created_at_utc, updated_at_utc)`. Migration from v16 creates an empty table and
sync triggers only. After P3.5, a note may be created, edited, or deleted while
its Plan is current or ended. Editing preserves `created_at_utc`; blank content is
rejected. Notes never enter Record or change Plan, PlanItem, Event, or WorldNode.

An unexecuted Plan remains physically deletable even if it has review notes.
Deletion writes note and item tombstones before the Plan tombstone. A Plan with
dispatched/done items or a linked Event remains non-deletable and retains notes
when ended.

## Sync contract

Sync protocol 5 added `planReviewNote` with `planSyncId` and `content`; P3.5
protocol 6 preserves it while moving attention to WorldNode. Notes are
part of snapshots, business fingerprints, three-way comparison, mutation plans,
apply, tombstones, and readiness. Concurrent content edits are field conflicts,
not last-writer-wins. Protocol 4 baselines normalize without inventing notes;
protocol 5 baselines then normalize Plan attention without changing generation.

Readiness rejects missing/invalid identities, blank content, invalid timestamp
order, dangling Plan references, and normal FK failures. Apply upserts Plan before
its notes and deletes notes before Plan.

## UI contract

Plan Detail shows a lightweight review section newest first, with timestamps and
edit/delete actions. The multiline dialog scrolls on narrow Android layouts.
Review remains optional and ending a Plan never prompts for one.

Clicking a WorldNode opens a read-only detail with overview, current Plan summary,
ended Plan history, and execution history. A current Plan has `status == current`
and `endedAt == null`; an ended Plan has `status == ended` and a non-null
`endedAt`. Historical Plans use deterministic round/created order and open the
canonical Plan Detail.
Execution history is derived only through
`Event.sourcePlanItem → PlanItem → Plan → exact WorldNode`; standalone Events,
other nodes, and descendants are excluded. WorldNode attention is independent
from Plan status and does not hide detail or history. Direct RunSegment duration is shown,
but no execution controls are added.

## Explicit exclusions

P4 does not add PDCA stages, AI summaries, replanning, reminders, daily-review
workflows, descendant duration aggregation, withdraw, or a second Plan editor.
