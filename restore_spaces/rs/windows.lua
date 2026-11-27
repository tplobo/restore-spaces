-- `windows.lua`

-- Initialize window functions (recognition rules, state, frame)
return function(rs,hs)

    -- Recognition rule of an app: nil (only by ID and exact title), "tabs"
    -- (by its tabs), "app" (by the app, when it has one saved window) or a list
    -- of title terms (by the first term found in the title)
    rs.getRecognition = function(app)
        return rs.legacy.getRecognition()[app]
    end

    -- First title term (plain text) of an app that appears in `title`, if the app
    -- has terms
    rs.getTitleKey = function(app, title)
        local keys = rs.getRecognition(app)
        if type(keys) ~= "table" then return nil end
        for _, key in ipairs(keys) do
            if tostring(title):find(key, 1, true) then return key end
        end
    end

    -- Whether `save` and `apply` skip the windows of an app (`rs.ignored_apps`)
    rs.isIgnoredApp = function(app)
        return rs.contains(rs.ignored_apps or {}, app)
    end

    -- Fullscreen state ("no", "yes", "left", "right") and frame of a window; the
    -- edges are those of its own screen
    rs.getFrameState = function(window)
        local frame = window:frame()
        local area = window:screen():fullFrame()
        local tolerance = 4
        local frame_state = {
            ["x"] = frame.x,
            ["y"] = frame.y,
            ["w"] = frame.w,
            ["h"] = frame.h,
        }
        local isLeftEdge = math.abs(frame.x - area.x) <= tolerance
        local isRightEdge = math.abs(frame.x + frame.w - (area.x + area.w)) <= tolerance
        local isLessThanFullWidth = frame.w < area.w - tolerance

        local fullscreen_state = "no"
        if window:isFullScreen() then
            if isLessThanFullWidth then
                if isLeftEdge then
                    fullscreen_state = "left"
                elseif isRightEdge then
                    fullscreen_state = "right"
                end
            else
                fullscreen_state = "yes"
            end
        end
        return fullscreen_state, frame_state
    end

    rs.getWindowState = function(window)
        --TODO: Change "WindowState" to "AppState"
        local window_state = {}
        local window_id = tostring(window:id())

        --TODO: check if app window is hidden

        -- A window can vanish while the loops run (_e.g._ its app quits). It is
        -- reported without a title, which makes the callers ignore it.
        local app = window:application()
        if not (app and window:screen()) then
            rs.issueVerbose("window vanished: " .. window_id, rs.verbose)
            return {
                title = "", app = "(unknown)", fullscreen = "no", multitab = false,
                frame = {x = 0, y = 0, w = 0, h = 0}
            }, window_id
        end

        local fullscreen_state, frame_state = rs.getFrameState(window)
        window_state["fullscreen"] = fullscreen_state
        window_state["frame"] = frame_state
        window_state["title"] = window:title()
        window_state["app"] = app:name()
        window_state["multitab"] = rs.getRecognition(window_state["app"]) == "tabs"
        window_state["tabs"] = window_state["multitab"] and {} or nil

        rs.issueVerbose("get window " .. window_id, rs.verbose)
        return window_state, window_id
    end

    -- Space (and index of its screen) where a saved desktop window must go, from
    -- the maps of saved to current spaces (`all_maps`); the saved space itself,
    -- and no screen, if the maps do not know it
    rs.getTargetSpace = function(window_state, all_maps)
        local space = window_state["space"]
        for screen_index, space_map in pairs(all_maps or {}) do
            for _, pair in pairs(space_map) do
                if pair[1] == space then
                    return pair[2], screen_index
                end
            end
        end
        return space, nil
    end

    -- Set the frame of a window; apps that refuse it (minimum sizes,
    -- constraints) are warned about
    rs.setFrameState = function(window, frame_state)
        if not frame_state then return end
        local frame = window:frame()
        frame.x = frame_state["x"]
        frame.y = frame_state["y"]
        frame.w = frame_state["w"]
        frame.h = frame_state["h"]
        window:setFrame(frame)

        local after = window:frame()
        for _, key in ipairs({"x", "y", "w", "h"}) do
            if math.abs(after[key] - frame[key]) > 4 then
                local app = window:application()
                rs.warn(string.format("window %d of '%s': frame not set (%s is %.0f, wanted %.0f)",
                    window:id(), app and app:name() or "?", key, after[key], frame[key]), "frames")
                break
            end
        end
    end

    -- Move a saved desktop window to `target_space` and set its frame. Windows
    -- saved in a full-screen space are placed later (`rs.restoreFullScreen`).
    -- The frame is only set if the move worked: a window left on the wrong
    -- desktop must not be dragged to a frame saved for another one. A failed
    -- move is counted in `rs.failed_count`.
    -- Returns: true | nil, error message
    rs.setWindowState = function(window, window_state, target_space)
        if window_state["space_kind"] == "fullscreen" then
            return true
        end
        if not rs.leaveFullScreen(window) then
            rs.warn(string.format("window %d of '%s' is in a full-screen space and did not leave it",
                window:id(), window_state["app"]), "fullscreen")
        end

        -- Move to target space (falls back to another desktop/screen if needed)
        local status, err_msg = rs.moveWindowToSpace(window, target_space)
        if status then
            rs.setFrameState(window, window_state["frame"])
            rs.issueVerbose("set window " .. window:id(), rs.verbose)
            -- Keep the window in view (a no-op unless `rs.min_window_visibility` > 0)
            rs.realignWindow(window)
        else
            rs.failed_count = rs.failed_count + 1
            rs.issueVerbose("failed to set window " .. window:id() .. ": "
                .. tostring(err_msg), rs.verbose)
        end
        return status, err_msg
    end

end