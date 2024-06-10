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