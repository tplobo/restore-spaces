-- `spaces.lua`

-- Initialize space-control functions (native API with Mission Control fallback)
return function(rs,hs)

    -- Processes that may host the Mission Control accessibility tree (in order)
    local mc_hosts = {"com.apple.WindowManager", "com.apple.dock"}

    -- Mouse event number shared by all events of one synthetic drag gesture
    local drag_counter = 32000

    -- Safe read of an accessibility attribute (nil if missing or invalid)
    local function getAttribute(element, name)
        local success, value = pcall(function() return element:attributeValue(name) end)
        return success and value or nil
    end

    -- Descendants of `root` (up to `max_depth` levels) with the given AXIdentifier
    local function findElements(root, identifier, max_depth)
        local found = {}
        local function walk(node, depth)
            for _, child in ipairs(getAttribute(node, "AXChildren") or {}) do
                if getAttribute(child, "AXIdentifier") == identifier then
                    table.insert(found, child)
                elseif depth < max_depth then
                    walk(child, depth + 1)
                end
            end
        end
        walk(root, 1)
        return found
    end

    -- Bounding box {x, y, w, h} of an accessibility element
    local function getBox(element)
        local position = getAttribute(element, "AXPosition")
        local size = getAttribute(element, "AXSize")
        if position and size then
            return {x = position.x, y = position.y, w = size.w, h = size.h}
        end
    end

    -- Point on an element: its center or, if `anchored`, its reported anchor
    -- (`WindowManager` reports an anchor that is already inside the thumbnail)
    local function getPoint(element, anchored)
        local box = getBox(element)
        if not box then return nil end
        if anchored then
            return {x = box.x, y = box.y}
        end
        return {x = box.x + box.w / 2, y = box.y + box.h / 2}
    end

    -- Mission Control tree: {displays = {...}, host = bundle ID} (nil if closed)
    local function getMissionControl()
        for _, bundle in ipairs(mc_hosts) do
            local app = hs.application.applicationsForBundleID(bundle)[1]
            local root = app and hs.axuielement.applicationElement(app)
            local displays = root and findElements(root, "mc.display", 3) or {}
            if #displays > 0 then
                return {displays = displays, host = bundle}
            end
        end
    end

    -- Poll `predicate` until it returns a truthy value or `rs.mc_timeout` expires
    local function waitUntil(predicate)
        local waited = 0
        local value = predicate()
        while not value and waited < rs.mc_timeout do
            rs.delayExecution(rs.mc_pause)
            waited = waited + rs.mc_pause
            value = predicate()
        end
        return value
    end

    -- Run `action(mc)` with Mission Control open; close it afterwards unless
    -- `keep_open`. Returns the action results, or nil and an error message.
    local function withMissionControl(action, keep_open)
        local mc = getMissionControl()
        if not mc then
            hs.spaces.openMissionControl()
            mc = waitUntil(getMissionControl)
        end
        local success, result, err = false, nil, "Mission Control tree not found"
        if mc then
            success, result, err = pcall(action, mc)
            if not success then
                result, err = nil, result
            end
        end
        if not keep_open and (getMissionControl() or not mc) then
            hs.spaces.closeMissionControl()
        end
        return result, err
    end

    local function getScreenByUUID(uuid)
        for _, screen in ipairs(hs.screen.allScreens()) do
            if screen:getUUID() == uuid then return screen end
        end
    end

    -- `mc.display` group of a screen (by display ID or by full frame)
    local function findDisplay(mc, screen)
        local frame = screen:fullFrame()
        for _, display in ipairs(mc.displays) do
            local box = getBox(display)
            local same_frame = box
                and math.abs(box.x - frame.x) < 2 and math.abs(box.y - frame.y) < 2
                and math.abs(box.w - frame.w) < 2 and math.abs(box.h - frame.h) < 2
            if getAttribute(display, "AXDisplayID") == screen:id() or same_frame then
                return display
            end
        end
    end

    -- Run `action(display, mc)` for the Mission Control display of `screen`
    local function withDisplay(screen, action, keep_open)
        return withMissionControl(function(mc)
            local display = findDisplay(mc, screen)
            if not display then
                error("display not found in Mission Control", 0)
            end
            return action(display, mc)
        end, keep_open)
    end

    -- Space thumbnails (desktop buttons) of a Mission Control display
    local function getThumbnails(display)
        local list = findElements(display, "mc.spaces.list", 3)[1]
        return list and getAttribute(list, "AXChildren") or {}
    end

    -- Position of a space among the thumbnails of its screen (the hidden
    -- "dashboard" space has no thumbnail), and that screen
    local function getSpaceIndex(space)
        local uuid = hs.spaces.spaceDisplay(space)
        local index = 0
        for _, id in ipairs(hs.spaces.allSpaces()[uuid] or {}) do
            if hs.spaces.spaceType(id) ~= "system" then
                index = index + 1
            end
            if id == space then
                return index, getScreenByUUID(uuid)
            end
        end
    end

    local function countSpaces(screen)
        return #(hs.spaces.spacesForScreen(screen:id()) or {})
    end

    -- Switch to a space by pressing its thumbnail in Mission Control
    local function gotoSpaceViaMC(space)
        local index, screen = getSpaceIndex(space)
        if not screen then
            return nil, "unknown space: " .. tostring(space)
        end
        return withDisplay(screen, function(display)
            local thumbnail = getThumbnails(display)[index]
            if not (thumbnail and thumbnail:performAction("AXPress")) then
                error("failed to press space thumbnail", 0)
            end
            local active = function()
                return hs.spaces.activeSpaceOnScreen(screen) == space
            end
            if not waitUntil(active) then
                error("space did not become active", 0)
            end
            return true
        end)
    end

    -- Go to a space. Uses the native API, falling back to Mission Control
    -- (the native API fails where the accessibility tree has moved).
    -- Returns: true | nil, error message
    rs.gotoSpace = function(space)
        local status, err = hs.spaces.gotoSpace(space)
        if not status then
            local msg = "native gotoSpace failed (" .. tostring(err) .. ")"
            rs.issueVerbose(msg .. "; using Mission Control", rs.verbose)
            status, err = gotoSpaceViaMC(space)
        end
        if not status then
            print("(gotoSpace) failed for space " .. tostring(space) .. ": " .. tostring(err))
        end
        return status, err
    end

    -- Add a space to a screen (native API, falling back to Mission Control).
    -- `close_mc == false` keeps Mission Control open for consecutive calls.
    -- Returns: true | nil, error message
    rs.addSpaceToScreen = function(screen, close_mc)
        local status, err = hs.spaces.addSpaceToScreen(screen, close_mc)
        if status then return true end
        local count = countSpaces(screen)
        return withDisplay(screen, function(display)
            local button = findElements(display, "mc.spaces.add", 4)[1]
            if not (button and button:performAction("AXPress")) then
                error("add-space button not found", 0)
            end
            if not waitUntil(function() return countSpaces(screen) > count end) then
                error("space was not added", 0)
            end
            return true
        end, close_mc == false)
    end

    -- Remove a space (native API, falling back to Mission Control).
    -- Returns: true | nil, error message
    rs.removeSpace = function(space, close_mc)
        local status, err = hs.spaces.removeSpace(space, close_mc)
        if status then return true end
        local index, screen = getSpaceIndex(space)
        if not screen then
            return nil, "unknown space: " .. tostring(space)
        end
        return withDisplay(screen, function(display)
            local thumbnail = getThumbnails(display)[index]
            local removed = thumbnail and thumbnail:performAction("AXRemoveDesktop")
            if thumbnail and not removed then
                for _, child in ipairs(getAttribute(thumbnail, "AXChildren") or {}) do
                    removed = removed or child:performAction("AXPress")
                end
            end
            local gone = function()
                return not rs.contains(hs.spaces.spacesForScreen(screen:id()) or {}, space)
            end
            if not (removed and waitUntil(gone)) then
                error("space was not removed", 0)
            end
            return true
        end, close_mc == false)
    end

    -- Window thumbnails of a display that belong to the `source` space
    local function getWindowThumbnails(display, source)
        local thumbnails = {}
        local function walk(node, depth)
            for _, child in ipairs(getAttribute(node, "AXChildren") or {}) do
                local id = tostring(getAttribute(child, "AXIdentifier"))
                local owner = id:match("%.space%.(%d+)$")
                if not id:match("^mc%.spaces") then
                    if getAttribute(child, "AXRole") == "AXButton" then
                        if not owner or tonumber(owner) == source then
                            table.insert(thumbnails, child)
                        end
                    elseif depth < 3 then
                        walk(child, depth + 1)
                    end
                end
            end
        end
        walk(display, 1)
        return thumbnails
    end

    -- Compare a thumbnail title with a window title; Mission Control shortens
    -- long titles with a middle ellipsis
    local function titleMatches(shown, title)
        if shown == title then return true end
        local head, tail = shown:match("^(.-)…(.*)$")
        return head ~= nil
            and #title >= #head + #tail
            and title:sub(1, #head) == head
            and (tail == "" or title:sub(-#tail) == tail)
    end

    local function postMouse(kind, point, previous, number)
        local event = hs.eventtap.event
        local mouse = event.newMouseEvent(event.types[kind], point)
        mouse:setProperty(event.properties.mouseEventNumber, number)
        mouse:setProperty(event.properties.mouseEventClickState, 1)
        mouse:setProperty(event.properties.mouseEventPressure, kind == "leftMouseUp" and 0 or 1)
        mouse:setProperty(event.properties.mouseEventDeltaX, point.x - previous.x)
        mouse:setProperty(event.properties.mouseEventDeltaY, point.y - previous.y)
        mouse:post()
    end

    -- Drag (button held) from one point to another in small timed steps
    local function glide(from, to, number)
        local previous = from
        for step = 1, rs.mc_drag_steps do
            local point = {
                x = from.x + (to.x - from.x) * step / rs.mc_drag_steps,
                y = from.y + (to.y - from.y) * step / rs.mc_drag_steps
            }
            postMouse("leftMouseDragged", point, previous, number)
            previous = point
            rs.delayExecution(rs.mc_drag_pause)
        end
        return to
    end

    -- Move a window by dragging its Mission Control thumbnail onto a space
    -- thumbnail; success is verified with the window's actual spaces.
    -- Windows with identical titles are indistinguishable (first one is used).
    local function moveWindowViaMC(window, space)
        local index, target_screen = getSpaceIndex(space)
        local source = (hs.spaces.windowSpaces(window) or {})[1]
        if not (index and source) then
            return nil, "unknown source or target space"
        end
        if source == space then return true end

        local cursor = hs.mouse.absolutePosition()
        local result, err = withMissionControl(function(mc)
            local title = window:title()
            local source_display = findDisplay(mc, window:screen())
            local target_display = findDisplay(mc, target_screen)
            if not (source_display and target_display) then
                error("display not found in Mission Control", 0)
            end
            local matches = hs.fnutils.filter(
                getWindowThumbnails(source_display, source),
                function(thumbnail)
                    return titleMatches(getAttribute(thumbnail, "AXTitle") or "", title)
                end
            )
            if #matches == 0 then
                error("window thumbnail not found: " .. title, 0)
            elseif #matches > 1 then
                rs.issueVerbose("ambiguous title; using first thumbnail: " .. title, rs.verbose)
            end

            -- Hover the top edge of the target display to expand its spaces bar
            local box = getBox(target_display)
            local start = getPoint(matches[1])
            local top = {x = box.x + box.w / 2, y = box.y + 2}
            drag_counter = drag_counter + 1
            local number, last = drag_counter, start
            local success, drag_err = pcall(function()
                hs.mouse.absolutePosition(start)
                rs.delayExecution(rs.mc_pause)
                postMouse("leftMouseDown", start, start, number)
                last = glide(start, top, number)
                rs.delayExecution(rs.mc_settle)
                local drop = getPoint(getThumbnails(target_display)[index], mc.host == mc_hosts[1])
                if not drop then
                    error("target space thumbnail not found", 0)
                end
                last = glide(top, drop, number)
                rs.delayExecution(rs.mc_settle)
            end)
            postMouse("leftMouseUp", last, last, number)
            if not success then error(drag_err, 0) end

            local arrived = function()
                return rs.contains(hs.spaces.windowSpaces(window) or {}, space)
            end
            if not waitUntil(arrived) then
                error("window did not arrive at space " .. tostring(space), 0)
            end
            return true
        end)
        hs.mouse.absolutePosition(cursor)
        return result, err
    end

    -- Native API up to macOS 14 (verified there); from macOS 15 it reports
    -- success without moving the window, so Mission Control is used instead
    local function moveWindow(window, space)
        if hs.host.operatingSystemVersion().major <= 14 then
            return hs.spaces.moveWindowToSpace(window, space)
        end
        return moveWindowViaMC(window, space)
    end

    -- First/last user space (per `rs.fallback_space`) of the screen of a space
    local function getFallbackSpace(space)
        local user_spaces = {}
        for _, id in ipairs(hs.spaces.allSpaces()[hs.spaces.spaceDisplay(space)] or {}) do
            if hs.spaces.spaceType(id) == "user" then
                table.insert(user_spaces, id)
            end
        end
        return rs.fallback_space == "last" and user_spaces[#user_spaces] or user_spaces[1]
    end

    -- Move a window to a space. If that fails, the window goes to the fallback
    -- space of the target screen, or else to that screen (visible console
    -- warning in all cases).
    -- Returns: true | nil, error message
    rs.moveWindowToSpace = function(window, space)
        if not space then
            return nil, "undefined target space"
        end
        local status, err = moveWindow(window, space)
        if status then return true end

        local fallback = getFallbackSpace(space)
        local screen = getScreenByUUID(hs.spaces.spaceDisplay(space))
        local outcome = "window left in place"
        if fallback and fallback ~= space and moveWindow(window, fallback) then
            outcome = "moved to fallback space " .. fallback
        elseif screen and window:screen() ~= screen then
            window:moveToScreen(screen)
            outcome = "moved to screen '" .. screen:name() .. "'"
        end
        print("(moveWindowToSpace) WARNING: window " .. window:id() .. " -> space "
            .. tostring(space) .. " failed (" .. tostring(err) .. "): " .. outcome)
        if outcome == "window left in place" then
            return nil, err
        end
        rs.fallback_count = rs.fallback_count + 1
        return true
    end

    -- One-line description of the machine and the strategies in use
    rs.getSystemInfo = function()
        local version = hs.host.operatingSystemVersion()
        local screens = {}
        for _, screen in ipairs(hs.screen.allScreens()) do
            table.insert(screens, screen:name() .. " [" .. tostring(screen:fullFrame()) .. "]")
        end
        return string.format(
            "macOS %d.%d.%d, Hammerspoon %s, separate spaces: %s, move: %s, screens: %s",
            version.major, version.minor, version.patch, hs.processInfo.version,
            tostring(hs.spaces.screensHaveSeparateSpaces()),
            version.major <= 14 and "native" or "Mission Control",
            table.concat(screens, "; ")
        )
    end

    rs.logSystemInfo = function()
        rs.issueVerbose(rs.getSystemInfo(), rs.verbose)
    end

    -- Append an indented dump of an accessibility subtree to `lines`
    local function dumpTree(element, depth, lines)
        local function show(name)
            return hs.inspect(getAttribute(element, name), {newline = "", indent = ""})
        end
        local fields = {show("AXRole"), show("AXIdentifier"), show("AXTitle"),
                        show("AXPosition"), show("AXSize")}
        table.insert(lines, string.rep("  ", depth + 1) .. table.concat(fields, " | "))
        if depth < 5 then
            for i, child in ipairs(getAttribute(element, "AXChildren") or {}) do
                if i > 40 then
                    table.insert(lines, string.rep("  ", depth + 2) .. "...")
                    break
                end
                dumpTree(child, depth + 1, lines)
            end
        end
    end

    -- Diagnostic: tests goto/move with the focused window (needs 2+ user spaces
    -- on its screen) and dumps the Mission Control tree. Prints one report;
    -- window titles appear in it, so redact before sharing.
    rs.testSpaceControl = function()
        local lines = {rs.getSystemInfo()}
        local function report(text) table.insert(lines, text) end
        local function timed(label, action)
            local start = hs.timer.secondsSinceEpoch()
            local success, status, err = pcall(action)
            if not success then status, err = nil, status end
            report(string.format("%-24s %s (%.2fs) %s", label, status and "OK" or "FAIL",
                hs.timer.secondsSinceEpoch() - start, tostring(err or "")))
        end

        local window = hs.window.focusedWindow()
        local screen = window and window:screen()
        local active = screen and hs.spaces.activeSpaceOnScreen(screen)
        local other
        for _, id in ipairs(screen and hs.spaces.spacesForScreen(screen:id()) or {}) do
            if id ~= active and hs.spaces.spaceType(id) == "user" then
                other = id
                break
            end
        end

        if other then
            report("active space " .. active .. ", test space " .. other)
            timed("goto other", function() return rs.gotoSpace(other) end)
            timed("goto back", function() return rs.gotoSpace(active) end)
            timed("move to other", function() return moveWindow(window, other) end)
            timed("goto moved window", function() return rs.gotoSpace(other) end)
            timed("move back", function() return moveWindow(window, active) end)
            timed("goto original", function() return rs.gotoSpace(active) end)
        else
            report("SKIPPED tests: need a focused window and 2+ user spaces on its screen")
        end

        hs.spaces.openMissionControl()
        waitUntil(getMissionControl)
        for _, bundle in ipairs(mc_hosts) do
            report("Mission Control tree under " .. bundle .. ":")
            local app = hs.application.applicationsForBundleID(bundle)[1]
            if app then
                dumpTree(hs.axuielement.applicationElement(app), 0, lines)
            else
                report("  (process not running)")
            end
        end
        if getMissionControl() then hs.spaces.closeMissionControl() end

        print("---- restore_spaces diagnostic ----\n" .. table.concat(lines, "\n"))
    end

end