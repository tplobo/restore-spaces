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

    rs.validateSpaces = function(all_spaces, verbose)
        verbose = verbose or rs.verbose
        local function extractNestedTable(key_sequence, table)
            local current_table = table
            for _, key in ipairs(key_sequence) do
                if type(current_table) ~= "table" then
                    error("Value is not a table at key: " .. key)
                end
                if current_table[key] then
                    current_table = current_table[key]
                else
                    error("Key not found: " .. key)
                end
            end
            return current_table
        end

        local plist_path = "~/Library/Preferences/com.apple.spaces.plist"
        local plist_spaces = hs.plist.read(plist_path)
        if not plist_spaces then
            print("Failed to read plist file")
        end

        local count = 0
        local valid_spaces = {}
        local all_screens = hs.screen.allScreens()
        for screen_i in ipairs(all_screens) do
            local key_sequence = {
                "SpacesDisplayConfiguration",
                "Management Data",
                "Monitors",
                screen_i,
                "Spaces",
            }
            local all_spaces_info = extractNestedTable(key_sequence, plist_spaces)
            for _, space_info in ipairs(all_spaces_info) do
                local uuid = space_info["uuid"]
                local id = space_info["id64"]
                if uuid ~= "dashboard" then
                    count = count + 1
                    valid_spaces[count] = id
                end
                local text = "screen: " .. screen_i .. ", space id: " .. id
                text = text .. ", space uuid:  " .. uuid
                rs.issueVerbose(text, verbose)
            end
        end

        local validated_spaces = {}
        for _, space in ipairs(all_spaces) do
            if hs.fnutils.contains(valid_spaces, space) then
                table.insert(validated_spaces, space)
            end
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

        --mod.issueVerbose("get window " .. window_id, mod.verbose)
        return window_state, window_id
    end

    rs.setWindowState = function(window,window_state,space_map)
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
        --local screen = window_state["screen"]
        local space = window_state["space"]
        local target_space = nil
        if space_map then
            for _, pair in pairs(space_map) do
                local old_space = pair[1]
                local new_space = pair[2]
                if old_space == space then
                    target_space = new_space
                    break
                end
            end
        else
            target_space = space
        end
        --target_space = tonumber(target_space)

        if rs.spaces_fixed_after_macOS14_5 then
            hs.spaces.moveWindowToSpace(window, target_space)
        else
            -- solution by `cunha`
            -- (see: https://github.com/Hammerspoon/hammerspoon/pull/3638#issuecomment-2252826567)
            local target_screen, _ = hs.spaces.spaceDisplay(target_space)
            hs.spaces.moveWindowToSpace(window, target_space)
            window:focus()
            rs.delayExecution(0.4)
            window:moveToScreen(target_screen)
            window:focus()
        end

        rs.setFrameState(window, frame_state, fullscreen_state)
        rs.issueVerbose("set window " .. window:id(), rs.verbose)
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