# World parent browse / leaf attention

Current main-tree interaction:

- Parent tap toggles hierarchy immediately, including completed parents, without
  changing attention. Chevron calls the same browse action.
- An inProgress leaf tap toggles attention using the existing Core/Data API.
  Its indicator, name and planning summary share the target; completed leaf is
  a no-op and may only be restored through the explicit lifecycle menu.
- Every eligible parent and leaf retains More focus/unfocus. Parent attention
  remains fully supported; this is a UI shortcut, not a leaf-only domain rule.
- More and parent chevron are siblings of the main InkWell. They cannot invoke
  its callback. Detail remains in More; View Current Plan remains removed.
- The main tree registers only onTap. No custom timing window or timer exists.
  The former combined tap recognizers delayed browse while deciding the gesture;
  this implementation removes that source of latency.
- Standard tap/drag arbitration cancels attention when scrolling. Existing focus
  indicator refreshes after successful writes; failures use the existing error
  feedback, without an optimistic mutation or success notification.
- Semantics and keyboard activation use the same parent browse / leaf attention
  action. More remains discoverable. TalkBack's own activation gesture has no
  competing custom business recognizer.

Planning and next-item recommendation eligibility still use existing attention
logic. Dispatched Event, EventDayPlan, RunSegment, PlanItem, and tombstones are
compared as complete rows in SQLite regression tests; schema21/protocol8 and
all Domain, Sync, hierarchy and tree-renderer code remain unchanged.

## Verification

The shared mouse/touch suite checks next-frame parent expansion without advancing
an arbitration timeout, focused parents, completed parents/leaves, leaf toggle,
no-plan Planning entries, plan recommendation eligibility, More equivalence,
independent controls, leaf drag cancellation, accessibility and write failure.
Old business-gesture tests have been replaced by the current tap rules.

2026-09-08 validation: all 293 Flutter tests pass; analyze reports no issues.
Ordinary main-entry Windows Debug and Android Debug builds both succeed.
Windows mouse checks verified focused-parent collapse/expand without attention
changes, leaf focus/unfocus, and parent More attention without collapsing.
<device-model> touch checks verified parent collapse in the immediate post-tap capture
(no added wait), re-expansion, leaf focus/unfocus, dragging from a leaf scrolls
without focus, completed-leaf no-op and More isolation. This is observable
response verification plus a next-frame widget assertion, not a millisecond
latency benchmark. TalkBack was not enabled; semantics activation is tested.
Android screenshots are retained locally in `.debug_backups/world_tap_20260908/`.

Private device/data evidence omitted; engineering behavior is described separately.

## Historical incident record

Private device/data evidence omitted; engineering behavior is described separately.

The first physical-device test installation was rejected by the phone.
Flutter's runner then automatically uninstalled the existing package and retried
installation. This removed the existing app data directory. The backup had
already been exported after force-stop, with no WAL/journal present, and passed
read-only integrity/FK checks before installation.

Private device/data evidence omitted; engineering behavior is described separately.

Private device/data evidence omitted; engineering behavior is described separately.

Private device/data evidence omitted; engineering behavior is described separately.

Local logs, current-turn backup/audit and Android screenshots are under
`.debug_backups/world_attention_20260908/` and are not committed to Git.
