-- `porcelain.lua`

-- Initialize porcelain
return function(rs,hs)

    -- Run `action` and always remove the plist of the configuration afterwards
    local function withPlistConfig(action)
        rs.processPlistConfig("create")
        local success, err = xpcall(action, debug.traceback)
        pcall(rs.processPlistConfig, "destroy")
        if not success then error(err, 0) end
    end

    rs.saveEnvironmentState = function()
        rs.runAction("save environment state", function()
            rs.logSystemInfo()
            withPlistConfig(rs.getEnvironmentState)
        end)
    end

    rs.applyEnvironmentState = function()
        rs.runAction("apply environment state", function()
            rs.logSystemInfo()
            withPlistConfig(rs.setEnvironmentState)
        end)
    end

    -- `apply` with the detailed record of the placement check
    -- (tmp/data_check.json), for debugging
    rs.applyAndCheck = function()
        local previous = rs.debug_check
        rs.debug_check = true
        local success, err = pcall(rs.applyEnvironmentState)
        rs.debug_check = previous
        if not success then error(err, 0) end
    end

    -- Bring the windows into view (`rs.min_window_visibility`, see
    -- `rs.realignWindow`): cycles through all desktops of all screens like
    -- `save`, but records and changes nothing else
    rs.realignWindows = function()
        rs.runAction("realign windows", function()
            if not hs.spaces.screensHaveSeparateSpaces() then
                error("'Displays have separate Spaces' must be on")
            end
            rs.logSystemInfo()
            for _, screen in ipairs(rs.getSortedScreens()) do
                rs.visitSpaces(screen, function(space)
                    for _, window in ipairs(hs.window.visibleWindows()) do
                        if rs.realignWindow(window, space) then
                            rs.countStat(screen, "windows")
                        end
                    end
                end, true)
            end
        end)
    end

    --[[
    function rs.refineWindowState(window_state)
    end
    --]]

    -- Save the windows of every space (desktops and full-screen spaces) of every
    -- monitor, where each one is: `screen_index`, `space_kind`, `slot` (position
    -- among the spaces of the monitor) and `anchor` (desktops up to its space)
    rs.getEnvironmentState = function()
        local env_name = rs.processEnvironment(true)
        if not env_name then
            error("Undefined environment name!")
        end
        rs.stats.environment = env_name
        local env_state, boot = {}, rs.getBootTime()

        for screen_i, screen in ipairs(rs.getSortedScreens()) do
            local screen_index = rs.paddedToStr(screen_i)
            rs.visitSpaces(screen, function(space, item)
                -- Keep each window in view before recording it (a no-op unless
                -- `rs.min_window_visibility` > 0)
                local infos = rs.getSpaceWindows(screen, function(window)
                    rs.realignWindow(window, space)
                end)
                local tabs = rs.readSpaceTabs(screen, space, infos)
                for _, info in ipairs(infos) do
                    local state = info.state
                    -- A window of all desktops also shows up in full-screen spaces:
                    -- only the windows that belong to this space are recorded there
                    local windows_spaces = hs.spaces.windowSpaces(info.window) or {}
                    if item.kind == "desktop" or (#windows_spaces == 1 and windows_spaces[1] == space) then
                        state["screen"], state["space"], state["boot"] = screen:id(), space, boot
                        state["screen_index"], state["space_kind"] = screen_index, item.kind
                        state["slot"], state["anchor"] = item.slot, item.anchor
                        if state["multitab"] then
                            state["tabs"] = tabs[info.id]
                        end
                        rs.issueVerbose(rs.describeState(state), rs.verbose)
                        env_state[info.id] = state
                    end
                end
            end)
        end

        -- Read the saved windows of the other environments first, or they are lost
        rs.data_wins = rs.processDataInFile("read","windows") or {}
        rs.data_wins[env_name] = env_state
        rs.data_wins = rs.processDataInFile("write","windows")
        if rs.restore_scan then
            local success, err = pcall(rs.measure, "display scan", rs.recordScan, env_name)
            if not success then
                rs.warn("the scan of the monitors could not be recorded: " .. tostring(err), "scan")
            end
        end
        rs.notifyUser("save")
    end

    -- Recognize the open windows of every space and put them where they were
    -- saved: desktop windows are moved while visiting, and the windows saved in
    -- full-screen spaces enter full screen afterwards, in order
    rs.setEnvironmentState = function()
        local env_name, env = rs.processEnvironment(false)
        if not env_name then
            error("Undefined environment name!")
        end
        rs.stats.environment = env_name
        rs.fallback_count = 0
        rs.failed_count = 0
        rs.native_failed = false

        --TODO: open apps if they are not open?
        --TODO: close apps if they are not saved?

        rs.data_wins = rs.processDataInFile("read","windows")
        if not rs.data_wins[env_name] then
            error("State for environment has never been saved!")
        end
        local saved = rs.loadSavedWindows(rs.data_wins[env_name])
        local screens = rs.getSortedScreens()

        -- Build all_maps with all space maps to ensure windows can be
        -- relocated to spaces on different screens.
        local all_maps, initial = {}, {}
        for screen_i, screen in ipairs(screens) do
            local screen_index = rs.paddedToStr(screen_i)
            all_maps[screen_index] = env[screen_index]["space_map"]
            initial[screen] = hs.spaces.activeSpaceOnScreen(screen)
        end

        -- Windows already placed in this run: when they show up again (on the
        -- desktop they were moved to) they are not processed or counted twice;
        -- `seen` has every other window met, for the placement check; `listed`
        -- has the unrecognized windows already named in the summary
        local placed, seen, listed = {}, {}, {}

        for _, screen in ipairs(screens) do
            rs.visitSpaces(screen, function(space, item)
                local infos = rs.getSpaceWindows(screen, nil, function(id) return placed[id] end)
                for _, info in ipairs(infos) do
                    info.visit_space = space
                    table.insert(seen, info)
                end

                rs.recognizeWindows(saved, infos, screen, space)

                -- Place the windows that were recognized
                for _, info in ipairs(infos) do
                    local entry = info.entry
                    if entry then
                        placed[info.id] = true
                        entry.window = info.window
                        if entry.state["space_kind"] ~= "fullscreen" then
                            entry.target = rs.getTargetSpace(entry.state, all_maps)
                        end
                        rs.issueVerbose("LOADED WINDOW STATE: " .. rs.describeState(entry.state), rs.verbose)
                        rs.issueVerbose("WINDOW STATE: " .. rs.describeState(info.state), rs.verbose)
                        rs.setWindowState(info.window, entry.state, entry.target)
                    end
                end

                -- The others stay where they are (and the summary names them), or go
                -- to the fallback desktop of their monitor (`rs.unrecognized_windows`);
                -- those that stay are still checked for visibility
                local fallback = rs.unrecognized_windows == "fallback" and item.kind == "desktop"
                    and rs.getFallbackSpace(space)
                for _, info in ipairs(infos) do
                    if not info.entry then
                        if not listed[info.id] then
                            listed[info.id] = true
                            rs.addNote("Open windows not recognized", string.format("%s - %s",
                                info.state["app"], rs.shortTitle(info.state["title"])))
                        end
                        if fallback and fallback ~= space then
                            placed[info.id] = true
                            local moved = rs.moveWindowToSpace(info.window, fallback)
                            rs.issueVerbose(string.format("unrecognized window %s of '%s' %s the fallback desktop",
                                info.id, info.state["app"], moved and "sent to" or "could not be sent to"),
                                rs.verbose, 1)
                        else
                            rs.realignWindow(info.window, space)
                        end
                    end
                end
            end)
        end

        rs.measure("entering full screen", rs.restoreFullScreen, saved.entries, all_maps, initial)
        rs.listMissingWindows(saved.entries)

        if rs.verify_placement or rs.debug_check then
            local success, err = pcall(rs.measure, "placement check", rs.checkPlacement, env_name, seen)
            if not success then
                rs.warn("the placement check failed: " .. tostring(err), "placement")
            end
        end
        pcall(rs.reportSpaceOrder, env_name)

        if rs.restore_scan then
            local success, err = pcall(rs.measure, "display scan", rs.applyScanState, env_name)
            if not success then
                rs.warn("the scan of the monitors could not be set: " .. tostring(err), "scan")
            end
        end
        if rs.fallback_count > 0 then
            rs.notifyUser("fallback")
        end
        rs.notifyUser(rs.failed_count > 0 and "failed" or "apply")
    end

    --[[
    --TODO: function mod.turnoffEnvironment()
    -- save environment state, close each app running, and turn-off
    function mod.turnoff()
        os.execute("osascript -e 'tell app \"System Events\" to shut down'")
    end
    --]]

end