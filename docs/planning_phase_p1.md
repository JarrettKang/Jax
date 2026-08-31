# Planning Phase P1: WorldNode shadow foundation

## Scope and invariants

P1 introduces a non-executable `WorldNode` while deliberately keeping the
current Event-based World UI and execution workflow. A WorldNode can be
`inProgress` or `completed`; it cannot run, wait, pause, enter Today, own a
RunSegment, or contribute directly to daily/weekly Record calculations.

No Plan or PlanItem is created in this phase. Legacy Events remain normal sync
entities and retain their IDs, statuses, hierarchy fields, EventDayPlans,
RunSegments, timestamps, completion history, and all current UI entry points.

## SQLite v14

`world_nodes` stores:

- `id`: stable global UUID primary key;
- `name`;
- `status`: `inProgress` or `completed`;
- nullable `parent_world_node_id` with a self FK;
- non-null `sort_order`;
- nullable root `category_id` reusing the existing World Category table;
- `created_at_utc` and `updated_at_utc`.

`legacy_event_world_node_links` stores an independent one-to-one mapping with
`id == legacy_event_id`, unique FKs for `legacy_event_id` and `world_node_id`,
and sync timestamps. It keeps migration provenance out of the normal
WorldNode business fields.

Both tables participate in the existing tombstone triggers. Deleting or
syncing a WorldNode never rewrites a RunSegment owner to a WorldNode.

## Deterministic shadow migration

The migration validates the complete legacy Event hierarchy for missing
parents and cycles before inserting rows. For each Event, it derives:

```text
UUIDv5(
  namespace = d2f1148c-42f1-4a40-8cb8-9c4f4ad86238,
  name = "jax:legacy-event:<legacyEventId>"
)
```

The fixed namespace is a persistent cross-device contract. The same legacy ID
therefore produces the same WorldNode ID on Windows, Android, migration reruns,
and old-baseline normalization.

The hierarchy is inserted parent-first. Root Category is copied directly;
children store null and inherit from their root. Root order is normalized
within each Category (including virtual null/unclassified), and child order is
normalized within each parent, preserving the legacy display ordering.

Initial status mapping is `completed → completed`; pending/running/paused/
waiting all map to `inProgress`. This mapping happens once. Later Event and
WorldNode edits do not propagate in either direction.

The normal SQLite schema upgrade callback is transactional. Validation or
insert failure therefore leaves schema v13 and all legacy facts intact. The
backfill is also directly rerunnable: deterministic primary keys, unique links,
conflict-ignore inserts, and explicit mapping verification prevent duplicates.

## Sync protocol 2

WorldNode and LegacyEventWorldNodeLink are normal business sync records.
WorldNode hierarchy/category fields use global IDs; deletion uses normal
tombstones. Root and child ordering uses `worldNodeSiblings` full scoped lists:

```text
category:<category UUID | uncategorized>
parent:<WorldNode UUID>
```

The existing list compare/resolution/apply engine owns ordering, so raw row
indexes are never field-level LWW state. Snapshot validation and SQLite
readiness block invalid UUIDs, missing parents/categories/owners, cycles,
child direct categories, invalid migration mappings, duplicate mapping
identities, incomplete/incorrect list scopes, and duplicate scoped order.

Persisted protocol 1 baselines are not silently treated as though they already
contained WorldNodes. The parser recognizes protocol 1 and explicitly derives
the same WorldNode, link, and scoped-list records before returning a protocol 2
baseline. This preserves three-way history when both devices independently
migrate the same legacy dataset. Other protocol mismatches remain blocking.

WorldNode operations pass through the existing SHA-256 fingerprint, compare,
resolution, mutation plan, stale-plan guard, per-database transaction,
readiness/final verification, two-device backup, and rollback layers.

## Verification and rollout

`tool/world_node_migration_report.dart <database>` opens an already-backed-up
database through AppDatabase, performs the v14 upgrade when needed, and prints
the Legacy World → WorldNode report as JSON. Exact initial migration requires
equal Event/WorldNode/mapping counts and zero missing, duplicate,
deterministic-ID, hierarchy, category, order, or initial-status mismatches.

Production rollout must record pre-migration Event/completed/unfinished/
running/open-segment/Today/root/Category counts and take a verified independent
backup on each device first. It must then verify schema v14, integrity,
foreign keys, the migration report, and unchanged legacy Event/Today/segment
facts. A disconnected device is reported as not verified; an older backup is
never substituted for the current device.
