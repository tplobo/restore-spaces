local restore_spaces = require 'restore_spaces'

-- Configure 'restore_spaces'
restore_spaces.mode = "quiet"
restore_spaces.pause = 0.3

-- Bind hotkeys for 'restore_spaces'
hs.hotkey.bind({"cmd", "alt", "ctrl"}, "S", restore_spaces.saveSpacesStates)
hs.hotkey.bind({"cmd", "alt", "ctrl"}, "A", restore_spaces.applySpacesStates)