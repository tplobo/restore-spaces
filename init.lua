hs.inspect = require 'hs.inspect'
hs.hotkey = require 'hs.hotkey'
hs.window = require 'hs.window'
hs.json = require 'hs.json'

-- Requires installing the `spaces` module
-- See: https://github.com/asmagill/hs._asm.spaces
hs.spaces = require 'hs.spaces'

-- Global variables
all_info = {}
mode = "verbose"
--mode = "quiet"

local function retrieveDesktopEntities(entity,mode)
    local all_entities
    if entity == "spaces" then
        all_entities = hs.spaces.allSpaces()
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
    for _, window in ipairs(all_windows) do
        local id = tostring(window:id())
        local title = window:title()
        local application = window:application():name()
        local minimized = window:isMinimized()

        local info = {}
        info["title"] = title
        info["app"] = application
        info["minimized"] = minimized
        if not minimized then
            local space = hs.spaces.windowSpaces(window:id())
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
    end
    all_info = processFile("write", all_info)
    notifyUser("save")
end

local function applyWindowPositions()
    all_info = processFile("read", all_info)
    local all_spaces = retrieveDesktopEntities("spaces",mode)
    local all_windows = retrieveDesktopEntities("windows",mode)
    for _, window in ipairs(all_windows) do
        local id = tostring(window:id())
        print("id: " .. id)

        if all_info[id] then
            saved_minimized = all_info[id]["minimized"]
            print("title: " .. all_info[id]["title"])
            print("minimized': " .. tostring(saved_minimized))

            if not saved_minimized then
                --print("id for non-minimized: " .. id)

                local saved_frame = all_info[id]["frame"]
                local frame = window:frame()
                frame.x = saved_frame["x"]
                frame.y = saved_frame["y"]
                frame.w = saved_frame["w"]
                frame.h = saved_frame["h"]
                window:setFrame(frame)

                local saved_space = all_info[id]["space"]
                hs.spaces.moveWindowToSpace(tonumber(id), saved_space[1])

                print("frame: " .. hs.inspect(saved_frame))
                print("space: " .. hs.inspect(saved_space))
            else
                -- handle the case where the window was minimized
            end

        else
            -- handle the case where the window is not in the saved info
        end
    end
    notifyUser("apply")
end

hs.hotkey.bind({"cmd", "alt", "ctrl"}, "S", saveWindowPositions)
hs.hotkey.bind({"cmd", "alt", "ctrl"}, "A", applyWindowPositions)