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
   install [Hammerspoon](https://www.hammerspoon.org) for Mac automation:

```
   brew install --cask hammerspoon
```

already including the [spaces module](https://github.com/asmagill/hs._asm.spaces)
in its latest version.

> ⚠️ **Note:** From macOS 15 on, the native `hs.spaces` functions that move
> windows (and, from macOS 26/27 on, those that switch, add and remove
> spaces) do not work
> ([#3698](https://github.com/Hammerspoon/hammerspoon/issues/3698),
> [#3897](https://github.com/Hammerspoon/hammerspoon/issues/3897)). This
> module detects the macOS version and replaces them with its own
> implementation (_vide_ **Moving windows on macOS 15+** below). It needs
> Hammerspoon 1.1.1 or above, with Accessibility permission enabled.

<br>

2. Run `install.sh` to copy the `init.lua` file and the `restore_spaces` folder
   and into your `.hammerspoon` directory:

```
   zsh install.sh
```

or just copy `restore_spaces` into `.hammerspoon/hs`, and import the module
in your own `.hammerspoon/init.lua` file to avoid conflicts with other
modules.

<br>

3. Set your preferred configurations and hotkey combinations, for example:

```
   local hs = {}
   hs.hotkey = require "hs.hotkey"
   hs.restore_spaces = require 'hs.restore_spaces.restore_spaces'

   -- Configure 'restore_spaces'
   hs.restore_spaces.verbose = false
   hs.restore_spaces.space_pause = 0.3
   hs.restore_spaces.screen_pause = 0.4

   -- Bind hotkeys for 'restore_spaces'
   hs.hotkey.bind({"cmd", "alt", "ctrl"}, "S", hs.restore_spaces.saveEnvironmentState)
   hs.hotkey.bind({"cmd", "alt", "ctrl"}, "A", hs.restore_spaces.applyEnvironmentState)
   hs.hotkey.bind({"cmd", "alt", "ctrl"}, "T", hs.restore_spaces.testSpaceControl)
```

<br>

4. Open the Hammerspoon app, enable it in Accessibility, restart it and select
   `Reload Config`.

<br>

5. Run the commands a few times to check whether the `space_pause` and
   `screen_pause` settings comply with your mac. They might need to be
   increased if the console prints:

```
   ... attempt to index a nil value (local 'child')
    stack traceback:
   ...: in function 'hs.spaces.gotoSpace' ...
```

6. Run the commands a few times with multi-tab apps open to check whether the
   settings of the function defined in `getVisibleTabs.applescript` comply with
   your mac. In particular, the `tabDelay` setting in `scp/scp_config.json`
   might need to be increased if cycling through tabs seems to be stopping
   before all tabs are cycled through. This is can be true if, _e.g._ loading
   unloaded tabs takes longer than the value in `tabDelay`. For more
   information, _vide_ item **Window IDs change...** in **Known Issues**.

7. On macOS 15 or above, focus any window on a screen with two or more
   desktops and press the "test" hotkey. It switches desktops, moves that
   window to another desktop and back, and prints a report (timings, results
   and a dump of the Mission Control accessibility tree) to the Hammerspoon
   console. Please attach it (with window titles redacted) to any bug report.

## Usage

1. Press the "save" hotkey combination to save current state.

   _e.g._: <kbd>Ctrl</kbd> + <kbd>Opt</kbd> + <kbd>Cmd</kbd> + <kbd>S</kbd>

1. Press the "apply" hotkey combination to restore that state.

   _e.g._: <kbd>Ctrl</kbd> + <kbd>Opt</kbd> + <kbd>Cmd</kbd> + <kbd>A</kbd>

## Moving windows on macOS 15+

Up to macOS 14, the native `hs.spaces` functions are used. From macOS 15 on,
`hs.spaces.moveWindowToSpace` returns `true` without moving anything, and from
macOS 26/27 on the Mission Control accessibility tree moved from the Dock to
the `WindowManager` process, which also breaks `gotoSpace`, `addSpaceToScreen`
and `removeSpace`. The module therefore tries the native function first
(except for moving) and otherwise drives Mission Control itself:

- **Switch/add/remove spaces:** presses the desktop thumbnails (or the add
  button) through the accessibility API.
- **Move windows:** drags the window thumbnail onto the target desktop
  thumbnail with a timed, multi-step synthetic drag (single jumps are ignored by
  recent macOS versions), and verifies that the window actually arrived.

Consequences and limitations:

- Mission Control visibly opens and closes for each operation, so `apply` is
  slower than on macOS 14. The cursor is moved temporarily and restored.
- The window must be visible on the active space of its screen (guaranteed by
  the way `apply` cycles through spaces).
- Windows are identified in Mission Control by title. Windows with identical
  titles are indistinguishable (the first thumbnail is used).
- **Fallback behavior:** if a window cannot be moved to its target desktop (_e.g._
  the move to a desktop of a different monitor does not work on your macOS
  version), it is moved to the **first** (or **last**, with
  `rs.fallback_space = "last"`) desktop of the target monitor; if that fails
  too, it is moved to the target monitor itself. A warning is printed to the
  console for each such window and a notification is shown at the end of
  `apply`.
- Status: macOS 14 uses the previous (verified) code path. The other paths are
  **untested** at the time of writing: macOS 15 and 26 have not been verified
  by anyone, and macOS 27.0 has only been verified by third parties for the
  approach in general. Timings can be tuned with `rs.mc_timeout`,
  `rs.mc_pause`, `rs.mc_settle`, `rs.mc_drag_steps` and `rs.mc_drag_pause`.

### Acknowledgements

The approach (Mission Control through the accessibility tree, pressing
thumbnails with `AXPress`, a timed drag that shares one mouse event number,
reading the tree from `WindowManager` with a Dock fallback) was inspired by:

- [`Drag.spoon`](https://github.com/mogenson/Drag.spoon) and
  [`PaperWM.spoon`](https://github.com/mogenson/PaperWM.spoon),
  in particular
  [PR #174](https://github.com/mogenson/PaperWM.spoon/pull/174) and
  [issue #173](https://github.com/mogenson/PaperWM.spoon/issues/173).
- Hammerspoon issues
  [#3698](https://github.com/Hammerspoon/hammerspoon/issues/3698) and
  [#3897](https://github.com/Hammerspoon/hammerspoon/issues/3897), and their
  contributors.

## Development

Following features have already been implemented:

- Add functionality for multiple monitors (_e.g._ move space to other monitor).
- Save JSON files with multiple save-state, for different work environments
  (_e.g._ office and home office), based on the list of monitors connected to
  Mac. The saved states are unique for each set and order of monitors (\_i.e.,
  an "envirnment").
- Ask name of environment when saving state for inclusion in JSON files.
- Fix restore for when current number of screens is different than the number
  of saved ones.
- Check functionalities if/when space IDs change with space deletion/creation.
- Add a workaround to deal with the phantom dashboard space (_vide_ **Known
  Issues**).
- Fix restore for windows that have empty title.
- Fix restore for a list of spaces that has their order changed, by using a
  `space_map` variable to store the order of space IDs.
- Fix restore for windows that changed their ID after app restart (_vide_
  item **Window IDs change...** in **Known Issues**).
- Move windows, switch, add and remove spaces on macOS 15+ (_vide_ **Moving
  windows on macOS 15+**), selected by detecting the macOS version.

Current features under development; any help is appreciated:

- Fix the problems listed in **TODO** (Item 1, high priority).
- Modernize logging to produce debugging reports (levels, log file, redaction
  of titles, one-shot diagnostic dump).
- Refactor the package (shared helpers, fewer nested loops, stable data schema
  with migration of old JSON files).
- Handle windows in fullscreen spaces (currently only restored as single
  fullscreen, _vide_ **Known Issues**).
- Optional "Switch to Desktop N" keyboard-shortcut fallback for `gotoSpace` (only
  if Mission Control proves unreliable).
- Add a `notifyUser` call if `gotoSpace` fails due too short pause setting.
- Fix restore for two windows in Fullscreen, Tile left and Tile right, which
  current does not work (afaik, cannot be implemented).
- Ensure save/apply do not consider hidden windows.
- Ask if the name of new environment should overwrite an environment already
  saved.
- Add a user variable that enforces a maximum number of spaces or a list of
  space indexes, per screen, that are restored by the functions (so that spaces
  manipulation is limited).
- Modify functions to create "profiles" instead of "environment" states, as
  to allow for multiply profiles in the same environment.
- Add tests with mocking, due to the dependence on mac features.
- ...

To use a development version of the `spaces` module, install it from its
[repo](https://github.com/asmagill/hs._asm.spaces) package:

- Download `spaces-v0.x-universal.tar.gz`
- Extract it in your `.hammerspoon` folder:

```
cd ~/.hammerspoon
tar -xzf ~/Downloads/spaces-v0.x.tar.gz
```

## TODO

Problems found by reading the code (nothing here was run). Each item states
where it is, what goes wrong and the suggested fix. Fixing them is independent
of the macOS 15+ work, except where noted. Ordered by severity.

1. **Saving wipes other environments' window data** (`porcelain.lua`,
   `getEnvironmentState`). `rs.data_wins` starts as `{}` and is never read
   before `rs.data_wins[env_name] = env_state` is written back with
   `processDataInFile("write","windows")`. After a Hammerspoon reload, saving
   environment B overwrites the file with only B, so applying A later fails with
   "State for environment has never been saved!". Fix: call
   `rs.data_wins = rs.processDataInFile("read","windows")` before assigning.

1. **Tab similarity thresholds never apply** (`applescript.lua`, `compareTabs`;
   `utilities.lua`, `list2dict`). `list2dict` builds string keys ("1","2",...),
   and JSON decoding returns string keys too, so `#window_tabs` and
   `#stored_tabs` are `0`. The ratios become `inf`/`NaN`, so any single shared
   title counts as a match (the `isNaN` guards hide this). Fix: count entries
   with a helper that iterates `pairs`, or store tabs as arrays (note that JSON
   objects lose order; arrays do not).

1. **`apply` runs the multitab refinement inside the per-window loop**
   (`porcelain.lua`, `setEnvironmentState`). The `--refineSpaceState:` block is
   nested inside the `else` of the empty-title check, inside
   `for _, window in ipairs(space_windows)`, so the AppleScript tab cycling and
   the matching re-run for every non-empty-title window. It also calls
   `setWindowState(window, ...)` with the loop variable `window`, which is not
   necessarily the window with `window_id`, so the wrong window can be moved.
   `getEnvironmentState` does this correctly (after the loop). Fix: move the
   block after the window loop and look the window up by `window_id`
   (_e.g._ `hs.window.get(tonumber(window_id))`).

1. **Non-multitab title match passes the wrong state** (`porcelain.lua`,
   `setEnvironmentState`). It calls `setWindowState(window, window_state, ...)`
   with the _current_ state, which has no `screen`/`space` fields (so the target
   space is `nil`), instead of `stored_state`. The loop has no `break` after a
   match and calls `rs.rename_key(env_state, ...)` while iterating `env_state`
   with `pairs`, which is undefined behavior in Lua (assigning new keys during
   traversal) and can rename several stored states onto one window ID. Fix: pass
   `stored_state`, collect the match first, then rename and `break`.

1. **`runApplescript` does not quote its arguments** (`applescript.lua`). The
   command is built by concatenation, so `"Google Chrome"` (in `multitab_apps`)
   is split into two arguments and a plist path with spaces breaks too. Fix:
   quote both arguments (_e.g._ single quotes with escaping) or use `hs.task`.

1. **AppleScript consecutive-title counter never resets**
   (`getVisibleTabs.applescript`, `getWindowTabs`). It increments and checks
   `counterIdenticalConsecutives` but resets `identicalTabCounter` (different
   variable), so non-consecutive repeats accumulate and can end the cycle early.
   Fix: reset `counterIdenticalConsecutives` to 0 in the `else` branch.

1. **Error handling around AppleScript/plist/loops** (`applescript.lua`,
   `porcelain.lua`). `run` returns `errMsg` as if it were data, so
   `buildTabList` silently yields an empty list; titles containing `", "` or
   `"###"` break the delimiter-based parsing; an error between
   `processPlistConfig("create")` and `("destroy")` leaves the plist behind;
   an error mid-loop leaves the user on a different space (the final
   `gotoSpace(initial_space)` is skipped). Fix: return/raise errors explicitly
   from AppleScript (prefer JSON output), and wrap the bodies in `pcall` so that
   cleanup (destroy plist, return to `initial_space`) always runs before
   re-raising.

1. **`setWindowState` target handling** (`plumbing.lua`).
   - `target_screen` changes type (number from the state, then a `"001"` index).
     It is only used in a log message now (screen moves are handled by
     `rs.moveWindowToSpace`), so it can be removed.
   - `break` only exits the inner loop; the outer `pairs(all_maps)` keeps going.
   - The "kept unchanged" message only runs when `all_maps` is `nil`, not when no
     match is found.
   - If no match is found, the saved space ID is used as is, even if it no longer
     exists. Fix: use a helper that returns `target_space` or `nil`, and log
     the no-match case.

1. **`getAppTabsInSpace` aliases and mutates its argument** (`applescript.lua`).
   `app_tabs = id2title` and then `app_tabs[id] = ...` overwrites the caller's
   titles with tables. Windows whose first tab matches no title keep the _string_
   title, so saved `tabs` is sometimes a string and sometimes a table. Duplicate
   titles overwrite each other. Fix: build a new table, always store tables, and
   match by identity (_e.g._ by order) when titles repeat.

1. **`validateEnvironment` depends on `pairs` order** (`environment.lua`). Monitor
   lists are built with `pairs` over string keys ("001", "002"), whose order is
   arbitrary, so `hs.inspect(saved) == hs.inspect(current)` may fail on a valid
   match. `processEnvironment` also sorts screens by `x` only (ties for vertical
   layouts). Fix: iterate sorted keys; sort by `x` then `y`.

1. **`retrieveEnvironmentEntities("spaces", screen)` may pass `nil` to
   `validateSpaces`** (`environment.lua`). `hs.spaces.spacesForScreen` can return
   `nil`; only the "all screens" branch handles that, so `ipairs(nil)` raises.
   Fix: `all_entities = ... or {}` in the screen branch.

1. **`validateSpaces` plist handling** (`plumbing.lua`). If the plist read fails
   it only prints and then fails with a misleading "Value is not a table" error
   (fail early with a clear message). It indexes
   `Monitors[screen_i]` using `hs.screen.allScreens()` order, which may differ
   from the plist order on multi-monitor setups. `uuid` can be `nil`, which
   breaks the debug concatenation. The key path is untested on macOS 27; if it
   changed, the error should name the missing key (it does) and the dashboard
   filter could use `hs.spaces.spaceType(id) ~= "system"` instead of the plist.

1. **`getFrameState` ignores the screen origin** (`plumbing.lua`). Left/right
   edge and full-width checks compare global frame coordinates with
   `screen_frame.w` and `0`, which is wrong on secondary monitors (origin ≠ 0).
   Fix: subtract `screen_frame.x`/`y`. Also, the saved `screen` field is a
   `screen:id()`, which is not stable across reconnections and is not used on
   apply; store the screen index instead.

1. **`issueVerbose`/`validateSpaces` use `verbose = verbose or rs.verbose`**
   (`plumbing.lua`). An explicit `false` cannot override `rs.verbose = true`.
   Fix: `if verbose == nil then verbose = rs.verbose end`. Other small items:
   `validateScreen` uses `match("hs.screen")` where `.` is a wildcard (use a
   real type check); porcelain iterates space arrays with `pairs` instead of
   `ipairs`; `recursiveKeysAreStrings` concatenates non-strings; leftover
   comments still say `mod.` instead of `rs.`.

1. **Install and layout** (`install.sh`, `utilities.lua`, README).
   `install.sh` copies `init.lua` over an existing `~/.hammerspoon/init.lua`
   (back it up or merge); `packagePath` hardcodes
   `~/.hammerspoon/hs/restore_spaces/` and the `tmp/` folder must exist
   (`io.open(...,'w')` fails silently otherwise); the README example uses
   `local hs = {}`, which shadows Hammerspoon's global `hs` in that file.

1. **New code (macOS 15+) to double check when tested.** The `AXRemoveDesktop`
   action and the fallback to the thumbnail's child buttons are based on third
   party reports; the drop point on `WindowManager` thumbnails uses `AXPosition`
   as reported in the PaperWM.spoon PR; the starting mouse event number (32000) is
   a guess; "Displays have separate Spaces" turned off is not handled by
   `findDisplay` beyond the single-display case.

## Known issues

1. The **"Dashboard"** feature may create a hidden space that cannot be
   accessed, and thus breaks the `hs.spaces.gotoSpace()` method, even in MacOS
   versions that do not feature Dashboard anymore. This can be see in the
   spaces plist file, for example:

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

The solution of forcefully deactivating the dashboard [has been
studied](https://discussions.apple.com/thread/255600670), but it does
not work and there are [no alternative official solutions
](https://forums.developer.apple.com/forums/thread/751143) so far:

```
   defaults write com.apple.dashboard mcx-disabled -boolean YES
   killall Dock
```

Instead, that `plist` file is read and used to validate the list of spaces
used to save the environment state.

1. There are no official APIs for putting two windows in **split-view**
   fullscreen mode, so the current approach is to place all windows that had a
   fullscreen state (split-view or not) into single fullscreen. Split-view has
   to be set manually by the user (with the mouse) after calling
   `applyEnvironmentState`.

1. In **Sonoma 14.5**, the function `spaces.moveWindowtoSpace` function
   [stopped working](https://github.com/Hammerspoon/hammerspoon/pull/3638), and
   it was fixed in Hammerspoon 1.0.0. The former `spaces_fixed_after_macOS14_5`
   switch and its workaround have been removed; the module now selects the
   strategy from the macOS version (_vide_ **Moving windows on macOS 15+**).

1. In **macOS 15 and above**, `spaces.moveWindowtoSpace` returns `true` without
   moving the window
   ([#3698](https://github.com/Hammerspoon/hammerspoon/issues/3698)), and in
   **macOS 26/27** the Mission Control based functions fail too
   ([#3897](https://github.com/Hammerspoon/hammerspoon/issues/3897)). They are
   replaced by this module's own implementation, with the limitations described
   in **Moving windows on macOS 15+** (visible Mission Control, title-based
   window identification, fallback to the first/last desktop of the target
   monitor). These code paths are not yet verified on real machines.

1. **Window IDs change when you close/open an app.** The current implementation
   is able to restore a window to a desired space during `apply` if that window
   title is the same as it was during the `save` call. If the title changes for
   any reason, that window will not be recognized.

   In the particular case of apps in which windows can have multiple tabs, the
   title tends to coincide with the title of the tab currently selected. This
   is taken into account by the module with the `multitab_apps` settings, which
   specifies for which apps the `save` and `apply` functions may cycle through
   all tabs of each window to gather a list of titles. This is done using a
   custom function developed in `applescript`. Windows are then restored during
   `apply` by determining whether they have a counterpart in the saved states,
   by comparing the current list of tabs with the saved one. Thresholds for
   what is considered a "counterpart" are defined by the `multitab_comparison`
   setting, by establishing a fraction of the list of tabs that must coincide
   (regardless of the order). Two fractions are defined, for comparing "short"
   and "long" tab lists, with the number of tabs that switches between them
   defined in `critical_tab_count`.

   Unfortunately, the process of cycling through all tabs also loads them,
   which might be undesireable. No workaround has been found yet.

1. The function defined in `getVisibleTabs.applescript` used to cycle through
   visible tabs in "multitab apps" needs to be modified to work with multiple
   monitors. It currently behaves poorly when more than one visible Desktop
   (_i.e._ a Space in focus) contains windows of apps defined as "multitab"
   apps; the **applescript cycles through visible tabs in all monitors**, in a
   similar way to how it cycles through visible tabs of multiple windows in a
   single Desktop. This means the generated tab lists do not distinguish
   between different displays. Suggestions on how to possibly circumvent this
   issue are appreciated.
