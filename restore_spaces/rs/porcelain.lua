-- Initialize porcelain
return function(rs,hs)

    rs.saveEnvironmentState = function()
        rs.processPlistConfig("create")
        rs.getEnvironmentState()
        rs.processPlistConfig("destroy")
    end

    rs.applyEnvironmentState = function()
        rs.processPlistConfig("create")
        rs.setEnvironmentState()
        rs.processPlistConfig("destroy")
    end

    --[[
    function rs.refineWindowState(window_state)
    end
    --]]

    rs.getEnvironmentState = function()
        local save_new_env = true
        local env_name = rs.processEnvironment(save_new_env)
        if not env_name then
            error("Undefined environment name!")
        end
        local env_state = {}

        local all_screens = rs.retrieveEnvironmentEntities("screens",nil)
        for _, screen in ipairs(all_screens) do
            local screen_id = tostring(screen:id())

            local initial_space = hs.spaces.activeSpaceOnScreen(screen)
            local screen_spaces = rs.retrieveEnvironmentEntities("spaces", screen)

            rs.delayExecution(rs.screen_pause)
            for _, space in pairs(screen_spaces) do
                rs.issueVerbose(
                    "go to space: " .. space .. " on screen: " .. screen_id,
                    rs.verbose
                )
                hs.spaces.gotoSpace(space)
                rs.delayExecution(rs.space_pause)

                local space_state = {}
                local space_windows = rs.retrieveEnvironmentEntities("windows", screen)
                local multitab_windows = rs.list2table(rs.multitab_apps)
                for _, window in ipairs(space_windows) do
                    local window_state, window_id = rs.getWindowState(window)
                    window_state["screen"] = tonumber(screen_id)
                    window_state["space"] = space
                    if window_state["title"] == "" then
                        local msg = "ignored (no title): "
                        msg = msg .. "\tapp (" .. window_state["app"] .. ")"
                        msg =  msg .. "\twindow id (" .. window_id .. ")"
                        rs.issueVerbose(msg,rs.verbose)
                    else
                        rs.issueVerbose(hs.inspect(window_state),rs.verbose)
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
                        local app_tabs = rs.getAppTabsInSpace(app,id2title)
                        for window_id, _ in pairs(id2title) do
                            local window_state = space_state[window_id]
                            window_state["tabs"] = app_tabs[window_id]
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
        rs.data_wins[env_name] = env_state
        rs.data_wins = rs.processDataInFile("write","windows")
        rs.notifyUser("save")
    end

    rs.setEnvironmentState = function()
        local save_new_env = false
        local env_name, env = rs.processEnvironment(save_new_env)
        if not env_name then
            error("Undefined environment name!")
        end

        --TODO: open apps if they are not open?
        --TODO: close apps if they are not saved?

        rs.data_wins = rs.processDataInFile("read","windows")
        if not rs.data_wins[env_name] then
            error("State for environment has never been saved!")
        end
        local env_state = rs.data_wins[env_name]

        local all_screens = rs.retrieveEnvironmentEntities("screens",nil)
        for screen_i, screen in ipairs(all_screens) do
            local screen_id = tostring(screen:id())
            local screen_index = rs.paddedToStr(screen_i)
            local space_map = env[screen_index]["space_map"]

            local initial_space = hs.spaces.activeSpaceOnScreen(screen)
            local screen_spaces = rs.retrieveEnvironmentEntities("spaces", screen)

            rs.delayExecution(rs.screen_pause)
            for _, space in pairs(screen_spaces) do
                rs.issueVerbose(
                    "go to space: " .. space .. " on screen: " .. screen_id,
                    rs.verbose
                )
                hs.spaces.gotoSpace(space)
                rs.delayExecution(rs.space_pause)
                
                local space_state = {}
                local space_windows = rs.retrieveEnvironmentEntities("windows", screen)
                local multitab_windows = rs.list2table(rs.multitab_apps)
                for _, window in ipairs(space_windows) do
                    local window_state, window_id = rs.getWindowState(window)
                    space_state[window_id] = window_state

                    if window_state["title"] == "" then
                        local msg = "ignored (no title): "
                        msg = msg .. "\tapp (" .. window_state["app"] .. ")"
                        msg =  msg .. "\twindow id (" .. window_id .. ")"
                        rs.issueVerbose(msg,rs.verbose)
                    else
                        if env_state[window_id] then
                            window_state = env_state[window_id]
                            rs.issueVerbose(hs.inspect(window_state),rs.verbose)
                            rs.setWindowState(window, window_state, space_map)
                        else
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
                                        rs.rename_key(env_state,stored_id,window_id)
                                        rs.setWindowState(window, stored_state, space_map)
                                    end
                                end
                                if not found_state then
                                    local msg = "Unknown state for non-multitab app "
                                    msg = msg.."window ID ("..window_id..") and "
                                    msg = msg.."title ("..window_title..")"
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
                                local app_tabs = rs.getAppTabsInSpace(app,id2title)
                                for window_id, window_tabs in pairs(app_tabs) do
                                    local window_matched = false
                                    for stored_id, stored_state in pairs(env_state) do
                                        local stored_tabs = stored_state["tabs"]
                                        rs.delayExecution(rs.multitab_pause)
                                        if rs.compareTabs(window_tabs,stored_tabs) then
                                            rs.rename_key(env_state,stored_id,window_id)
                                            rs.setWindowState(window, stored_state, space_map)
                                            window_matched = true
                                            break
                                        end
                                    end
                                    if not window_matched then
                                        local msg = "No state found for window: "..window_id
                                        rs.issueVerbose(msg,rs.verbose)
                                    end
                                end
                            end
                        end
                    end
                    
                end
            end
            hs.spaces.gotoSpace(initial_space)
        end
        rs.notifyUser("apply")
    end

    --[[
    --TODO: function mod.turnoffEnvironment()
    -- save environment state, close each app running, and turn-off
    function mod.turnoff()
        os.execute("osascript -e 'tell app \"System Events\" to shut down'")
    end
    --]]

end