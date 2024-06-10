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

2. Install the [spaces module](https://github.com/asmagill/hs._asm.spaces)
   for Hammerspoon:

- Download `spaces-v0.x-universal.tar.gz`
- Extract it in your `.hammerspoon` folder:

```
cd ~/.hammerspoon
tar -xzf ~/Downloads/spaces-v0.x.tar.gz
```

3. Run `install.sh` to copy the `init.lua` file and the `restore_spaces` folder
   and into your `.hammerspoon` directory:

   ```
   zsh install.sh
   ```

   or just copy `restore_spaces` into `.hammerspoon/hs`, and import the module
   in your own `.hammerspoon/init.lua` file to avoid conflicts with other
   modules.

4. Set your preferred configurations and hotkey combinations, for example:

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

5. Open the Hammerspoon app, enable it in Accessibility, restart it and select
   `Reload Config`.

6. Run the commands a few times to check whether the `space_pause` and
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

Current features under development; any help is appreciated:

- Add a `notifyUser` call if `gotoSpace` fails due too short pause setting.
- Fix restore for windows that have empty title.
- Fix restore for windows that changed their ID after app restart (_vide_
  **Known Issues**).
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

## Known issues

1. The "Dashboard" feature may create a hidden space that cannot be accessed,
   and thus breaks the `hs.spaces.gotoSpace()` method, even in MacOS versions
   that do not feature Dashboard anymore. This can be see in the spaces plist
   file, for example:

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

   Instead, the `plist` file is read and used to validate the list of spaces
   used to save the environment state.

1. There are no official APIs for putting two windows in split-view fullscreen
   mode, so the current approach is to place all windows that had a fullscreen
   state (split-view or not) into single fullscreen. Split-view has to be set
   manually by the user (with the mouse) after calling `applyEnvironmentState`.

1. Window IDs change when you close/open an app. The current implementation
   needs to be changed to take into account this.
