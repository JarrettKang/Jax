# World quick attention gesture

2026-09-08

## Interaction

- Parent main content: single click/tap browses the hierarchy. Leaf single tap is
  a no-op. Neither navigates to Detail.
- An inProgress node's main content double tap toggles attention, including
  leaves. Completed double tap is a no-op (including completed parents), with
  no restore, attention write, navigation or collapse.
- `WorldNodeBrowsingRow` uses the framework's InkWell single/double-tap
  arbitration and default threshold. No application timer or immediate first
  tap mutation is used. A recognized double tap suppresses both single taps.
  The normal single-pointer action waits for Flutter's double-tap timeout;
  chevron and keyboard/accessibility activation do not wait for this arbitration.
- Chevron and More are sibling regions outside that InkWell. Two quick chevron
  taps only toggle twice; they cannot enter the attention recognizer. Scrolling
  wins the normal ListView gesture arena and cancels row actions.
- The existing focus marker remains a status indicator, not an extra button.
  Double tap and explicit More focus/unfocus call `_changeAttention`, then the
  existing controller/repository attention API. No optimistic field edits occur.
  While an attention write is pending, duplicate writes for that node are ignored.
  Repository failure keeps the old visual and uses the existing error snackbar.
- More: Detail first, explicit focus/unfocus, contextual Add Plan/new round,
  history, structural management, then lifecycle actions. Only World More's
  View Current Plan is removed. Detail/current Plan navigation elsewhere remains.
- Planning and Today recommendation reuse the shared PlanningController's
  existing eligibility. No Plan is auto-created; dispatched execution facts are
  unaffected. Schema remains 21 and Sync protocol remains 8.

## Accessibility

Pointer double tap is excluded from automatic InkWell semantics. The main
Semantics node explicitly exposes only the parent browse action. Screen-reader
activation therefore browses; a leaf does not expose a fake tap/focus action.
More retains discoverable focus/unfocus for screen readers and keyboard users.
Tests perform semantic activation and verify parent collapse without focus,
leaf's absent tap action, and desktop keyboard access to More. Existing
Enter/Space browsing regression also passes. TalkBack was not enabled on the
physical device; these are semantics tests, not a claim of spoken TalkBack QA.

## Verification

Private device/data evidence omitted; engineering behavior is described separately.

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
