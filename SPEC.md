# windowTABBED — v1 spec (tabbing only)

macOS menu bar app. Swift + AppKit (SwiftUI for the tab bar view).
Groups windows from any app into browser-style tabs. Pinning comes after v1.

Design: https://www.figma.com/design/Ny6Db7XxBcnAkFWUHjaYnA

## Grouping

- Hold the **grouping key** and drag a window onto another window to group them.
- The key has **no default**: on first launch WT asks you to pick it. Changeable in Settings.
- Drop **anywhere on the target window**. A blue outline shows the drop will group.
- Dropping onto a window that is already grouped adds a tab to that group.
- A window belongs to **one group at most**. Dropping a grouped window into another group moves it.

## Tabs

- Background windows are **parked** off the bottom corner of their display (a 1 pt sliver stays on screen), so they never trail behind a drag. Switching to one moves it into the group's frame. Quitting puts them back; after a crash, the next launch does.
- Click a tab → that window comes to the front. Window content switches **instantly** (no fade).
- Only the tabs animate: fast, slightly bouncy spring. Active tab rises, old one sinks.
- **×** removes the window from the group. It never closes the real window.
- Drag a tab **out** of the bar and drop it on the desktop → it leaves the group and lands where dropped.
  - Pulling a tab up or down stretches it with resistance (rubber band); about 24 pt out it comes loose
    and follows the pointer. Dropping it back over the bar puts it back.
  - Settings › Dragging a tab out picks what follows the pointer once it's loose:
    **Window** (default: the real window leaves the group right away and follows, with the tab on top),
    **Outline** (a floating tab and a dashed outline where the window will land) or
    **Tab** (just the floating tab). With Outline and Tab, the window moves when you let go.
- Drag tabs within the bar to reorder. The other tabs slide aside as the dragged one passes their middle, and it glides into its slot when you let go.
- Dragging empty space on the bar does **nothing**. Move the group with the active window's title bar.
- When a group is down to **one window**, the group dissolves and the bar disappears.
- Tab switching shortcuts (Ctrl+Option+←/→) exist but are **off by default**.

## Keeping the group in sync

- Moving or resizing the active window moves/resizes **all** windows in the group to the same frame.
  If an app has a minimum/maximum size, use the closest size it accepts.
- Focusing a background window another way (Cmd-Tab, Dock, Mission Control) **makes it the active tab**.
- Minimizing the active window **minimizes the whole group**. Restoring one restores the group.
- Full screen (green button) **pauses** the group: the bar hides, and comes back on exit.
- A window that closes, or whose app quits, is removed from its group.

## Tab bar placement

1. Above the window (default).
2. No room above → **flip below** the window (tab shapes flip upside down).
3. No room above or below → **shrink the window by the bar's height** and put the bar above it.

## Not in v1

- Restoring groups after restarting WT or the Mac.
- Pinning (live-mirror approach, like WindowPin).
- Tab search, badges, rules, colors per group.

## Architecture

| Part | Job |
|---|---|
| WindowDriver | Accessibility API wrapper: read/set position, size, title; raise; minimize. |
| WindowWatcher | AXObserver + NSWorkspace notifications: moved, resized, focused, minimized, closed, app quit. |
| DragWatcher | Global mouse monitor: grouping key + window drag + drop target hit-test + blue outline. |
| GroupManager | Source of truth: groups, tab order, active tab; applies all the rules above. |
| TabBar | One borderless WT window per group, ordered just above its active window. |
| Settings | Grouping key, shortcuts toggle. Stored in UserDefaults. |

Build: Swift Package Manager + a script that wraps the binary in `windowTABBED.app` and signs it
with a stable local certificate, so the Accessibility permission survives rebuilds.
