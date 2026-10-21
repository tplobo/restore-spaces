-- `plumbing.lua`

-- Initialize plumbing
return function(rs,hs)

    rs.issueVerbose = function(text, verbose)
        verbose = verbose or rs.verbose
        if verbose then
            local info = debug.getinfo(2, "n")
            local calling_function = info and info.name or "unknown"
            print("(" .. calling_function .. ") " .. text)
        end
    end

    rs.notifyUser = function(case,verbose)
        local text = nil
        if case == "save" then
            text = "Windows saved!"
        elseif case == "apply" then
            text = "Windows applied!"
        elseif case == "fallback" then
            text = "Some windows were moved to fallback locations!"
        elseif case == "environment" then
            text = "Environment undefined!"
        else
            error("Unknown case: " .. case)
        end
        rs.issueVerbose(text, verbose)
        local message = {
            title="Restore Spaces",
            informativeText=text
        }
        hs.notify.new(message):send()
    end

    rs.processDataInFile = function(case, data)
        local function readFile(abs_path)
            local file = io.open(abs_path, 'r')
            if not file then
                print("Failed to open file: " .. abs_path)
                return {}
            end
            local json_contents = file:read('*all')
            file:close()
            return hs.json.decode(json_contents)
        end
        local function writeFile(abs_path, contents)
            if not contents then
                print("No contents to write!")
                return
            end
            --[[
            --TODO: fix recursive test to accept arrays (which are dicts in Lua)
            if not mod.recursiveKeysAreStrings(contents) then
                print("contents: " .. hs.inspect(contents))
                error("Keys in a table must be strings for JSON encoding!")
            end
            --]]
            local file = io.open(abs_path, 'w')
            if not file then
                print("Failed to open file: " .. abs_path)
                return
            end
            local json_contents = hs.json.encode(
                contents,
                true -- true: prettyprint
            )
            file:write(json_contents)
            file:close()
        end

        local contents
        if data == "windows" then
            contents = rs.data_wins
        elseif data == "environments" then
            contents = rs.data_envs
        else
            error("Unknown data: " .. data)
        end
        local filepath = "tmp/data_" .. data.. ".json"
        local abs_path = rs.packagePath(filepath)

        if case == "write" then
            writeFile(abs_path, contents)
        elseif case == "read" then
            contents = readFile(abs_path)
        else
            error("Unknown case: " .. case)
        end
        return contents
    end

    -- IDs of the spaces listed in `com.apple.spaces.plist`, without the hidden
    -- "dashboard" space (nil and an error message if the file cannot be read)
    rs.getPlistSpaces = function()
        local plist = hs.plist.read("~/Library/Preferences/com.apple.spaces.plist")
        local config = plist and plist["SpacesDisplayConfiguration"]
        local monitors = config and config["Management Data"] and config["Management Data"]["Monitors"]
        if not monitors then
            return nil, "Failed to read the spaces in com.apple.spaces.plist"
        end
        local plist_spaces = {}
        for _, monitor in ipairs(monitors) do
            for _, info in ipairs(monitor["Spaces"] or {}) do
                if info["uuid"] ~= "dashboard" then
                    table.insert(plist_spaces, info["id64"])
                end
            end
        end
        return plist_spaces
    end

    -- Keep only desktops (spaces of type "user"), in the given order. This drops
    -- the hidden "dashboard" space and the full-screen/split-view spaces. With
    -- `rs.use_plist_check`, desktops must also be listed in the spaces plist
    -- (which lags behind right after spaces are added or removed); if macOS
    -- reports no space types at all, the plist is used instead.
    rs.validateSpaces = function(all_spaces, verbose)
        verbose = verbose or rs.verbose
        all_spaces = all_spaces or {}
        local plist_spaces
        if rs.use_plist_check then
            local err
            plist_spaces, err = rs.getPlistSpaces()
            if not plist_spaces then error(err) end
        end

        local validated_spaces, ignored, untyped = {}, {}, 0
        for _, space in ipairs(all_spaces) do
            local space_type = hs.spaces.spaceType(space)
            if space_type == "user" and (not plist_spaces or rs.contains(plist_spaces, space)) then
                table.insert(validated_spaces, space)
            else
                table.insert(ignored, space .. ":" .. tostring(space_type))
            end
            untyped = untyped + (space_type == nil and 1 or 0)
        end
        if #all_spaces > 0 and untyped == #all_spaces then
            plist_spaces = rs.getPlistSpaces()
            for _, space in ipairs(plist_spaces and all_spaces or {}) do
                if rs.contains(plist_spaces, space) then
                    table.insert(validated_spaces, space)
                end
            end
        end
        if #ignored > 0 then
            rs.issueVerbose("ignored spaces (id:type): " .. table.concat(ignored, ", "), verbose)
        end
        return validated_spaces
    end

    rs.getWindowState = function(window)
        --TODO: Change "WindowState" to "AppState"
        local window_state = {}
        local window_id = tostring(window:id())

        --TODO: check if app window is hidden

        local fullscreen_state, frame_state = rs.getFrameState(window)
        window_state["fullscreen"] = fullscreen_state
        window_state["frame"] = frame_state
        window_state["title"] = window:title()
        window_state["app"] = window:application():name()
        if rs.contains(rs.multitab_apps, window_state["app"]) then
            window_state["multitab"] = true
            window_state["tabs"] = {}
        else
            window_state["multitab"] = false
            window_state["tabs"] = nil
        end

        rs.issueVerbose("get window " .. window:id(), rs.verbose)
        return window_state, window_id
    end

    --rs.setWindowState = function(window,window_state,space_map)
    rs.setWindowState = function(window,window_state,all_maps)
        if not window_state then
            --TODO: use window title to identify window (this creastes a
            --      problem if the window has multiple tabs)
            --TODO: if not found, minimize window
            window:minimize()
            return
        end
        --local title = window_state["title"]
        --local app = window_state["app"]
        local frame_state = window_state["frame"]
        local fullscreen_state = window_state["fullscreen"]
        local screen = window_state["screen"]
        local space = window_state["space"]
        local target_screen = screen
        local target_space = space
        
        --TODO: change argument to `all_maps` to loop through each 
        -- space_map of each screen, and find `target_space` when it is
        -- in a screen different than the one the window currently is.
        --if space_map then
        local msg
        if all_maps then
            for screen_index, space_map in pairs(all_maps) do
                for _, pair in pairs(space_map) do
                    local old_space = pair[1]
                    local new_space = pair[2]
                    if old_space == space then
                        target_space = new_space
                        target_screen = screen_index
                        msg = "target space " .. tostring(target_space)
                        msg = msg .. " identified"
                        msg = msg .. " in screen " .. tostring(target_screen)
                        msg = msg .. " for window " .. window:id()
                        rs.issueVerbose(msg, rs.verbose)
                        break
                    end
                end
            end
            
        else
            msg = "screen and space kept unchanged since "
            msg = msg .. "target space was not identified "
            msg = msg .. "for window " .. window:id()
            rs.issueVerbose(msg, rs.verbose)
        end

        -- Move to target space (falls back to another desktop/screen if needed)
        local status, err_msg = rs.moveWindowToSpace(window, target_space)

        rs.setFrameState(window, frame_state, fullscreen_state)
        if status then
            rs.issueVerbose("set window " .. window:id(), rs.verbose)
        else
            rs.issueVerbose("failed to set window " .. window:id(), rs.verbose)
            msg = "moveWindowToSpace status (" .. tostring(status)
            msg = msg .. "): " .. tostring(err_msg)
            rs.issueVerbose(msg, rs.verbose)
        end
    end

    rs.getFrameState = function(window)
        local frame = window:frame()
        local screen_frame = window:screen():frame()
        local frame_state = {
            ["x"] = frame.x,
            ["y"] = frame.y,
            ["w"] = frame.w,
            ["h"] = frame.h,
        }
        local isLeftEdge = frame.x == 0
        local isRightEdge = frame.x + frame.w == screen_frame.w
        local isLessThanFullWidth = frame.w < screen_frame.w

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

    rs.setFrameState = function(window, frame_state, fullscreen_state)
        if fullscreen_state == "yes" then
            window:setFullScreen(true)
        elseif fullscreen_state == "left" then
            window:setFullScreen(true)
            --TODO: find a way to make it left split-view
        elseif fullscreen_state == "right" then
            window:setFullScreen(true)
            --TODO: find a way to make it right split-view
        else
            local frame = window:frame()
            frame.x = frame_state["x"]
            frame.y = frame_state["y"]
            frame.w = frame_state["w"]
            frame.h = frame_state["h"]
            window:setFrame(frame)
        end
    end

end