-- Import Hammerspoon modules
--hs.chooser = require 'hs.chooser'
hs.application = require 'hs.application'
hs.fnutils = require 'hs.fnutils'
hs.inspect = require 'hs.inspect'
hs.hotkey = require 'hs.hotkey'
hs.notify = require 'hs.notify'
hs.window = require 'hs.window'
hs.screen = require 'hs.screen'
hs.dialog = require 'hs.dialog'
hs.timer = require 'hs.timer'
hs.plist = require 'hs.plist'
hs.json = require 'hs.json'

-- Use default `spaces` module:
hs.spaces = require 'hs.spaces'
-- Use development `spaces` module (https://github.com/asmagill/hs._asm.spaces)
--hs.spaces = require 'hs.spaces_v04.spaces'

-- Initialize module `restore_spaces`
local rs = {}

-- Global variables (defaults)
--mod.mode = "quiet" -- "quiet" or "verbose"
rs.verbose = false
rs.space_pause = 0.3 -- in seconds (<0.3 breaks the spaces module)
rs.screen_pause = 0.4 -- in seconds (<0.4 breaks the spaces module)
rs.multitab_pause = 0.01 -- in seconds (=0 breaks tab lists comparison)
rs.multitab_comparison = {
    critical_tab_count = 10,            -- decides which threshold to use
    small_similarity_threshold = 0.8,   -- 80%, for a small number of tabs
    large_similarity_threshold = 0.6    -- 60%, for a large number of tabs
}
rs.multitab_apps = {"Google Chrome", "Firefox", "Safari"}
rs.config_path = "scp/scp_config"
rs.spaces_fixed_after_macOS14_5 = true
--TODO: mod.max_spaces = 0 (maximum number of spaces saved per screen)

-- Global variables (dynamic)
rs.data_wins = {} -- collected info for each window
rs.data_envs = {} -- collected info for each environment

-- Import utilities
require('hs.restore_spaces.rs.utilities')(rs, hs)

-- Import environment functions
require('hs.restore_spaces.rs.environment')(rs, hs)

-- Import applescript functions
require('hs.restore_spaces.rs.applescript')(rs, hs)

-- Import plumbing (private) functions
require('hs.restore_spaces.rs.plumbing')(rs, hs)

-- Import porcelain (public) functions
require('hs.restore_spaces.rs.porcelain')(rs, hs)

return rs