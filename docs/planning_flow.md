# Planning flow redesign

World previously changed attention without offering a target-specific route;
Overview then required finding the node again, and every new item opened a
context-obscuring modal. All entry points now use PlanDetailPage as the canonical
WorldNode workspace. A worldNodeId resolves the current plan; an explicit planId
pins Home's source/current choice or a historical plan.

New attention offers a five-second Snackbar action “开始规划”, replacing the
previous no-success-notification policy. It is optional and does not create
anything. It leaves the compact tree layout unchanged. Overview shows node,
round, counts and up to two next titles, with no-plan nodes also navigable.

Navigation and unsubmitted input do not write. With no plan history, the first
valid Quick Add submit calls FirstPlanningStepRepository.createFirstPlanningStep:
the SQLite transaction reuses the existing plan/item creation helpers and rolls
back both on any failure. A concurrently created plan/history is rejected rather
than guessed. Ended-only history requires explicit new-round creation. No new
entity/status, schema or protocol was introduced (schema21/protocol8).

The list contains a persistent inline input, optional note and “设为下一步” checkbox.
Each item defaults to draft, including the item after a next submission. Enter,
Android Done and the visible add button submit; successful writes clear fields
and retain focus. Busy prevents duplicate concurrent submission, failures retain
text, blank titles show inline validation, and duplicates are allowed. Keyboard
metrics trigger scrolling to the input. Existing scoped order is preserved.

The title is the WorldNode, followed by breadcrumb and a secondary round summary.
Empty plans explain that the first idea need not be a complete plan. Review CRUD,
history and all item lifecycle/reorder/detail actions remain. Detailed existing
item edits retain their modal for now; no modal can create a new PlanItem.
Ended plan structure is still read-only. Home source-resolution and explicit
ended/current/new-round decisions are unchanged; openAddItemOnLaunch now focuses
this inline input instead of showing a dialog. Event and segment state is untouched.

Validation: SQLite transaction failure and ended-history rejection; 390/1200-wide
World shortcut -> empty workspace -> cancellation -> blank input -> repeated
Enter with same titles and stable focus -> next recommendation without dispatch.
Home regression compares running Event and open segment identity/start/state.
All 296 tests passed after removal of the unreachable modal-add branch.
The extended flow tests also pass for ended-only history, explicit second-round
creation and read-only historical structure. Flutter analyze reports no issues.
Ordinary Windows Debug and Android Debug builds both pass. Standard output
artifacts have been rebuilt with the production main target, not the QA fixture.

Windows native acceptance used a nonempty isolated fixture. The World shortcut
opened the matching workspace; native Enter added three draft steps continuously,
then the visible add button added a fourth as next. Existing steps stayed visible,
input focus returned after each submit, and the checkbox reset to draft. With a
Chinese IME, Enter first commits composition and a subsequent Enter submits.

Android real-device installation initially returned INSTALL_FAILED_ABORTED. After
explicit user authorization, one guarded install -r retry succeeded for
com.example.jax.worldfixture. APK SHA-256:
204AC02475FDE21B7864D847389892C5B82F6E1D55274A6A3676BA60084746C3.
There was no uninstall, data clear or automatic retry. Formal Jax was not updated.

Android native acceptance on <device-model> (2026-09-08) passed the main entry flow:
World focus -> optional shortcut -> matching node workspace -> three consecutive
draft submissions (a, b, c) using the actual on-screen keyboard -> fourth step d
explicitly next. The keyboard stayed open and accepted the next title without
retapping the field. Existing steps and Quick Add stayed visible, scoped order
was a/b/c/d, and the next checkbox reset after submission. After hiding the
keyboard the summary showed one next and zero dispatched. Optional-note input
was canceled without adding a fifth item; existing-item detail editing opened
with title and note fields and was canceled. The QA app was force-stopped after
acceptance. Screenshots are retained locally under .debug_backups as
planning-android-three-drafts.png and planning-android-four-items.png.

Native acceptance detail: with a long list and the keyboard open, expanding the
optional note may require scrolling to reveal its field. The main title input
remains visible. ADB text injection changed the phone IME display/composition
mode, so acceptance was repeated in a fresh temporary QA session using only
touches on the actual soft keyboard. No production workaround was introduced.
Home running-event and ended-history invariants remain covered by the automated
regressions; they were not exercised against real user records on the phone.
Desktop native mouse navigation and keyboard checks used the isolated temporary
fixture database; no real Windows business data was used or changed.

## Formal Android rollout (2026-09-08)

Private device rollout evidence omitted from this historical version.

