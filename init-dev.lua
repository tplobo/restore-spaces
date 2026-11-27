-- `init-dev.lua` (installed as `init.lua` by `zsh install.sh --dev`)

local restore_spaces = require 'hs.restore_spaces.restore_spaces'

-- Configure 'restore_spaces'
restore_spaces.build = "build 1" -- development label, shown in the console and the summary
restore_spaces.verbose = 1
restore_spaces.log_titles = true -- development only: set to false before sharing logs
restore_spaces.space_pause = 0.3
restore_spaces.screen_pause = 0.4
restore_spaces.min_window_visibility = 0
restore_spaces.restore_scan = true
restore_spaces.check_updates = false

-- Bind hotkeys for 'restore_spaces'
hs.hotkey.bind({"cmd", "alt", "ctrl"}, "S", restore_spaces.saveEnvironmentState)
hs.hotkey.bind({"cmd", "alt", "ctrl"}, "A", restore_spaces.applyEnvironmentState)
hs.hotkey.bind({"cmd", "alt", "ctrl"}, "V", restore_spaces.applyAndCheck)
hs.hotkey.bind({"cmd", "alt", "ctrl"}, "R", restore_spaces.realignWindows)
hs.hotkey.bind({"cmd", "alt", "ctrl"}, "O", restore_spaces.applyScan)
hs.hotkey.bind({"cmd", "alt", "ctrl"}, "T", restore_spaces.testSpaceControl)