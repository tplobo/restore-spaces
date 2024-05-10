local hs = {}
hs.inspect = require 'hs.inspect'

-- Requires installing the `spaces` module
-- See: https://github.com/asmagill/hs._asm.spaces
hs.spaces = require 'hs.spaces'

-- Import plumbing (inner functions)
local mod = require("_restore_spaces")

-- Global variables (defaults)
--mod.mode = "quiet" -- "quiet" or "verbose"
mod.verbose = false
mod.space_pause = 0.3 -- in seconds (<0.3 breaks the spaces module)
mod.screen_pause = 0.4 -- in seconds (<0.4 breaks the spaces module)
--TODO: mod.max_spaces = 0 (maximum number of spaces saved per screen)

function mod.detectEnvironment(save_flag)
    local function sortByFrame(a, b)
        return a:frame().x < b:frame().x
    end
    local function listKeys(table)
        local keys_list = ""
        for key, _ in pairs(table) do
            keys_list = keys_list .. "'" .. key .. "'\n"
        end
        return keys_list
    end

    mod.data_envs = mod.processDataInFile("read","environments")
    
    local all_screens = mod.retrieveEnvironmentEntities("screens")
    table.sort(all_screens, sortByFrame)
    
    local env = {}
    for screen_i, screen in ipairs(all_screens) do
        local screen_name = screen:name()
        local screen_spaces = mod.retrieveEnvironmentEntities("spaces", screen)
        local screen_index = mod.paddedToStr(screen_i)
        local space_map = {}
        for space_i, space in ipairs(screen_spaces) do
            local space_index = mod.paddedToStr(space_i)
            --TODO: add docstrings that explain that the first value is
            --      the original space id during `save`, and the second
            --      is the current space id during `apply`
            space_map[space_index] = {space, space}
        end
        env[screen_index] = {
            ["monitor"] = screen_name,
            ["space_map"] = space_map
        }
    end

    local env_exists = false
    local env_name
    for saved_name, saved_env in pairs(mod.data_envs) do
        local saved_monitors = {}
        for _, value in pairs(saved_env) do
            table.insert(saved_monitors, value["monitor"])
        end

        local current_monitors = {}
        for _, value in pairs(env) do
            table.insert(current_monitors, value["monitor"])
        end

        local check_monitors = (
            hs.inspect(saved_monitors) == hs.inspect(current_monitors)
        )
        if check_monitors then
            env_exists = true
            env_name = saved_name
            break
        end
    end

    local text
    if env_exists then
        text = "Environment detected: '" .. env_name .. "'"
        mod.issueVerbose(text, mod.verbose)
        --[[
        -- FOR TESTING ONLY:
        local envs_list = listKeys(mod.data_envs)
        env_name = mod.askEnvironmentName(envs_list, mod.verbose)
        if not env_name then
            error("Undefined environment name: !")
        else
            mod.data_envs[env_name] = env
        end
        --]]
        if save_flag then
            text = "Overwriting space order and map..."
            mod.issueVerbose(text, mod.verbose)
        else
            text = "Re-building environment..."
            mod.issueVerbose(text, mod.verbose)
            local saved_env = mod.data_envs[env_name]
            for screen_i, screen in ipairs(all_screens) do
                local screen_index = mod.paddedToStr(screen_i)
                local screen_spaces = mod.retrieveEnvironmentEntities("spaces", screen)
                local saved_map = saved_env[screen_index]["space_map"]
                local saved_spaces = {}
                for _, pair in pairs(saved_map) do
                    table.insert(saved_spaces, pair[1])
                end
                while #screen_spaces < #saved_spaces do
                    hs.spaces.addSpaceToScreen(screen_index)
                    screen_spaces = mod.retrieveEnvironmentEntities("spaces", screen)
                end
                while #screen_spaces > #saved_spaces do
                    --TODO: do not decrease number of spaces (only increase)?
                    local last_space_id = screen_spaces[#screen_spaces]
                    hs.spaces.removeSpace(last_space_id)
                    screen_spaces = mod.retrieveEnvironmentEntities("spaces", screen)
                end
                --]]
                local screen_map = {}
                for space_i, space in ipairs(screen_spaces) do
                    local space_index = mod.paddedToStr(space_i)
                    screen_map[space_index] = {saved_spaces[space_i], space}
                end
                env[screen_index]["space_map"] = screen_map
                mod.issueVerbose("env: " .. hs.inspect(env), mod.verbose)
            end
        end
        mod.data_envs[env_name] = env
        mod.processDataInFile("write","environments")
    else
        text = "Environment does not exist."
        mod.issueVerbose(text, mod.verbose)
        text = "Environment name undefined!"
        if save_flag then
            local envs_list = listKeys(mod.data_envs)
            env_name = mod.askEnvironmentName(envs_list, mod.verbose)
            if not env_name then
                error(text)
            else
                mod.data_envs[env_name] = env
            end
            mod.data_envs = mod.processDataInFile("write","environments")
        else
            mod.notifyUser("environment")
            error(text)
        end
    end
    text = "Environment (" .. env_name .. "): " .. hs.inspect(env)
    mod.issueVerbose(text, mod.verbose)
    return env_name, env
