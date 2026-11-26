[![Buy Me a Coffee](https://img.shields.io/badge/-Buy%20Me%20a%20Coffee-FFDD00?logo=buymeacoffee&logoColor=black&logoSize=auto&style=flat-square)](https://buymeacoffee.com/tplobo)[![Buy Me a Coffee user](https://img.shields.io/badge/user%3A-tplobo-57606A?labelColor=57606A&style=flat-square)](https://buymeacoffee.com/tplobo)

# Hammerspoon Module: restore-spaces

Hammerspoon implementation to restore organization of windows throughout
spaces on MacOS.

## Comparisons

- Better than [DisplayMaid](https://funk-isoft.com/display-maid.html) because
  it cycles through every space to save the state of all of them.
- Less resource-intensive than [Workspaces](https://www.apptorium.com/workspaces).
- No need to disable SIP like [yabai](https://github.com/koekeishiya/yabai).

## Installation

1. If you do not have [**Homebrew**](https://brew.sh) yet, install it and
   install [Hammerspoon](https://www.hammerspoon.org) for Mac automation
   (version 1.1.1 or above):

   ```
   brew install --cask hammerspoon
   ```

<br>

2. Run `install.sh` to copy the `init.lua` file and the `restore_spaces` folder
   into your `.hammerspoon` directory:

   ```
   zsh install.sh
   ```

   This keeps the saved states already installed. Use `zsh install.sh --clean`
   to overwrite everything (the saved states are backed up first), _e.g._ when
   a release changes their format.

   Or just copy `restore_spaces` into `.hammerspoon/hs`, and import the module
   in your own `.hammerspoon/init.lua` file to avoid conflicts with other
   modules.

<br>

3. Set your preferred configurations and hotkey combinations, for example:

   ```
   local restore_spaces = require 'hs.restore_spaces.restore_spaces'

   -- Configure 'restore_spaces'
   restore_spaces.verbose = false
   restore_spaces.min_window_visibility = 0

   -- Bind hotkeys for 'restore_spaces'
   hs.hotkey.bind({"cmd", "alt", "ctrl"}, "S", restore_spaces.saveEnvironmentState)
   hs.hotkey.bind({"cmd", "alt", "ctrl"}, "A", restore_spaces.applyEnvironmentState)
   hs.hotkey.bind({"cmd", "alt", "ctrl"}, "O", restore_spaces.applyScan)

   ```

   The module is also available in the Hammerspoon console as `hs.restore_spaces`.

<br>

4. Open the Hammerspoon app, enable it in Accessibility, restart it and select
   `Reload Config`. Allow it to control Safari and Chrome when macOS asks.

<br>

5. On macOS 15 or above, keep the "Move left/right a space" shortcuts enabled
   (System Settings → Keyboard → Keyboard Shortcuts → Mission Control).

<br>

6. Run the commands a few times to check whether the `space_pause` and
   `screen_pause` settings comply with your mac. They might need to be
   increased if the console prints:

   ```
   ... attempt to index a nil value (local 'child')
    stack traceback:
   ...: in function 'hs.spaces.gotoSpace' ...
   ```

7. Run the "test" hotkey with a normal window focused. It prints a report to
   the console, with recommended `move_speed` and `mc_settle` values. Attach it
   (window titles redacted) to any bug report.

## Usage

1. Press the "save" hotkey combination to save current state.

   _e.g._: <kbd>Ctrl</kbd> + <kbd>Opt</kbd> + <kbd>Cmd</kbd> + <kbd>S</kbd>

1. Press the "apply" hotkey combination to restore that state.

   _e.g._: <kbd>Ctrl</kbd> + <kbd>Opt</kbd> + <kbd>Cmd</kbd> + <kbd>A</kbd>

1. Press the "realign" hotkey combination to bring every window into view
   (see `min_window_visibility`).

   _e.g._: <kbd>Ctrl</kbd> + <kbd>Opt</kbd> + <kbd>Cmd</kbd> + <kbd>R</kbd>

1. Press the "apply and check" hotkey combination to apply the saved state and
   write a detailed record of where every window ended up
   (`restore_spaces/tmp/data_check.json`), for bug reports.

   _e.g._: <kbd>Ctrl</kbd> + <kbd>Opt</kbd> + <kbd>Cmd</kbd> + <kbd>V</kbd>

1. Press the "scan" hotkey combination to set the recorded over/underscan of
   the monitors (macOS forgets it after sleep or restart).

   _e.g._: <kbd>Ctrl</kbd> + <kbd>Opt</kbd> + <kbd>Cmd</kbd> + <kbd>O</kbd>

When an action ends, a summary window shows the time, the desktops and windows
per monitor, the warnings by kind, the saved windows that were not found, how
the tabs were read, and the time breakdown. Click **OK** to close it. The saved
states are in `restore_spaces/tmp/`; the previous version of each file is kept
next to it as `.bak`.

## Settings

Set them in your `init.lua` (`hs.restore_spaces.<name> = ...`).

| Name                          | Default                                                                                                                                          | Meaning                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `verbose`                     | `false`                                                                                                                                          | Console detail: `false`/`0` none, `1` key steps (tab reading, recognized windows, moves, scan), `true`/`3` all messages, `5` everything. Banners and warnings are always printed.                                                                                                                                                                                                                                                                                                                          |
| `restore_scan`                | `true`                                                                                                                                           | `save` records the over/underscan of the monitors that have the setting (in the environments file) and `apply` sets it. System Settings opens briefly. The "scan" hotkey sets it alone, and `hs.restore_spaces.saveScan()` records it alone.                                                                                                                                                                                                                                                               |
| `log_titles`                  | `false`                                                                                                                                          | Show window and tab titles in the console. Off by default because titles are private; the summary window always shows them.                                                                                                                                                                                                                                                                                                                                                                                |
| `multitab_apps`               | `{"Google Chrome", "Firefox", "Safari", "Finder", MATLAB = {"Editor", "MATLAB R"}}`                                                              | Apps with several tabs per window. Plain entries are recognized by their tabs. `App = {terms}` entries are recognized by the first term found in the window title (for apps with one window per kind, such as the MATLAB editor). Set it in your `init.lua`, not in the module file.                                                                                                                                                                                                                       |
| `multitab_comparison`         | see file                                                                                                                                         | Similarity of tab lists that recognizes a window (`small`/`large` thresholds); `title_fallback_threshold` is the minimum for recognizing a window only by its title.                                                                                                                                                                                                                                                                                                                                       |
| `show_summary`                | `true`                                                                                                                                           | Show the summary window. Set to `false` to run the actions without interaction.                                                                                                                                                                                                                                                                                                                                                                                                                            |
| `check_updates`               | `false`                                                                                                                                          | Ask GitHub (at most every 12 hours) for the latest release of `repository` and say in the summary if it is newer than the installed one. It sends one request to `api.github.com`; nothing else leaves your mac.                                                                                                                                                                                                                                                                                           |
| `repository`                  | `"tplobo/restore-spaces"`                                                                                                                        | GitHub repository (`owner/name`) used by `check_updates`.                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| `verify_placement`            | `true`                                                                                                                                           | At the end of `apply`, check on which desktop each recognized window is and whether its frame was set; mismatches are in the summary and the warnings.                                                                                                                                                                                                                                                                                                                                                     |
| `debug_check`                 | `false`                                                                                                                                          | Also write the record of that check to `tmp/data_check.json` (the "apply and check" hotkey sets it for one run).                                                                                                                                                                                                                                                                                                                                                                                           |
| `min_window_visibility`       | `0`                                                                                                                                              | Fraction (0-1) of the area of each window that must be visible on its desktop. `0` only counts the windows out of view. Windows are moved, never resized, by the smallest distance.                                                                                                                                                                                                                                                                                                                        |
| `use_direct_tabs`             | `true`                                                                                                                                           | List the tabs of Safari and Chrome by scripting them. Other apps, and any failure, use tab cycling.                                                                                                                                                                                                                                                                                                                                                                                                        |
| `space_pause`, `screen_pause` | `0.3`, `0.4`                                                                                                                                     | Seconds to wait after switching desktops and screens.                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| `move_strategy`               | `"titlebar"`                                                                                                                                     | Same-screen moves on macOS 15+: `"titlebar"` or `"mission_control"`.                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| `move_max_hops`               | `15`                                                                                                                                             | Spaces (desktops and full-screen ones) that `"titlebar"` may cross per move; each takes about half a second.                                                                                                                                                                                                                                                                                                                                                                                               |
| `move_cross_fullscreen`       | `true`                                                                                                                                           | `"titlebar"` may cross full-screen spaces (verified on macOS 27.2.1). If `false`, moves that must cross one use `"mission_control"`.                                                                                                                                                                                                                                                                                                                                                                       |
| `native_move`                 | `false`                                                                                                                                          | Before the strategies, the first move of each run tries `hs.spaces.moveWindowToSpace` and checks with `hs.spaces.windowSpaces` that the window arrived; if not, native moves are skipped for the rest of the run. Off by default because on macOS 15+ with Hammerspoon 1.1.1 it reports success without moving the window, so it only costs about a second per run. Turn it on to test a Hammerspoon release that fixes it ([Hammerspoon PR #3889](https://github.com/Hammerspoon/hammerspoon/pull/3889)). |
| `native_move_timeout`         | `1.0`                                                                                                                                            | Seconds to wait for a native move to arrive.                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| `move_apps`                   | `{}`                                                                                                                                             | Apps that use only one strategy: `{titlebar = {...}, mission_control = {...}}`.                                                                                                                                                                                                                                                                                                                                                                                                                            |
| `move_speed`, `mc_settle`     | `1`, `0.3`                                                                                                                                       | Speed of the drags and wait for Mission Control. Use the values recommended by "test".                                                                                                                                                                                                                                                                                                                                                                                                                     |
| `fallback_space`              | `"last"`                                                                                                                                         | Desktop of the target monitor for windows that cannot be moved: `"first"` or `"last"`.                                                                                                                                                                                                                                                                                                                                                                                                                     |
| `unrecognized_windows`        | `"leave"`                                                                                                                                        | Open windows that `apply` does not recognize stay where they are (`"leave"`) or go to the `fallback_space` desktop of their monitor (`"fallback"`). The summary lists them either way.                                                                                                                                                                                                                                                                                                                     |
| `borrow_spaces`               | `true`                                                                                                                                           | Create desktops on another monitor and drag them over when a monitor is at the 16 spaces limit.                                                                                                                                                                                                                                                                                                                                                                                                            |
| `use_plist_check`             | `false`                                                                                                                                          | Also require desktops to be listed in `com.apple.spaces.plist` (_vide_ **Known issues**).                                                                                                                                                                                                                                                                                                                                                                                                                  |
| `use_ax_tabs`                 | `true`                                                                                                                                           | Read the tab strip of Firefox through accessibility (no cycling). If it fails, tabs are read by cycling. Turn it off if Firefox gets slow.                                                                                                                                                                                                                                                                                                                                                                 |
| `tab_cycling`                 | see file                                                                                                                                         | Overrides of `scp/scp_config.json` for the tab cycling (`maxIdenticalConsecutives`, `maxStagnantTabs`).                                                                                                                                                                                                                                                                                                                                                                                                    |
| `window_recognition`          | `{["Google Chrome"] = "tabs", Firefox = "tabs", Safari = "tabs", Finder = "tabs", ["Microsoft Teams"] = "app", MATLAB = {"Editor", "MATLAB R"}}` | How the windows of an app are recognized when their ID and title fail (apps not listed are recognized only by ID and exact title). `"tabs"`: by their tabs. `"app"`: the app has one saved window, whatever its title (_e.g._ Teams, whose title shows its view). `{terms}`: by the first term found in the title (_e.g._ the MATLAB editor). The old `multitab_apps` list is still read. Set it in your `init.lua`, not in the module file.                                                               |
| `ignored_apps`                | `{}`                                                                                                                                             | Apps that `save` and `apply` skip, _e.g._ `{"System Settings"}` (the scan restore opens its Displays pane).                                                                                                                                                                                                                                                                                                                                                                                                |
| `restore_fullscreen`          | `true`                                                                                                                                           | `apply` puts the windows that were in full-screen spaces back in full screen.                                                                                                                                                                                                                                                                                                                                                                                                                              |

## Moving windows on macOS 15+

Up to macOS 14, the native `hs.spaces` functions are used. From macOS 15 on,
`hs.spaces.moveWindowToSpace` does nothing, and from macOS 26/27 on the
Mission Control accessibility tree moved to the `WindowManager` process, which
also breaks `gotoSpace`, `addSpaceToScreen` and `removeSpace`. This module
replaces them with its own implementation:

- Switching, adding and removing desktops: presses the thumbnails in Mission
  Control.
- Moving windows, `"mission_control"`: drags the window thumbnail onto the
  desktop thumbnail. Works for any distance and between monitors, but is slower,
  and windows are identified by app and title (windows of one app with
  identical titles are indistinguishable; the first one is used).
- Moving windows, `"titlebar"`: holds the title bar while pressing the "Move
  left/right a space" shortcuts. Fast for nearby spaces of the same monitor (it
  can cross full-screen spaces, see `move_cross_fullscreen`), but each space
  takes about half a second and the window needs a title bar.

Moves between monitors always use `"mission_control"`. If a strategy fails, the
other one is tried; if both fail, the window goes to the `fallback_space`
desktop of its target monitor, and a warning is shown.

### Limitations

- Mission Control opens visibly and the cursor moves during `apply`, so it is
  slower than on macOS 14.
- macOS shows no "+" button on a monitor with 16 spaces (full-screen ones
  included). With `borrow_spaces`, missing desktops are created on another
  monitor and dragged over, which worked on macOS 27.0.1 (about 5 s each). If it
  fails, the windows of the missing desktops go to the `fallback_space` desktop.
- Windows assigned to several desktops are not moved.
- `realign` needs "Displays have separate Spaces" on.
- Do not use `hs.window:moveToScreen` or drag windows between monitors by their
  title bar in this module: the window changes monitor but stays assigned to the
  desktop it came from, and the app can stop responding to title-bar drags.
- Status: macOS 14 uses the previous (verified) code. On macOS 27.0.1 and 27.2.1
  the author verified switching, adding and removing desktops, both move
  strategies and `save`/`apply`. macOS 15 and 26 are untested.
- Dragging a window in Mission Control can show the prompt to create a
  full-screen space between two desktops (macOS 27.2). The window still reaches
  the right desktop.
  - Firefox tabs are read through accessibility, which switches on Firefox's
    accessibility support until Firefox restarts (it can raise its CPU use). Set
    `use_ax_tabs = false` to read them by cycling instead. Tabs in collapsed groups
    or hidden tabs might not be listed (unverified).
- Only monitors that have an over/underscan setting (_e.g._ TVs) are recorded.
  The first `save` checks every monitor; later ones only those that have it.
- Full-screen and split-view spaces are saved with their windows, their position
  among the spaces and the desktop they follow. `apply` recognizes those windows
  and makes them full screen again from that desktop. Where macOS puts the new
  space is checked at the end ("Space order" in the summary). The two windows of
  a split view cannot be joined again: only the first one enters full screen.
- Missing desktops are appended after the last space of the monitor, so their
  position can differ from the saved one.
- Windows that were full screen at save time and are on a desktop after a
  restart are recognized like any other window. Apps with a title that changes
  (_e.g._ Calendar) need `window_recognition = {Calendar = "app"}`.

### Acknowledgements

The approach (Mission Control through the accessibility tree, a timed drag that
shares one mouse event number, reading the tree from `WindowManager`) comes from
the public work of others. The code here is original and none was copied:

- [`mogenson/Drag.spoon`](https://github.com/mogenson/Drag.spoon) and
  [`mogenson/PaperWM.spoon`](https://github.com/mogenson/PaperWM.spoon) (MIT),
  in particular [PR #174](https://github.com/mogenson/PaperWM.spoon/pull/174)
  by `MOB-34` and [issue #173](https://github.com/mogenson/PaperWM.spoon/issues/173).
- Hammerspoon issues
  [#3698](https://github.com/Hammerspoon/hammerspoon/issues/3698) and
  [#3897](https://github.com/Hammerspoon/hammerspoon/issues/3897), and their
  contributors.
- [`freeman106`](https://github.com/freeman106),
  [PR #5](https://github.com/tplobo/restore-spaces/pull/5): verifying native
  moves with `hs.spaces.windowSpaces` before using Mission Control, and leaving
  the frame alone when a move failed (`native_move`). Original code modified.

## Development

Following features have already been implemented:

- Functionality for multiple monitors and for multiple environments (sets of
  monitors, in a given order, with their own saved states and names).
- Restore for windows that have empty title, for a different number or order of
  desktops, and for windows whose ID changed after an app restart.
- Moving windows, switching, adding and removing desktops on macOS 15+.
- Summary window, banners and warnings, `test` report with recommended settings.
- Realigning windows into view.
- Tab lists of Safari and Chrome by scripting them.
- Restore of the over/underscan, and of full-screen and split-view spaces.

Current features under development; any help is appreciated:

- Fix the problems listed in **TODO**.
- Full-screen and split-view spaces.
- Logging levels and a support report.
- Refactoring, renaming and tests with mocking.

## Known issues

1. The **"Dashboard"** feature may create a hidden space that cannot be
   accessed, and thus breaks `hs.spaces.gotoSpace()`, even in MacOS versions
   that do not feature Dashboard anymore. It shows in the spaces plist file:

   ```
   defaults read com.apple.spaces.plist
   > ...
      {
         ManagedSpaceID = 23;
         id64 = 23;
         pid = 321;
         type = 2;
         uuid = dashboard;
      }
     ...
   ```

   [Disabling it](https://discussions.apple.com/thread/255600670) does not
   work. Instead, only spaces of type `"user"` (desktops) are used, which
   excludes the dashboard. If that is not enough on your mac, set
   `use_plist_check = true` to also require desktops to be listed in the plist
   file (which lags behind right after spaces are added or removed). The plist
   is also used if macOS reports no space types at all.

1. There are no official APIs for putting two windows in **split-view**
   fullscreen mode. The windows are saved, but only the first one of each split
   view enters full screen again; the other one stays on a desktop and is listed
   in the summary ("Split views to set by hand").

1. **Window IDs change when you close/open an app.** A window is restored if
   its title is the same as when it was saved. For apps with tabs
   (`multitab_apps`), the list of tab titles is compared instead, using the
   thresholds of `multitab_comparison`. Cycling through the tabs loads them,
   which might be undesirable, and is slow.

1. The tab cycling (`getVisibleTabs.applescript`) does not distinguish between
   monitors: it cycles through the visible windows of the app on all of them.

1. On **macOS 27.2** the spaces bar of Mission Control rearranges itself while a
   window hovers over it, and a window dropped between two desktops creates a
   full-screen space. The drop approaches each thumbnail from above and
   re-checks its position, and a window that still ends in such a space is made
   to leave full screen again (a warning is shown). High `move_speed` or low
   `mc_settle` values make it more likely (`test` failed with `move_speed = 2`
   and `mc_settle = 0.2`): keep the defaults unless `test` recommends others.

1. Windows moved completely off all monitors may report no desktop (macOS 27.2).
   `realign` then asks the desktop being visited whether it lists the window.

1. On **macOS 27.2** the thumbnails of Mission Control can show black for a
   fraction of a second when it opens. It also happens with Hammerspoon not
   running, so it is not caused by this module.

1. **Reordering full-screen spaces** does not work yet: the experimental
   `probeSpaceReorder` could not move a full-screen space on macOS 27.2.1.
   `apply` only reports the difference ("Space order" in the summary, after a
   new `save`).

## TODO

Problems found by reading the code. Each item states where it is, what goes
wrong and how to fix it. Ordered by severity.

1. **Tab collection is the slowest part.** Cycling is kept as the fallback.
   Safari/Chrome are scripted, Firefox is read through accessibility
   (`use_ax_tabs`; the tree of Firefox is unverified: run the tabs probe). The
   cycling script now restores the selected tab after every stop, stops only
   after 12 identical titles in a row, and the report lists how each window was
   read. Windows with more than `maxTabs` tabs are truncated (a warning is
   shown). `hs.execute` blocks Hammerspoon; use `hs.task`.

1. **Matching windows after an app restart or reboot.** A saved window ID is
   trusted only if the app agrees and the boot time (from `kern.boottime`) is
   the same; states saved by attempt 2 carry an inexact boot time and must be
   saved again. Windows already placed in a run are skipped when they show up
   again. Single-tab windows are matched by title, multi-tab windows by their
   tabs (most alike pairs first, then the only saved window with the same title
   if its tabs are at least `title_fallback_threshold` alike). A saved state
   that belongs to a window that is still open can be taken by a look-alike.

1. **Over/underscan.** Verified on macOS 27.2.0 with a TV: the value is recorded
   and set again through `AXValue` (7964 restored). It is stored in the field
   `scan` of each monitor in the environments file (`false`: no setting). Not
   verified: the effect after sleep/restart, monitors with the same name, and
   other macOS versions. The pane is controlled by mouse clicks, so it is
   fragile.

1. **Console privacy.** Window and tab titles are redacted in the console unless
   `log_titles` is on. Still to review: the reports of `test`, the probes and
   `hs.inspect` calls in the files not listed here.

1. **Realign and monitors side by side.** A window placed 50% on a monitor next
   to another one can be assigned by macOS to the neighbor. `realign` now asks
   for more visibility until the monitor clearly holds most of the window, and
   warns if the window changed monitor anyway.

1. **`runApplescript` does not quote its arguments** (`applescript.lua`):
   `"Google Chrome"` becomes two arguments. It also uses a login shell (prints
   the shell profile output) and blocks Hammerspoon. Use `hs.task` with an
   argument list, as `getDirectTabs` does with quoting.

1. **Error handling around AppleScript, plist and loops.** `run` returns the
   error message as data; titles containing `, ` or `###` break the parsing; an
   error between `processPlistConfig("create")` and `("destroy")` leaves the
   plist; an error in a loop leaves the user on another desktop. Return JSON or
   separator characters (as `getTabsDirect.applescript`), and wrap the actions
   in `pcall` to always clean up.

1. **`setWindowState` target handling.** `target_screen` changes type and is
   only used in a message; `break` exits only the inner loop; the "kept
   unchanged" message only runs when `all_maps` is `nil`; a saved space not
   found in the maps is used as is.

1. **`validateEnvironment` depends on `pairs` order** (`environment.lua`) and
   `processEnvironment` sorts screens by `x` only. Iterate sorted keys; sort by
   `x`, then `y`.

1. **`getFrameState` ignores the screen origin** (`plumbing.lua`), so
   left/right/full detection is wrong on secondary monitors. The saved `screen`
   (a screen ID) is not stable across reconnections and is unused.

1. **Small items.** `validateScreen` uses `match("hs.screen")` (`.` is a
   wildcard); `verbose or rs.verbose` cannot be overridden with `false`; porcelain
   iterates desktops with `pairs`; `recursiveKeysAreStrings` concatenates
   non-strings; some comments still say `mod.`; `packagePath` hardcodes
   `~/.hammerspoon/hs/restore_spaces/` and needs the `tmp/` folder; the example
   in this README uses `local hs = {}`, which shadows the global `hs`.

1. **New code (macOS 15+) to double check when tested.** The `AXRemoveDesktop`
   action and the fallback to the thumbnail's child buttons are based on third
   party reports; the drop point on `WindowManager` thumbnails uses `AXPosition`
   as reported in the PaperWM.spoon PR; the starting mouse event number (32000)
   is a guess; "Displays have separate Spaces" turned off is not handled by
   `findDisplay` beyond the single-display case.

1. **Renaming.** The package should incorporate better names for its elements
   and functions; e.g. "environment" should be renamed to "profile", and the
   provisional "realign" (maybe "rearrange"). All other words in the package
   should be revised to ensure comprehension and an elegant implementation.

1. **Actions as combinations of steps.** `save` and `apply` could become
   _recipes_ that combine steps (record, place, realign, and later close/open
   apps) bound to a hotkey, like the rules and recipes of LaTeX Workshop; a step
   such as realign could then get a different visibility value in each recipe.
   Also add a **soft** (record/move only) and a **hard** (close the apps after
   saving, open them before applying) version of `save` and `apply`.

1. **Environment identity and frames.** An environment is the ordered list of
   monitor names, so another arrangement (Z,X,Y instead of X,Y,Z) is another
   environment. Resolution and vertical position are not part of it yet. Frames
   are saved in global coordinates; save them relative to their monitor.

1. **Realigning windows.** Notes for debugging:
   - Windows larger than their monitor get a capped requirement (a window can
     never be 100% visible); this is a possible culprit if windows misbehave.
   - Windows assigned to several desktops and apps with their own placement
     rules are skipped or can refuse the move (a warning is shown).
   - The cause of lost windows is unknown; `realign` always counts the windows
     below 50% visibility, even with `min_window_visibility = 0`.
   - `window_selection = "owner"` (internal) assigns windows to the screen of
     their desktop instead of the screen of their frame, which is probably how
     lost windows end up attributed to another monitor. The "test" report lists
     the windows where both differ; evaluate before making it the default.
   - `save` records windows assigned to several desktops once per desktop.

1. **Desktop creation limit.** A monitor holds 16 spaces, full-screen ones
   included, before macOS hides the "+" button. Verified on macOS 27.0.1:
   dragging a desktop from another monitor onto a monitor that already has 16
   spaces works (`createSpaceByMoving`, about 5 s). Not verified: other macOS
   versions, and whether the limit (`space_limit`) is the same there.

1. **AirPlay and other virtual displays** (iPad/Sidecar, a Mac as a display)
   appear as monitors and change the environment. Add a list of screens to
   ignore, applied to the screen list and to `validateEnvironment`.

1. **Verbosity levels.** `rs.verbose` accepts `false`, `true` or a number
   (`getVerbosity`) and `issueVerbose(text, verbose, level)` takes a level, but
   no message has a level yet (1 key steps, 2 per space/window, 3 states,
   4-5 internals). Add a log file and a support report. `issueVerbose` prints
   `(unknown)` in anonymous functions.

1. **Configurable title-bar grab point and batched moves.** `"titlebar"` grabs
   10 px right of the zoom button (apps with tabs there need `move_apps`), and
   every `"mission_control"` move opens and closes Mission Control; batching the
   moves of a desktop would make `apply` faster.

1. **Project refactor.** The files are very uneven: `spaces.lua` holds the
   Mission Control access, the move strategies, the desktop creation and the
   diagnostic, and `porcelain.lua` has two functions of about 150 lines. Split by
   topic (_e.g._ `mission_control.lua`, `moves.lua`, `diagnostic.lua`), break
   `getEnvironmentState` and `setEnvironmentState` into steps, and split
   `testSpaceControl` into one helper per section of its report.

1. **`Unable to fetch NSRunningApplication for pid` in the console** during
   `apply`. Hammerspoon logs it when `hs.window:application()` is called on a
   window of a process without an application object (_e.g._ a helper or an app
   that just quit). It is harmless; avoid it by filtering the windows by process
   before calling it.

1. **Over/underscan: displays probe.** On macOS 27.2 the probe shows the skeleton
   of the pane (window, group, split group, content group, two scroll areas, an
   "Add" menu button), but the scroll areas look empty. It now also lists
   `AXContents`/`AXVisibleChildren` and the attribute names of scroll areas. Run
   it again with a monitor that has a scan setting selected (the TV), before and
   after changing the scan.

1. **Scan restore after the display sleeps.** `apply display scan` failed twice
   with "the Displays pane did not open" after the monitors slept, although the
   pane was open. Suspected cause: accessibility only lists the windows of the
   active desktop, so a System Settings window on another desktop (or one that
   did not wake up) is invisible. System Settings is now restarted once when the
   pane does not show up, and the error says what was seen. Not verified.

1. **Recognition by elimination.** A window whose only tab changed its title
   (_e.g._ a streaming page that shows the browser name after a restart) is not
   recognized even if it is the only window of the app left. Pairing the last
   unmatched window with the last unmatched saved window of the same app would
   catch it, but only at the end of the run, when the desktops were already
   visited.

1. **Tab counts from accessibility are higher than the visible tabs.** Firefox
   gives 9 for a window with 3 tabs and 64 for one with 58 (6 more, twice).
   Recognition is not affected (both sides are read alike), but shared extras
   make small windows look alike. `probeTabs` lists what is counted.

1. **Order of the spaces.** `apply` makes each full-screen space from the desktop
   that preceded it, last slot first, expecting macOS to insert the new space
   right after that desktop (unverified: see the "Space order" note of the
   summary). A full-screen space that was before the first desktop cannot be
   made that way, and desktops that were created are appended. Dragging
   thumbnails (`probeSpaceReorder`) is still unreliable.

1. **Refactor.** Pending split: `spaces.lua` (Mission Control, moves,
   diagnostics), `plumbing.lua` (statistics, summary, realign, updates),
   `applescript.lua` (tabs, cycling), and the `#` splitting of `compareTabs`
   into `legacy.lua`.
