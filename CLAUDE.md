# windowTABBED

A personal macOS menu bar app (one user, not distributed) that groups windows from any app into
browser-style tabs. Pinning windows on top is planned next. "WT" is just chat shorthand: the app,
repo and code all say windowTABBED.

`SPEC.md` holds the behavior rules (grouping, tabs, sync, placement). Keep it in step with the code.

## Build and run

- Swift 6 with command-line tools only, **no Xcode**. SwiftPM, Swift 5 language mode, macOS 14+.
- `scripts/build.sh debug --install` builds `build/windowTABBED.app`, copies it to
  `/Applications` and relaunches it. Use the installed copy, which is the one granted Accessibility.
- It signs with the self-signed `windowTABBED Dev` certificate in the login keychain, which keeps the
  Accessibility permission across rebuilds. If the permission is suddenly gone, check that the
  certificate still exists before asking the user to re-allow it.
- No `@State` and other macro-based SwiftUI: the macro plugin ships only with Xcode. Use
  `@GestureState`, or an `ObservableObject` held outside the view.
- Reinstalling kills the running app without `applicationWillTerminate`, so parked tabs stay
  parked. The next launch's recovery brings them back (`Grouping/Parking.swift`).

## Code map

- `App/`: entry point and status menu (`AppDelegate`), Accessibility permission, and `DebugHooks`
  (debug builds only).
- `Windows/`: other apps' windows. `WindowDriver` reads and moves them through Accessibility and
  reads the window server. `WindowWatcher` turns AX notifications into `WindowEvent`s.
  `ScreenGeometry` converts coordinates: AX uses a top-left origin, AppKit bottom-left.
- `Grouping/`: `GroupManager` is the source of truth and applies `SPEC.md`. `DragWatcher` watches
  global mouse drags for grouping-key drops, and keeps the bar on a dragged window.
  `Parking` decides where background tabs hide.
- `TabBar/`: the tab strip, one borderless non-activating `NSPanel` per group, ordered just above
  the group's active window. SwiftUI tabs, tinted by the app icon's color (`AppTint`).
- `Settings/`: preferences (`Settings`), the Settings window with its key recorder, and the
  ⌃⌥←/→ tab shortcuts (Carbon hot keys).

## Things that look wrong but aren't

- **Background tabs are parked off screen** (bottom-right corner, 1 pt sliver), not stacked behind
  the active window. Moving another app's window always lags a few frames, so stacked tabs
  trailed behind every drag. A switched-to tab gets moved into `group.frame`.
- **During a drag, the bar follows the window server position**, not AX notifications, which
  arrive late. Adding the pointer's latest movement on top cut the lag but made the bar jiggle, and
  the user preferred the steady version. Linking the bar to the window server-side
  (`SLSAddWindowToWindowMovementGroup`) fails with error 1001 for windows of another app.
- **Raising a window also sets `kAXFrontmost` on its app**: since macOS 14, a background app's
  `activate()` request can be ignored after a click on the non-activating bar.
- **The grouping key is modifiers only** (⇧ ⌃ ⌥ ⌘ fn), so holding it never types into the app.
  ⌃ turns the click into a right-click, and ⌥ triggers macOS window tiling. Settings warns about both.

## Debugging and testing

The user wants Claude to test on screen itself rather than hand tests back.

- Logs: `os.Logger` with subsystem `windowTABBED`, logged `privacy: .public`. Read them with
  `/usr/bin/log show --last 30s --predicate 'subsystem == "windowTABBED"' --style compact`.
  Plain `log` is a zsh builtin.
- Drive a debug build with `swift scripts/debug.swift "<command>"`, **quoted as one argument**.
  Commands (see `App/DebugHooks.swift`) act on the first group:
  - Tabs: `select n`, `close n`, `move n m`, `dragout n`.
  - Drags: `keydrag x1 y1 x2 y2` (with the grouping key), `drag x1 y1 x2 y2` (plain, logs the
    bar's lag), `setpos n x y`.
  - Settings: `settings`, `style full|icon`, `record`, `press ctrl,opt`.
  - Other: `release` (clears stuck modifiers), `snapshot` (saves the bars and Settings to `build/*.png`).
- Computer use can't click WT's own windows or see them in screenshots. Check WT through `snapshot`
  images and window server listings instead.

Safe on-screen testing, learned the hard way:

- **Test with your own throwaway windows** (new TextEdit documents set with `osascript ... set bounds`).
  Put them where none of the user's windows are, and list every on-screen window first. A drop
  point that lands on a user window groups it.
- Start drags on a blank part of the title bar. TextEdit's "Edited" title button eats the click.
- Events posted with modifier flags leave them set system-wide. Check the flags afterwards and run
  `release` if anything is stuck, or the user's own drags start grouping windows.
- A full-screen computer-use screenshot hides other apps, and releasing control doesn't bring them
  back. Unhide them (`System Events` › `set visible of process ... to true`), or prefer
  `app_screenshot`.
- Changing the user's settings while testing? Put them back afterwards: quit WT, run
  `defaults write local.larieght.windowtabbed ...`, then relaunch.
- macOS ignores a background app's `activate()` when no click caused it. To bring Settings to the
  front for a test, use `osascript -e 'tell application "windowTABBED" to activate'`.

## Design rules (the user's choices)

- Tack-style tabs: app icon + short title, left-aligned, not full width. An "icon only" style is a
  setting. Light Aqua gradient and gloss, strong active/background contrast. **No Liquid Glass.**
  Figma: https://www.figma.com/design/Ny6Db7XxBcnAkFWUHjaYnA
- Tab switches use a fast, jumpy spring (stiffness 700, damping 18). **Only the tabs animate**: the
  real window's content swaps instantly, with no fade.

## Working with the user

- Ask clarifying questions when a choice is theirs to make; they like being asked.
- Commit and push only when asked. Commits end with the `Co-Authored-By` line.
