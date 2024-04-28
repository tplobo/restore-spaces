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
pause = 0.5

local function retrieveDesktopEntities(entity, mode)
    local all_entities
    if entity == "spaces" then
        all_entities = hs.spaces.allSpaces()
        _, all_entities = next(all_entities) -- extract first value
    elseif entity == "windows" then
        all_entities = hs.window.allWindows()
        --all_entities = hs.window.orderedWindows()
    elseif entity == "visible" then
        all_entities = hs.window.visibleWindows()
    else
        hs.showError("Unknown entity: " .. entity)
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

local function isTile(side, window)
    local frame = window:frame()
    local screen_frame = window:screen():frame()
    if side == "left" then
        return frame.x == 0 and frame.w == screen_frame.w / 2
    elseif side == "right" then
        return frame.x == screen_frame.w / 2 and frame.w == screen_frame.w / 2
    else
        hs.showError("Unknown side: " .. side)
        return nil
    end
end

local function setTile(side, window)
    local screen_frame = window:screen():frame()
    if side == "left" then
        window:setFrame({x=0, y=0, w=screen_frame.w / 2, h=screen_frame.h})
    elseif side == "right" then
        window:setFrame({x=screen_frame.w / 2, y=0, w=screen_frame.w / 2, h=screen_frame.h})
    else
        hs.showError("Unknown side: " .. side)
        return nil
    end
end

local function saveWindowPositions()
    initial_space = hs.spaces.activeSpaceOnScreen()

    local all_spaces = retrieveDesktopEntities("spaces",mode)
    local all_windows = retrieveDesktopEntities("windows",mode)
    local info = {}

    for _, space in pairs(all_spaces) do
        print("space: " .. space)
        hs.spaces.gotoSpace(space)
        hs.timer.usleep(1e6 * pause)
        
        local space_windows = retrieveDesktopEntities("visible",mode)
        for _, window in ipairs(space_windows) do
            info = {}
            local id = tostring(window:id())

            info["title"] = window:title()
            info["app"] = window:application():name()
            if window:isFullScreen() then
                info["fullscreen"] = "yes"
            elseif isTile("left", window) then
                info["fullscreen"] = "left"
            elseif isTile("right", window) then
                info["fullscreen"] = "right"
            else
                local frame = window:frame()
                info["fullscreen"] = "no"
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
    all_info = processFile("write", all_info)

    notifyUser("save")
    hs.spaces.gotoSpace(initial_space)
end

local function applyWindowPositions()
    initial_space = hs.spaces.activeSpaceOnScreen()

    all_info = processFile("read", all_info)
    local all_spaces = retrieveDesktopEntities("spaces",mode)
    local all_windows = retrieveDesktopEntities("windows",mode)
    
    for _, space in ipairs(all_spaces) do
        hs.spaces.gotoSpace(space)
        hs.timer.usleep(1e6 * pause)

        local space_windows = retrieveDesktopEntities("visible",mode)
        for _, window in ipairs(space_windows) do
            local id = tostring(window:id())

            if all_info[id] then
                local saved_fullscreen = all_info[id]["fullscreen"]

                if saved_fullscreen == "yes" then    
                    window:setFullScreen(true)
                elseif saved_fullscreen == "left" then
                    setTile("left", window)
                elseif saved_fullscreen == "right" then
                    setTile("right", window)
                else
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
                        saved_space
                    )
                end
            else
                window:minimize()
            end
        end
    end
    notifyUser("apply")
    hs.spaces.gotoSpace(initial_space)
end

hs.hotkey.bind({"cmd", "alt", "ctrl"}, "S", saveWindowPositions)
hs.hotkey.bind({"cmd", "alt", "ctrl"}, "A", applyWindowPositions)