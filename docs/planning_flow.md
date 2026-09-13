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

The title is the WorldNode, followed by full ancestry and a secondary round summary.
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

## Workspace hierarchy refinement (2026-09-12)

UI-only changes in planning_page.dart: full ancestry is now a compact vertical
context with short branch connectors, wrapping names and an indentation budget
of 22% of available width. AppBar height accommodates long node titles. Round
metadata is body-small text; the summary begins with total steps and omits zero
next/dispatched counts. A light “计划步骤” heading introduces the continuous list.
Dense item rows use dot/arrow/dispatched/check/dropped markers. Draft/next still
toggle directly through the leading control; existing up/down ordering moves
into More to free title width. No drag mechanism was added.

Quick Add stays at the list end. Its options appear on focus, cancel is visually
secondary, submit retains focus and defaults to draft. Expanding note schedules
input reveal. Empty plans and Home's add intent retain initial focus. Review has
a small add button; existing notes show a one-line latest preview and expand to
the existing CRUD controls. No empty-review message is shown.

The World tree painter was not reused: it represents branching sibling rows,
whereas this context is a single ancestry chain. Lightweight text connectors
avoid fixed-depth layout assumptions. Data models, repositories, state semantics,
dispatch, Event creation, navigation and Review persistence are unchanged.
Responsive widget checks exercise six-level long-name ancestry and twelve steps
at 390 and 1200 logical pixels, plus continuous submit, cancellation, Home source
selection and historical plans. This revision has not been installed on a phone;
the native acceptance and rollout above refer specifically to the September 8
revision, not this UI refinement.
Validation: all 298 tests pass; flutter analyze reports no issues; ordinary
Windows Debug and Android Debug builds succeed. Physical-device keyboard and
native desktop visual acceptance have not been repeated for this revision.

## Draft inline title editing (2026-09-13)

PlanDetailPage now hides round, optional plan title and all step/status counts in
the main workspace; overview/history and roundNumber data remain unchanged.
_WorkspaceDivider supplies both section dividers with outlineVariant color and
0.5 thickness. Quick Add title and optional-note fields have no underline.

_DraftInlineContent owns its text controller and focus node. Only current-plan
draft main text opens this inline single-line editor, placing the caret at the
end. Enter/Done, tapping outside or focus traversal saves through the existing
PlanningController.editItem method, preserving the note. Blank/unchanged input
exits without a write; Escape cancels. Save failures keep the editor and display
the error. Stable row keys preserve edits across reorder/load; changing item or
leaving draft cancels the editor. More and marker controls are separate targets.
TextField scrollPadding and Flutter's focused-field keyboard reveal handle
the active editor; no scroll-to-top operation is performed.

No schema, repository, state-machine, dispatch, Today, Event, Review or navigation
logic changed. Android (390px) and Windows (1200px) widget tests cover caret/focus,
submit, outside save, empty rollback, Escape, refresh and reorder preservation,
keyboard insets, More isolation, direct status control and all four non-draft
states. Row comparisons preserve all fields except title/update timestamp;
execution tables, plan data and tombstones remain unchanged. All 300 tests pass,
including the added targeted reorder/inset checks; analyze has no issues.
These are automated platform/layout checks. Physical phone IME and native Windows
mouse/keyboard acceptance have not been repeated for this revision; no real-data
app installation or business mutation was performed during this change.
Ordinary Windows Debug and Android Debug builds both succeed.

## Formal rollout and no-op native check (2026-09-13)

Private device rollout evidence omitted from this historical version.

## Capture-only Quick Add (2026-09-13)

Quick Add now accepts only a title and always submits null note + draft through
the existing repository/controller path. The next checkbox, note editor and
up-arrow submit control have been removed from this UI only. Existing item
status controls and More -> detailed editing still provide refinement and notes.

_PlanQuickAdd and _DraftInlineContent share _InlineTitleEditor: a borderless title
field and a compact right-aligned Cancel + Add/Save text-button row. The primary
action uses the theme accent and a stronger label; no filled panel or modal was
added. Enter/Done invokes the same submission as the button; Escape cancels.
Capture success clears input and retains focus for continuous entry. Capture
cancel discards input and collapses. Outside capture clicks never create an item:
empty input collapses; nonempty input loses focus but remains available.

Draft cancel discards edits without calling persistence. TextFieldTapRegion and
a Focus ancestor wrap the entire editor including buttons, so clicking Cancel
does not count as an outside tap or a departure from the editor's focus group.
Outside clicks/focus traversal out of the group still save draft edits. Empty
capture stays open with validation; empty draft restores the stored title.
No schema, state machine, dispatch, Today, Event or note persistence changed.

Android/Windows widget regressions cover add/save/cancel, unchanged execution
facts, continuous Done, Escape, outside save, field rebuild/reorder, keyboard
insets and a 360px scaled Home editor. Native phone IME and native desktop
acceptance have not been repeated for this revision; previous rollout evidence
above applies to earlier revisions. No real-data app was installed or modified.
Validation: all 300 tests pass, analyze reports no issues, and final ordinary
Windows Debug and Android Debug builds succeed.

## Capture editor formal Android rollout (2026-09-13)

Private device rollout evidence omitted from this historical version.

