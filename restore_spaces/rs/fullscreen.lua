-- `fullscreen.lua`

-- Initialize full-screen functions (windows in full-screen and split-view spaces)
return function(rs,hs)

    -- Type of the first space of a window ("user", "fullscreen"...; nil if it has
    -- none) and that space
    local function getSpaceKind(window)
        local space = (hs.spaces.windowSpaces(window) or {})[1]
        return space and hs.spaces.spaceType(space), space
    end

    -- Whether a window is in a full-screen (or split-view) space
    rs.isInFullScreenSpace = function(window)
        local kind = getSpaceKind(window)
        return kind ~= nil and kind ~= "user" and kind ~= "system"
    end

    -- Make a window leave full screen (macOS then puts it on a desktop). The
    -- window must be on the active space of its screen.
    -- Returns: whether the window is on a desktop afterwards
    rs.leaveFullScreen = function(window)
        if not rs.isInFullScreenSpace(window) then return true end
        window:setFullScreen(false)
        return rs.waitUntil(function() return getSpaceKind(window) == "user" end, 4) and true or false
    end

    -- Whether a window of the list is the second of a split view (saved in the
    -- same slot as an earlier one): macOS has no way to create split views
    local function listCandidates(entries)
        local todo, slots = {}, {}
        for _, entry in ipairs(entries) do
            local state = entry.state
            if state["space_kind"] == "fullscreen" and entry.window
                and not rs.isInFullScreenSpace(entry.window) then
                local key = tostring(state["screen_index"]) .. ":" .. tostring(state["slot"])
                if slots[key] then
                    entry.manual = true
                    rs.addNote("Split views to set by hand", string.format("%s - %s (with %s)",
                        state["app"], rs.shortTitle(state["title"]), slots[key]))
                else
                    slots[key] = state["app"]
                    table.insert(todo, entry)
                end
            end
        end
        -- Last slot first: a new full-screen space is expected to appear right
        -- after the desktop that the window comes from, so the spaces that share
        -- a desktop come out in their saved order
        table.sort(todo, function(a, b)
            local first, second = a.state["screen_index"] or "", b.state["screen_index"] or ""
            if first ~= second then return first < second end
            return (a.state["slot"] or 0) > (b.state["slot"] or 0)
        end)
        return todo
    end

    -- Position (and count) of a space among the spaces of its screen
    local function getPosition(space)
        local screen = rs.getScreenByUUID(hs.spaces.spaceDisplay(space))
        local position, total
        for _, item in ipairs(screen and rs.getSpaceLayout(screen) or {}) do
            total = item.slot
            if item.id == space then position = item.slot end
        end
        return position, total
    end

    -- Put the recognized windows that were saved in full-screen spaces back in
    -- full screen: each one is moved to the desktop that preceded its space
    -- (`anchor`, mapped by `all_maps`) and made full screen from there. Windows
    -- already in a full-screen space are left alone. The active space of each
    -- screen is restored (`initial`: screen -> space). The position of every new
    -- space is logged: macOS decides where it goes.
    rs.restoreFullScreen = function(entries, all_maps, initial)
        if not rs.restore_fullscreen then return end
        for _, entry in ipairs(listCandidates(entries)) do
            local state, window = entry.state, entry.window
            local index = rs.paddedToStr(math.max(state["anchor"] or 0, 1))
            local pair = (all_maps[state["screen_index"] or ""] or {})[index]
            local desktop = pair and pair[2]
            local label = string.format("window %s of '%s'", tostring(entry.window_id), state["app"])
            if not desktop then
                rs.warn(label .. " was saved in a full-screen space, but its desktop is unknown", "fullscreen")
            elseif not rs.moveWindowToSpace(window, desktop) then
                rs.warn(label .. " could not be moved to its desktop to enter full screen", "fullscreen")
            else
                rs.gotoSpace(desktop)
                rs.delayExecution(rs.space_pause)
                window:setFullScreen(true)
                local arrived = rs.waitUntil(function()
                    local kind, space = getSpaceKind(window)
                    return kind ~= nil and kind ~= "user" and space
                end, 6)
                if arrived then
                    rs.delayExecution(rs.mc_settle)
                    local position, total = getPosition(arrived)
                    rs.issueVerbose(string.format("%s entered full screen at position %s of %s (saved: %s)",
                        label, tostring(position), tostring(total), tostring(state["slot"])), rs.verbose, 1)
                else
                    rs.warn(label .. " did not enter full screen", "fullscreen")
                end
            end
        end
        for screen, space in pairs(initial or {}) do
            if hs.spaces.activeSpaceOnScreen(screen) ~= space then
                rs.gotoSpace(space)
            end
        end
    end

    -- Compare the order of the spaces of each monitor (desktops and full-screen
    -- spaces) with the saved one; the result goes to the summary, and a warning
    -- (kind "order") says where it differs
    rs.reportSpaceOrder = function(env_name)
        local saved_env = (rs.data_envs or {})[env_name] or {}
        for screen_i, screen in ipairs(rs.getSortedScreens()) do
            local saved = (saved_env[rs.paddedToStr(screen_i)] or {})["layout"]
            if saved then
                local now = rs.getLayoutKinds(screen)
                if table.concat(now, ",") == table.concat(saved, ",") then
                    rs.addNote("Space order", string.format("%s: as saved (%s)", screen:name(),
                        rs.describeLayout(now)))
                else
                    local text = string.format("%s: now %s, saved %s (D: desktop, F: full screen)",
                        screen:name(), rs.describeLayout(now), rs.describeLayout(saved))
                    rs.addNote("Space order", text)
                    rs.warn("the order of the spaces differs: " .. text, "order")
                end
            end
        end
    end

end