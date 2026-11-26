-- `recognition.lua`

-- Initialize recognition functions (which open window is which saved window)
return function(rs,hs)

    -- Whether a saved window with the ID of an open window is that window: IDs
    -- are reused after a restart, so the app (and the boot time, if recorded)
    -- must agree
    local function isSameWindow(entry, state, boot)
        local saved = entry.state
        if saved["app"] ~= state["app"] then return false end
        if saved["boot"] and boot then return math.abs(saved["boot"] - boot) < 60 end
        return true
    end

    local function claim(info, entry, how)
        entry.window_id, info.entry = info.id, entry
        rs.issueVerbose(string.format("window %s of '%s' recognized by %s: '%s'",
            info.id, info.state["app"], how, rs.redact(info.state["title"])), rs.verbose, 1)
    end

    -- Saved window (not matched yet) of the same app with the same title or, for
    -- apps with title terms, with the same term. `untabbed`: only saved windows
    -- that have no tab list (states of older versions).
    local function findByTitle(entries, app, title, untabbed)
        local key = rs.getTitleKey(app, title)
        local by_key
        for _, entry in ipairs(entries) do
            local state = entry.state
            if not entry.window_id and state["app"] == app
                and not (untabbed and rs.countEntries(state["tabs"]) > 0) then
                if state["title"] == title then return entry end
                if key and not by_key and rs.getTitleKey(app, state["title"]) == key then
                    by_key = entry
                end
            end
        end
        return by_key
    end

    -- The saved window of an app (rule "app") if the app has exactly one and it
    -- is not matched yet: its title can be anything (_e.g._ Teams shows its view)
    local function findOnlyWindow(entries, app)
        local found, count = nil, 0
        for _, entry in ipairs(entries) do
            if entry.state["app"] == app then
                count = count + 1
                if not entry.window_id then found = entry end
            end
        end
        return count == 1 and found or nil
    end

    -- Match multi-tab windows with saved windows of the same app by their tabs:
    -- the most alike pairs first (above `rs.multitab_comparison`), then the saved
    -- window with the same title if it is the only one left and its tabs are alike
    -- enough (`title_fallback_threshold`). What was closest is logged for the
    -- windows that stay unrecognized. The order of the tabs and which one is
    -- selected do not matter.
    local function matchByTabs(entries, infos, tabs)
        local candidates, scores = {}, {}
        for _, info in ipairs(infos) do
            scores[info.id] = {}
            for _, entry in ipairs(entries) do
                if not entry.window_id and entry.state["app"] == info.state["app"] then
                    local similar, score = rs.compareTabs(tabs[info.id], entry.state["tabs"])
                    scores[info.id][entry] = score
                    table.insert(candidates, {info = info, entry = entry, score = score, similar = similar})
                end
            end
        end
        table.sort(candidates, function(a, b) return a.score > b.score end)
        for _, candidate in ipairs(candidates) do
            if candidate.similar and not candidate.info.entry and not candidate.entry.window_id then
                claim(candidate.info, candidate.entry,
                    string.format("its tabs (%.0f%% alike)", candidate.score * 100))
            end
        end

        local minimum = rs.multitab_comparison["title_fallback_threshold"] or 0.25
        for _, info in ipairs(infos) do
            if not info.entry then
                local same, closest_title, closest_score = {}, nil, -1
                for entry, score in pairs(scores[info.id]) do
                    if not entry.window_id then
                        if score > closest_score then
                            closest_title, closest_score = entry.state["title"], score
                        end
                        if entry.state["title"] == info.state["title"] then
                            table.insert(same, entry)
                        end
                    end
                end
                local near = closest_title
                    and string.format("closest saved window: '%s', %.0f%% alike", rs.redact(closest_title), closest_score * 100)
                    or "no saved window of this app is left"
                local own = #same == 1 and scores[info.id][same[1]] or 0
                if #same == 1 and own >= minimum then
                    claim(info, same[1], string.format("its title (its tabs are %.0f%% alike)", own * 100))
                else
                    rs.issueVerbose(string.format("window %s of '%s' ('%s') not recognized (%s; %d saved windows have its title%s)",
                        info.id, info.state["app"], rs.redact(info.state["title"]), near, #same,
                        #same == 1 and string.format(", tabs only %.0f%% alike", own * 100) or ""), rs.verbose, 1)
                end
            end
        end
    end

    -- Saved windows of an environment: {entries, by_id, boot}, where each entry is
    -- {id, state, window_id} and `window_id` is the open window matched with it
    rs.loadSavedWindows = function(env_state)
        local entries, by_id = {}, {}
        for id, state in pairs(env_state) do
            local entry = {id = id, state = rs.legacy.normalizeState(state)}
            table.insert(entries, entry)
            by_id[id] = entry
        end
        table.sort(entries, function(a, b) return tostring(a.id) < tostring(b.id) end)
        return {entries = entries, by_id = by_id, boot = rs.getBootTime()}
    end

    -- Recognize the open windows `infos` of a visited space (`info.entry` is the
    -- saved window of each recognized one): 1) by saved ID, 2) by title (a title
    -- term, or the only saved window of the app, for apps with such a rule),
    -- 3) multi-tab windows by their tabs (read once per window and run)
    rs.recognizeWindows = function(saved, infos, screen, space)
        for _, info in ipairs(infos) do
            local entry = saved.by_id[info.id]
            if entry and not entry.window_id and isSameWindow(entry, info.state, saved.boot) then
                claim(info, entry, "its ID")
            end
        end

        local multitab = {}
        for _, info in ipairs(infos) do
            if not info.entry then
                local app, title = info.state["app"], info.state["title"]
                local entry = findByTitle(saved.entries, app, title, info.state["multitab"])
                if entry then
                    claim(info, entry, "its title")
                elseif info.state["multitab"] then
                    table.insert(multitab, info)
                else
                    entry = rs.getRecognition(app) == "app" and findOnlyWindow(saved.entries, app)
                    if entry then
                        claim(info, entry, "its app")
                    else
                        rs.issueVerbose(string.format("window %s of '%s' ('%s') is not in the saved state",
                            info.id, app, rs.redact(title)), rs.verbose, 1)
                    end
                end
            end
        end

        if #multitab > 0 then
            matchByTabs(saved.entries, multitab, rs.readSpaceTabs(screen, space, multitab))
        end
    end

    -- Add the saved windows that were not found to `rs.stats.missing`, with the
    -- state of their app (from the list of running apps: looking apps up by name
    -- prints Spotlight hints)
    rs.listMissingWindows = function(entries)
        local running = {}
        for _, application in ipairs(hs.application.runningApplications()) do
            running[application:name() or ""] = true
        end
        for _, entry in ipairs(entries) do
            if not entry.window_id then
                local app = entry.state["app"] or "?"
                table.insert(rs.stats.missing, {
                    app = app .. (running[app] and " (app open)" or " (app not running)"),
                    title = entry.state["title"] or ""})
            end
        end
        table.sort(rs.stats.missing, function(a, b)
            if a.app ~= b.app then return a.app < b.app end
            return a.title < b.title
        end)
    end

end