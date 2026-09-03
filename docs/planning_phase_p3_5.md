# Planning Phase P3.5: WorldNode attention

P3.5 moves the ownership of “currently worth actively advancing” from Plan to
WorldNode. WorldNode lifecycle remains `inProgress/completed`; the independent
business field `isFocused` is synchronized across devices. Plan status is now
only `current/ended`, with at most one current round per WorldNode.

## Lifecycle rules

- Any number of in-progress WorldNodes may be focused, including nodes without a
  current Plan. Parent, child, and Category attention never propagates.
- Focusing or unfocusing changes only `WorldNode.isFocused`. A current Plan,
  PlanItem states, dispatched Events, Today order, segments, Routine, and Record
  facts remain untouched.
- Ending a Plan keeps its WorldNode focused. Planning then shows the node with no
  current Plan and offers a new round.
- A current Plan blocks WorldNode completion. Once no current Plan exists,
  completion atomically sets `status=completed,isFocused=false`; restoration sets
  `status=inProgress,isFocused=false`.

## Projections and UI

Planning Overview is the ordered projection of focused + in-progress WorldNodes.
The node is the visual subject and its current Plan is nullable. A focused node
without one shows “暂无当前计划” and “添加计划/添加新一轮”. The global Plan picker
still includes eligible not-focused nodes, and creating a Plan never focuses one.
Plan Detail contains no Plan focus/wait controls; it may offer a convenience
action that writes WorldNode attention. World keeps planning/history operations
available regardless of attention and shows only a lightweight “关注中” marker.

Today recommendations use one rule in presentation and transaction validation:

`WorldNode inProgress + focused + Plan current + PlanItem next`.

Unfocus removes an un-dispatched suggestion immediately; refocus reveals the same
Plan and item again. Already dispatched/done items and their execution facts are
outside attention control.

## Migration and sync

SQLite v17→v18 adds `world_nodes.is_focused` and rebuilds the Plan dependency
chain to replace the status CHECK. Old `focused` maps to focused WorldNode +
current Plan; old `waiting` maps to not-focused WorldNode + current Plan; `ended`
remains ended. All copied rows retain identity and metadata, and no execution row
is derived or created.

Sync protocol 6 includes `isFocused` in snapshot, fingerprint, compare, apply,
tombstones, and readiness. Protocol 5 normalization performs the same mapping,
preserves dataset generation and schema provenance, and does not write the stored
baseline. One-side attention changes follow ordinary three-way merge; concurrent
different edits to the same WorldNode are explicit field conflicts, never LWW.

Readiness rejects non-boolean attention, completed + focused nodes, legacy active
Plan values, current Plan with `endedAt`, ended Plan without `endedAt`, duplicate
current rounds, and all pre-existing FK/execution invariant failures.
