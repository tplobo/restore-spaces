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
        rs.waitUntil(function() return not getMissionControl() end)
        rs.delayExecution(rs.mc_settle)
    end

    -- Run `action(mc)` with Mission Control open; close it afterwards unless
    -- `keep_open`. Returns the action results, or nil and an error message.
    local function withMissionControl(action, keep_open)
        local mc = getMissionControl()
        if not mc then
            hs.spaces.openMissionControl()
            mc = rs.waitUntil(getMissionControl)
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

    function rs.getScreenByUUID(uuid)
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
            local display = findDisplay(mc, screen) or rs.waitUntil(function()
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
        local screen = rs.getScreenByUUID(hs.spaces.spaceDisplay(space))
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
    function rs.getWindowScreen(window)
        local space = (hs.spaces.windowSpaces(window) or {})[1]
        return space and rs.getScreenByUUID(hs.spaces.spaceDisplay(space)) or window:screen()
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
                if rs.waitUntil(active) then
                    rs.waitUntil(function() return not getMissionControl() end)
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

    -- Identifiers (or roles) of the children of the spaces bar of a display
    local function describeBar(display)
        local bar = findElements(display, "mc.spaces", 2)[1]
        if not bar then return "no spaces bar" end
        local names = {}
        for _, child in ipairs(getAttribute(bar, "AXChildren") or {}) do
            table.insert(names, tostring(getAttribute(child, "AXIdentifier") or getAttribute(child, "AXRole")))
        end
        return table.concat(names, ", ")
    end

    -- Add a space to a screen (native API where it works, else Mission Control).
    -- `close_mc == false` keeps Mission Control open for consecutive calls
    -- (see `rs.closeMissionControl`). A screen at `rs.space_limit` spaces
    -- (full-screen ones included) is refused at once, because macOS hides the
    -- "+" button there.
    -- Returns: true | nil, error message
    rs.addSpaceToScreen = function(screen, close_mc)
        if useNative() and hs.spaces.addSpaceToScreen(screen, close_mc) then
            return true
        end
        local count = countSpaces(screen)
        if #getScreenSpaces(screen) >= rs.space_limit then
            return nil, string.format("'%s' is at the limit of %d spaces (full-screen ones included)",
                screen:name(), rs.space_limit)
        end
        return withDisplay(screen, function(display)
            hoverTopEdge(display)
            local button = rs.waitUntil(function() return findElements(display, "mc.spaces.add", 4)[1] end)
            if not (button and button:performAction("AXPress")) then
                error(string.format("add-space button not available: the display has %d spaces (spaces bar: %s)",
                    count, describeBar(display)), 0)
            end
            if not rs.waitUntil(function() return countSpaces(screen) > count end) then
                error("space was not added", 0)
            end
            return true
        end, close_mc == false)
    end

    -- Close Mission Control if a call left it open (`close_mc == false`)
    rs.closeMissionControl = function()
        closeMC()
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
            if not (removed and rs.waitUntil(gone)) then
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
        return rs.waitUntil(settled) or getPoint(element, anchored)
    end

    -- With the mouse pressed at the top edge of a display, go above the target
    -- thumbnail and descend onto it, re-reading its position until it stops
    -- shifting. On macOS 27.2 the spaces bar rearranges itself while a window
    -- hovers over it, and a drop between two thumbnails creates a full-screen
    -- space. `locate()` returns the point to aim at.
    local function dropOnThumbnail(gesture, box, locate)
        local aim = locate()
        if not aim then
            error("target space thumbnail not found", 0)
        end
        gesture.drag({x = aim.x, y = box.y + 2})
        for attempt = 1, 4 do
            aim = locate() or aim
            gesture.drag(aim, attempt == 1 and 12 or 6)
            rs.delayExecution(rs.mc_settle / 2)
            local now = locate()
            if now and math.abs(now.x - aim.x) < 6 and math.abs(now.y - aim.y) < 6 then
                break
            end
        end
        return aim
    end

    -- Make a window that a drag dropped into a new full-screen space leave it
    -- again (macOS removes the empty space and puts the window on a desktop)
    local function leaveFullScreen(window, space)
        rs.gotoSpace(space)
        rs.delayExecution(rs.mc_settle)
        window:setFullScreen(false)
        local left = rs.waitUntil(function()
            local current = (hs.spaces.windowSpaces(window) or {})[1]
            return current and hs.spaces.spaceType(current) == "user"
        end, 4)
        return left and "the drop created a full-screen space, which the window left again"
            or "the drop created a full-screen space and the window is still in it"
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
        if hs.spaces.activeSpaceOnScreen(rs.getWindowScreen(window)) ~= source then
            return nil, "window is not on the active space of its screen"
        end

        local result, err = withMissionControl(function(mc)
            local source_display = findDisplay(mc, rs.getWindowScreen(window))
            local target_display = findDisplay(mc, target_screen)
            if not (source_display and target_display) then
                error("display not found in Mission Control", 0)
            end
            local thumbnail, candidates = findWindowThumbnail(
                getWindowThumbnails(source_display, source), window)
            if not thumbnail then
                error("window thumbnail not found: " .. window:application():name()
                    .. " / " .. rs.redact(window:title()), 0)
            elseif candidates > 1 then
                rs.issueVerbose("ambiguous window; using first of " .. candidates
                    .. " thumbnails: " .. rs.redact(window:title()), rs.verbose)
            end

            -- Hover the top edge of the target display to expand its spaces bar
            local box = getBox(target_display)
            local top = {x = box.x + box.w / 2, y = box.y + 2}
            local start, drop = getSettledPoint(thumbnail)
            local function locate()
                local target = getThumbnails(target_display)[index]
                local point = target and getPoint(target, mc.host == mc_hosts[1])
                -- A collapsed bar reports thumbnails above the display edge
                if point then point.y = math.max(point.y, box.y + 15) end
                return point
            end
            holdMouse(start, function(gesture)
                gesture.drag(top)
                gesture.drag({x = top.x + 30, y = top.y}, 8)
                gesture.drag(top, 8)
                rs.delayExecution(rs.mc_settle)
                drop = dropOnThumbnail(gesture, box, locate)
                rs.delayExecution(rs.mc_settle)
            end)
            if not rs.waitUntil(function() return isOnSpace(window, space) end) then
                local after = getPoint(thumbnail) or start
                error(string.format("window did not arrive at space %s (thumbnail %.0f,%.0f -> %.0f,%.0f; drop %.0f,%.0f)",
                    tostring(space), start.x, start.y, after.x, after.y, drop.x, drop.y), 0)
            end
            return true
        end)

        if not result then
            local landed = (hs.spaces.windowSpaces(window) or {})[1]
            if landed and landed ~= source and hs.spaces.spaceType(landed) ~= "user" then
                err = tostring(err) .. " - " .. leaveFullScreen(window, landed)
            end
        end
        return result, err
    end

    -- Move a desktop to another screen by dragging its thumbnail from the spaces
    -- bar of its screen to the spaces bar of the target screen (it goes last)
    local function moveSpaceToScreen(space, target_screen)
        local index, source_screen = getSpaceIndex(space)
        if not (index and source_screen) then
            return nil, "unknown space: " .. tostring(space)
        end
        local count = countSpaces(target_screen)
        return withMissionControl(function(mc)
            local source_display = findDisplay(mc, source_screen)
            local target_display = findDisplay(mc, target_screen)
            if not (source_display and target_display) then
                error("display not found in Mission Control", 0)
            end
            local anchored = mc.host == mc_hosts[1]
            hoverTopEdge(source_display)
            local thumbnail = getThumbnails(source_display)[index]
            if not thumbnail then
                error("desktop thumbnail not found", 0)
            end
            local start = getSettledPoint(thumbnail, anchored)
            local box = getBox(target_display)
            local top = {x = box.x + box.w / 2, y = box.y + 2}
            holdMouse(start, function(gesture)
                gesture.drag(top)
                gesture.drag({x = top.x + 30, y = top.y}, 8)
                gesture.drag(top, 8)
                rs.delayExecution(rs.mc_settle)
                local thumbnails = getThumbnails(target_display)
                local last = thumbnails[#thumbnails]
                local drop = last and getSettledPoint(last, anchored)
                local size = last and getBox(last)
                if not (drop and size) then
                    error("target spaces bar not found", 0)
                end
                -- Drop on the right part of the last desktop, so that it goes last
                gesture.drag({x = drop.x + size.w * 0.3, y = math.max(drop.y, box.y + 15)})
                rs.delayExecution(rs.mc_settle)
            end)
            if not rs.waitUntil(function() return countSpaces(target_screen) > count end) then
                error("the desktop did not move to '" .. target_screen:name() .. "'", 0)
            end
            return true
        end)
    end

    -- Create a desktop on a screen that is at the space limit: create it on
    -- another screen with room, and drag it over (needs 2+ screens; macOS may
    -- refuse the drag, in which case the new desktop is removed again).
    -- Returns: true | nil, error message
    rs.createSpaceByMoving = function(screen)
        for _, donor in ipairs(hs.screen.allScreens()) do
            if donor ~= screen and #getScreenSpaces(donor) < rs.space_limit then
                local before = hs.spaces.spacesForScreen(donor:id()) or {}
                local status, err = rs.addSpaceToScreen(donor)
                if not status then
                    return nil, "could not create a desktop on '" .. donor:name() .. "': " .. tostring(err)
                end
                local created
                for _, id in ipairs(hs.spaces.spacesForScreen(donor:id()) or {}) do
                    if not rs.contains(before, id) then created = id end
                end
                if not created then
                    return nil, "could not identify the new desktop of '" .. donor:name() .. "'"
                end
                status, err = moveSpaceToScreen(created, screen)
                if status then return true end
                rs.removeSpace(created)
                return nil, "could not move a desktop from '" .. donor:name() .. "': " .. tostring(err)
            end
        end
        return nil, "no other screen has room for a new desktop"
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
    -- cannot change the window's screen (dragging a window between screens
    -- this way can leave it assigned to the desktop of its old screen). It
    -- crosses full-screen spaces only if `rs.move_cross_fullscreen`. A failed
    -- switch reports the hop that failed and the space that was active then.
    local function moveWindowViaTitlebar(window, space)
        local target = rs.getScreenByUUID(hs.spaces.spaceDisplay(space))
        if not target then
            return nil, "unknown target space"
        end
        if rs.getWindowScreen(window) ~= target then
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
        for position = math.min(from, to), math.max(from, to) do
            if not rs.move_cross_fullscreen and hs.spaces.spaceType(spaces[position]) ~= "user" then
                return nil, "a full-screen space lies on the way (use mission_control)"
            end
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
                local expected = spaces[position]
                local previous = hs.spaces.activeSpaceOnScreen(target)
                -- Arrow keys carry the `fn` flag on real keyboards (macOS needs it)
                hs.eventtap.keyStroke({"ctrl", "fn"}, step > 0 and "right" or "left", 0)
                -- A full-screen space may not be reported as the active one while a
                -- window is held: any change of the active space counts there
                local desktop = hs.spaces.spaceType(expected) == "user"
                local reached = function()
                    local current = hs.spaces.activeSpaceOnScreen(target)
                    if desktop then return current == expected end
                    return current ~= previous
                end
                if not rs.waitUntil(reached) then
                    error(string.format("space switch failed at hop %d of %d, to %s (active: %s; "
                        .. "are the 'Move left/right a space' shortcuts enabled?)", math.abs(position - from),
                        hops, rs.describeSpace(expected),
                        rs.describeSpace(hs.spaces.activeSpaceOnScreen(target))), 0)
                end
                rs.delayExecution(desktop and rs.mc_pause or rs.mc_settle)
            end
        end)
        local arrived = success and rs.waitUntil(function() return isOnSpace(window, space) end)
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
        local target = rs.getScreenByUUID(hs.spaces.spaceDisplay(space))
        if rs.getWindowScreen(window) ~= target then
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

    -- Go to the space where the window currently is, so that a strategy can
    -- start from it (a failed attempt may have left the window on another space)
    local function surface(window)
        local space = (hs.spaces.windowSpaces(window) or {})[1]
        local screen = space and rs.getScreenByUUID(hs.spaces.spaceDisplay(space))
        if screen and hs.spaces.activeSpaceOnScreen(screen) ~= space then
            rs.gotoSpace(space)
        end
    end

    -- Native move (`rs.native_move`): `hs.spaces.moveWindowToSpace` can report
    -- success without moving the window (macOS 15+), so the arrival is checked.
    -- After a failure it is not tried again in this run (`rs.native_failed`).
    -- Thanks to freeman106 (PR #5).
    local function moveWindowNatively(window, space)
        local called, status = pcall(hs.spaces.moveWindowToSpace, window, space)
        if called and status and rs.waitUntil(function() return isOnSpace(window, space) end,
            rs.native_move_timeout) then
            return true
        end
        rs.native_failed = true
        rs.issueVerbose("the native window move failed; it is not tried again in this run",
            rs.verbose, 1)
    end

    local function moveWindow(window, space)
        if useNativeMove() then
            return hs.spaces.moveWindowToSpace(window, space)
        end
        if rs.native_move and not rs.native_failed and moveWindowNatively(window, space) then
            local app = window:application()
            rs.issueVerbose(string.format("window %d of '%s' moved to space %s with native",
                window:id(), app and app:name() or "?", tostring(space)), rs.verbose, 1)
            return true
        end
        -- Reading tabs or an earlier failed attempt can leave another desktop
        -- active, and the strategies need the window's desktop to be active
        surface(window)
        local errors = {}
        for _, name in ipairs(getStrategies(window, space)) do
            local success, status, err = pcall(movers[name], window, space)
            if not success then
                status, err = nil, status
            end
            if status or isOnSpace(window, space) then
                local app = window:application()
                rs.issueVerbose(string.format("window %d of '%s' moved to space %s with %s",
                    window:id(), app and app:name() or "?", tostring(space), name), rs.verbose, 1)
                return true
            end
            table.insert(errors, name .. ": " .. tostring(err))
            rs.issueVerbose(string.format("window %d: '%s' failed (%s); trying the next strategy",
                window:id(), name, tostring(err)), rs.verbose, 1)
            surface(window)
        end
        return nil, table.concat(errors, " | ")
    end

    -- First/last user space (per `rs.fallback_space`) of the screen of a space
    function rs.getFallbackSpace(space)
        local screen = rs.getScreenByUUID(hs.spaces.spaceDisplay(space))
        local user_spaces = filterList(screen and getScreenSpaces(screen) or {}, function(id)
            return hs.spaces.spaceType(id) == "user"
        end)
        return rs.fallback_space == "first" and user_spaces[1] or user_spaces[#user_spaces]
    end

    -- Move a window to a space. Windows already there, windows assigned to
    -- several desktops and (from macOS 15 on) windows inside full-screen spaces
    -- are left alone; only desktops are valid targets. If the move fails, the
    -- window goes to the fallback space of the target screen, or else stays where
    -- it is (a warning in both cases). Never uses `window:moveToScreen`, which
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
        local window_spaces = hs.spaces.windowSpaces(window) or {}
        if #window_spaces > 1 then
            return nil, "window is assigned to several desktops (not moved)"
        end
        local source = window_spaces[1]
        if not useNativeMove() and source and hs.spaces.spaceType(source) ~= "user" then
            return nil, "window is in a full-screen space (not moved)"
        end
        local status, err = moveWindow(window, space)
        if status then return true end

        local fallback = rs.getFallbackSpace(space)
        local moved = fallback and fallback ~= space and moveWindow(window, fallback)
        local app = window:application()
        local owner = source and rs.getScreenByUUID(hs.spaces.spaceDisplay(source))
        rs.warn(string.format("window %d of '%s' could not go to space %s (%s; from space %s, active there: %s): %s",
            window:id(), app and app:name() or "?", tostring(space), tostring(err), tostring(source),
            tostring(owner and hs.spaces.activeSpaceOnScreen(owner)),
            moved and ("moved to fallback space " .. fallback) or "left in place"), "moves")
        if not moved then
            return nil, err
        end
        rs.fallback_count = rs.fallback_count + 1
        return true
    end

    -- One-line description of the build, the machine and the strategies in use
    rs.getSystemInfo = function()
        local version = hs.host.operatingSystemVersion()
        local screens = {}
        for _, screen in ipairs(hs.screen.allScreens()) do
            table.insert(screens, screen:name() .. " [" .. tostring(screen:fullFrame()) .. "]")
        end
        local move = version.major <= 14 and "native" or rs.move_strategy
        return string.format(
            "%s, macOS %d.%d.%d, Hammerspoon %s, separate spaces: %s, same-screen move: %s, screens: %s",
            rs.tagBuild("restore_spaces"), version.major, version.minor, version.patch, hs.processInfo.version,
            tostring(hs.spaces.screensHaveSeparateSpaces()), move, table.concat(screens, "; ")
        )
    end

    -- Print the line above (`rs.verbose` of 1 or more)
    rs.logSystemInfo = function()
        rs.issueVerbose(rs.getSystemInfo(), rs.verbose, 1)
    end

    -- Append an indented dump of an accessibility subtree to `lines` (at most
    -- `limit` children per node, down to `max_depth`; `detailed` adds values, the
    -- attribute names of scroll areas, and `AXContents`/`AXVisibleChildren` for
    -- elements without `AXChildren`)
    function rs.dumpTree(element, depth, lines, limit, max_depth, detailed)
        limit, max_depth = limit or 40, max_depth or 5
        local function show(name)
            return hs.inspect(getAttribute(element, name), {newline = "", indent = ""})
        end
        local fields = {show("AXRole"), show("AXIdentifier"), show("AXTitle"),
                        show("AXPosition"), show("AXSize")}
        if detailed then
            table.insert(fields, show("AXSubrole"))
            table.insert(fields, "value=" .. show("AXValue"))
            table.insert(fields, "desc=" .. show("AXDescription"))
            if getAttribute(element, "AXRole") == "AXScrollArea" then
                local success, names = pcall(function() return element:attributeNames() end)
                table.insert(fields, "attributes=" .. hs.inspect(success and names or {}, {newline = "", indent = ""}))
            end
        end
        table.insert(lines, string.rep("  ", depth + 1) .. table.concat(fields, " | "))
        if depth < max_depth then
            local children = getAttribute(element, "AXChildren") or {}
            if detailed and #children == 0 then
                for _, name in ipairs({"AXContents", "AXVisibleChildren"}) do
                    local alternative = getAttribute(element, name)
                    if type(alternative) == "table" and #alternative > 0 then
                        children = alternative
                        break
                    end
                end
            end
            for i, child in ipairs(children) do
                if i > limit then
                    table.insert(lines, string.rep("  ", depth + 2) .. "...")
                    break
                end
                rs.dumpTree(child, depth + 1, lines, limit, max_depth, detailed)
            end
        end
    end

    -- Diagnostic (takes 1-3 minutes; do not touch the mouse): clears the
    -- console, then with the first standard window (not Hammerspoon) that sits
    -- on a desktop of a screen with 2+ desktops, tests goto, adding/removing a
    -- desktop (also through another screen, if one has room), each move strategy
    -- (title bar within the screen; Mission Control within the screen and to
    -- another screen), the assignment of windows to screens (by frame and by
    -- desktop) and the realignment of a window pushed out of view, putting the
    -- window back after each one, and probes faster timings. Prints one framed
    -- report that ends with recommended settings. Pass `true` to also dump the
    -- Mission Control tree. Window titles appear in the report, so redact before
    -- sharing.
    rs.testSpaceControl = function(dump)
        hs.console.clearConsole()
        print("restore_spaces diagnostic running: do not touch the mouse (1-3 minutes)...")
        rs.resetStats()
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
                rs.getWindowScreen(window):name(), window:screen():name())
        end
        -- Create a desktop with `create(screen)`, then remove it
        local function createAndRemove(label, home, create)
            local base, created = getDesktops(home), nil
            timed(label, function()
                local status, err = create(home)
                for _, id in ipairs(getDesktops(home)) do
                    if not rs.contains(base, id) then created = id end
                end
                return status and created, err or ("new desktop " .. tostring(created))
            end)
            if created then
                timed("remove desktop", function()
                    local status, err = rs.removeSpace(created)
                    return status and not rs.contains(getDesktops(home), created), err
                end)
            end
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
            if #getScreenSpaces(home) < rs.space_limit then
                createAndRemove("add desktop", home, rs.addSpaceToScreen)
            else
                report("SKIPPED: the screen is at the limit of " .. rs.space_limit .. " spaces")
            end
            section(3, "creating a desktop through another screen")
            local donor
            for _, screen in ipairs(hs.screen.allScreens()) do
                if screen ~= home and #getScreenSpaces(screen) < rs.space_limit then donor = screen end
            end
            if donor then
                createAndRemove("create via other screen", home, rs.createSpaceByMoving)
            else
                report("SKIPPED: no other screen has room (needs 2+ screens, one below "
                    .. rs.space_limit .. " spaces)")
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

            section(3, "window selection: screen of the frame vs screen of the desktop")
            local checked, disagree = 0, 0
            for _, candidate in ipairs(hs.window.visibleWindows()) do
                local frame_screen = candidate:application() and candidate:isStandard() and candidate:screen()
                if frame_screen then
                    checked = checked + 1
                    local owner = rs.getWindowScreen(candidate)
                    if frame_screen ~= owner then
                        disagree = disagree + 1
                        report(string.format("  '%s' (%s): frame on '%s', desktop on '%s'",
                            candidate:title(), candidate:application():name(),
                            frame_screen:name(), owner:name()))
                    end
                end
            end
            report(string.format("%d windows checked, %d disagree", checked, disagree))

            section(3, "realigning a window pushed out of view")
            local right = 0
            for _, screen in ipairs(hs.screen.allScreens()) do
                local full = screen:fullFrame()
                right = math.max(right, full.x + full.w)
            end
            local limit = rs.min_window_visibility
            rs.min_window_visibility = 0.5
            -- Mostly below its monitor: the window keeps its desktop and monitor
            timed("push down, realign", function()
                local screen = rs.getWindowScreen(window)
                local area = screen:frame()
                window:setTopLeft({x = window:frame().x, y = area.y + area.h - 40})
                rs.delayExecution(rs.mc_settle)
                local status, err = rs.realignWindow(window, active)
                local visible = rs.getVisibility(window:frame(), area)
                local owner = rs.getWindowScreen(window)
                return status == "moved" and visible > 0.49 and owner == screen,
                    string.format("%s, %.0f%% visible, desktop on '%s'", tostring(status or err),
                        visible * 100, owner:name())
            end)
            recover()
            -- Far outside every monitor: macOS can hand the window to another monitor
            timed("push far away, realign", function()
                window:setTopLeft({x = right + 800, y = window:frame().y})
                rs.delayExecution(rs.mc_settle)
                local spaces = hs.spaces.windowSpaces(window) or {}
                local listed = false
                for _, candidate in ipairs(hs.window.visibleWindows()) do
                    listed = listed or candidate:id() == window:id()
                end
                local owner = rs.getWindowScreen(window)
                local status, err = rs.realignWindow(window)
                local visible = rs.getVisibility(window:frame(), owner:frame())
                local after = rs.getWindowScreen(window)
                return status == "moved" and visible > 0.49 and after == owner,
                    string.format("desktops %s of '%s', listed by visibleWindows: %s; %s, %.0f%% visible, desktop on '%s' afterwards",
                        hs.inspect(spaces, {newline = "", indent = ""}), owner:name(), tostring(listed),
                        tostring(status or err), visible * 100, after:name())
            end)
            rs.min_window_visibility = limit
            recover()

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
            rs.waitUntil(getMissionControl)
            for _, bundle in ipairs(mc_hosts) do
                section(4, "Mission Control tree under " .. bundle)
                local app = hs.application.applicationsForBundleID(bundle)[1]
                if app then
                    rs.dumpTree(hs.axuielement.applicationElement(app), 0, lines)
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

    -- Add the time of the public operations to the statistics of the action
    for name, category in pairs({
        gotoSpace = "switching desktops",
        moveWindowToSpace = "moving windows",
        addSpaceToScreen = "creating/removing desktops",
        removeSpace = "creating/removing desktops",
        createSpaceByMoving = "creating/removing desktops"
    }) do
        local operation = rs[name]
        rs[name] = function(...) return rs.measure(category, operation, ...) end
    end

    -- Readable place of a space: "<monitor> desktop <n>" (n counts desktops only)
    rs.describeSpace = function(space)
        if not space then return "no desktop" end
        local screen = rs.getScreenByUUID(hs.spaces.spaceDisplay(space))
        if not screen then
            return "space " .. tostring(space) .. " (unknown monitor)"
        end
        local space_type = hs.spaces.spaceType(space)
        if space_type ~= "user" then
            return string.format("%s %s space", screen:name(), tostring(space_type))
        end
        local index = 0
        for _, id in ipairs(getScreenSpaces(screen)) do
            if hs.spaces.spaceType(id) == "user" then index = index + 1 end
            if id == space then break end
        end
        return string.format("%s desktop %d", screen:name(), index)
    end
    
end