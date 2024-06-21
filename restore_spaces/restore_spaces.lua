--local hs = {}
hs.inspect = require 'hs.inspect'

-- Requires installing the `spaces` module
-- See: https://github.com/asmagill/hs._asm.spaces
hs.spaces = require 'hs.spaces.spaces'

-- Import plumbing (private functions)
local mod = require 'hs.restore_spaces._restore_spaces'

-- Global variables (defaults)
--mod.mode = "quiet" -- "quiet" or "verbose"
mod.verbose = false
mod.space_pause = 0.3 -- in seconds (<0.3 breaks the spaces module)
mod.screen_pause = 0.4 -- in seconds (<0.4 breaks the spaces module)
--TODO: mod.max_spaces = 0 (maximum number of spaces saved per screen)

function mod.saveEnvironmentState()
    local save_new_env = true
    local env_name = mod.processEnvironment(save_new_env)
    if not env_name then
        error("Undefined environment name!")
    end
    local env_state = {}

    local all_screens = mod.retrieveEnvironmentEntities("screens",nil)
    for _, screen in ipairs(all_screens) do
        local screen_id = tostring(screen:id())

        local initial_space = hs.spaces.activeSpaceOnScreen(screen)
        local screen_spaces = mod.retrieveEnvironmentEntities("spaces", screen)

        mod.delayExecution(mod.screen_pause)
        for _, space in pairs(screen_spaces) do
            mod.issueVerbose(
                "go to space: " .. space .. " on screen: " .. screen_id,
                mod.verbose
            )
            hs.spaces.gotoSpace(space)
            mod.delayExecution(mod.space_pause)
            
            local space_windows = mod.retrieveEnvironmentEntities("windows", screen)
            for _, window in ipairs(space_windows) do
                local window_state, window_id = mod.getWindowState(window)
                window_state["screen"] = tonumber(screen_id)
                window_state["space"] = space

                if window_state["title"] == "" then
                    --print("App:", window_state["app"])
                    --print("Window ID:", window_id)
                    mod.issueVerbose(
                        (
                            "ignored (no title): " ..
                            "\tapp (" .. window_state["app"] .. ")" ..
                            "\twindow id (" .. window_id .. ")"
                        ),
                        mod.verbose
                    )
                else
                    mod.issueVerbose(
                        hs.inspect(window_state),
                        mod.verbose
                    )
                    env_state[window_id] = window_state
                end
            end
        end
        hs.spaces.gotoSpace(initial_space)
    end
    mod.data_wins[env_name] = env_state
    mod.data_wins = mod.processDataInFile("write","windows")
    mod.notifyUser("save")
end

function mod.applyEnvironmentState()
    local save_new_env = false
    local env_name, env = mod.processEnvironment(save_new_env)
    if not env_name then
        error("Undefined environment name!")
    end

    --TODO: open apps if they are not open?
    --TODO: close apps if they are not saved?

    mod.data_wins = mod.processDataInFile("read","windows")
    if not mod.data_wins[env_name] then
        error("State for environment has never been saved!")
    end
    local env_state = mod.data_wins[env_name]

    local all_screens = mod.retrieveEnvironmentEntities("screens",nil)
    for screen_i, screen in ipairs(all_screens) do
        local screen_id = tostring(screen:id())
        local screen_index = mod.paddedToStr(screen_i)
        local space_map = env[screen_index]["space_map"]

        local initial_space = hs.spaces.activeSpaceOnScreen(screen)
        local screen_spaces = mod.retrieveEnvironmentEntities("spaces", screen)

        mod.delayExecution(mod.screen_pause)
        for _, space in pairs(screen_spaces) do
            mod.issueVerbose(
                "go to space: " .. space .. " on screen: " .. screen_id,
                mod.verbose
            )
            hs.spaces.gotoSpace(space)
            mod.delayExecution(mod.space_pause)
            
            local space_windows = mod.retrieveEnvironmentEntities("windows", screen)
            for _, window in ipairs(space_windows) do
                local window_state, window_id = mod.getWindowState(window)
                window_state = env_state[window_id]
                mod.issueVerbose(
                    hs.inspect(window_state),
                    mod.verbose
                )
                mod.setWindowState(window, window_state, space_map)
            end
        end
        hs.spaces.gotoSpace(initial_space)
    end
    mod.notifyUser("apply")
end

--[[
--TODO: function mod.turnoffEnvironment()
-- save environment state, close each app running, and turn-off
function mod.turnoff()
    os.execute("osascript -e 'tell app \"System Events\" to shut down'")
end
--]]

return mod