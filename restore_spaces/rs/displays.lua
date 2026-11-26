-- `displays.lua`

-- Initialize display-settings functions (over/underscan)
return function(rs,hs)

    local bundle = "com.apple.systempreferences"
    local pane_url = "x-apple.systempreferences:com.apple.Displays-Settings.extension"

    local function getSettingsApp()
        return hs.application.applicationsForBundleID(bundle)[1]
    end

    local function attr(element, name)
        local success, value = pcall(function() return element:attributeValue(name) end)
        return success and value or nil
    end

    local function description(element)
        return tostring(attr(element, "AXDescription") or "")
    end

    local function waitFor(predicate, timeout)
        local waited = 0
        local value = predicate()
        while not value and waited < timeout do
            rs.delayExecution(0.1)
            waited = waited + 0.1
            value = predicate()
        end
        return value
    end

    -- First descendant (up to `depth` levels) for which `test(element)` is true
    local function find(root, test, depth)
        for _, child in ipairs(attr(root, "AXChildren") or {}) do
            if test(child) then return child end
            if depth > 1 then
                local found = find(child, test, depth - 1)
                if found then return found end
            end
        end
    end

    -- The slider of the scan: the only slider of the pane with this identifier
    -- (found by identifier, not by its English description)
    local function isScanSlider(element)
        return attr(element, "AXRole") == "AXSlider"
            and attr(element, "AXIdentifier") == "characteristicSection"
    end

    local function matchesDisplay(text, name)
        return text:find(name, 1, true) ~= nil
            or (name:find("Built-in", 1, true) ~= nil and text:find("Built-in", 1, true) ~= nil)
    end

    -- The two scroll areas of the pane: the list of displays and the settings of
    -- the selected one (found by structure, so it does not depend on the language)
    local function getAreas(window)
        local function walk(node, depth)
            local areas = {}
            for _, child in ipairs(attr(node, "AXChildren") or {}) do
                if attr(child, "AXRole") == "AXScrollArea" then
                    table.insert(areas, child)
                end
            end
            if #areas >= 2 then return areas[1], areas[2] end
            if depth > 1 then
                for _, child in ipairs(attr(node, "AXChildren") or {}) do
                    local list, settings = walk(child, depth - 1)
                    if list then return list, settings end
                end
            end
        end
        return walk(window, 10)
    end

    -- Settings area of the display `name`, if it is the selected one
    local function selectedSettings(window, name)
        local _, settings = getAreas(window)
        if settings and matchesDisplay(description(settings), name) then
            return settings
        end
    end

    -- Click an element of System Settings with the mouse (the cursor is restored)
    local function click(element, app)
        local position, size = attr(element, "AXPosition"), attr(element, "AXSize")
        if not (position and size) then return false end
        local cursor = hs.mouse.absolutePosition()
        app:activate()
        rs.delayExecution(0.3)
        hs.eventtap.leftClick({x = position.x + size.w / 2, y = position.y + size.h / 2})
        rs.delayExecution(0.3)
        hs.mouse.absolutePosition(cursor)
        return true
    end

    -- Select the display of `screen` in the pane. The accessibility "press" does
    -- not select it on macOS 27.2, so it falls back to a mouse click, and then to
    -- moving the window of System Settings to that display (the pane shows the
    -- settings of the display that holds its window). Returns the settings area
    -- and how it was selected, or nil and the reason.
    local function selectDisplay(window, screen, app)
        local name = screen:name()
        local settings = selectedSettings(window, name)
        if settings then return settings, "already selected" end
        local list = getAreas(window)
        if not list then
            return nil, "list of displays not found"
        end
        local button
        for _, candidate in ipairs(attr(list, "AXChildren") or {}) do
            if attr(candidate, "AXRole") == "AXButton" and matchesDisplay(description(candidate), name) then
                button = candidate
                break
            end
        end
        if not button then
            return nil, "display not listed in System Settings"
        end

        button:performAction("AXPress")
        settings = waitFor(function() return selectedSettings(window, name) end, 1.5)
        if settings then return settings, "pressed" end

        click(button, app)
        settings = waitFor(function() return selectedSettings(window, name) end, 3)
        if settings then return settings, "clicked" end

        local main = app:mainWindow()
        if main then
            local area = screen:frame()
            main:setTopLeft({x = area.x + 40, y = area.y + 60})
            settings = waitFor(function() return selectedSettings(window, name) end, 3)
            if settings then return settings, "window moved" end
        end
        return nil, "the settings of the display did not appear (press, click and moving the window failed)"
    end
    
    -- Open the Displays pane and wait for its accessibility tree. Returns the app,
    -- the window with the pane (nil if it never appeared) and what was seen.
    local function openPane(timeout)
        local state = {running = false, windows = 0}
        local app, window
        hs.execute('open "' .. pane_url .. '"')
        waitFor(function()
            app = getSettingsApp()
            state.running = app ~= nil
            if not app then return false end
            local element = hs.axuielement.applicationElement(app)
            for _, name in ipairs({"AXEnhancedUserInterface", "AXManualAccessibility"}) do
                pcall(function() element:setAttributeValue(name, true) end)
            end
            local windows = attr(element, "AXWindows") or {}
            state.windows = #windows
            for _, candidate in ipairs(windows) do
                if getAreas(candidate) then
                    window = candidate
                    return true
                end
            end
            return false
        end, timeout)
        return app, window, state
    end

    -- Run `action(window, app)` with the Displays pane of System Settings open.
    -- If the pane does not show up (accessibility cannot see windows that are on
    -- another desktop, and a window may not wake up after sleep), System Settings
    -- is restarted once. Puts everything back afterwards: the display that was
    -- selected, the window position, the app (closed if it was not running) and
    -- the desktops that were active (opening the pane can switch desktops).
    local function withDisplaysPane(action)
        local was_running = getSettingsApp() ~= nil
        local active = {}
        for _, screen in ipairs(hs.screen.allScreens()) do
            active[screen] = hs.spaces.activeSpaceOnScreen(screen)
        end

        local app, window, state = openPane(8)
        if not window then
            local details = string.format("System Settings %s, %d windows visible to accessibility, none with the Displays pane",
                state.running and "running" or "not running", state.windows)
            rs.issueVerbose("the Displays pane did not show up (" .. details .. "); restarting System Settings",
                rs.verbose, 1)
            if app then
                pcall(function() app:kill() end)
                if not waitFor(function() return getSettingsApp() == nil end, 5) then
                    pcall(function() app:kill9() end)
                    waitFor(function() return getSettingsApp() == nil end, 3)
                end
            end
            app, window, state = openPane(15)
            if window then
                rs.addNote("Display scan", "System Settings had to be restarted (" .. details .. ")")
            end
        end

        local main = window and app:mainWindow()
        local origin = main and main:topLeft()
        local initial_screen
        if window then
            local _, settings = getAreas(window)
            local initial = settings and description(settings)
            for _, screen in ipairs(hs.screen.allScreens()) do
                if initial and matchesDisplay(initial, screen:name()) then initial_screen = screen end
            end
        end

        local results = table.pack(pcall(function()
            if not window then
                error(string.format("the Displays pane did not open (System Settings %s, %d windows visible to accessibility, none with the Displays pane, even after restarting it)",
                    state.running and "running" or "not running", state.windows), 0)
            end
            return action(window, app)
        end))

        if window and was_running then
            pcall(function()
                if main and origin then main:setTopLeft(origin) end
                if initial_screen then selectDisplay(window, initial_screen, app) end
            end)
        end
        if app and not was_running then pcall(function() app:kill() end) end
        for screen, space in pairs(active) do
            if hs.spaces.activeSpaceOnScreen(screen) ~= space then
                rs.gotoSpace(space)
            end
        end
        if not results[1] then error(results[2], 0) end
        return table.unpack(results, 2, results.n)
    end

    -- Over/underscan of the monitors in `wanted` (a set of monitor names; all
    -- connected monitors if nil). Returns monitor name -> {value, min, max}, or
    -- false if the monitor has no scan setting; monitors that could not be checked
    -- are not in the result.
    rs.readScan = function(wanted)
        local found = {}
        withDisplaysPane(function(window, app)
            for _, screen in ipairs(hs.screen.allScreens()) do
                local name = screen:name()
                if not wanted or wanted[name] then
                    local settings, how = selectDisplay(window, screen, app)
                    if not settings then
                        rs.warn(string.format("the scan of '%s' could not be read (%s)", name, tostring(how)), "scan")
                    else
                        local slider = find(settings, isScanSlider, 6)
                        if slider then
                            found[name] = {value = attr(slider, "AXValue"),
                                min = attr(slider, "AXMinValue"), max = attr(slider, "AXMaxValue")}
                            rs.addNote("Display scan", string.format("%s: scan %s (display %s)",
                                name, tostring(found[name].value), how))
                        else
                            found[name] = false
                            rs.addNote("Display scan", name .. ": no scan setting")
                        end
                    end
                end
            end
        end)
        return found
    end

    -- Put the slider at `target`: by setting its value or, if that is refused, by
    -- pressing its increment/decrement actions. Returns {ok, how, before, final}.
    local function setSlider(slider, target, saved)
        local function read() return attr(slider, "AXValue") end
        local range = (saved.max and saved.min) and math.abs(saved.max - saved.min) or 0
        local tolerance = math.max(1, range * 0.005)
        local before = read()
        if before and math.abs(before - target) <= tolerance then
            return {ok = true, how = "already set", before = before, final = before}
        end
        local settable = false
        pcall(function() settable = slider:isAttributeSettable("AXValue") end)
        if settable then
            pcall(function() slider:setAttributeValue("AXValue", target) end)
            rs.delayExecution(0.5)
            local after = read()
            if after and math.abs(after - target) <= tolerance then
                return {ok = true, how = "AXValue", before = before, final = after}
            end
        end
        local current = read() or before
        if not current then
            return {ok = false, how = "the slider has no value", before = before}
        end
        local action = target > current and "AXIncrement" or "AXDecrement"
        for _ = 1, 120 do
            slider:performAction(action)
            rs.delayExecution(0.1)
            local now = read()
            if not now or now == current then break end
            current = now
            if math.abs(current - target) <= tolerance or (action == "AXIncrement") == (current > target) then
                break
            end
        end
        return {ok = math.abs(current - target) <= 4 * tolerance, how = action .. " steps",
            before = before, final = current}
    end

    -- Set the scan of the monitors in `saved` (monitor name -> {value, min, max})
    rs.writeScan = function(saved)
        withDisplaysPane(function(window, app)
            for _, screen in ipairs(hs.screen.allScreens()) do
                local name = screen:name()
                local wanted = saved[name]
                if wanted and wanted.value then
                    local settings, how = selectDisplay(window, screen, app)
                    local slider = settings and find(settings, isScanSlider, 6)
                    if not slider then
                        rs.warn(string.format("the scan of '%s' could not be set (%s)", name,
                            tostring(settings and "no scan setting found" or how)), "scan")
                    else
                        local result = setSlider(slider, wanted.value, wanted)
                        rs.addNote("Display scan", string.format("%s: %s -> %s (wanted %s; %s)", name,
                            tostring(result.before), tostring(result.final), tostring(wanted.value), result.how))
                        if not result.ok then
                            rs.warn(string.format("the scan of '%s' could not be set: wanted %s, got %s (%s)",
                                name, tostring(wanted.value), tostring(result.final), result.how), "scan")
                        end
                    end
                end
            end
        end)
    end

    -- Record the scan of the monitors of an environment in the environments file
    -- (field `scan` of each monitor: {value, min, max}, or false if the monitor has
    -- no scan setting, which is not checked again; delete the field to check again)
    rs.recordScan = function(env_name)
        rs.data_envs = rs.processDataInFile("read","environments") or {}
        local env = rs.data_envs[env_name]
        if not env then
            error("no saved environment named '" .. tostring(env_name) .. "'")
        end
        local to_read, any = {}, false
        for _, entry in pairs(env) do
            if entry["scan"] ~= false then
                to_read[entry["monitor"]], any = true, true
            end
        end
        if not any then
            rs.issueVerbose("no monitor of '" .. env_name .. "' has a scan setting", rs.verbose, 1)
            return
        end
        local found = rs.readScan(to_read)
        for _, entry in pairs(env) do
            local scan = found[entry["monitor"]]
            if scan ~= nil then entry["scan"] = scan end
        end
        rs.processDataInFile("write","environments")
    end

    -- Set the recorded scan of an environment. `explicit` (the scan action) warns
    -- if none was recorded; `apply` just goes on.
    rs.applyScanState = function(env_name, explicit)
        rs.data_envs = rs.processDataInFile("read","environments") or {}
        local saved, any = {}, false
        for _, entry in pairs(rs.data_envs[env_name] or {}) do
            if type(entry["scan"]) == "table" and entry["scan"].value then
                saved[entry["monitor"]], any = entry["scan"], true
            end
        end
        if not any then
            local text = "no scan is recorded for '" .. env_name .. "'"
            if explicit then
                rs.warn(text .. " (run `save` with `restore_scan` on, or `hs.restore_spaces.saveScan()`)", "scan")
            else
                rs.issueVerbose(text, rs.verbose, 1)
            end
            return
        end
        rs.writeScan(saved)
    end

    -- Action: record the scan of the monitors connected now (also done by `save`
    -- when `rs.restore_scan` is on). From the Hammerspoon console:
    -- hs.restore_spaces.saveScan()
    rs.saveScan = function()
        rs.runAction("save display scan", function()
            local env_name = rs.getEnvironmentName()
            if not env_name then
                error("These monitors are not a saved environment: run `save` first")
            end
            rs.stats.environment = env_name
            rs.measure("display scan", rs.recordScan, env_name)
        end)
    end

    -- Action: set the recorded scan of the monitors connected now (its own hotkey,
    -- because macOS forgets the scan after sleep or restart; also done by `apply`
    -- when `rs.restore_scan` is on)
    rs.applyScan = function()
        rs.runAction("apply display scan", function()
            local env_name = rs.getEnvironmentName()
            if not env_name then
                error("These monitors are not a saved environment: run `save` first")
            end
            rs.stats.environment = env_name
            rs.measure("display scan", rs.applyScanState, env_name, true)
        end)
    end

    -- Diagnostic: opens the Displays pane, selects each display in turn and dumps
    -- the accessibility tree of its settings; the scan slider is reported with its
    -- range, actions and whether its value can be set. The selection is restored.
    rs.probeDisplaySettings = function()
        hs.console.clearConsole()
        local lines = {rs.getSystemInfo()}
        local success, err = pcall(withDisplaysPane, function(window, app)
            local list = getAreas(window)
            for _, candidate in ipairs(attr(list, "AXChildren") or {}) do
                table.insert(lines, "listed display: " .. description(candidate))
            end
            for _, screen in ipairs(hs.screen.allScreens()) do
                table.insert(lines, "\n" .. rs.banner(4, "display: " .. screen:name()))
                local settings, how = selectDisplay(window, screen, app)
                if not settings then
                    table.insert(lines, "  (" .. tostring(how) .. ")")
                else
                    table.insert(lines, "  selected: " .. how)
                    rs.dumpTree(settings, 0, lines, 40, 8, true)
                    local slider = find(settings, isScanSlider, 6)
                    if slider then
                        local settable, actions = false, {}
                        pcall(function() settable = slider:isAttributeSettable("AXValue") end)
                        pcall(function() actions = slider:actionNames() end)
                        table.insert(lines, string.format("  SCAN SLIDER: value=%s min=%s max=%s settable=%s actions=%s",
                            tostring(attr(slider, "AXValue")), tostring(attr(slider, "AXMinValue")),
                            tostring(attr(slider, "AXMaxValue")), tostring(settable),
                            hs.inspect(actions, {newline = "", indent = ""})))
                    else
                        table.insert(lines, "  (no scan slider)")
                    end
                end
            end
        end)
        if not success then
            table.insert(lines, "ERROR: " .. tostring(err))
        end
        print("\n" .. rs.banner(1, "displays probe") .. "\n" .. table.concat(lines, "\n")
            .. "\n" .. rs.banner(1, "end of displays probe"))
    end

end