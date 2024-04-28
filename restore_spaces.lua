hs.fnutils = require 'hs.fnutils'
hs.inspect = require 'hs.inspect'
hs.hotkey = require 'hs.hotkey'
hs.window = require 'hs.window'
hs.timer = require 'hs.timer'
hs.json = require 'hs.json'

-- Requires installing the `spaces` module
-- See: https://github.com/asmagill/hs._asm.spaces
hs.spaces = require 'hs.spaces'

local mod = {}

-- Global variables (defaults)
mod.mode = "quiet" -- or "verbose"
mod.pause = 0.3 -- in seconds (less than 0.3 is too fast)
mod.all_info = {}

function mod.retrieveDesktopEntities(entity, mode)
    mode = mode or mod.mode
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

function mod.notifyUser(case)
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

function mod.processFile(case, all_info)
    all_info  = all_info or mod.all_info
    local json_contents
    local file
    file_name = os.getenv('HOME') .. '/.hammerspoon/info_spaces.json'
    if case == "write" then
        file = io.open(file_name,'w')
        json_contents = hs.json.encode(all_info, true) -- true: prettyprint
        file:write(json_contents)

    elseif case == "read" then
        file = io.open(file_name,'r')
        json_contents = file:read('*all')
        all_info = hs.json.decode(json_contents)

    end
    file:close()
    return all_info
end

function mod.isTile(side, window)
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

function mod.setTile(side, window)
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

function mod.saveSpacesStates()
    initial_space = hs.spaces.activeSpaceOnScreen()

    local all_spaces = mod.retrieveDesktopEntities("spaces")
    local all_windows = mod.retrieveDesktopEntities("windows")
    local info = {}

    for _, space in pairs(all_spaces) do
        hs.spaces.gotoSpace(space)
        hs.timer.usleep(1e6 * mod.pause)
        
        local space_windows = mod.retrieveDesktopEntities("visible")
        for _, window in ipairs(space_windows) do
            info = {}
            local id = tostring(window:id())

            info["title"] = window:title()
            info["app"] = window:application():name()
            info["space"] = space
            if window:isFullScreen() then
                info["fullscreen"] = "yes"
            elseif mod.isTile("left", window) then
                info["fullscreen"] = "left"
            elseif mod.isTile("right", window) then
                info["fullscreen"] = "right"
            else
                local frame = window:frame()
                info["fullscreen"] = "no"
                info["frame"] = {
                    ["x"] = frame.x, 
                    ["y"] = frame.y,
                    ["w"] = frame.w,
                    ["h"] = frame.h,
                }
            end
            mod.all_info[id] = info
        end
    end
    mod.all_info = mod.processFile("write")

    mod.notifyUser("save")
    hs.spaces.gotoSpace(initial_space)
end

function mod.applySpacesStates()
    initial_space = hs.spaces.activeSpaceOnScreen()

    mod.all_info = mod.processFile("read")
    local all_spaces = mod.retrieveDesktopEntities("spaces")
    local all_windows = mod.retrieveDesktopEntities("windows")
    
    for _, space in ipairs(all_spaces) do
        hs.spaces.gotoSpace(space)
        hs.timer.usleep(1e6 * mod.pause)

        local space_windows = mod.retrieveDesktopEntities("visible")
        for _, window in ipairs(space_windows) do
            local id = tostring(window:id())

            if mod.all_info[id] then
                local saved_space = mod.all_info[id]["space"]
                hs.spaces.moveWindowToSpace(
                    tonumber(id),
                    saved_space
                )

                local saved_fullscreen = mod.all_info[id]["fullscreen"]
                if saved_fullscreen == "yes" then    
                    window:setFullScreen(true)
                elseif saved_fullscreen == "left" then
                    mod.setTile("left", window)
                elseif saved_fullscreen == "right" then
                    mod.setTile("right", window)
                else
                    local saved_frame = mod.all_info[id]["frame"]
                    local frame = window:frame()
                    frame.x = saved_frame["x"]
                    frame.y = saved_frame["y"]
                    frame.w = saved_frame["w"]
                    frame.h = saved_frame["h"]
                    window:setFrame(frame)
                end
            else
                window:minimize()
            end
        end
    end
    mod.notifyUser("apply")
    hs.spaces.gotoSpace(initial_space)
end

return mod