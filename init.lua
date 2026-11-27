-- `init.lua`

local restore_spaces = require 'hs.restore_spaces.restore_spaces'

-- Configure 'restore_spaces' (the values below are the defaults)
restore_spaces.verbose = false -- console detail: false, 1 (key steps), 3 (all messages)
restore_spaces.log_titles = false -- show window and tab titles in the console (they are private data)
restore_spaces.min_window_visibility = 0 -- 0-1: fraction of each window that must be visible (0: off)
restore_spaces.restore_scan = true -- also save and restore the over/underscan of the monitors

-- Bind hotkeys for 'restore_spaces'
hs.hotkey.bind({"cmd", "alt", "ctrl"}, "S", restore_spaces.saveEnvironmentState)
hs.hotkey.bind({"cmd", "alt", "ctrl"}, "A", restore_spaces.applyEnvironmentState)
hs.hotkey.bind({"cmd", "alt", "ctrl"}, "O", restore_spaces.applyScan)