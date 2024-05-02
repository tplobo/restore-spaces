# Hammerspoon Module: restore-spaces

Hammerspoon implementation to restore organization of windows throughout
spaces on MacOS.

## Installation

1. If you do not have [**Homebrew**](https://brew.sh) yet, install it and
   install [Hammerspoon](https://www.hammerspoon.org) for Mac automation:

```
brew install --cask hammerspoon
```

2. Install the [spaces module](https://github.com/asmagill/hs._asm.spaces)
   for Hammerspoon:

- Download `spaces-v0.x-universal.tar.gz`
- Place the file in your `.hammerspoon` folder and extract it:

```
cd ~/.hammerspoon
tar -xzf ~/Downloads/spaces-v0.x.tar.gz
```

3. Run `install.sh` to copy both `init.lua` and `restore_spaces.lua` files
   into your `.hammerspoon` folder:

   ```
   zsh install.sh
   ```

   or just copy `restore_spaces.lua` and import the module in your own
   `.hammerspoon/init.lua` file to avoid conflicts with other modules.

4. Set your preferred configurations and hotkey combinations, for example:

```
local hs = {}
hs.hotkey = require "hs.hotkey"
hs.restore_spaces = require 'restore_spaces'

-- Configure 'restore_spaces'
hs.restore_spaces.mode = "quiet"
hs.restore_spaces.space_pause = 0.3
hs.restore_spaces.screen_pause = 0.4

-- Bind hotkeys for 'restore_spaces'
hs.hotkey.bind({"cmd", "alt", "ctrl"}, "D", hs.restore_spaces.detectEnvironment)
hs.hotkey.bind({"cmd", "alt", "ctrl"}, "S", hs.restore_spaces.saveState)
hs.hotkey.bind({"cmd", "alt", "ctrl"}, "A", hs.restore_spaces.applyState)
```

5. Open the Hammerspoon app, enable it in Accessibility, restart it and select
   `Reload Config`.

6. Run the commands a few times to check whether the `space_pause` and
   `screen_pause` settings comply with your mac. They might need to be
   increased if the console issues:
   ```
   ... attempt to index a nil value (local 'child')
    stack traceback:
   ...: in function 'hs.spaces.gotoSpace' ...
   ```

## Usage

1. Press the "save" hotkey combination to save current state.

   _e.g._: <kbd>Ctrl</kbd> + <kbd>Opt</kbd> + <kbd>Cmd</kbd> + <kbd>S</kbd>

2. Press the "apply" hotkey combination to restore that state.

   _e.g._: <kbd>Ctrl</kbd> + <kbd>Opt</kbd> + <kbd>Cmd</kbd> + <kbd>A</kbd>

## Development

Following features have already been implemented:

- Add functionality for multiple monitors (_e.g._ move space to other monitor).
- Save JSON files with multiple save-state, for different work environments
  (_e.g._ office and home office), based on the list of monitors connected to
  Mac.
- Ask name of environment when saving state for inclusion in JSON files.

Current features under development; any help is appreciated:

- Add a `notifyUser` call if `gotoSpace` fails due too short pause setting.
- Fix restore for two windows in Fullscreen, Tile left and Tile right, which
  current does not work (afaik, cannot be implemented).
- Ensure save/apply do not consider hidden windows.
- Fix restore for when current number of screens is different than the number
  of saved ones.
- Ask if the name of new environment should overwrite an environment already
  saved.
- Check functionalities if/when space IDs change with space deletion/creation.
- Add tests.
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
   The current studied solution is to forcefully deactivate the
   dashboard, but it does not always work:
   ```
   defaults write com.apple.dashboard mcx-disabled -boolean YES
   killall Dock
   ```
