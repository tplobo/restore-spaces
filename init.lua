hs.fnutils = require 'hs.fnutils'
hs.inspect = require 'hs.inspect'
hs.hotkey = require 'hs.hotkey'
hs.window = require 'hs.window'
hs.timer = require 'hs.timer'
hs.json = require 'hs.json'

-- Requires installing the `spaces` module
-- See: https://github.com/asmagill/hs._asm.spaces
hs.spaces = require 'hs.spaces'
hs.spaces.setDefaultMCwaitTime()

-- Global variables
all_info = {}
mode = "verbose"
--mode = "quiet"
pause = 1

local function retrieveDesktopEntities(entity,mode)
    local all_entities
    if entity == "spaces" then
        all_entities = hs.spaces.allSpaces()
        _, all_entities = next(all_entities) -- extract first value
    elseif entity == "windows" then
        all_entities = hs.window.allWindows()
        --all_entities = hs.window.orderedWindows()
    end

    if mode ==  "verbose" then
        message = string.format(
            "all %s: %s",
            entity,
            hs.inspect(all_entities)
        )
        print(message)
    elseif mode == 'quiet' then
        -- do nothing
    end

    return all_entities
end

local function notifyUser(case)
    if case == "save" then
        text = "Windows saved!"
    elseif case == "apply" then
        text = "Windows applied!"
    end
    message = {
        title="Hammerspoon",
        informativeText=text
    }
    hs.notify.new(message):send()
end

local function processFile(case, all_info)
    local json_contents
    local file
    if case == "write" then
        file = io.open(
            os.getenv('HOME') .. '/.hammerspoon/info_windows.json',
            'w'
        )
        json_contents = hs.json.encode(all_info, true) -- true: prettyprint
        file:write(json_contents)

    elseif case == "read" then
        file = io.open(
            os.getenv('HOME') .. '/.hammerspoon/info_windows.json',
            'r'
        )
        json_contents = file:read('*all')
        all_info = hs.json.decode(json_contents)

    end
    file:close()
    return all_info
end

local function saveWindowPositions()
    local all_spaces = retrieveDesktopEntities("spaces",mode)
    local all_windows = retrieveDesktopEntities("windows",mode)
    local info = {}

    for _, space in pairs(all_spaces) do
        print("space: " .. space)
        hs.spaces.gotoSpace(space)
        hs.timer.usleep(1e6 * pause)
        
        space_windows = hs.window.visibleWindows()
        print("space_windows: " .. hs.inspect(space_windows))

        for _, window in ipairs(all_windows) do
            local window_spaces = hs.spaces.windowSpaces(window:id())
            --print("window_spaces: " .. hs.inspect(window_spaces))

            info = {}
            if hs.fnutils.contains(window_spaces, space) then
                local id = tostring(window:id())

                info["title"] = window:title()
                info["app"] = window:application():name()
                info["minimized"] = window:isMinimized()
                if not minimized then
                    local frame = window:frame()
                    info["space"] = space
                    info["frame"] = {
                        ["x"] = frame.x, 
                        ["y"] = frame.y,
                        ["w"] = frame.w,
                        ["h"] = frame.h,
                    }
                end
                all_info[id] = info
                print("info: " .. hs.inspect(info))
            end

        end
        
    end
    all_info = processFile("write", all_info)
    notifyUser("save")
end

local function applyWindowPositions()
    all_info = processFile("read", all_info)
    local all_spaces = retrieveDesktopEntities("spaces",mode)
    local all_windows = retrieveDesktopEntities("windows",mode)

    for _, space in ipairs(all_spaces) do
        hs.spaces.gotoSpace(space)
        hs.timer.usleep(1e6 * pause)
        for _, window in ipairs(all_windows) do
            local id = tostring(window:id())

            if all_info[id] then
                --local saved_space = all_info[id]["space"]
                local saved_minimized = all_info[id]["minimized"]

                --local check_space = hs.fnutils.contains(
                --    saved_space_ids,
                --    space
                --)
                --local check_minimized = not saved_minimized

                --if check_minimized and check_space then
                if not saved_minimized then    
                    local saved_frame = all_info[id]["frame"]
                    local frame = window:frame()
                    frame.x = saved_frame["x"]
                    frame.y = saved_frame["y"]
                    frame.w = saved_frame["w"]
                    frame.h = saved_frame["h"]
                    window:setFrame(frame)

                    local saved_space = all_info[id]["space"]
                    hs.spaces.moveWindowToSpace(
                        tonumber(id),
                        saved_space[1]
                    )
                end
            end

        end
    end
    notifyUser("apply")
end

hs.hotkey.bind({"cmd", "alt", "ctrl"}, "S", saveWindowPositions)
hs.hotkey.bind({"cmd", "alt", "ctrl"}, "A", applyWindowPositions)