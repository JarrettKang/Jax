# Sync Phase 2A: Read / Compare / Conflict Preview

## Boundary

Phase 2A is a read-only analysis pipeline:

`acquire -> SQLite adapter -> snapshot -> readiness -> compare -> plan -> preview`

It has no Apply API or repository mutation dependency. It does not update rows,
tombstones, baselines, order values, or conflict choices. The ADB PowerShell
tool only acquires a stopped Debug app's database/WAL files and restarts the app
if it was running. The adapter and compare engine contain no ADB code.

## Snapshot protocol 1

`syncProtocolVersion = 1` is independent from SQLite schema v13. A future
schema may continue to emit protocol 1 if an adapter can map every business
fact without loss. Unknown protocol versions stop comparison.

`SyncSnapshot` contains schema/protocol versions, export UTC time, readiness
warnings, sorted records, and sorted logical lists. Records cover EventCategory,
Event, EventDayPlan, EventRunSegment, RoutineCategory, Routine,
RoutineExecution, RoutineRunSegment, and deletion tombstones. Relations use
global IDs and times use UTC epoch milliseconds. UI collapse preferences and
derived summaries are excluded.

Serialization is deterministic: record/list keys and payload keys are sorted.
`businessFingerprint` excludes acquisition time and local warnings so it can
prove Analyze did not change synchronized facts.

## SQLite adapter and acquisition

`SqliteSyncSnapshotAdapter` accepts an already-open database and only issues
queries. It refuses unsupported schema or blocking readiness errors and carries
nonblocking warnings into the snapshot. It resolves integer orders into the
actual stable display sequence using `sort/order + createdAt + id`.

`tool/sync_phase2a.ps1` requires an explicit serial when multiple devices are
connected, checks package/run-as access, makes transaction-consistent safe
copies, exports snapshots, builds a plan, then repeats acquisition and compares
business fingerprints. Deliberate conflicts must use fixtures, never real DBs.

## Comparison and baseline

Identity is `entity kind + global ID`. Direct comparison reports Same,
OnlyWindows, OnlyAndroid, Different, DeletedWindows, DeletedAndroid, and
DeletedBoth. Missing and tombstoned are distinct. Different is refined into
auto-mergeable, manual, list, and invariant outcomes; `updatedAt` never selects
a winner.

With no baseline, independent identities are propagation candidates, while a
shared divergent identity is `unknownHistory` manual conflict. Delete versus
existing is explicit and cannot silently delete or resurrect.

The future Last Successful Sync Baseline is a protocol snapshot stored outside
business databases. Three-way comparison follows:

- one side differs from Base: compatible change;
- both equal Base: unchanged;
- both reach the same result: compatible final result;
- both differ from Base and each other: conflict.

Analyze never creates or updates a baseline. Phase 2B may update it only after
both applies and post-apply validation succeed.

## Conflicts and plans

`SyncPlan` is non-executable pure data. Entity items include both records,
optional Base, field diffs, human labels, comparison class, conflict type, and
an in-memory proposed side. Conflict types include entity, field, hierarchy,
delete/modify, list, global-one-running, multiple-open-segment, and segment
overlap.

Orders are compared as complete logical lists of global IDs. Independent list
membership additions are entity changes; a changed relative order of shared
members is a ListConflict. This avoids treating duplicate integer order values
as writes and preserves Android's current stable tie-break without repair.

The engine simulates cross-device global-running, open-segment, and segment
overlap invariants. It never auto-pauses or edits history.

`SyncPreviewPage` displays summary metrics, warnings, automatic candidates,
field differences, complete order alternatives, and invariant explanations.
Computer/phone/unresolved choices live only in widget memory. A generated plan
can be shown in Windows Debug by setting `JAX_SYNC_PLAN` to its JSON path before
launching Jax.

## Deferred to Phase 2B

- Safe transactional Apply to both devices and backup/rollback.
- Core-backed candidate validation and post-apply verification.
- Durable conflict choices and successful-sync baseline update.
- Tombstone acknowledgement, retention, and garbage collection.
- Final conflict policy and production navigation.

LAN discovery/authorization remains Phase 3 and will reuse protocol 1,
snapshots, comparison, and plans.