end

function mod.saveEnvironmentState()
    local save_new_env = true
    local env_name = mod.detectEnvironment(save_new_env)
    if not env_name then
        error("Undefined environment name!")
    end
    local env_state = {}

    local all_screens = mod.retrieveEnvironmentEntities("screens",nil)
    for _, screen in ipairs(all_screens) do
        local screen_id = tostring(screen:id())

        local initial_space = hs.spaces.activeSpaceOnScreen(screen)
        local screen_spaces = mod.retrieveEnvironmentEntities("spaces", screen)
        local screen_windows = mod.retrieveEnvironmentEntities("windows", screen)

        mod.delayExecution(mod.screen_pause)
        for _, space in pairs(screen_spaces) do
            mod.issueVerbose(
                "go to space: " .. space .. " on screen: " .. screen_id,
                mod.verbose
            )
            hs.spaces.gotoSpace(space)
            mod.delayExecution(mod.space_pause)
            
            local space_windows = mod.retrieveEnvironmentEntities("visible", screen)
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
    local env_name = mod.detectEnvironment(save_new_env)
    if not env_name then
        error("Undefined environment name!")
    end

    --mod.buildEnvironment(env_name)

    --TODO: build environment to ensure every space id exists or has an
    --      equivalent, by creating a mapping between old and new space
    --      ids and save it in the environment JSON
    --TODO: open apps if they are not open
    --TODO: close apps if they are not saved?

    mod.data_wins = mod.processDataInFile("read","windows")
    if not mod.data_wins[env_name] then
        error("State for environment has never been saved!")
    end
    local env_state = mod.data_wins[env_name]

    local all_screens = mod.retrieveEnvironmentEntities("screens",nil)
    for _, screen in ipairs(all_screens) do
        local screen_id = tostring(screen:id())

        local initial_space = hs.spaces.activeSpaceOnScreen(screen)
        local screen_spaces = mod.retrieveEnvironmentEntities("spaces", screen)
        local screen_windows = mod.retrieveEnvironmentEntities("windows", screen)

        mod.delayExecution(mod.screen_pause)
        for _, space in pairs(screen_spaces) do
            mod.issueVerbose(
                "go to space: " .. space .. " on screen: " .. screen_id,
                mod.verbose
            )
            hs.spaces.gotoSpace(space)
            mod.delayExecution(mod.space_pause)
            
            local space_windows = mod.retrieveEnvironmentEntities("visible", screen)
            for _, window in ipairs(space_windows) do
                local window_state, window_id = mod.getWindowState(window)
                window_state = env_state[window_id]
                mod.issueVerbose(
                    hs.inspect(window_state),
                    mod.verbose
                )
                --TODO: send window to space equivalent space in map
                mod.setWindowState(window,window_state)
            end
        end
        hs.spaces.gotoSpace(initial_space)
    end
    mod.notifyUser("apply")
end

return mod