# hs_select_window.spoon — Issues

Comprehensive evaluation performed 2026-04-05.

## Bugs

### 1. `selectApp` references undefined variables (lines 457-508)
`onlyCurrentApp` (line 490) and `currentWin` (line 504) are never passed as
parameters nor defined locally — they'll always be `nil`. The `onlyCurrentApp`
guard is dead code, and `list_window_choices` gets `nil` for `currentWin`, so it
won't exclude the focused window. Also `name` on line 485 is undefined — will
crash on the error path. This function appears broken and possibly unused.

### 2. `selectWindowGeneric` captures `moveToCurrentSpace` from wrong scope (line 316)
The chooser callback references `moveToCurrentSpace`, but that variable is a
parameter of `selectWindow` (line 384), not `selectWindowGeneric`. The closure
captures nothing — it's always `nil`. Move-to-current-space never actually works
through this code path.

### 3. `obj.name` set twice (lines 7 and 10)
Line 7 sets it to `"hs_select_window"`, line 10 overwrites it with
`"selectWindow"`. One is wrong.

### 4. `bindHotkeys` mutates the caller's modifier table (lines 704-705)
`local ks = v[1]` copies the *reference*, not the table. Then
`ks[#ks+1] = "shift"` permanently appends `"shift"` to the original mapping
table. On each reload or re-bind call, `"shift"` accumulates. This corrupts the
caller's data.

### 5. `theWindows` is a global (line 89)
Should be `local` or on `obj`.

### 6. `w` is a global in `focus_by_title` (line 167)
`w = obj:find_window_by_title(t)` — missing `local`.

### 7. `list_window_first_choices` is a global (line 421)
`function list_window_first_choices()` inside `selectFirstAppWindow` — should be
`local function`.

### 8. `display_currently_selected_window_callback` is a global (line 640)
Should be `local`.

## Dead / Redundant Code

### 9. `count_app_windows` is now unused (line 215)
Only caller was `selectWindow`, which was refactored to build the list inline.
Still referenced from `selectApp` which is itself broken.

### 10. `selectApp` appears to be dead code (line 457)
Not wired to any hotkey in `bindHotkeys`. Has multiple bugs (see #1, #2 above).
Duplicates logic from `selectWindowGeneric` poorly.

### 11. `windowActivate` is unused (line 295)
Not called anywhere in the file. The same focus+activate pattern is inlined in
3 other places.

### 12. `previousSelection` is set but never read (line 91)

### 13. `obj.PrevWindow` vs `obj.trackPrevWindow` — two different fields
`trackPrevWindow` is set/cleared in `enter_chooser`/`leave_chooser`.
`PrevWindow` is used in `display_currently_selected_window_callback` and the
shift+tab binding. These are different fields tracking the same concept.
`trackPrevWindow` appears unused — `PrevWindow` is the one that actually
controls thumbnail refresh.

### 14. Redundant nil check (lines 654-661)
After checking `if not selectedWin` and returning, line 661 checks
`if selectedWin` — this is always true at that point.

## Design Issues

### 15. `enter_chooser`/`leave_chooser` not called on early-exit paths
When `selectWindowGeneric` detects 0 or 1 choices (lines 355-377), it calls
`windowChooser:hide()` but not `leave_chooser()`. The poll timer keeps running,
hotkeys stay disabled, modal keys stay active. This relies on `hide()` triggering
the chooser callback (which calls `leave_chooser`), but that's an implicit
contract that's easy to break.

### 16. Window focus+activate pattern repeated 5 times
Lines 297-299, 328-331, 366-367, 404-405, 482-483 — all do
`w:focus(); w:application():activate()`. `windowActivate` exists for this
(line 295) but is never used.

### 17. Snapshot capture shells out to `screencapture` (line 592-593)
`hs.execute(command)` is synchronous and blocks the main thread. This is called
from a 200ms poll timer. If screencapture is slow, it blocks the entire UI.

### 18. No `stop()` on `pollChooser` during `leave_chooser`
`enter_chooser` starts the poll timer (line 512), but `leave_chooser` never
stops it. It keeps polling after the chooser is dismissed until the next
`enter_chooser` or spoon reload.

### 19. No cleanup/stop method
No way to unsubscribe from window events, stop timers, or unbind hotkeys. If the
spoon is reloaded, old timers and subscriptions leak.
