-- `visit.lua`

-- Initialize the functions that visit spaces and list their windows
return function(rs,hs)

    -- Time the system was booted (nil if unknown), from the kernel: window IDs are
    -- only valid until the next restart, after which other windows reuse them.
    -- (`hs.host.uptime` is not used: it does not count the time spent asleep.)
    local boot_time
    rs.getBootTime = function()
        if boot_time == nil then
            local output = hs.execute("/usr/sbin/sysctl -n kern.boottime")
            boot_time = tonumber(tostring(output):match("sec%s*=%s*(%d+)")) or false
        end
        return boot_time or nil
    end

    -- Reading tabs can activate an app, and macOS then switches to the desktop of
    -- its windows: go back to the space being visited
    local function stayOnSpace(screen, space)
        if hs.spaces.activeSpaceOnScreen(screen) ~= space then
            rs.issueVerbose("the space changed while reading tabs; going back to " .. space,
                rs.verbose, 1)
            rs.gotoSpace(space)
            rs.delayExecution(rs.space_pause)
        end
    end

    -- Visit each space of a screen (desktops and full-screen spaces, or only the
    -- desktops with `desktops_only`) and call `visit(space, item)` on it, where
    -- `item` is its entry of `rs.getSpaceLayout`. A space that cannot be reached
    -- is skipped (and warned about), so that its windows are not taken for those
    -- of another one. The active space is restored afterwards.
    rs.visitSpaces = function(screen, visit, desktops_only)
        local initial_space = hs.spaces.activeSpaceOnScreen(screen)
        local layout, desktops, fullscreen = rs.getSpaceLayout(screen), 0, 0
        for _, item in ipairs(layout) do
            if item.kind == "desktop" then desktops = desktops + 1 else fullscreen = fullscreen + 1 end
        end
        rs.countStat(screen, "spaces", desktops)
        if fullscreen > 0 and not desktops_only then
            rs.addNote("Full-screen spaces", string.format("%s: %d", screen:name(), fullscreen))
        end

        rs.delayExecution(rs.screen_pause)
        for _, item in ipairs(layout) do
            if item.kind == "desktop" or not desktops_only then
                rs.issueVerbose(string.format("go to %s space: %s on screen: %s", item.kind,
                    item.id, tostring(screen:id())), rs.verbose)
                rs.gotoSpace(item.id)
                rs.delayExecution(rs.space_pause)
                if hs.spaces.activeSpaceOnScreen(screen) == item.id then
                    visit(item.id, item)
                else
                    rs.warn(string.format("could not go to the %s space %s of '%s'; its windows were skipped",
                        item.kind, item.id, screen:name()), "moves")
                end
            end
        end
        rs.gotoSpace(initial_space)
    end

    -- Windows of the screen's active space with their states, as a list of
    -- {window, id, state}; windows without title, those of `rs.ignored_apps` and
    -- those for which `skip(id)` is true are ignored (and not counted).
    -- `before(window)`, if given, is called for each window first.
    rs.getSpaceWindows = function(screen, before, skip)
        local infos = {}
        for _, window in ipairs(rs.retrieveEnvironmentEntities("windows", screen)) do
            if before then before(window) end
            local state, id = rs.getWindowState(window)
            if state["title"] == "" then
                rs.issueVerbose(string.format("ignored (no title): \tapp (%s)\twindow id (%s)",
                    state["app"], id), rs.verbose)
            elseif rs.isIgnoredApp(state["app"]) then
                rs.issueVerbose(string.format("ignored (app): \tapp (%s)\twindow id (%s)",
                    state["app"], id), rs.verbose, 4)
            elseif not (skip and skip(id)) then
                rs.countStat(screen, "windows")
                table.insert(infos, {window = window, id = id, state = state})
            end
        end
        return infos
    end

    -- Tab lists of the multi-tab windows in `infos`: window ID -> tabs
    rs.readSpaceTabs = function(screen, space, infos)
        local by_app, tabs = {}, {}
        for _, info in ipairs(infos) do
            if info.state["multitab"] then
                local app = info.state["app"]
                by_app[app] = by_app[app] or {titles = {}, windows = {}}
                by_app[app].titles[info.id] = info.state["title"]
                by_app[app].windows[info.id] = info.window
            end
        end
        for app, group in pairs(by_app) do
            for id, window_tabs in pairs(rs.getAppTabsInSpace(app, group.titles, group.windows)) do
                tabs[id] = window_tabs
            end
            stayOnSpace(screen, space)
        end
        return tabs
    end

end