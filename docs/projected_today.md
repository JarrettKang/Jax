# Planning / Today execution boundary — 2026-09-14

## Read-only audit before implementation

The working tree was clean at `76008ec`. No applicable AGENTS.md was found.
The following findings were reported before changing business code.

| Concern | Existing implementation |
| --- | --- |
| Enum/storage | `lib/core/entities/plan_item.dart`: draft, next, dispatched, done, dropped; SQLite stores names, not ordinals. `app_database.dart` CHECK accepts all five. |
| Creation | `PlanningRepository`, `SqlitePlanningRepository`, `PlanningController.addItem` defaulted to draft. Quick Add explicitly supplied draft. FirstPlanningStepRepository used the same creation helper. |
| Editing/UI | `planning_page.dart` allowed draft title inline editing, draft/next detail editing, toggle-next, move/drop/delete, dropped→draft restore. dispatched/done protected execution history. |
| Today data | `EventController.todayEvents` joins loaded EventDayPlan IDs to Events. Routine uses the existing recurrence/execution data. |
| Old suggestions | `PlanningController.recommendationGroups` selected next from focused inProgress nodes/current plans, ordered by category, node path/order and item order. |
| Manual dispatch | Planning More and Today checkbox section → `dispatchRecommendations` → `DispatchPlanItems` → `SqlitePlanningRepository.dispatchPlanItems`. |
| Old transaction | Recheck eligibility/unique link; create pending Event with sourcePlanItemId; update dispatched; append current JaxDay EventDayPlan. No segment yet. |
| Existing start | `EventController.start` → `StartEvent` / `RunningEventSwitchService` → SQLite repository. Creates open RunSegment when execution starts, pausing previous Event or Routine. |
| Data refresh | PlanningController separately loads WorldNode/Plan/PlanItem and links; Today listens to both controllers; Home consumes EventController. |
| Home recommendations | HomeCandidateProvider accepts Today Event and scheduled Routine only, not PlanItem. Home limits rendered recommendations to three. |
| Sync | Snapshot adapter exports raw strings; validator/readiness allow draft, next, dropped without Event and require executed links. Mutation executor imports existing strings. Tombstones and concurrent-link validation are already supported. |
| Migrations/platforms | Schema 21/protocol 8; Android and Windows share Dart repository/UI/Sync, with platform database factory adapters. No platform-native state enum. |
| Tests | draft assumptions in repository, dispatch, withdrawal, capture/inline edit, suggestion and UI fixtures; completion/restore and Sync cover dispatched/done linkage. |

The chosen minimal approach was read compatibility, direct projection using the existing
Planning data, and a new atomic start capability. No table rewrite, migration,
new Today table, source copies, new order field or Sync engine refactor was needed.

## Final behavior

- Normal product statuses: next, dispatched, done, dropped. Defaults and Quick Add write next.
- `draft` remains in the storage enum/CHECK and Sync contract only. `readPlanItemStatus`
  maps historical draft to next. Reads preserve the raw row, including ID, title, note,
  sort order and timestamps. Explicit old creation/status callers are normalized to next.
  This includes old draft values received over Sync. Neither peer rewrites its baseline.
- `projectedTodayGroups` / `projectedTodayItems` derive eligibility from
  inProgress + focused WorldNode + current Plan + next. They hold the original
  loaded PlanItem objects. All app edits/focus/status changes reload Planning.
- Unstarted projected steps persist no Event, EventDayPlan, daily carry-over or copy.
  The Event/Routine sources and their existing Today lifecycle remain separate.
- Planning next titles allow inline edit with the existing Save/Cancel/Done/Escape/blur
  behavior. Default-state labels and toggle/dispatch buttons are removed. More retains
  details, order, drop/delete and dropped→next restore. dispatched/done editing stays restricted.
- Today places projected steps in the ordinary item list with a Start action; the old
  checkbox recommendation/dispatch section is removed. Home does not ingest these steps.

## Atomic start and refresh

`PlanningExecutionRepository.startPlanItem` is implemented in the shared SQLite
repository. One transaction:

