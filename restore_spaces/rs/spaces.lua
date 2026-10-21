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
        if not screen then
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
                error("add-space button not found", 0)
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
        if not screen then
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

    -- Window thumbnails of a display (only those of the `source` space, if given)
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

    -- Drag (button held) from one point to another in small timed steps
    -- (at least `rs.mc_drag_steps`, and one step per ~20 pixels)
    local function glide(from, to, number, steps)
        local distance = math.sqrt((to.x - from.x) ^ 2 + (to.y - from.y) ^ 2)
        steps = steps or math.max(rs.mc_drag_steps, math.ceil(distance / 20))
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

    -- Thumbnail of a window among those of its space, and how many candidates
    -- there were. Matches by bundle ID (when the identifier carries one) and
    -- then by title, since some apps (_e.g._ Safari) report an empty title.
    local function findWindowThumbnail(thumbnails, window)
        local bundle = window:application():bundleID()
        local title = window:title()
        local pool = hs.fnutils.filter(thumbnails, function(thumbnail)
            local id = tostring(getAttribute(thumbnail, "AXIdentifier"))
            local owner = id:match("^(.*)%.space%.%d+$")
            return not owner or owner == bundle
        end)
        local titled = hs.fnutils.filter(pool, function(thumbnail)
            return titleMatches(getAttribute(thumbnail, "AXTitle") or "", title)
        end)
        if #titled > 0 then
            return titled[1], #titled
        end
        return pool[1], #pool
    end

    -- Move a window by dragging its Mission Control thumbnail onto a space
    -- thumbnail; success is verified with the window's actual spaces.
    -- Windows of one app with identical (or empty) titles are
    -- indistinguishable (the first one is used).
    local function moveWindowViaMC(window, space)
        local index, target_screen = getSpaceIndex(space)
        local source = (hs.spaces.windowSpaces(window) or {})[1]
        if not (index and source) then
            return nil, "unknown source or target space"
        end
        if source == space then return true end

        local cursor = hs.mouse.absolutePosition()
        local result, err = withMissionControl(function(mc)
            local source_display = findDisplay(mc, window:screen())
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
            local start = getPoint(thumbnail)
            local top = {x = box.x + box.w / 2, y = box.y + 2}
            local trace = {}
            local function note(label, point)
                table.insert(trace, point
                    and string.format("%s (%.0f,%.0f)", label, point.x, point.y)
                    or label .. " n/a")
            end
            note("start", start)
            drag_counter = drag_counter + 1
            local number, last = drag_counter, start
            local success, drag_err = pcall(function()
                hs.mouse.absolutePosition(start)
                postMouse("mouseMoved", start, start, number)
                rs.delayExecution(rs.mc_settle)
                postMouse("leftMouseDown", start, start, number)
                rs.delayExecution(2 * rs.mc_pause)
                last = glide(start, top, number)
                last = glide(top, {x = top.x + 30, y = top.y}, number, 8)
                last = glide(last, top, number, 8)
                rs.delayExecution(rs.mc_settle)
                -- `WindowManager` reports the CENTER of a space thumbnail
                local target = getThumbnails(target_display)[index]
                local drop = target and getPoint(target, mc.host == mc_hosts[1])
                if not drop then
                    error("target space thumbnail not found", 0)
                end
                note("drop", drop)
                last = glide(top, drop, number)
                rs.delayExecution(rs.mc_settle)
            end)
            postMouse("leftMouseUp", last, last, number)
            if not success then error(drag_err, 0) end

            local arrived = function()
                return rs.contains(hs.spaces.windowSpaces(window) or {}, space)
            end
            if not waitUntil(arrived) then
                error("window did not arrive at space " .. tostring(space)
                    .. " (" .. table.concat(trace, "; ") .. ")", 0)
            end
            return true
        end)
        hs.mouse.absolutePosition(cursor)
        return result, err
    end

    -- Move a window by sending it to the target screen while the target space
    -- is active there (a window moved to a screen joins that screen's active
    -- space). Moves within one screen hop through another screen first, so
    -- they need 2+ screens. The previously active space is restored afterwards.
    local function moveWindowViaScreens(window, space)
        local target = getScreenByUUID(hs.spaces.spaceDisplay(space))
        if not target then
            return nil, "unknown target space"
        end
        local function onSpace()
            return rs.contains(hs.spaces.windowSpaces(window) or {}, space)
        end
        -- Focusing the window around the move makes macOS reassign its space
        local function send(screen)
            window:focus()
            rs.delayExecution(rs.mc_settle)
            window:moveToScreen(screen, true, true)
            waitUntil(function() return window:screen() == screen end)
            window:focus()
            rs.delayExecution(rs.mc_settle)
        end

        if window:screen() == target and onSpace() then return true end
        local home = hs.spaces.activeSpaceOnScreen(target)
        if window:screen() == target then
            local hop
            for _, screen in ipairs(hs.screen.allScreens()) do
                if screen ~= target then hop = hop or screen end
            end
            if not hop then
                return nil, "same-screen moves need a second screen"
            end
            send(hop)
        end
        if home ~= space then
            local status, err = rs.gotoSpace(space)
            if not status then return nil, err end
        end
        send(target)
        local arrived = waitUntil(onSpace)
        local where = hs.inspect(hs.spaces.windowSpaces(window) or {}, {newline = "", indent = ""})
        if home ~= space then rs.gotoSpace(home) end
        if not arrived then
            return nil, "window did not land on space " .. tostring(space)
                .. " (is on " .. where .. ", screen '" .. window:screen():name() .. "')"
        end
        return true
    end

    -- Non-system space IDs of a screen, in Mission Control order
    local function getScreenSpaces(screen)
        local ids = {}
        for _, id in ipairs(hs.spaces.allSpaces()[screen:getUUID()] or {}) do
            if hs.spaces.spaceType(id) ~= "system" then
                table.insert(ids, id)
            end
        end
        return ids
    end

    local function indexOf(list, value)
        for i, element in ipairs(list) do
            if element == value then return i end
        end
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

    -- Move a window within its screen by holding its title bar while switching
    -- spaces with the "Move left/right a space" shortcuts (ctrl+arrows, which
    -- need the fn flag). The view is restored afterwards.
    local function moveWindowViaTitlebar(window, space)
        local target_screen = getScreenByUUID(hs.spaces.spaceDisplay(space))
        if not target_screen or window:screen() ~= target_screen then
            return nil, "window is not on the target screen"
        end
        local windowSpaces = function() return hs.spaces.windowSpaces(window) or {} end
        if rs.contains(windowSpaces(), space) then return true end

        local spaces = getScreenSpaces(target_screen)
        local home = hs.spaces.activeSpaceOnScreen(target_screen)
        local from, to = indexOf(spaces, home), indexOf(spaces, space)
        if not (from and to and rs.contains(windowSpaces(), home)) then
            return nil, "window is not on the active space of its screen"
        end

        local grab = getGrabPoint(window)
        local cursor = hs.mouse.absolutePosition()
        local direction = to > from and 1 or -1
        drag_counter = drag_counter + 1
        local number, last = drag_counter, grab
        local success, err = pcall(function()
            hs.mouse.absolutePosition(grab)
            postMouse("mouseMoved", grab, grab, number)
            rs.delayExecution(rs.mc_pause)
            postMouse("leftMouseDown", grab, grab, number)
            rs.delayExecution(rs.mc_pause)
            last = glide(grab, {x = grab.x + 8, y = grab.y + 8}, number, 8)
            for position = from + direction, to, direction do
                hs.eventtap.keyStroke({"ctrl", "fn"}, direction > 0 and "right" or "left", 0)
                local reached = function()
                    return hs.spaces.activeSpaceOnScreen(target_screen) == spaces[position]
                end
                if not waitUntil(reached) then
                    error("space switch failed (are the 'Move left/right a space' shortcuts enabled?)", 0)
                end
                rs.delayExecution(rs.mc_pause)
            end
        end)
        postMouse("leftMouseUp", last, last, number)
        local arrived = success and waitUntil(function()
            return rs.contains(windowSpaces(), space)
        end)
        if hs.spaces.activeSpaceOnScreen(target_screen) ~= home then
            gotoSpaceViaMC(home)
        end
        hs.mouse.absolutePosition(cursor)
        if not success then return nil, err end
        if not arrived then return nil, "window did not follow the space switch" end
        return true
    end

    -- JavaScript for Automation program that replays a list of mouse/keyboard
    -- actions as HID-level events, the closest to real hardware input that
    -- needs no compiled helper
    local jxa_script = [==[
ObjC.import("CoreGraphics");
ObjC.import("Foundation");
function run(argv) {
    var job = JSON.parse(argv[0]);
    var source = $.CGEventSourceCreate($.kCGEventSourceStateHIDSystemState);
    var kinds = {
        move: $.kCGEventMouseMoved, down: $.kCGEventLeftMouseDown,
        drag: $.kCGEventLeftMouseDragged, up: $.kCGEventLeftMouseUp
    };
    job.actions.forEach(function (a) {
        var event;
        if (a.kind === "wait") {
            $.NSThread.sleepForTimeInterval(a.seconds);
            return;
        } else if (a.kind === "key") {
            event = $.CGEventCreateKeyboardEvent(source, a.code, a.down);
            $.CGEventSetFlags(event, a.flags);
        } else {
            event = $.CGEventCreateMouseEvent(source, kinds[a.kind],
                $.CGPointMake(a.x, a.y), $.kCGMouseButtonLeft);
            $.CGEventSetIntegerValueField(event, $.kCGMouseEventNumber, job.number);
            $.CGEventSetIntegerValueField(event, $.kCGMouseEventClickState, 1);
            $.CGEventSetIntegerValueField(event, $.kCGMouseEventDeltaX, a.dx);
            $.CGEventSetIntegerValueField(event, $.kCGMouseEventDeltaY, a.dy);
            $.CGEventSetDoubleValueField(event, $.kCGMouseEventPressure, a.kind === "up" ? 0 : 1);
        }
        $.CGEventPost($.kCGHIDEventTap, event);
    });
    return "ok";
}
]==]

    -- Replay a list of actions with the JXA program above
    local function postGesture(actions)
        drag_counter = drag_counter + 1
        local job = hs.json.encode({number = drag_counter, actions = actions})
        local command = string.format("/usr/bin/osascript -l JavaScript -e '%s' '%s' 2>&1",
            jxa_script, job)
        local output, status = hs.execute(command, true)
        if not status then
            return nil, output
        end
        return true
    end

    local function mouseAction(kind, point, previous)
        return {
            kind = kind, x = point.x, y = point.y,
            dx = math.floor(point.x - previous.x + 0.5),
            dy = math.floor(point.y - previous.y + 0.5)
        }
    end

    -- Actions to press the mouse at `from`, drag to `to`, press the "Move
    -- left/right a space" shortcut `hops` times (left control + arrow, with the
    -- raw flags of a real keyboard) and release
    local function buildGesture(from, to, hops, direction)
        local actions = {
            mouseAction("move", from, from), {kind = "wait", seconds = rs.mc_settle},
            mouseAction("down", from, from), {kind = "wait", seconds = rs.mc_pause}
        }
        local previous = from
        for step = 1, rs.mc_drag_steps do
            local point = {
                x = from.x + (to.x - from.x) * step / rs.mc_drag_steps,
                y = from.y + (to.y - from.y) * step / rs.mc_drag_steps
            }
            table.insert(actions, mouseAction("drag", point, previous))
            table.insert(actions, {kind = "wait", seconds = rs.mc_drag_pause})
            previous = point
        end
        local arrow = direction > 0 and 124 or 123
        for _ = 1, hops do
            table.insert(actions, {kind = "key", code = 59, down = true, flags = 0x40001})
            table.insert(actions, {kind = "wait", seconds = rs.mc_pause})
            table.insert(actions, {kind = "key", code = arrow, down = true, flags = 0xA40001})
            table.insert(actions, {kind = "key", code = arrow, down = false, flags = 0xA40001})
            table.insert(actions, {kind = "key", code = 59, down = false, flags = 0})
            table.insert(actions, {kind = "wait", seconds = 2 * rs.mc_settle + 0.2})
        end
        table.insert(actions, mouseAction("up", previous, previous))
        return actions
    end

    -- Where a window is according to the API and, as ground truth, according
    -- to Mission Control (its thumbnails carry the ID of the window's space)
    local function locate(window)
        local bundle = window:application():bundleID()
        local title = window:title()
        local found = {}
        withMissionControl(function(mc)
            for _, display in ipairs(mc.displays) do
                for _, thumbnail in ipairs(getWindowThumbnails(display)) do
                    local id = tostring(getAttribute(thumbnail, "AXIdentifier"))
                    local owner, space = id:match("^(.*)%.space%.(%d+)$")
                    if owner == bundle and titleMatches(getAttribute(thumbnail, "AXTitle") or "", title) then
                        table.insert(found, tonumber(space))
                    end
                end
            end
            return true
        end)
        return {api = hs.spaces.windowSpaces(window) or {}, mc = found, screen = window:screen():name()}
    end

    local function describeLocation(location)
        return string.format("api {%s}, Mission Control {%s}, screen '%s'",
            table.concat(location.api, ","), table.concat(location.mc, ","), location.screen)
    end

    -- Whether either source says the window is on the space; also its location
    local function isOnSpace(window, space)
        local location = locate(window)
        return rs.contains(location.api, space) or rs.contains(location.mc, space), location
    end

    -- Move a window by holding its title bar while switching spaces with the
    -- "Move left/right a space" shortcuts, all posted as HID-level events.
    -- Windows on other screens are first sent to the target screen. The view
    -- is restored afterwards.
    local function moveWindowViaHID(window, space)
        local target = getScreenByUUID(hs.spaces.spaceDisplay(space))
        if not target then
            return nil, "unknown target space"
        end
        if window:screen() == target and rs.contains(hs.spaces.windowSpaces(window) or {}, space) then
            return true
        end
        if window:screen() ~= target then
            window:moveToScreen(target, true, true)
            waitUntil(function() return window:screen() == target end)
            rs.delayExecution(rs.mc_settle)
        end

        local spaces = getScreenSpaces(target)
        local home = hs.spaces.activeSpaceOnScreen(target)
        local from, to = indexOf(spaces, home), indexOf(spaces, space)
        if not (from and to) then
            return nil, "unknown space order"
        end
        if from == to then
            return isOnSpace(window, space)
        end

        window:focus()
        rs.delayExecution(rs.mc_settle)
        local grab = getGrabPoint(window)
        local cursor = hs.mouse.absolutePosition()
        local nudge = {x = grab.x + 8, y = grab.y + 8}
        local status, err = postGesture(buildGesture(grab, nudge, math.abs(to - from), to > from and 1 or -1))
        hs.mouse.absolutePosition(cursor)
        rs.delayExecution(rs.mc_settle)
        local arrived, location
        if status then
            arrived, location = isOnSpace(window, space)
        end
        if hs.spaces.activeSpaceOnScreen(target) ~= home then
            gotoSpaceViaMC(home)
        end
        if not status then
            return nil, "gesture failed: " .. tostring(err)
        elseif not arrived then
            return nil, "window did not follow (" .. describeLocation(location) .. ")"
        end
        return true
    end

    -- Strategies to move windows from macOS 15 on; the last one that worked
    -- is tried first
    local movers = {moveWindowViaHID, moveWindowViaScreens, moveWindowViaMC, moveWindowViaTitlebar}

    -- Native API up to macOS 14 (verified there); from macOS 15 it reports
    -- success without moving the window, so the strategies above are used
    local function moveWindow(window, space)
        if hs.host.operatingSystemVersion().major <= 14 then
            return hs.spaces.moveWindowToSpace(window, space)
        end
        local errors = {}
        for i, mover in ipairs(movers) do
            local status, err = mover(window, space)
            if status then
                movers[1], movers[i] = movers[i], movers[1]
                return true
            end
            table.insert(errors, tostring(err))
        end
        return nil, table.concat(errors, " | ")
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

-- REPLACE in `spaces.lua`: dumpTree and rs.testSpaceControl

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

    -- Diagnostic (takes 1-2 minutes; do not touch the mouse): clears the
    -- console, reports permissions, tests goto, whether synthetic title-bar
    -- drags are accepted (Hammerspoon events vs HID events), and every move
    -- strategy on the same screen and on another screen, checking the result
    -- against Mission Control and restoring the window after each one. Pass
    -- `true` to also dump the Mission Control tree. Prints one report; window
    -- titles appear in it, so redact before sharing.
    rs.testSpaceControl = function(dump)
        hs.console.clearConsole()
        local lines = {rs.getSystemInfo()}
        local function report(text) table.insert(lines, text) end
        local function timed(label, action)
            local start = hs.timer.secondsSinceEpoch()
            local success, status, info = pcall(action)
            if not success then status, info = nil, status end
            report(string.format("%-36s %s (%.2fs) %s", label, status and "OK" or "FAIL",
                hs.timer.secondsSinceEpoch() - start, tostring(info or "")))
            return status
        end
        -- A user space of the screen other than its active one, and the active one
        local function getOtherSpace(screen)
            local active = hs.spaces.activeSpaceOnScreen(screen)
            for _, id in ipairs(hs.spaces.spacesForScreen(screen:id()) or {}) do
                if id ~= active and hs.spaces.spaceType(id) == "user" then
                    return id, active
                end
            end
        end

        local tap = hs.eventtap.new({hs.eventtap.event.types.keyDown}, function() end)
        tap:start()
        report(string.format("accessibility: %s, event tap enabled: %s",
            tostring(hs.accessibilityState()), tostring(tap:isEnabled())))
        tap:stop()

        local window, other, active
        for _, candidate in ipairs(hs.window.orderedWindows()) do
            if candidate:isStandard() and candidate:application():name() ~= "Hammerspoon" then
                other, active = getOtherSpace(candidate:screen())
                if other then
                    window = candidate
                    break
                end
            end
        end

        if window then
            local home, frame = window:screen(), window:frame()
            local function where() return describeLocation(locate(window)) end
            local function restore()
                rs.gotoSpace(active)
                if window:screen() ~= home then window:moveToScreen(home, true, true) end
                window:setFrame(frame)
            end
            local function dragProbe(label, perform)
                timed(label, function()
                    local before = window:frame()
                    local grab = getGrabPoint(window)
                    local cursor = hs.mouse.absolutePosition()
                    local status, err = perform(grab, {x = grab.x + 100, y = grab.y})
                    rs.delayExecution(rs.mc_settle)
                    local moved = window:frame().x - before.x
                    window:setFrame(before)
                    hs.mouse.absolutePosition(cursor)
                    return moved > 50, string.format("window moved by %.0f px %s",
                        moved, status and "" or tostring(err))
                end)
            end
            -- Move out, follow the window, move back; always restore afterwards
            local function roundTrip(label, mover, to)
                local moved = timed(label .. " out", function() return mover(window, to) end)
                report("    now: " .. where())
                if moved then
                    timed("  goto moved window", function() return rs.gotoSpace(to) end)
                    timed(label .. " back", function() return mover(window, active) end)
                    report("    now: " .. where())
                end
                restore()
            end

            report("window of '" .. window:application():name() .. "' on '" .. home:name()
                .. "', active space " .. active .. ", test space " .. other)
            report("  start: " .. where())
            timed("goto other", function() return rs.gotoSpace(other) end)
            timed("goto back", function() return rs.gotoSpace(active) end)

            window:focus()
            rs.delayExecution(rs.mc_settle)
            report("synthetic title-bar drag of 100 px:")
            dragProbe("  Hammerspoon events", function(from, to)
                drag_counter = drag_counter + 1
                local number = drag_counter
                hs.mouse.absolutePosition(from)
                postMouse("mouseMoved", from, from, number)
                rs.delayExecution(rs.mc_settle)
                postMouse("leftMouseDown", from, from, number)
                rs.delayExecution(rs.mc_pause)
                local last = glide(from, to, number)
                postMouse("leftMouseUp", last, last, number)
                return true
            end)
            dragProbe("  HID events (JXA)", function(from, to)
                return postGesture(buildGesture(from, to, 0, 1))
            end)

            local strategies = {
                {"HID gesture", moveWindowViaHID},
                {"screens", moveWindowViaScreens},
                {"Mission Control drag", moveWindowViaMC},
                {"title bar (HS events)", moveWindowViaTitlebar}
            }
            for _, strategy in ipairs(strategies) do
                roundTrip(strategy[1] .. " / same screen", strategy[2], other)
            end
            for _, screen in ipairs(hs.screen.allScreens()) do
                local away = hs.spaces.activeSpaceOnScreen(screen)
                if screen ~= home and hs.spaces.spaceType(away) == "user" then
                    report("other screen: '" .. screen:name() .. "', space " .. away)
                    for _, strategy in ipairs(strategies) do
                        roundTrip(strategy[1] .. " / other screen", strategy[2], away)
                    end
                    break
                end
            end
            report("end: " .. where())
        else
            report("SKIPPED tests: no standard window on a screen with 2+ user spaces")
        end

        if dump then
            hs.spaces.openMissionControl()
            local mc = waitUntil(getMissionControl)
            for _, bundle in ipairs(mc_hosts) do
                report("Mission Control tree under " .. bundle .. ":")
                local app = hs.application.applicationsForBundleID(bundle)[1]
                if app then
                    dumpTree(hs.axuielement.applicationElement(app), 0, lines)
                else
                    report("  (process not running)")
                end
            end
            closeMC()
        end

        print("---- restore_spaces diagnostic ----\n" .. table.concat(lines, "\n"))
    end

end