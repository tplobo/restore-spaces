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

3. Copy the `restore_spaces.lua` module into your `.hammerspoon` folder.

4. Copy the `init.lua` file into your `.hammerspoon` folder, or import the
   module and set your preferred configurations and hotkey combinations in your
   own `.hammerspoon/init.lua` file to avoid conflicts with other modules, for
   example:

```
local restore_spaces = require 'restore_spaces'

restore_spaces.mode = "quiet"
restore_spaces.pause = 0.3

hs.hotkey.bind({"cmd", "alt", "ctrl"}, "S", restore_spaces.saveSpacesStates)
hs.hotkey.bind({"cmd", "alt", "ctrl"}, "A", restore_spaces.applySpacesStates)
```

5. Open the Hammerspoon app, enable it in Accessibility, restart it and select
   `Reload Config`.

## Usage

1. Press the "save" hotkey combination to save current state.

   _e.g._: <kbd>Ctrl</kbd> + <kbd>Opt</kbd> + <kbd>Cmd</kbd> + <kbd>S</kbd>

2. Press the "apply" hotkey combination to restore that state.

   _e.g._: <kbd>Ctrl</kbd> + <kbd>Opt</kbd> + <kbd>Cmd</kbd> + <kbd>A</kbd>

## Development

Current features under development; any help is appreciated:

- Fix restore for two windows in Fullscreen, Tile left and Tile right, which
  current does not work (afaik, cannot be implemented).
- Add functionality for multiple monitors (_e.g._ move space to other monitor).
- Set multiple save-state JSON files, for different work environments (_e.g._
  office and home office), based on the list of monitors connected to Mac.
- ...