1. Rechecks node focus/status, current plan, next/legacy draft, and absence of linked Event.
2. Validates and closes previous Event/Routine open segments and pauses their owners.
3. Creates running Event with original sourcePlanItemId and firstStartedAt.
4. Updates the same PlanItem to dispatched.
5. Appends current JaxDay EventDayPlan using existing Event order.
6. Inserts open RunSegment.

Every write, including previous execution pause, rolls back if any step fails.
Repeated starts are blocked in the controller and rechecked in the transaction.
Editing, dropping/restoring and deleting a step now also validate inside their write
transaction, so a stale edit cannot cross the new execution boundary.
Completion→done and restore→dispatched are untouched.

Today uses `plan-<PlanItem.id>` as logical identity for both sources. Events already renderable from Today relations suppress stale projected rows while
the controllers refresh; merely loading an Event does not hide its projection. Event data loads
before the new Planning snapshot; Planning publishes complete maps together instead
of clearing and rebuilding visible state during async reads. The page remembers only
the identity order during a start transition. No business data is copied or persisted.
The projected source has no independent Today reorder. Event reorder clears the
transient positioning and uses the original EventDayPlan implementation; Routine order
is unchanged. A newly opened page uses existing Event order followed by Planning order.

## Legacy compatibility and limits

- `PlanningController.canDispatch` and `dispatchRecommendations`, Planning dispatch
  callbacks, status toggle, and Today batch UI were removed. `DispatchPlanItems` and
  the repository's pending-dispatch API remain documented as legacy compatibility;
  no production Controller/UI calls them. Historical fixture tests use them explicitly.
- Existing pending planned Events are not migrated into PlanItems or deleted. Their
  legacy withdrawal menus remain; never-executed Events restore the original item to next.
  Event/all-day-plan tombstones, execution evidence checks, and ended read-only behavior remain.
- Old and new clients exchange the existing wire values. An old app can still show its old
  UI/dispatch behavior; both clients must run the new build for matching product behavior.
- Concurrent offline starts still produce the existing explicit duplicate-source conflict;
  this change does not silently pick one execution or delete execution facts.
- Projection ordering across reopening is intentionally not persisted. It follows
  Planning order until started, then uses the existing Event order.
- Historical deleted manual segments with neither owner-bearing tombstone nor firstStartedAt
  cannot be reconstructed; the earlier documented execution-evidence limit is unchanged.

## Verification

Validation uses isolated test databases only; the Windows/Android Sync test uses two
separate file paths, never two potentially shared in-memory connections.

Tests cover default next, read-only legacy draft compatibility, no projection writes,
rename/drop/delete, focus/unfocus/refocus, ended plans, running creation and source link,
open segments, duplicate/concurrent start, late rollback including prior Event/Routine,
completion/restore, immutable executed steps, and Home remaining empty with 42 projections.
Android 390px and Windows 1200px widget flows verify live title changes and visibility,
then inspect 20 transition frames for one row/title and stable second-row position.
A deliberately delayed EventDayPlan read tests the Event-loaded / relation-pending
interval that the full regression initially exposed.
The existing legacy withdrawal, standalone, Routine, carry-over, migration and Sync
suites remain in the full regression run.

Final validation (2026-09-14):

- `flutter analyze --no-pub`: no issues.
- `flutter test --no-pub --reporter expanded`: 331 passed.
- Windows Debug build: succeeded, `build/windows/x64/runner/Debug/jax.exe`
  and its updated Flutter data bundle.
- Android Debug build: succeeded, `build/app/outputs/flutter-apk/app-debug.apk`.
- Logs: `.debug_backups/projected_today_analyze.log`,
  `.debug_backups/projected_today_final_tests.log`,
  `.debug_backups/projected_today_windows_build.log`,
  `.debug_backups/projected_today_android_build.log`.
- SDK: `<flutter-sdk>`; Android SDK:
  `<android-sdk>`; JBR: `<jdk-home>`.
  The Android SDK/JBR environment paths were supplied explicitly for the build.

No production installation, Sync Apply or real-data mutation is part of this change.

## Authorized Android rollout — 2026-09-14

Private device rollout evidence omitted from this historical version.

