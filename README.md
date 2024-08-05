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

   > ⚠️ **Note:** As of macOS 14.5, some `spaces` functions [do not work correctly](https://github.com/Hammerspoon/hammerspoon/pull/3638). As a temporary solution, the Hammerspoon
   > [build by user `gartnera`](https://github.com/gartnera/hammerspoon/releases/tag/0.10.0)
   > can be used instead ((_vide_ **Known Issues**)).

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
   hs.restore_spaces = require 'hs.restore.spaces.restore_spaces'

   -- Configure 'restore_spaces'
   hs.restore_spaces.verbose = false
   hs.restore_spaces.space_pause = 0.3
   hs.restore_spaces.screen_pause = 0.4

   -- Bind hotkeys for 'restore_spaces'
   hs.hotkey.bind({"cmd", "alt", "ctrl"}, "S", hs.restore_spaces.saveState)
   hs.hotkey.bind({"cmd", "alt", "ctrl"}, "A", hs.restore_spaces.applyState)
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

## Usage

1. Press the "save" hotkey combination to save current state.

   _e.g._: <kbd>Ctrl</kbd> + <kbd>Opt</kbd> + <kbd>Cmd</kbd> + <kbd>S</kbd>

1. Press the "apply" hotkey combination to restore that state.

   _e.g._: <kbd>Ctrl</kbd> + <kbd>Opt</kbd> + <kbd>Cmd</kbd> + <kbd>A</kbd>

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
  **Known Issues**).

Current features under development; any help is appreciated:

- Add a `notifyUser` call if `gotoSpace` fails due too short pause setting.
- Add better logging to produce debugging reports.
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
   fullscreen mode, so the current approach is to place all windows that had a fullscreen
   state (split-view or not) into single fullscreen. Split-view has to be set
   manually by the user (with the mouse) after calling `applyEnvironmentState`.

1. **Window IDs change when you close/open an app.** The current implementation is
   able to restore a window to a desired space during `apply` if that window
   title is the same as it was during the `save` call. If the title changes for
   any reason, that window will not be recognized.
   In the particular case of apps in which windows can have multiple tabs, the
   title tends to coincide with the title of the tab currently selected. This
   is taken into account by the module with the `multitab_apps` settings, which
   specifies for which apps the `save` and `apply` functions may cycle through
   all tabs of each window to gather a list of titles. This is done using a
   custom function developed in `applescript`. Windows are then restored during
   `apply` by determiing whether they have a counterpart in the saved states,
   by comparing the current list of tabs with the saved one. Thresholds for
   what is considered a "counterpart" are defined by the `multitab_comparison`
   setting, by establishing a fraction of the list of tabs that must coincide
   (regardless of the order). Two fractions are defined, for comparing "short"
   and "long" tab lists, with the number of tabs that switches between them
   defined in `critical_tab_count`.
   Unfortunately, the process of cycling through all tabs also loads them,
   which might be undesireable. No workaround has been found yet.

1. The function `spaces.moveWindowtoSpace` function [stopped working in MacOS
   14.5](https://github.com/Hammerspoon/hammerspoon/pull/3638). The current
   solution is to use the Hammerspoon app build by the `gartnera` user in
   Github. This solution does not work when spaces are distributed across
   multiple screens/monitors, so a [follow-up solution](https://github.com/Hammerspoon/hammerspoon/pull/3638#issuecomment-2252826567) was proposed by `cunha`,
   which slightly increases the delay time of processing each Space. To avoid
   this increase in unnecessary cases, a switch for this is implemented as the
   `spaces_fixed_after_macOS14_5` global variable. It might become obsolete
   after the `spaces` extension is updated to work with **Sonoma 14.5** in the
   Hammerspoon repo itself.
