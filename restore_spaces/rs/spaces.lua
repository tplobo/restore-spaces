-- `spaces.lua`

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

    local function filterList(list, predicate)
        local result = {}
        for _, element in ipairs(list) do
            if predicate(element) then
                table.insert(result, element)
            end
        end
        return result
    end

    local function indexOf(list, value)
        for i, element in ipairs(list) do
            if element == value then return i end
        end
    end

    -- Bounding box {x, y, w, h} of an accessibility element
    local function getBox(element)
        local position = getAttribute(element, "AXPosition")
        local size = getAttribute(element, "AXSize")
        if position and size then
            return {x = position.x, y = position.y, w = size.w, h = size.h}
        end
    end

    -- Point on an element: its center or, if `anchored`, its reported position
    -- (`WindowManager` reports the CENTER of a space thumbnail as its position)
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

    -- Poll `predicate` until it returns a truthy value or the timeout expires
    -- (`rs.mc_timeout` by default)
    local function waitUntil(predicate, timeout)
        timeout = timeout or rs.mc_timeout
        local waited = 0
        local value = predicate()
        while not value and waited < timeout do
            rs.delayExecution(rs.mc_pause)
            waited = waited + rs.mc_pause
            value = predicate()
        end
        return value
    end

    -- Native `hs.spaces` functions are only trusted up to macOS 15; from macOS
    -- 26 on, the Mission Control tree they rely on has moved (and calling them
    -- there only toggles Mission Control, which races with our own calls)
    local function useNative()
        return hs.host.operatingSystemVersion().major <= 15
    end

    -- Close Mission Control (Escape key from macOS 26 on, because the Dock no
    -- longer hosts the tree) and wait until it is gone
    local function closeMC()
        if not getMissionControl() then return end
        if useNative() then
            hs.spaces.closeMissionControl()
        else
            hs.eventtap.keyStroke({}, "escape", 0)
        end
        waitUntil(function() return not getMissionControl() end)
        rs.delayExecution(rs.mc_settle)
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
        if not keep_open then
            closeMC()
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
    -- (the tree can be incomplete right after opening, so wait for it)
    local function withDisplay(screen, action, keep_open)
        return withMissionControl(function(mc)
            local display = findDisplay(mc, screen) or waitUntil(function()
                local fresh = getMissionControl()
                return fresh and findDisplay(fresh, screen)
            end)
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

    -- Space IDs of a screen in Mission Control order (the hidden "dashboard"
    -- space has no thumbnail)
    local function getScreenSpaces(screen)
        return filterList(hs.spaces.allSpaces()[screen:getUUID()] or {}, function(id)
            return hs.spaces.spaceType(id) ~= "system"
        end)
    end

    -- Position of a space among the thumbnails of its screen, and that screen
    local function getSpaceIndex(space)
        local screen = getScreenByUUID(hs.spaces.spaceDisplay(space))
        return screen and indexOf(getScreenSpaces(screen), space), screen
    end

    local function countSpaces(screen)
        return #(hs.spaces.spacesForScreen(screen:id()) or {})
    end

    local function isOnSpace(window, space)
        return rs.contains(hs.spaces.windowSpaces(window) or {}, space)
    end

    -- Screen that owns the window's space (more reliable than `window:screen()`,
    -- which follows the window's frame and can disagree right after a move)
    local function getWindowScreen(window)
        local space = (hs.spaces.windowSpaces(window) or {})[1]
        return space and getScreenByUUID(hs.spaces.spaceDisplay(space)) or window:screen()
    end

    -- Hover the top edge of a display, which expands its spaces bar
    local function hoverTopEdge(display)
        local box = getBox(display)
        local event = hs.eventtap.event
        local top = {x = box.x + box.w / 2, y = box.y + 2}
        event.newMouseEvent(event.types.mouseMoved, top):post()
        rs.delayExecution(rs.mc_settle)
    end

    -- Switch to a space by pressing its thumbnail in Mission Control
    local function gotoSpaceViaMC(space)
        local index, screen = getSpaceIndex(space)
        if not (index and screen) then
            return nil, "unknown space: " .. tostring(space)
        end
        local cursor = hs.mouse.absolutePosition()
        local result, err = withDisplay(screen, function(display)
            local active = function()
                return hs.spaces.activeSpaceOnScreen(screen) == space
            end
            local title
            for _ = 1, 2 do
                hoverTopEdge(display)
                local thumbnail = getThumbnails(display)[index]
                if not thumbnail then
                    error("space thumbnail #" .. index .. " not found", 0)
                end
                title = getAttribute(thumbnail, "AXTitle")
                thumbnail:performAction("AXPress")
                if waitUntil(active) then
                    waitUntil(function() return not getMissionControl() end)
                    return true
                end
            end
            error(string.format("space did not become active (pressed #%d '%s', active is %s)",
                index, tostring(title), tostring(hs.spaces.activeSpaceOnScreen(screen))), 0)
        end)
        hs.mouse.absolutePosition(cursor)
        return result, err
    end

    -- Go to a space. Uses the native API where it works (macOS 15 and below),
    -- falling back to Mission Control.
    -- Returns: true, method used | nil, error message
    rs.gotoSpace = function(space)
        local method = "native"
        local status, err
        if useNative() then
            status, err = hs.spaces.gotoSpace(space)
            if not status then
                local msg = "native gotoSpace failed (" .. tostring(err) .. ")"
                rs.issueVerbose(msg .. "; using Mission Control", rs.verbose)
            end
        end
        if not status then
            method = "Mission Control"
            status, err = gotoSpaceViaMC(space)
        end
        if not status then
            print("(gotoSpace) failed for space " .. tostring(space) .. ": " .. tostring(err))
            return nil, err
        end
        return true, method
    end

    -- Add a space to a screen (native API where it works, else Mission Control).
    -- `close_mc == false` keeps Mission Control open for consecutive calls.
    -- Returns: true | nil, error message
    rs.addSpaceToScreen = function(screen, close_mc)
        if useNative() and hs.spaces.addSpaceToScreen(screen, close_mc) then
            return true
        end
        local count = countSpaces(screen)
        return withDisplay(screen, function(display)
            hoverTopEdge(display)
            local button = findElements(display, "mc.spaces.add", 4)[1]
            if not (button and button:performAction("AXPress")) then
                error("add-space button not available (macOS allows at most 16 spaces per display)", 0)
            end
            if not waitUntil(function() return countSpaces(screen) > count end) then
                error("space was not added", 0)
            end
            return true
        end, close_mc == false)
    end

    -- Remove a space (native API where it works, else Mission Control).
    -- Returns: true | nil, error message
    rs.removeSpace = function(space, close_mc)
        if useNative() and hs.spaces.removeSpace(space, close_mc) then
            return true
        end
        local index, screen = getSpaceIndex(space)
        if not (index and screen) then
            return nil, "unknown space: " .. tostring(space)
        end
        return withDisplay(screen, function(display)
            hoverTopEdge(display)
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

    local function postMouse(kind, point, previous, number)
        local event = hs.eventtap.event
        local mouse = event.newMouseEvent(event.types[kind], point)
        local function round(value) return math.floor(value + 0.5) end
        local pressed = kind == "leftMouseDown" or kind == "leftMouseDragged"
        mouse:setProperty(event.properties.mouseEventNumber, number)
        mouse:setProperty(event.properties.mouseEventClickState, pressed and 1 or 0)
        mouse:setProperty(event.properties.mouseEventPressure, pressed and 1 or 0)
        mouse:setProperty(event.properties.mouseEventDeltaX, round(point.x - previous.x))
        mouse:setProperty(event.properties.mouseEventDeltaY, round(point.y - previous.y))
        mouse:post()
    end

    -- Drag (button held) from one point to another in small timed steps (at
    -- least `rs.mc_drag_steps`, one per ~20 pixels), divided by `rs.move_speed`
    local function glide(from, to, number, steps)
        local distance = math.sqrt((to.x - from.x) ^ 2 + (to.y - from.y) ^ 2)
        steps = steps or math.max(rs.mc_drag_steps, math.ceil(distance / 20))
        steps = math.max(5, math.ceil(steps / rs.move_speed))
        local previous = from
        for step = 1, steps do
            local point = {
                x = from.x + (to.x - from.x) * step / steps,
                y = from.y + (to.y - from.y) * step / steps
            }
            postMouse("leftMouseDragged", point, previous, number)
            previous = point
            rs.delayExecution(rs.mc_drag_pause)
        end
        return to
    end

    -- Press the mouse at `from`, run `action(gesture)` (`gesture.drag(to, steps)`
    -- moves the pressed mouse) and always release it and restore the cursor,
    -- so that no application is ever left with a pressed button
    local function holdMouse(from, action)
        local cursor = hs.mouse.absolutePosition()
        drag_counter = drag_counter + 1
        local number, point = drag_counter, from
        local gesture = {
            drag = function(to, steps) point = glide(point, to, number, steps) end
        }
        local success, err = pcall(function()
            hs.mouse.absolutePosition(from)
            postMouse("mouseMoved", from, from, number)
            rs.delayExecution(rs.mc_settle)
            postMouse("leftMouseDown", from, from, number)
            rs.delayExecution(rs.mc_pause)
            action(gesture)
        end)
        postMouse("leftMouseUp", point, point, number)
        hs.mouse.absolutePosition(cursor)
        if not success then error(err, 0) end
    end

    -- Strip invisible direction marks, which some apps put in their titles
    local function cleanTitle(text)
        return (text:gsub("\226\128[\142\143]", ""))
    end

    -- Compare a thumbnail title with a window title; Mission Control may shorten
    -- long titles with a middle ellipsis
    local function titleMatches(shown, title)
        shown, title = cleanTitle(shown), cleanTitle(title)
        if shown == title then return true end
        local head, tail = shown:match("^(.-)…(.*)$")
        return head ~= nil
            and #title >= #head + #tail
            and title:sub(1, #head) == head
            and (tail == "" or title:sub(-#tail) == tail)
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
                        if not owner or not source or tonumber(owner) == source then
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

    -- Thumbnail of a window among those of its space, and how many candidates
    -- there were. Matches by bundle ID (when the identifier carries one) and
    -- then by title, since some apps (_e.g._ Safari) report an empty title.
    local function findWindowThumbnail(thumbnails, window)
        local bundle = window:application():bundleID()
        local title = window:title()
        local pool = filterList(thumbnails, function(thumbnail)
            local id = tostring(getAttribute(thumbnail, "AXIdentifier"))
            local owner = id:match("^(.*)%.space%.%d+$")
            return not owner or owner == bundle
        end)
        local titled = filterList(pool, function(thumbnail)
            return titleMatches(getAttribute(thumbnail, "AXTitle") or "", title)
        end)
        if #titled > 0 then
            return titled[1], #titled
        end
        return pool[1], #pool
    end

    -- Point of an element once it stops moving (animations are over)
    local function getSettledPoint(element, anchored)
        local previous
        local function settled()
            local point = getPoint(element, anchored)
            local same = point and previous
                and math.abs(point.x - previous.x) < 1 and math.abs(point.y - previous.y) < 1
            previous = point
            return same and point
        end
        return waitUntil(settled) or getPoint(element, anchored)
    end

    -- Strategy "mission_control": drag the window thumbnail onto a space
    -- thumbnail; works across screens and for any distance, but is slower and
    -- identifies windows by title (identical titles: the first one is used).
    -- The window must be on the active space of its screen, because Mission
    -- Control only lays out the windows of the active spaces.
    local function moveWindowViaMC(window, space)
        local index, target_screen = getSpaceIndex(space)
        local source = (hs.spaces.windowSpaces(window) or {})[1]
        if not (index and source) then
            return nil, "unknown source or target space"
        end
        if source == space then return true end
        if hs.spaces.activeSpaceOnScreen(getWindowScreen(window)) ~= source then
            return nil, "window is not on the active space of its screen"
        end

        return withMissionControl(function(mc)
            local source_display = findDisplay(mc, getWindowScreen(window))
            local target_display = findDisplay(mc, target_screen)
            if not (source_display and target_display) then
                error("display not found in Mission Control", 0)
            end
            local thumbnail, candidates = findWindowThumbnail(
                getWindowThumbnails(source_display, source), window)
            if not thumbnail then
                error("window thumbnail not found: " .. window:application():name()
                    .. " / " .. window:title(), 0)
            elseif candidates > 1 then
                rs.issueVerbose("ambiguous window; using first of " .. candidates
                    .. " thumbnails: " .. window:title(), rs.verbose)
            end

            -- Hover the top edge of the target display to expand its spaces bar
            local box = getBox(target_display)
            local top = {x = box.x + box.w / 2, y = box.y + 2}
            local start, drop = getSettledPoint(thumbnail)
            holdMouse(start, function(gesture)
                gesture.drag(top)
                gesture.drag({x = top.x + 30, y = top.y}, 8)
                gesture.drag(top, 8)
                rs.delayExecution(rs.mc_settle)
                local target = getThumbnails(target_display)[index]
                drop = target and getSettledPoint(target, mc.host == mc_hosts[1])
                if not drop then
                    error("target space thumbnail not found", 0)
                end
                -- A collapsed bar reports thumbnails above the display edge
                drop.y = math.max(drop.y, box.y + 15)
                gesture.drag(drop)
                rs.delayExecution(rs.mc_settle)
            end)
            if not waitUntil(function() return isOnSpace(window, space) end) then
                local after = getPoint(thumbnail) or start
                error(string.format("window did not arrive at space %s (thumbnail %.0f,%.0f -> %.0f,%.0f; drop %.0f,%.0f)",
                    tostring(space), start.x, start.y, after.x, after.y, drop.x, drop.y), 0)
            end
            return true
        end)
    end

    -- Point on the title bar, right of the zoom button, to grab a window
    local function getGrabPoint(window)
        local button = window:zoomButtonRect()
        if button then
            return {x = button.x + button.w + 10, y = button.y + button.h / 2}
        end
        local frame = window:frame()
        return {x = frame.x + 80, y = frame.y + 14}
    end

    -- Strategy "titlebar": hold the window by its title bar while switching
    -- spaces with the "Move left/right a space" shortcuts (ctrl+arrows), up to
    -- `rs.move_max_hops` spaces. Fast for nearby spaces, needs a title bar, and
    -- cannot change the window's screen: dragging a window between screens
    -- this way can leave it assigned to the desktop of its old screen.
    local function moveWindowViaTitlebar(window, space)
        local target = getScreenByUUID(hs.spaces.spaceDisplay(space))
        if not target then
            return nil, "unknown target space"
        end
        if getWindowScreen(window) ~= target then
            return nil, "windows cannot change screen with the title bar (use mission_control)"
        end
        if isOnSpace(window, space) then return true end
        local spaces = getScreenSpaces(target)
        local home = hs.spaces.activeSpaceOnScreen(target)
        local from, to = indexOf(spaces, home), indexOf(spaces, space)
        if not (from and to) then
            return nil, "unknown space order"
        end
        local hops = math.abs(to - from)
        if hops > rs.move_max_hops then
            return nil, string.format("%d hops exceed the limit of %d", hops, rs.move_max_hops)
        end
        if not isOnSpace(window, home) then
            return nil, "window is not on the active space of its screen"
        end

        window:focus()
        rs.delayExecution(rs.mc_settle)
        local grab = getGrabPoint(window)
        local step = to > from and 1 or -1
        local success, err = pcall(holdMouse, grab, function(gesture)
            gesture.drag({x = grab.x + 8, y = grab.y + 8})
            for position = from + step, to, step do
                -- Arrow keys carry the `fn` flag on real keyboards (macOS needs it)
                hs.eventtap.keyStroke({"ctrl", "fn"}, step > 0 and "right" or "left", 0)
                local reached = function()
                    return hs.spaces.activeSpaceOnScreen(target) == spaces[position]
                end
                if not waitUntil(reached) then
                    error("space switch failed (are the 'Move left/right a space' shortcuts enabled?)", 0)
                end
                rs.delayExecution(rs.mc_pause)
            end
        end)
        local arrived = success and waitUntil(function() return isOnSpace(window, space) end)
        if hs.spaces.activeSpaceOnScreen(target) ~= home then
            rs.gotoSpace(home)
        end
        if not success then
            return nil, err
        elseif not arrived then
            return nil, "window did not follow the space switch"
        end
        return true
    end

    -- Strategies available to move windows (macOS 15 and later)
    local movers = {titlebar = moveWindowViaTitlebar, mission_control = moveWindowViaMC}

    -- Strategies to try for a window: "mission_control" alone for moves between
    -- screens; otherwise the per-app override alone, or else the configured
    -- strategy followed by the other as a fallback
    local function getStrategies(window, space)
        local target = getScreenByUUID(hs.spaces.spaceDisplay(space))
        if getWindowScreen(window) ~= target then
            return {"mission_control"}
        end
        local app = window:application():name()
        for name, apps in pairs(rs.move_apps) do
            if rs.contains(apps, app) then
                return {name}
            end
        end
        if not movers[rs.move_strategy] then
            error("Unknown move strategy: " .. tostring(rs.move_strategy))
        end
        return {rs.move_strategy, rs.move_strategy == "titlebar" and "mission_control" or "titlebar"}
    end

    -- The native move is verified up to macOS 14; from macOS 15 it reports
    -- success without moving the window, so the strategies above are used
    local function useNativeMove()
        return hs.host.operatingSystemVersion().major <= 14
    end

    local function moveWindow(window, space)
        if useNativeMove() then
            return hs.spaces.moveWindowToSpace(window, space)
        end
        local errors = {}
        for _, name in ipairs(getStrategies(window, space)) do
            local success, status, err = pcall(movers[name], window, space)
            if not success then
                status, err = nil, status
            end
            if status then return true end
            table.insert(errors, name .. ": " .. tostring(err))
        end
        return nil, table.concat(errors, " | ")
    end

    -- First/last user space (per `rs.fallback_space`) of the screen of a space
    local function getFallbackSpace(space)
        local screen = getScreenByUUID(hs.spaces.spaceDisplay(space))
        local user_spaces = filterList(screen and getScreenSpaces(screen) or {}, function(id)
            return hs.spaces.spaceType(id) == "user"
        end)
        return rs.fallback_space == "first" and user_spaces[1] or user_spaces[#user_spaces]
    end

    -- Move a window to a space. Windows already there, and (from macOS 15 on)
    -- windows inside full-screen/split-view spaces, are left alone; only
    -- desktops are valid targets. If the move fails, the window goes to the
    -- fallback space of the target screen, or else stays where it is (visible
    -- console warning in both cases). Never uses `window:moveToScreen`, which
    -- leaves windows assigned to the desktop they came from.
    -- Returns: true | nil, error message
    rs.moveWindowToSpace = function(window, space)
        if not space then
            return nil, "undefined target space"
        end
        if hs.spaces.spaceType(space) ~= "user" then
            return nil, "target is not a desktop (full-screen spaces are not supported yet)"
        end
        if isOnSpace(window, space) then
            return true
        end
        local source = (hs.spaces.windowSpaces(window) or {})[1]
        if not useNativeMove() and source and hs.spaces.spaceType(source) ~= "user" then
            return nil, "window is in a full-screen space (not moved)"
        end
        local status, err = moveWindow(window, space)
        if status then return true end

        local fallback = getFallbackSpace(space)
        local moved = fallback and fallback ~= space and moveWindow(window, fallback)
        print("(moveWindowToSpace) WARNING: window " .. window:id() .. " -> space "
            .. tostring(space) .. " failed (" .. tostring(err) .. "): "
            .. (moved and "moved to fallback space " .. fallback or "window left in place"))
        if not moved then
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
        local move = version.major <= 14 and "native" or rs.move_strategy
        return string.format(
            "macOS %d.%d.%d, Hammerspoon %s, separate spaces: %s, same-screen move: %s, screens: %s",
            version.major, version.minor, version.patch, hs.processInfo.version,
            tostring(hs.spaces.screensHaveSeparateSpaces()), move, table.concat(screens, "; ")
        )
    end

    rs.logSystemInfo = function()
        rs.issueVerbose(rs.getSystemInfo(), rs.verbose)
    end

    -- Append an indented dump of an accessibility subtree to `lines`
    -- (at most `limit` children per node, default 40)
    local function dumpTree(element, depth, lines, limit)
        limit = limit or 40
        local function show(name)
            return hs.inspect(getAttribute(element, name), {newline = "", indent = ""})
        end
        local fields = {show("AXRole"), show("AXIdentifier"), show("AXTitle"),
                        show("AXPosition"), show("AXSize")}
        table.insert(lines, string.rep("  ", depth + 1) .. table.concat(fields, " | "))
        if depth < 5 then
            for i, child in ipairs(getAttribute(element, "AXChildren") or {}) do
                if i > limit then
                    table.insert(lines, string.rep("  ", depth + 2) .. "...")
                    break
                end
                dumpTree(child, depth + 1, lines, limit)
            end
        end
    end

    -- Diagnostic (takes 1-3 minutes; do not touch the mouse): clears the
    -- console, then with the first standard window (not Hammerspoon) that sits
    -- on a desktop of a screen with 2+ desktops, tests goto, adding/removing a
    -- desktop, each move strategy (title bar within the screen; Mission Control
    -- within the screen and to another screen), putting the window back after
    -- each one, and probes faster timings. Prints one framed report that ends
    -- with recommended settings. Pass `true` to also dump the Mission Control
    -- tree. Window titles appear in the report, so redact before sharing.
    rs.testSpaceControl = function(dump)
        hs.console.clearConsole()
        print("restore_spaces diagnostic running: do not touch the mouse (1-3 minutes)...")
        local lines, failures = {rs.getSystemInfo()}, 0
        local verbose, speed, settle = rs.verbose, rs.move_speed, rs.mc_settle
        rs.verbose = false
        local function report(text) table.insert(lines, text) end
        local function section(level, title) report("\n" .. rs.banner(level, title)) end
        local function timed(label, action)
            local start = hs.timer.secondsSinceEpoch()
            local success, status, info = pcall(action)
            if not success then status, info = nil, status end
            if not status then failures = failures + 1 end
            report(string.format("%-38s %s (%.2fs) %s", label, status and "OK" or "FAIL",
                hs.timer.secondsSinceEpoch() - start, tostring(info or "")))
            return status
        end
        local function getDesktops(screen)
            return rs.validateSpaces(hs.spaces.spacesForScreen(screen:id()) or {})
        end
        -- A desktop of the screen other than its active one, and the active one
        local function getOtherSpace(screen)
            local active = hs.spaces.activeSpaceOnScreen(screen)
            for _, id in ipairs(getDesktops(screen)) do
                if id ~= active then
                    return id, active
                end
            end
        end
        -- Window location by space, by the screen owning that space and by frame
        local function where(window)
            return string.format("spaces %s, space of '%s', frame on '%s'",
                hs.inspect(hs.spaces.windowSpaces(window) or {}, {newline = "", indent = ""}),
                getWindowScreen(window):name(), window:screen():name())
        end

        local function run()
            report("accessibility: " .. tostring(hs.accessibilityState()))
            local window, other, active
            for _, candidate in ipairs(hs.window.orderedWindows()) do
                if candidate:isStandard() and candidate:application():name() ~= "Hammerspoon" then
                    other, active = getOtherSpace(candidate:screen())
                    if other and isOnSpace(candidate, active) then
                        window = candidate
                        break
                    end
                end
            end
            if not window then
                report("SKIPPED tests: no standard window on a desktop of a screen with 2+ desktops")
                return
            end
            local home, frame = window:screen(), window:frame()
            -- Bring the window back to its starting space and size
            local function recover()
                if not isOnSpace(window, active) then
                    rs.gotoSpace((hs.spaces.windowSpaces(window) or {})[1] or active)
                    timed("  recover (all strategies)", function() return moveWindow(window, active) end)
                end
                rs.gotoSpace(active)
                window:setFrame(frame)
            end
            -- Move out, follow the window, move back; always recover afterwards
            local function roundTrip(label, name, to)
                if not isOnSpace(window, active) then
                    report(label .. ": SKIPPED, window is not at its start (" .. where(window) .. ")")
                    return
                end
                local mover = movers[name]
                if timed(label .. " out", function() return mover(window, to) end) then
                    timed("  goto moved window", function() return rs.gotoSpace(to) end)
                    timed(label .. " back", function() return mover(window, active) end)
                end
                report("    now: " .. where(window))
                recover()
            end

            report("window of '" .. window:application():name() .. "', " .. where(window)
                .. ", test space " .. other)

            section(3, "switching desktops")
            timed("goto other", function() return rs.gotoSpace(other) end)
            timed("goto back", function() return rs.gotoSpace(active) end)

            section(3, "adding and removing a desktop")
            local before = getDesktops(home)
            if #before < 16 then
                local added
                timed("add desktop", function()
                    local status, err = rs.addSpaceToScreen(home)
                    for _, id in ipairs(getDesktops(home)) do
                        if not rs.contains(before, id) then added = id end
                    end
                    return status and added, err or ("new desktop " .. tostring(added))
                end)
                if added then
                    timed("remove desktop", function()
                        local status, err = rs.removeSpace(added)
                        return status and not rs.contains(getDesktops(home), added), err
                    end)
                end
            else
                report("SKIPPED: the screen already has 16 desktops")
            end

            section(3, "moving the window within its screen")
            for _, name in ipairs({"titlebar", "mission_control"}) do
                roundTrip(name .. " / same screen", name, other)
            end

            section(3, "moving the window to another screen (mission_control only)")
            for _, screen in ipairs(hs.screen.allScreens()) do
                local away = hs.spaces.activeSpaceOnScreen(screen)
                if screen ~= home and hs.spaces.spaceType(away) == "user" then
                    report("other screen: '" .. screen:name() .. "', space " .. away)
                    roundTrip("mission_control / other screen", "mission_control", away)
                    break
                end
            end

            section(3, "faster timings (mission_control, same screen)")
            local best
            for _, probe in ipairs({{2, 0.2}, {4, 0.12}, {8, 0.08}}) do
                rs.move_speed, rs.mc_settle = probe[1], probe[2]
                local passed = timed(string.format("move_speed %d, mc_settle %.2f", probe[1], probe[2]), function()
                    local status, err = moveWindowViaMC(window, other)
                    if not status then return nil, err end
                    rs.gotoSpace(other)
                    return moveWindowViaMC(window, active)
                end)
                recover()
                if not passed then break end
                best = probe
            end
            rs.move_speed, rs.mc_settle = speed, settle
            report("\nend: " .. where(window))

            section(3, "recommended settings")
            if best then
                report("fastest probe that passed (use a slower one if apply is flaky):")
                report(string.format("  hs.restore_spaces.move_speed = %d", best[1]))
                report(string.format("  hs.restore_spaces.mc_settle = %.2f", best[2]))
            else
                report("keep the defaults (no faster probe passed)")
            end
        end

        local function dumpTrees()
            hs.spaces.openMissionControl()
            waitUntil(getMissionControl)
            for _, bundle in ipairs(mc_hosts) do
                section(4, "Mission Control tree under " .. bundle)
                local app = hs.application.applicationsForBundleID(bundle)[1]
                if app then
                    dumpTree(hs.axuielement.applicationElement(app), 0, lines)
                else
                    report("  (process not running)")
                end
            end
            closeMC()
        end

        local success, err = pcall(run)
        if not success then
            failures = failures + 1
            report("ERROR: " .. tostring(err))
        end
        rs.move_speed, rs.mc_settle = speed, settle
        if dump then pcall(dumpTrees) end
        rs.verbose = verbose
        print("\n" .. rs.banner(1, "restore_spaces diagnostic") .. "\n" .. table.concat(lines, "\n")
            .. "\n" .. rs.banner(1, string.format("end of diagnostic: %d failed steps", failures)))
    end

end