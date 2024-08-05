--local hs = {}
hs.inspect = require 'hs.inspect'

-- Use default `spaces` module:
hs.spaces = require 'hs.spaces'
-- Use development `spaces` module (https://github.com/asmagill/hs._asm.spaces)
--hs.spaces = require 'hs.spaces_v04.spaces'

-- Import plumbing (private functions)
local mod = require 'hs.restore_spaces._restore_spaces'

-- Global variables (defaults)
--mod.mode = "quiet" -- "quiet" or "verbose"
mod.verbose = false
mod.space_pause = 0.3 -- in seconds (<0.3 breaks the spaces module)
mod.screen_pause = 0.4 -- in seconds (<0.4 breaks the spaces module)
mod.multitab_comparison = {
    critical_tab_count = 10,            -- decides which threshold to use
    small_similarity_threshold = 0.8,   -- small number of tabs
    large_similarity_threshold = 0.6    -- large number of tabs
}
--TODO: mod.max_spaces = 0 (maximum number of spaces saved per screen)

function mod.saveEnvironmentState()
    mod.processPlistConfig("create")
    mod._saveEnvironmentState()
    mod.processPlistConfig("destroy")
end

function mod.applyEnvironmentState()
    mod.processPlistConfig("create")
    mod._applyEnvironmentState()
    mod.processPlistConfig("destroy")
end

function mod.refineWindowState(window_state)

end

function mod.runApplescript(app)
    local script_path = "scp/getVisibleTabs.applescript"
    local abs_path = mod.packagePath(script_path)
    local osascript = "/usr/bin/osascript"
    local plist_path = mod.getPlistInfo("path")

    local args = app .. " " .. plist_path
    local command = osascript .. " " .. abs_path .. " " .. args
    local output, status, exitType, rc = hs.execute(command,true)
    
    local msg =  "Status: "..tostring(status)..", exit: "..tostring(exitType)
    msg = msg ..", rc: "..tostring(rc)
    mod.issueVerbose(msg,mod.verbose)
    mod.issueVerbose(hs.inspect(output),mod.verbose)

    local report_delimiter = mod.getPlistInfo("reportDelimiter")
    local tab_list = mod.buildTabList(output,report_delimiter)
    return tab_list
end

function mod.getAppTabsInSpace(app,id2title)
    local app_tabs = id2title
    local tab_list = mod.runApplescript(app)
    for _, window_tabs in ipairs(tab_list) do
        local first_tab = window_tabs[1]
        for id, title in pairs(id2title) do
            if first_tab == title then
                app_tabs[id] = mod.list2dict(window_tabs)
            end
        end
    end
    return app_tabs
end

function mod._saveEnvironmentState()
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

            local space_state = {}
            local space_windows = mod.retrieveEnvironmentEntities("windows", screen)
            local multitab_windows = mod.list2table(mod.multitab_apps)
            for _, window in ipairs(space_windows) do
                local window_state, window_id = mod.getWindowState(window)
                window_state["screen"] = tonumber(screen_id)
                window_state["space"] = space
                if window_state["title"] == "" then
                    local msg = "ignored (no title): "
                    msg = msg .. "\tapp (" .. window_state["app"] .. ")"
                    msg =  msg .. "\twindow id (" .. window_id .. ")"
                    mod.issueVerbose(msg,mod.verbose)
                else
                    mod.issueVerbose(hs.inspect(window_state),mod.verbose)
                    if window_state["multitab"] == true then
                        local app = window_state["app"]
                        local id_list = multitab_windows[app]
                        id_list[#id_list + 1] = window_id
                        multitab_windows[app] = id_list
                    end
                    space_state[window_id] = window_state
                end
            end
            -- refineSpaceState:
            for app, id_list in pairs(multitab_windows) do
                if #id_list > 0 then
                    local id2title = {}
                    for _, window_id in ipairs(id_list) do
                        local window_state = space_state[window_id]
                        id2title[window_id] = window_state["title"]
                    end
                    local app_tabs = mod.getAppTabsInSpace(app,id2title)
                    for window_id, _ in pairs(id2title) do
                        local window_state = space_state[window_id]
                        window_state["tabs"] = app_tabs[window_id]
                        --print(hs.inspect(app_tabs[window_id]))
                        space_state[window_id] = window_state
                    end
                end
            end
            
            for window_id, window_state in pairs(space_state) do
                env_state[window_id] = window_state
            end

        end
        hs.spaces.gotoSpace(initial_space)
    end
    mod.data_wins[env_name] = env_state
    mod.data_wins = mod.processDataInFile("write","windows")
    mod.notifyUser("save")
end

function mod.compare_tabs(window_tabs,stored_tabs)
    if (stored_tabs == nil) or next(stored_tabs) == nil then
        return false
    end
    --print("window tabs: " .. hs.inspect(window_tabs))
    --print("stored tabs: " .. hs.inspect(stored_tabs))

   local  all_matches = {}
    for _, tab_title in pairs(window_tabs) do
        print("tab_title "..tab_title)
        if mod.contains(stored_tabs,tab_title) then
            table.insert(all_matches, true)
        end
    end
    local window_ratio = #all_matches / #window_tabs
    local stored_ratio = #all_matches / #stored_tabs

    local tab_limit
    if #window_tabs <= mod.multitab_comparison["critical_tab_count"] then
        tab_limit = mod.multitab_comparison["small_similarity_threshold"]
    else
        tab_limit = mod.multitab_comparison["large_similarity_threshold"]
    end

    --print("all matches: "..hs.inspect(all_matches))
    --print("window ratio: "..window_ratio)
    --print("stored ratio: "..stored_ratio)
    --print("tab limit: "..tab_limit)

    local window_check = window_ratio >= tab_limit
    if mod.isNaN(window_ratio) then
        window_check = false
    end
    local stored_check = stored_ratio >= tab_limit
    if mod.isNaN(stored_ratio) then
        stored_check = false
    end
    local match = window_check and stored_check
    print(match)
    return match
end

function mod._applyEnvironmentState()
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
    --print(hs.inspect(env_state))

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
            
            local space_state = {}
            local space_windows = mod.retrieveEnvironmentEntities("windows", screen)
            local multitab_windows = mod.list2table(mod.multitab_apps)
            for _, window in ipairs(space_windows) do
                local window_state, window_id = mod.getWindowState(window)
                space_state[window_id] = window_state
                print("START PROCESSING OF ID: "..window_id)

                if window_state["title"] == "" then
                    local msg = "ignored (no title): "
                    msg = msg .. "\tapp (" .. window_state["app"] .. ")"
                    msg =  msg .. "\twindow id (" .. window_id .. ")"
                    --print(msg)
                    mod.issueVerbose(msg,mod.verbose)
                else
                    if env_state[window_id] then
                        print("state for ID "..window_id.." is stored!")
                        window_state = env_state[window_id]
                        mod.issueVerbose(hs.inspect(window_state),mod.verbose)
                        print("space "..space)
                        mod.setWindowState(window, window_state, space_map)
                    else
                        print("STATE: "..hs.inspect(window_state))
                        if window_state["multitab"] == true then
                            local app = window_state["app"]
                            local id_list = multitab_windows[app]
                            id_list[#id_list + 1] = window_id
                            multitab_windows[app] = id_list
                        else
                            local found_state = false
                            local window_title = window_state["title"]
                            for stored_id, stored_state in pairs(env_state) do
                                local stored_title = stored_state["title"]
                                if window_title == stored_title then
                                    found_state = true
                                    mod.rename_key(env_state,stored_id,window_id)
                                    mod.setWindowState(window, stored_state, space_map)
                                end
                            end
                            if not found_state then
                                local msg = "Unknown state for non-multitab app "
                                msg = msg.."window ID ("..window_id..") and "
                                msg = msg.."title ("..window_title..")"
                                print(msg)
                            end
                        end
                    end
                    --refineSpaceState:
                    for app, id_list in pairs(multitab_windows) do
                        if #id_list > 0 then
                            local id2title = {}
                            for _, window_id in ipairs(id_list) do
                                local window_state = space_state[window_id]
                                id2title[window_id] = window_state["title"]
                            end
                            local app_tabs = mod.getAppTabsInSpace(app,id2title)
                            for window_id, window_tabs in pairs(app_tabs) do
                                local window_matched = false
                                for stored_id, stored_state in pairs(env_state) do
                                    local stored_tabs = stored_state["tabs"]
                                    print("stored tabs: "..hs.inspect(stored_tabs))
                                    if mod.compare_tabs(window_tabs,stored_tabs) then
                                        mod.rename_key(env_state,stored_id,window_id)
                                        mod.setWindowState(window, stored_state, space_map)
                                        window_matched = true
                                        break
                                    end
                                end
                                if not window_matched then
                                    print("No state found for window: "..window_id)
                                end
                            end
                        end
                    end
                end
                
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