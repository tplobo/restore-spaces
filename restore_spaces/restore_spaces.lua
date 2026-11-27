-- `restore_spaces.lua`

-- Import Hammerspoon modules
--hs.chooser = require 'hs.chooser'
hs.application = require 'hs.application'
hs.axuielement = require 'hs.axuielement'
hs.eventtap = require 'hs.eventtap'
hs.fnutils = require 'hs.fnutils'
hs.host = require 'hs.host'
hs.http = require 'hs.http'
hs.inspect = require 'hs.inspect'
hs.hotkey = require 'hs.hotkey'
hs.mouse = require 'hs.mouse'
hs.notify = require 'hs.notify'
hs.window = require 'hs.window'
hs.screen = require 'hs.screen'
hs.dialog = require 'hs.dialog'
hs.timer = require 'hs.timer'
hs.plist = require 'hs.plist'
hs.json = require 'hs.json'
hs.webview = require 'hs.webview'
hs.webview.usercontent = require 'hs.webview.usercontent'

-- Use default `spaces` module:
hs.spaces = require 'hs.spaces'
-- Use development `spaces` module (https://github.com/asmagill/hs._asm.spaces)
--hs.spaces = require 'hs.spaces_v04.spaces'

-- Initialize module `restore_spaces`
local rs = {}

-- Version of the module, and label of the development build being tested
rs.version = "0.4.0"
rs.build = false                        -- label of a development build (_e.g._ "build 8"), shown in the console and the summary

-- Global variables (defaults)
--mod.mode = "quiet"                    -- "quiet" or "verbose"
rs.verbose = false                      -- console detail: false/0 silent, 1 key steps, true/3 all messages, 5 everything
rs.log_titles = false                   -- show window and tab titles in the console (they are private data)
rs.banner_width = 72                    -- in characters, of the console banners
rs.show_summary = true                  -- show a summary window (with an OK button) after each action
rs.check_updates = false                -- look for a newer release on GitHub (at most every 12 hours) and say so in the summary
rs.repository = "tplobo/restore-spaces" -- GitHub repository ("owner/name") for the release check
rs.verify_placement = true              -- at the end of `apply`, check where each recognized window is
rs.debug_check = false                  -- also write the detailed check of `apply` to tmp/data_check.json
rs.min_window_visibility = 0            -- 0-1: fraction of each window that must be visible (0: off, windows are only counted)
rs.restore_scan = true                  -- record the over/underscan of the monitors in `save` and set it in `apply`
rs.restore_fullscreen = true            -- `apply` puts the windows that were in full-screen spaces back in full screen
rs.ignored_apps = {}                    -- apps that `save` and `apply` skip, _e.g._ {"System Settings"}
rs.use_plist_check = false              -- also check desktops against com.apple.spaces.plist
rs.use_direct_tabs = true               -- list the tabs of Safari/Chrome by scripting them (cycling through tabs is the fallback)
rs.use_ax_tabs = true                   -- read the tab strip of Firefox through accessibility (cycling through tabs is the fallback)
rs.tab_cycling = {                      -- overrides of scp/scp_config.json for the tab cycling
    maxIdenticalConsecutives = 12,      -- identical titles in a row that end the cycling
    maxStagnantTabs = 25                -- tabs without a new title that end the cycling
}
rs.space_pause = 0.3                    -- in seconds (<0.3 breaks the spaces module)
rs.screen_pause = 0.4                   -- in seconds (<0.4 breaks the spaces module)
rs.multitab_comparison = {
    critical_tab_count = 10,            -- decides which threshold to use
    small_similarity_threshold = 0.8,   -- 80%, for a small number of tabs
    large_similarity_threshold = 0.6,   -- 60%, for a large number of tabs
    title_fallback_threshold = 0.25     -- 25%, to recognize a window only by its title
}
rs.window_recognition = {               -- how the windows of an app are recognized after their ID and title fail
    ["Google Chrome"] = "tabs",         -- "tabs": by the list of their tabs
    Firefox = "tabs",
    Safari = "tabs",
    Finder = "tabs",
    ["Microsoft Teams"] = "app",        -- "app": the app has one saved window (its title changes with its view)
    MATLAB = {"Editor", "MATLAB R"}     -- {terms}: by the first term found in the title
}                                       -- (apps not listed are recognized by their ID and exact title only)
rs.config_path = "scp/scp_config"
rs.move_strategy = "titlebar"           -- same-screen moves (macOS 15+): "titlebar" or "mission_control"
                                        -- (moves between screens always use "mission_control")
rs.move_max_hops = 15                   -- spaces per move that "titlebar" may cross (slow: ~0.5 s each)
rs.move_cross_fullscreen = true         -- "titlebar" may cross full-screen spaces (false: "mission_control" does those moves)
rs.native_move = false                  -- try `hs.spaces.moveWindowToSpace` first (macOS 15+); off: it reports success without moving
rs.native_move_timeout = 1.0            -- in seconds, to wait for a native move to arrive
rs.move_speed = 1                       -- drag speed of all moves (1 = default; 2 = half the steps; lower it if windows stop following)
rs.move_apps = {                        -- apps that must use one strategy only
    titlebar = {},                      -- _e.g._ {"Terminal"}
    mission_control = {}                -- _e.g._ apps without a usable title bar
}
rs.fallback_space = "last"              -- "first" or "last" desktop of the target screen
rs.unrecognized_windows = "leave"       -- open windows that `apply` does not recognize: "leave" them, or send them to the `fallback_space` desktop of their monitor
rs.space_limit = 16                     -- spaces per display that macOS allows (full-screen ones included)
rs.borrow_spaces = true                 -- at the limit, create desktops on another screen and drag them over
rs.mc_timeout = 2.0                     -- in seconds, to wait for Mission Control (macOS 15+)
rs.mc_pause = 0.05                      -- in seconds, polling interval for Mission Control
rs.mc_settle = 0.3                      -- in seconds, to let Mission Control animations settle
rs.mc_drag_steps = 25                   -- steps of the synthetic drag (single jumps are ignored)
rs.mc_drag_pause = 0.01                 -- in seconds, between drag steps

-- Internal (not for users): which screen a window belongs to. "frame": where its
-- frame is (verified up to macOS 14); "owner": the screen of its desktop
-- (experimental, differs for windows whose frame is far from their desktop's screen)
rs.window_selection = "frame"
--TODO: mod.max_spaces = 0 (maximum number of spaces saved per screen)

-- Global variables (dynamic)
rs.data_wins = {}                       -- collected info for each window
rs.data_envs = {}                       -- collected info for each environment (monitors, desktops, layout, scan)
rs.fallback_count = 0                   -- windows sent to a fallback location during `apply`
rs.failed_count = 0                     -- windows that could not be moved during `apply`
rs.native_failed = false                -- a native move failed: it is not tried again in this run
rs.update_info = {}                     -- result of the release check

-- Import utilities
require('hs.restore_spaces.rs.utilities')(rs, hs)

-- Import compatibility with earlier versions (to be removed in 1.0)
require('hs.restore_spaces.rs.legacy')(rs, hs)

-- Import environment functions
require('hs.restore_spaces.rs.environment')(rs, hs)

-- Import layout functions (kind and order of the spaces of a monitor)
require('hs.restore_spaces.rs.layout')(rs, hs)

-- Import space-control functions
require('hs.restore_spaces.rs.spaces')(rs, hs)

-- Import display-settings functions
require('hs.restore_spaces.rs.displays')(rs, hs)

-- Import applescript functions
require('hs.restore_spaces.rs.applescript')(rs, hs)

-- Import plumbing (private) functions
require('hs.restore_spaces.rs.plumbing')(rs, hs)

-- Import window functions (state, frame, recognition settings)
require('hs.restore_spaces.rs.windows')(rs, hs)

-- Import the functions that visit spaces and list their windows
require('hs.restore_spaces.rs.visit')(rs, hs)

-- Import recognition functions (which open window is which saved window)
require('hs.restore_spaces.rs.recognition')(rs, hs)

-- Import placement-check functions
require('hs.restore_spaces.rs.placement')(rs, hs)

-- Import full-screen functions
require('hs.restore_spaces.rs.fullscreen')(rs, hs)

-- Import porcelain (public) functions
require('hs.restore_spaces.rs.porcelain')(rs, hs)

-- Initialize the statistics of the running action
rs.resetStats()

-- Make the module reachable from the Hammerspoon console: hs.restore_spaces.saveScan()
hs.restore_spaces = rs

rs.printBanner(3, rs.tagBuild("restore_spaces") .. " loaded")

return rs