# Sync Phase 2B-1: Safe Apply Infrastructure

## Boundary

Phase 2B-1 implements the safety pipeline needed before a real dual-device
Apply, but deliberately exposes only `applyFixtureOnly`. `FixtureSyncDatabase`
rejects every target outside the operating-system temporary directory. No UI
button, ADB write-back, production baseline store, LAN transport, tombstone GC,
or real-device Apply exists in this phase.

The supported pipeline is:

`ResolvedSyncPlan -> freshness check -> dry-run/simulation -> MutationPlan ->`
`backup both -> per-DB transactions -> validation -> final verification ->`
`test baseline`

## Resolved plans, freshness, and dry-run

Phase 2A `SyncPlan` remains non-executable. A `ResolvedSyncPlan` contains the
preview plus explicit Windows/Android choices for every manual record and list
conflict, and explicit record overrides for every invariant conflict. A missing
choice returns `PLAN_NOT_RESOLVED`; no default side, timestamp winner, or LWW is
used. In particular, resolving two running owners requires the caller to state
the complete legal losing state, rather than the engine inventing an auto-pause
policy.

Every preview records `syncProtocolVersion`, Windows and Android source SHA-256
fingerprints, and an optional baseline fingerprint. The hash is calculated from
the canonical synchronized business representation: sorted entity identities
and payloads (with logical order represented only by SyncLists), tombstone
facts, and complete ordered global-ID lists. Export time, warnings, SQLite file
size/mtime/WAL layout, local UI preferences, and raw integer order fields are
excluded. Apply re-exports both sources and checks the exact planned baseline;
any change returns `STALE_SYNC_PLAN` and requires a new analysis.

`SyncPlanCompiler.compile` is the dry-run API. It deterministically merges the
selected facts in memory, merges compatible independent list additions,
normalizes explicitly selected list scopes, and runs `SyncSnapshotValidator`.
It rejects cycles, missing owners/relations, invalid status/type/recurrence,
child direct categories, completed parents with unfinished children, incomplete
or wrong-scope lists, invalid/overlapping segments, status/open-segment
mismatches, multiple on-demand unfinished executions, and global multiple
running/open states with `PLAN_INVALID`. It performs no database writes.

## Mutation plan and ordering

The compiler emits a deterministic `SyncMutationPlan` containing per-side
operations, source/baseline fingerprints, and the exact expected final
snapshot. Stable identity keys and sorted operation keys are used; current
time, rowid, random UUID, Map iteration, and UI order do not affect operations.

`SqliteSyncMutationExecutor` is a Data-layer transaction adapter because normal
repositories cannot share one transaction across this import. Its dependency
order is explicit:

1. delete Today plans;
2. delete segments;
3. delete executions;
4. delete routines/events;
5. delete categories;
6. upsert categories;
7. upsert Events, then Routines;
8. upsert executions;
9. upsert segments;
10. upsert Today plans;
11. apply complete list scopes.

Foreign keys are deferred only inside that transaction and checked before
commit. Existing-row field upserts never overwrite `sort_order/order_index`:
logical order belongs exclusively to SyncList. A list mutation temporarily
moves all selected rows outside the normal range, writes `0..n-1`, and verifies
the complete scope before commit. Other scopes are not normalized. The
committed WAL is checkpointed before a standalone backup/read boundary.

Deleting an entity also stores its Phase 1 tombstone; no acknowledgement or GC
is performed. Upserting the same live identity uses the existing insert trigger
to clear its tombstone, which is covered by the restore test.

## Backup, transaction, and rollback contract

Both backups must complete before either mutation starts. The SQLite backup
service uses `VACUUM INTO`, not a raw main-file copy, then opens and exports the
backup to prove it is readable. A second-backup failure returns `BACKUP_FAILED`
without mutation.

Windows and Android cannot share a distributed SQLite transaction. The
orchestrator therefore applies one complete transaction per copy, validates its
readiness/invariants and expected fingerprint, then applies and validates the
other copy. It finally re-exports both and requires each canonical business
fingerprint to equal `MutationPlan.expectedFinalSnapshot`.

Any mutation, commit-boundary, validation, or final-verification failure
restores **both** backups and checks both pre-Apply fingerprints. Success is
reported as `APPLY_FAILED_ROLLED_BACK`; an unreadable or mismatching restore is
surfaced as `CRITICAL_ROLLBACK_FAILURE` and is never hidden. `SyncApplySession`
records prepared, backed-up, per-side applied/validated, final-verified,
baseline, committed, rollback, and failed stages.

## Baseline timing

`SyncBaselineStore` is an interface with an in-memory test implementation only.
It is called after both applies, both validations, and final cross-device
verification. A baseline write failure does not roll back already verified
business data; the result is `appliedBaselineWriteFailed`, requiring baseline
re-establishment at the next analysis. Phase 2B-1 never writes a real baseline.

## Verification

Tests cover unresolved/stale/invalid plans, deterministic dry-run, hierarchy,
field/list/segment/running choices, independent additions, tombstone delete and
same-ID restore, single-transaction rollback, both-side restoration, backup and
restore failures, post-validation/final-state failures, and baseline timing.
The Phase 2A captured Windows/Android database shape was copied into a new
system temporary directory and successfully exercised end-to-end; the captured
files and real databases were not Apply targets.

Phase 2B-2 must still design the production transport/write authorization,
durable conflict-choice UX, real backup locations and recovery UX, a production
baseline store, device identity/session ownership, and an explicit operator
confirmation flow before removing the fixture-only gate.
