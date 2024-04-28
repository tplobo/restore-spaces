# restore-spaces

Hammerspoon implementation to restore organization of windows throughout
spaces on MacOS.

## Installation

1. Install [spaces module](https://github.com/asmagill/hs._asm.spaces)
   for Hammerspoon:

- Download `spaces-v0.x-universal.tar.gz`
- Place it in your `.hammerspoon` folder and extract it:

```
cd ~/.hammerspoon
tar -xzf ~/Downloads/spaces-v0.x.tar.gz
```

2. Copy the `restore_spaces.lua` module into your `.hammerspoon` folder.

3. Copy the `init.lua` file into your `.hammerspoon` folder, or import the
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

4. Open the Hammerspoon app and select `Reload Config`.

## Usage

1. Press "save" hotkey combination to save current state.

   <kbd>Ctrl</kbd> + <kbd>Opt</kbd> + <kbd>Cmd</kbd> + <kbd>S</kbd>

2. Press "apply" hotkey combination to restore that state.

   <kbd>Ctrl</kbd> + <kbd>Opt</kbd> + <kbd>Cmd</kbd> + <kbd>A</kbd>
