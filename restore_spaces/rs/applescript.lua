-- `applescript.lua`

-- Initialize applescript functions (tab collection)
return function(rs,hs)

    -- Apps whose tabs can be listed by scripting them directly, with the script
    -- of each one in `scp/` (internal); other apps use the accessibility tree
    -- (if listed below) or tab cycling
    local direct_tab_scripts = {
        ["Safari"] = "scp/getTabsSafari.applescript",
        ["Google Chrome"] = "scp/getTabsChrome.applescript"
    }

    -- Apps whose tab strip can be read through the accessibility tree (internal).
    -- The value tells what a window without tab strip is: false = the tree is not
    -- built yet (Firefox builds it when asked), true = a window with a single tab
    -- (Finder shows no tab bar then).
    local ax_tab_apps = {
        ["Firefox"] = false,
        ["Finder"] = true
    }

    local function attr(element, name)
        local success, value = pcall(function() return element:attributeValue(name) end)
        return success and value or nil
    end

    -- Warn once per run about a key
    local function warnOnce(key, text, kind)
        if not rs.stats.noted[key] then
            rs.stats.noted[key] = true
            rs.warn(text, kind)
        end
    end

    rs.getPlistInfo = function(info)
        local plist_path = rs.packagePath(rs.config_path .. ".plist")
        if info == "path" then
            return plist_path
        else
            local key = info
            local plistTable = hs.plist.read(plist_path)
            if not plistTable then
                error("Failed to read plist file at: " .. plist_path)
            end
            if plistTable[key] ~= nil then
                local value = plistTable[key]
                return value
            else
                -- Key does not exist, handle accordingly
                return nil, "Key '" .. key .. "' does not exist in the plist file."
            end
        end
    end

    -- Create or destroy the plist with the settings of the AppleScript, which are
    -- those of the JSON file with the overrides of `rs.tab_cycling`
    rs.processPlistConfig = function(case)
        local plist_path = rs.getPlistInfo("path")

        if case == 'create' then
            local json_path = rs.packagePath(rs.config_path .. ".json")
            local json_file = io.open(json_path, "r")
            if not json_file then
                error("Unable to locate: " .. json_path)
            end
            local json_contents = json_file:read("*a")
            json_file:close()
            
            local json_table, _, err = hs.json.decode(json_contents)
            if not json_table then
                error("Failed to parse JSON: " .. err)
            end
            for key, value in pairs(rs.tab_cycling or {}) do
                json_table[key] = value
            end

            local success = hs.plist.write(plist_path, json_table, true)
            if not success then
                error("Failed to create PLIST file")
            end

        elseif case == 'destroy' then

            if not plist_path then
                error("PLIST path cannot be 'nil'")
            end
            local success, err = os.remove(plist_path)
            if not success then
                error("Failed to delete PLIST file: " .. err)
            end

        else
            error("Unknown routine to 'processPlistConfig' in case: " .. case)
        end

    end

    -- Parse the report of the tab cycling: a list of tab lists (one per window).
    -- Titles are split at the delimiter as plain text, so they may contain any
    -- character (`#` included).
    rs.buildTabList = function(output,report_delimiter)
        local applescript_delimiter = ", "
        local window_delimiter = report_delimiter .. report_delimiter
        local start_pattern = window_delimiter .. applescript_delimiter
        local end_pattern = applescript_delimiter .. window_delimiter

        local function split(text, delimiter)
            local parts, start = {}, 1
            while true do
                local from, to = text:find(delimiter, start, true)
                if not from then break end
                if from > start then table.insert(parts, text:sub(start, from - 1)) end
                start = to + 1
            end
            if start <= #text then table.insert(parts, text:sub(start)) end
            return parts
        end

        local newline_pattern = "\n+$"
        local processed_string = string.gsub(output, newline_pattern, end_pattern)

        local tab_lists = {}
        local window_pattern = start_pattern .. "(.-)" .. end_pattern
        for window_string in processed_string:gmatch(window_pattern) do
            local tab_titles = split(window_string, report_delimiter)
            if #tab_titles > 0 then
                table.insert(tab_lists, tab_titles)
            end
        end

        return tab_lists
    end

    -- Run `scp/getVisibleTabs.applescript` (tab cycling) for an app and parse its
    -- report. `titles` (optional) are the titles of the windows to read: the
    -- other windows of the app (_e.g._ on other monitors) are not cycled through.
    -- Besides the list of tab lists it returns how each window was cycled
    -- ({title, presses, reason, tabs}); the script writes that to its log
    -- (stderr). Reasons: loop (back at the first tab), stagnant (no new title
    -- for a while), identical (same title again and again), max (key press limit).
    rs.runApplescript = function(app, titles)
        local script_path = "scp/getVisibleTabs.applescript"
        local abs_path = rs.packagePath(script_path)
        local osascript = "/usr/bin/osascript"
        local plist_path = rs.getPlistInfo("path")
        local log_path = rs.packagePath("tmp/cycle.log")

        local args = {rs.shellQuote(abs_path), rs.shellQuote(app), rs.shellQuote(plist_path)}
        for _, title in ipairs(titles or {}) do
            table.insert(args, rs.shellQuote(title))
        end
        os.remove(log_path)
        local command = osascript .. " " .. table.concat(args, " ") .. " 2>" .. rs.shellQuote(log_path)
        local output, status, exitType, rc = hs.execute(command,true)
        
        local msg =  "Status: "..tostring(status)..", exit: "..tostring(exitType)
        msg = msg ..", rc: "..tostring(rc)
        rs.issueVerbose(msg,rs.verbose)
        rs.issueVerbose(hs.inspect(output),rs.verbose)
        if not status then
            rs.warn("tab cycling of '" .. app .. "' failed (exit code " .. tostring(rc) .. "): "
                .. tostring(output):sub(1, 200), "tabs")
        end

        local cycles = {}
        local log_file = io.open(log_path, "r")
        if log_file then
            for line in log_file:lines() do
                local title, presses, reason, count = line:match("^CYCLE|(.*)|(%d+)|(%a+)|(%d+)$")
                if title then
                    table.insert(cycles, {title = title, presses = tonumber(presses),
                        reason = reason, tabs = tonumber(count)})
                end
            end
            log_file:close()
            os.remove(log_path)
        end

        local report_delimiter = rs.getPlistInfo("reportDelimiter")
        local tab_list = rs.buildTabList(output,report_delimiter)
        return tab_list, cycles
    end

    -- Windows of an app with their tab titles, by scripting the app directly:
    -- a list of {id = window ID, active = title of the selected tab, tabs = {...}}.
    -- Raises an error if the app does not support it or the script fails (_e.g._
    -- the Automation permission was denied).
    rs.getDirectTabs = function(app)
        local script = direct_tab_scripts[app]
        if not script then
            error("do not use direct tab scripting with '" .. app .. "'")
        end
        local command = string.format("/usr/bin/osascript %s 2>&1", rs.shellQuote(rs.packagePath(script)))
        local output, status = hs.execute(command)
        if not status then
            error("direct tab scripting of '" .. app .. "' failed: " .. tostring(output))
        end
        local windows = {}
        for record in output:gmatch("[^\30]+") do
            if record:find("\31", 1, true) then
                local fields = {}
                for field in (record .. "\31"):gmatch("(.-)\31") do
                    table.insert(fields, field)
                end
                table.insert(windows, {id = fields[1], active = fields[2], tabs = {table.unpack(fields, 3)}})
            end
        end
        return windows
    end

    -- Tabs of the windows in `pending` (window ID -> title) by scripting the app
    -- directly: window ID -> tabs, for the windows that were found
    local function readDirect(app, pending)
        local found = {}
        local start = hs.timer.secondsSinceEpoch()
        local success, windows = pcall(rs.getDirectTabs, app)
        if not success then
            warnOnce("direct:" .. app, "direct tab scripting of '" .. app .. "' failed ("
                .. tostring(windows) .. "); using other methods", "tabs")
            return found
        end
        for window_id, title in pairs(pending) do
            local match
            for _, candidate in ipairs(windows) do
                if candidate.id == window_id then
                    match = candidate
                    break
                end
            end
            if not match then
                for _, candidate in ipairs(windows) do
                    if candidate.active ~= "" and title:sub(1, #candidate.active) == candidate.active then
                        match = candidate
                        break
                    end
                end
            end
            if match then
                found[window_id] = rs.list2dict(match.tabs)
            end
        end
        local seconds = (hs.timer.secondsSinceEpoch() - start) / math.max(1, rs.countEntries(pending))
        for window_id, title in pairs(pending) do
            if found[window_id] then
                rs.recordTabRead(app, title, "direct", rs.countEntries(found[window_id]), seconds)
            end
        end
        return found
    end

    -- Make an app build its accessibility tree (apps such as Firefox only do it
    -- when an assistive client asks for it)
    local function enableAccessibility(application)
        local element = hs.axuielement.applicationElement(application)
        for _, name in ipairs({"AXEnhancedUserInterface", "AXManualAccessibility"}) do
            pcall(function() element:setAttributeValue(name, true) end)
        end
    end

    -- Remove what Firefox adds to the label of a tab in a split view
    local function cleanTabTitle(title)
        return (title:gsub(",%s*Split view %a+$", ""))
    end

    -- Titles of the tabs of a window from its accessibility tree, in the order of
    -- the tab strip (which tab is selected does not matter): the radio buttons of
    -- its tab groups (web pages are not searched). Returns nil and a reason if the
    -- tree is not usable; "no tabs found" means that it is not built (yet), unless
    -- `lenient` (the app shows no tab strip for a single tab: the window then has
    -- one tab, its title).
    local function readAxTabs(window, lenient)
        local element = hs.axuielement.windowElement(window)
        if not element then return nil, "no accessibility element" end
        local titles, selected = {}, nil
        local function walk(node, depth, in_group)
            for _, child in ipairs(attr(node, "AXChildren") or {}) do
                local role = attr(child, "AXRole")
                if in_group and role == "AXRadioButton" then
                    local title = attr(child, "AXTitle")
                    if type(title) ~= "string" or title == "" then
                        title = attr(child, "AXDescription")
                    end
                    if type(title) == "string" and title ~= "" then
                        table.insert(titles, cleanTabTitle(title))
                        if attr(child, "AXValue") == 1 or attr(child, "AXValue") == true
                            or attr(child, "AXSelected") == true then
                            selected = #titles
                        end
                    end
                elseif depth < 10 and role ~= "AXWebArea" then
                    walk(child, depth + 1, in_group or role == "AXTabGroup")
                end
            end
        end
        walk(element, 1, false)
        local window_title = window:title()
        if #titles == 0 then
            if lenient and window_title ~= "" then return {window_title} end
            return nil, "no tabs found"
        end

        -- Sanity check: the tabs must be those of this window. Its title is the one
        -- of the selected tab, except for tabs without a title (the window is then
        -- named after the app, _e.g._ "Mozilla Firefox").
        local application = window:application()
        local app_name = application and application:name() or ""
        local function alike(a, b)
            return a == b or a:find(b, 1, true) ~= nil or b:find(a, 1, true) ~= nil
        end
        if selected then
            local generic = app_name ~= "" and window_title:find(app_name, 1, true) ~= nil
            if not generic and not alike(titles[selected], window_title) then
                return nil, string.format("the %d tabs found do not match the window title (selected: '%s')",
                    #titles, rs.redact(titles[selected]))
            end
        else
            for _, title in ipairs(titles) do
                if alike(title, window_title) then return titles end
            end
            return nil, string.format("none of the %d tabs found matches the window title", #titles)
        end
        return titles
    end

    -- Tabs of the windows in `pending` (window ID -> title) through the
    -- accessibility tree: window ID -> tabs, for the windows that were read
    local function readAccessibility(app, pending, windows)
        local found = {}
        if rs.stats.noted["ax-failed:" .. app] then return found end
        local lenient = ax_tab_apps[app]
        local start = hs.timer.secondsSinceEpoch()
        for window_id, title in pairs(pending) do
            local window = windows and windows[window_id] or hs.window.get(tonumber(window_id))
            local application = window and window:application()
            if application then
                if not lenient and not rs.stats.noted["ax-enabled:" .. app] then
                    rs.stats.noted["ax-enabled:" .. app] = true
                    enableAccessibility(application)
                end
                local tabs, reason
                for _ = 1, (lenient or rs.stats.noted["ax-works:" .. app]) and 1 or 10 do
                    tabs, reason = readAxTabs(window, lenient)
                    if tabs or reason ~= "no tabs found" then break end
                    rs.delayExecution(0.5)
                end
                if tabs then
                    rs.stats.noted["ax-works:" .. app] = true
                    found[window_id] = rs.list2dict(tabs)
                elseif reason == "no tabs found" then
                    rs.stats.noted["ax-failed:" .. app] = true
                    warnOnce("ax:" .. app, "the tabs of '" .. app .. "' are not in its accessibility tree"
                        .. " (run the tabs probe); cycling through tabs instead", "tabs")
                    break
                else
                    rs.issueVerbose(string.format("accessibility tabs of '%s' / '%s' rejected: %s",
                        app, rs.redact(title), tostring(reason)), rs.verbose, 1)
                end
            end
        end
        local seconds = (hs.timer.secondsSinceEpoch() - start) / math.max(1, rs.countEntries(pending))
        for window_id, title in pairs(pending) do
            if found[window_id] then
                rs.recordTabRead(app, title, "accessibility", rs.countEntries(found[window_id]), seconds)
            end
        end
        return found
    end

    -- Tabs of the windows in `pending` (window ID -> title) by cycling through
    -- them (slow, changes the focus, and it can activate the app, which can switch
    -- desktops, but it works for any app); only those windows are cycled through.
    -- Returns window ID -> tabs for the windows that were found.
    local function cycleTabs(app, pending)
        local titles = {}
        for _, title in pairs(pending) do
            table.insert(titles, title)
        end
        local start = hs.timer.secondsSinceEpoch()
        local tab_list, cycles = rs.runApplescript(app, titles)
        local elapsed = hs.timer.secondsSinceEpoch() - start
        rs.issueVerbose(string.format("cycling '%s': %d windows asked, %d tab lists and %d cycle records returned (%.1f s)",
            app, #titles, #tab_list, #cycles, elapsed), rs.verbose, 1)
        local total = 0
        for _, cycle in ipairs(cycles) do
            total = total + cycle.presses
        end

        local read, used, used_cycles = {}, {}, {}
        for window_id, title in pairs(pending) do
            local matched = false
            for i, window_tabs in ipairs(tab_list) do
                if not used[i] and window_tabs[1] == title then
                    used[i], matched = true, true
                    read[window_id] = rs.list2dict(window_tabs)
                    local info
                    for j, cycle in ipairs(cycles) do
                        if not used_cycles[j] and cycle.title == title then
                            used_cycles[j], info = true, cycle
                            break
                        end
                    end
                    local seconds = elapsed / math.max(1, #titles)
                    local note
                    if info then
                        seconds = total > 0 and elapsed * info.presses / total or seconds
                        note = string.format("%d key presses, stopped: %s", info.presses, info.reason)
                        if info.reason == "max" or info.reason == "identical" then
                            rs.warn(string.format("cycling the tabs of a window of '%s' stopped by '%s' after %d key presses (%d tabs found)",
                                app, info.reason, info.presses, info.tabs), "tabs")
                        end
                    end
                    rs.recordTabRead(app, title, "cycling", #window_tabs, seconds, note)
                    break
                end
            end
            if not matched then
                rs.issueVerbose(string.format("cycling '%s' returned no tab list for window %s ('%s')",
                    app, window_id, rs.redact(title)), rs.verbose, 1)
            end
        end
        return read
    end

    local function without(pending, found)
        local rest = {}
        for window_id, title in pairs(pending) do
            if not found[window_id] then rest[window_id] = title end
        end
        return rest
    end

    local function merge(target, source)
        for key, value in pairs(source) do target[key] = value end
    end

    -- Read the tabs of the windows in `pending` (window ID -> title): by scripting
    -- the app where possible, else through its accessibility tree, else by cycling
    -- (also for what the other methods could not read)
    local function readTabs(app, pending, windows)
        local read = {}
        if rs.use_direct_tabs and direct_tab_scripts[app] then
            merge(read, readDirect(app, pending))
            pending = without(pending, read)
        end
        if rs.use_ax_tabs and ax_tab_apps[app] ~= nil and next(pending) then
            merge(read, readAccessibility(app, pending, windows))
            pending = without(pending, read)
        end
        if next(pending) then
            merge(read, cycleTabs(app, pending))
        end
        return read
    end

    -- Tabs of the windows of `app` (`id2title`: window ID -> title; `windows`:
    -- window ID -> window, optional) as window ID -> tabs. Tab lists are remembered
    -- during the running action, so a window is read only once even if it is
    -- visited again (_e.g._ after being moved); a window that cannot be read gets a
    -- list with its title only (and a warning).
    rs.getAppTabsInSpace = function(app, id2title, windows)
        local app_tabs, pending = {}, {}
        for window_id, title in pairs(id2title) do
            local cached = rs.stats.tabs[window_id]
            if cached then
                app_tabs[window_id] = cached
                rs.recordTabRead(app, title, "cache", rs.countEntries(cached), 0)
            else
                pending[window_id] = title
            end
        end
        if next(pending) then
            local read = rs.measure("reading tabs", readTabs, app, pending, windows)
            for window_id, title in pairs(pending) do
                local tabs = read[window_id]
                if not tabs then
                    rs.warn(string.format("tabs of window %s of '%s' could not be read; only its title is used",
                        window_id, app), "tabs")
                    tabs = rs.list2dict({title})
                end
                rs.stats.tabs[window_id] = tabs
                app_tabs[window_id] = tabs
            end
        end
        return app_tabs
    end

    -- Number of the parts of each title once it is split at "#" (old saved states
    -- were split like that by a bug, so both kinds of lists must be comparable)
    local function tabBag(tabs)
        local counts, total = {}, 0
        for _, title in pairs(rs.validateTable(tabs)) do
            for part in (tostring(title) .. "#"):gmatch("([^#]*)#") do
                if part ~= "" then
                    counts[part] = (counts[part] or 0) + 1
                    total = total + 1
                end
            end
        end
        return counts, total
    end

    -- Compare the tab titles of a window with a saved list; repeated titles count
    -- as many times as they appear in both lists. Returns whether both lists
    -- share at least the similarity threshold of `rs.multitab_comparison` and the
    -- lower of the two ratios. Neither the order of the tabs nor the selected one
    -- matters.
    rs.compareTabs = function(window_tabs,stored_tabs)
        local current, n_window = tabBag(window_tabs)
        local available, n_stored = tabBag(stored_tabs)
        if n_window == 0 or n_stored == 0 then
            rs.issueVerbose("Comparison not possible with empty table; returning false", rs.verbose)
            return false, 0
        end

        local matches = 0
        for part, count in pairs(current) do
            matches = matches + math.min(count, available[part] or 0)
        end

        local tab_limit
        if n_window <= rs.multitab_comparison["critical_tab_count"] then
            tab_limit = rs.multitab_comparison["small_similarity_threshold"]
        else
            tab_limit = rs.multitab_comparison["large_similarity_threshold"]
        end
        local score = math.min(matches / n_window, matches / n_stored)
        return score >= tab_limit, score
    end

    -- Lines describing every radio button that the tab reading would count in a
    -- window: where it sits in the tree, its subrole, identifier, value, size and
    -- whether it lies inside the window (to find what is counted but is not a tab)
    local function describeAxTabs(window, lines)
        local element = hs.axuielement.windowElement(window)
        if not element then
            table.insert(lines, "    (no accessibility element)")
            return
        end
        local frame = window:frame()
        local buttons, counts, order = {}, {}, {}
        local function label(node)
            local text = tostring(attr(node, "AXRole") or "?")
            local identifier = attr(node, "AXIdentifier")
            if type(identifier) == "string" and identifier ~= "" then
                text = text .. "[" .. identifier:sub(1, 30) .. "]"
            end
            return text
        end
        local function walk(node, path, depth, in_group)
            for _, child in ipairs(attr(node, "AXChildren") or {}) do
                local role = attr(child, "AXRole")
                if in_group and role == "AXRadioButton" then
                    if not counts[path] then
                        counts[path] = 0
                        table.insert(order, path)
                    end
                    counts[path] = counts[path] + 1
                    table.insert(buttons, child)
                elseif depth < 10 and role ~= "AXWebArea" then
                    walk(child, path .. "/" .. label(child), depth + 1, in_group or role == "AXTabGroup")
                end
            end
        end
        walk(element, "", 1, false)
        table.insert(lines, string.format("    %d radio buttons in %d places of the tree:", #buttons, #order))
        for _, path in ipairs(order) do
            table.insert(lines, string.format("      %4d  %s", counts[path], path))
        end
        local function show(i)
            local child = buttons[i]
            local position, size = attr(child, "AXPosition"), attr(child, "AXSize")
            local inside = position and size and position.x >= frame.x - 1 and position.y >= frame.y - 1
                and position.x + size.w <= frame.x + frame.w + 1 and position.y + size.h <= frame.y + frame.h + 1
            table.insert(lines, string.format("      #%d subrole=%s id=%s value=%s size=%s inside=%s '%s'",
                i, tostring(attr(child, "AXSubrole")), tostring(attr(child, "AXIdentifier")):sub(1, 40),
                tostring(attr(child, "AXValue")),
                size and string.format("%.0fx%.0f", size.w, size.h) or "?", tostring(inside),
                rs.redact(attr(child, "AXTitle") or attr(child, "AXDescription") or "")))
        end
        if #buttons <= 60 then
            for i = 1, #buttons do show(i) end
        else
            for i = 1, 10 do show(i) end
            table.insert(lines, "      ...")
            for i = #buttons - 9, #buttons do show(i) end
        end
    end

    -- Diagnostic: for each visible window of the apps read through accessibility
    -- (and of tab apps that have no scripting), prints how many tabs the reading
    -- finds, every place of the tree that holds radio buttons and, per button, the
    -- data that tells a tab from something else; if the tree is not usable, the top
    -- of the tree. Only windows on the active desktops are visible to it.
    rs.probeTabs = function()
        hs.console.clearConsole()
        rs.resetStats()
        local lines = {rs.getSystemInfo()}
        local apps, enabled = {}, {}
        for name in pairs(ax_tab_apps) do apps[name] = true end
        for _, name in ipairs(rs.getTabApps()) do
            if not direct_tab_scripts[name] then apps[name] = true end
        end
        for _, window in ipairs(hs.window.visibleWindows()) do
            local application = window:application()
            local name = application and application:name()
            if name and apps[name] and window:isStandard() then
                local lenient = ax_tab_apps[name]
                if not lenient and not enabled[name] then
                    enableAccessibility(application)
                    enabled[name] = true
                    rs.delayExecution(1)
                end
                local tabs, reason
                for _ = 1, 6 do
                    tabs, reason = readAxTabs(window, lenient)
                    if tabs or reason ~= "no tabs found" then break end
                    rs.delayExecution(0.5)
                end
                table.insert(lines, string.format("%s / '%s': %s", name, rs.redact(window:title()),
                    tabs and (#tabs .. " tabs through accessibility")
                        or ("NOT READABLE (" .. tostring(reason) .. ")")))
                describeAxTabs(window, lines)
                if not tabs then
                    table.insert(lines, "    top of its tree:")
                    local element = hs.axuielement.windowElement(window)
                    if element then rs.dumpTree(element, 0, lines, 12, 5, true) end
                end
            end
        end
        print("\n" .. rs.banner(1, "tabs probe") .. "\n" .. table.concat(lines, "\n")
            .. "\n" .. rs.banner(1, "end of tabs probe"))
    end

end