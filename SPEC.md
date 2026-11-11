# windowTABBED — v1 spec (tabbing only)

macOS menu bar app. Swift + AppKit (SwiftUI for the tab bar view).
Groups windows from any app into browser-style tabs, and can pin a group's tab bar on top.

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
- **Scroll to switch tabs**: scrolling over a tab bar goes to the previous tab (pushing up: a wheel
  away from you, two fingers up a trackpad, whatever Natural scrolling is set to) or the next one
  (down). One wheel notch is one tab; a trackpad needs about 24 pt per tab, and the coasting after a
  flick is ignored.
  - Settings › Scrolling: **Over the tab bar** (default) or **Anywhere, holding a key**: with that key
    held (⌥ by default), scrolling anywhere over a group's window switches its tabs and the window
    doesn't scroll. Over the bar it works with no key either way.
  - At the first and last tab: **Stop** (default) or **Wrap around**.

## Stacking tabs by app

- **Experimental**, off by default: Settings › Stacking tabs by app › **Stack Tabs by App** turns it
  on. Turning it off spreads every stacked group out again.
- Right-click a tab bar › **Stack Tabs by App** (per group, a checkmark when on). Each app's tabs pile
  up in one place, like cards in a wallet: the front one is a normal tab and the others peek out
  above it (below, when the bar is flipped), each showing its icon and title. Up to 3 show behind the
  front one; the rest are still a scroll away.
- The front of a pile is the active tab if it's in that pile, else the one you last used there.
- Click a peeking card, or scroll, to bring that window to the front. Scrolling goes through a pile
  before moving to the next app.
- While stacked, an app's tabs stay together (where its first tab was), and dragging doesn't reorder
  tabs. Dragging the front tab out of the bar still takes it out of the group.
- The bar grows by one peek per card in its deepest pile.

## Pinned tab bars

- Right-click a tab bar › **Pin Tab Bar on Top** (a checkmark shows it's on; pick it again to unpin).
  Pinning is per group and lasts until you unpin it or the group dissolves.
- A pinned bar floats above every normal window, so the group's tabs stay reachable while other
  windows cover it. Clicking a tab brings that window to the front as usual.
- Only the bar is pinned, never the windows: macOS lets only the app that owns a window keep it on top.
- Settings › Pinned tab bars sets how a pinned bar looks while another window covers its group:
  **Dimmed** (default: faded, full strength under the pointer) or **Normal**.
- An unpinned bar sits just above its window, so other windows cover it normally.

## Keeping the group in sync

- Moving or resizing the active window moves/resizes **all** windows in the group to the same frame.
  If an app has a minimum/maximum size, use the closest size it accepts.
- Focusing a background window another way (Cmd-Tab, Dock, Mission Control) **makes it the active tab**.
- Minimizing the active window **minimizes the whole group**. Restoring one restores the group.
- Full screen (green button) **pauses** the group: the bar hides, and comes back on exit.
- A window that closes, or whose app quits, is removed from its group.

## Themes

- Settings › Tabs › Theme: **Liquid Glass** (default; macOS 26+, Aqua on older systems), **Aqua**,
  **Flat**, **Pill**, **Metallic**, **Retro 98**, picked from a grid of live previews. Changing it
  redraws every bar right away.
- Flat, Pill and Metallic are **experimental**: hidden unless "Show experimental themes" is on (off
  by default), then shown together as the grid's second row, tagged. Turning it off while using one
  switches to Liquid Glass.
- Settings › Tabs › Size: **Small** (default, the original size), **Medium**, **Large**,
  **Extra Large** on a slider. Everything in the bar scales with it: height, tab widths, text, icons.

## Settings › General and About

- **Open windowTABBED at login**, off by default. macOS keeps this (Login Items), so Settings reads it
  back from there; if macOS wants your OK first, Settings links to Login Items.
- **About**: version and build, links to the GitHub page, its Releases (to check for updates) and a
  new issue, and the copyright line.

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
