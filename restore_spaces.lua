local hs = {}
hs.fnutils = require 'hs.fnutils'
hs.inspect = require 'hs.inspect'
hs.hotkey = require 'hs.hotkey'
hs.notify = require 'hs.notify'
hs.window = require 'hs.window'
hs.screen = require 'hs.screen'
hs.dialog = require 'hs.dialog'
hs.timer = require 'hs.timer'
hs.json = require 'hs.json'

-- Requires installing the `spaces` module
-- See: https://github.com/asmagill/hs._asm.spaces
hs.spaces = require 'hs.spaces'

local mod = {}

-- Global variables (defaults)
mod.mode = "quiet" -- "quiet" or "verbose"
mod.space_pause = 0.3 -- in seconds (<0.3 breaks the spaces module)
mod.screen_pause = 0.4 -- in seconds (<0.4 breaks the spaces module)
mod.data_wins = {} -- collected info for each window
mod.data_envs = {} -- collected info for each environment
--mod.window_filter = hs.window.filter.new()

function mod.issueVerbose(text, mode)
    mode = mode or mod.mode
    if mode ==  "verbose" then
        print(text)
    elseif mode == 'quiet' then
        -- do nothing
    else
        error("Unknown mode: " .. mode)
    end
end

function mod.notifyUser(case,mode)
    local text = nil
    if case == "save" then
        text = "Windows saved!"
    elseif case == "apply" then
        text = "Windows applied!"
    end
    mod.issueVerbose(text, mode)
    local message = {
        title="Hammerspoon",
        informativeText=text
    }
    hs.notify.new(message):send()
end

function mod.processDataFile(case, data)
    local function openFile(abs_path, r_or_w)
        local file = io.open(abs_path, r_or_w)
        if not file and r_or_w == 'r' then
            return nil
        else
            return file
        end
    end

    local contents
    if data == "windows" then
        contents = mod.data_wins
    elseif data == "environments" then
        contents = mod.data_envs
    else
        error("Unknown data: " .. data)
    end
    local file_name = "data_" .. data
    local rel_path = '/.hammerspoon/' .. file_name .. '.json'
    local abs_path = os.getenv('HOME') .. rel_path

    local file
    local json_contents
    if case == "write" then
        file = openFile(abs_path,'w')
        json_contents = hs.json.encode(contents, true) -- true: prettyprint
        file:write(json_contents)
    elseif case == "read" then
        file = openFile(abs_path,'r')
        if not file then
            contents = {}
        else
            json_contents = file:read('*all')
            contents = hs.json.decode(json_contents)
        end
    else
        error("Unknown case: " .. case)
    end
    if file then
        file:close()
    end

    return contents
end

function mod.askEnvironmentName(mode)
    mode = mode or mod.mode
    local text
    local defaultResponse = "(environment name)"
    --TODO: dialog with list saved names for potential overwrite
    local button, answer = hs.dialog.textPrompt(
        "Name this environment setup",
        "Current environment is new. Please give it a name:",
        defaultResponse,
        "OK", "Cancel")
    if button == "OK" then
        text = "Environment name: " .. answer
    else
        text = "User cancelled"
        answer = nil
    end
    mod.issueVerbose(text, mode)
    return answer
end

function mod.retrieveDesktopEntities(entity, screen, mode)
    local function validateNil(arg)
        if not arg then
            return true
        else
            error("Argument not nil: " .. hs.inspect(arg))
        end
    end
    local function validateScreen(arg)
        local is_screen = tostring(arg):match("hs.screen")
        if is_screen then
            return true
        else
            error(
                "Argument is not a 'screen': " .. hs.inspect(screen)
            )
        end
    end
    local function isWindowOnScreen(window)
        return window:screen() == screen
    end

    local all_entities
    if entity == "screens" then
        validateNil(screen)
        all_entities = hs.screen.allScreens()
    elseif entity == "spaces" then
        validateScreen(screen)
        all_entities = hs.spaces.spacesForScreen(screen:id())
    elseif entity == "windows" then
        validateScreen(screen)
        local all_windows = hs.window.orderedWindows()
        all_entities = hs.fnutils.filter(
            all_windows,
            isWindowOnScreen
        )
    elseif entity == "visible" then
        validateScreen(screen)
        local all_visible = hs.window.visibleWindows()
        all_entities = hs.fnutils.filter(
            all_visible,
            isWindowOnScreen
        )
    else
        error("Unknown entity: " .. entity)
    end

    local message = string.format(
        "all %s: %s",
        entity,
        hs.inspect(all_entities)
    )
    mod.issueVerbose(message, mode)
    return all_entities
end

function mod.isTile(side, window)
    local frame = window:frame()
    local screen_frame = window:screen():frame()
    if side == "left" then
        return frame.x == 0 and frame.w == screen_frame.w / 2
    elseif side == "right" then
        return frame.x == screen_frame.w / 2 and frame.w == screen_frame.w / 2
    else
        error("Unknown side: " .. side)
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
        error("Unknown side: " .. side)
        return nil
    end
    --TODO: compatibility with non-half-half frame sizes
end

function mod.detectEnvironment()
    local function sortByFrame(a, b)
        return a:frame().x < b:frame().x
    end

    mod.data_envs = mod.processDataFile("read","environments")
    
    local all_screens = mod.retrieveDesktopEntities("screens")
    table.sort(all_screens, sortByFrame)

    local env = {}
    for index, screen in ipairs(all_screens) do
        local screen_name = screen:name()
        local num_spaces = #hs.spaces.spacesForScreen(screen:id())
        --TODO: store list of spaces instead of just number
        --TODO: what happens if space ids are not the same?
        local screen_index = tostring(index)
        env[screen_index] = {
            ["monitor"] = screen_name,
            ["spaces"] = num_spaces
        }
    end

    local env_exists = false
    local env_name
    for saved_name, saved_env in pairs(mod.data_envs) do
        local saved_monitors = {}
        for _, value in pairs(saved_env) do
            table.insert(saved_monitors, value["monitor"])
        end

        local current_monitors = {}
        for _, value in pairs(env) do
            table.insert(current_monitors, value["monitor"])
        end

        local check_monitors = (
            hs.inspect(saved_monitors) == hs.inspect(current_monitors)
        )
        if check_monitors then
            env_exists = true
            env_name = saved_name
            break
        end
    end

    local text
    if env_exists then
        text = "Environment already exists: " .. env_name
        mod.issueVerbose(text, mod.mode)
    else
        text = "Environment does not exist."
        mod.issueVerbose(text, mod.mode)

        env_name = mod.askEnvironmentName(mod.mode)
        if not env_name then
            error("Undefined environment name: !")
        else
            mod.data_envs[env_name] = env
        end
    end

    mod.data_envs = mod.processDataFile("write","environments")
    return env_name
end

--[[
function mod.buildEnvironment()
    --TODO: increase number of spaces if needed, but not decrease
end
--]]

function mod.saveState()
    local env_name = mod.detectEnvironment()
    if not env_name then
        error("Undefined environment name!")
    end

    mod.data_wins = mod.processDataFile("read","windows")
    if not mod.data_wins[env_name] then
        mod.data_wins[env_name] = {}
    end

    local all_screens = mod.retrieveDesktopEntities("screens",nil)
    for _, screen in ipairs(all_screens) do
        local screen_id = tostring(screen:id())

        local initial_space = hs.spaces.activeSpaceOnScreen(screen)
        local screen_spaces = mod.retrieveDesktopEntities("spaces", screen)
        local screen_windows = mod.retrieveDesktopEntities("windows", screen)

        hs.timer.usleep(1e6 * mod.screen_pause)
        for _, space in pairs(screen_spaces) do
            mod.issueVerbose(
                "go to space: " .. space .. " on screen: " .. screen_id,
                mod.mode
            )
            hs.spaces.gotoSpace(space)
            hs.timer.usleep(1e6 * mod.space_pause)
            
            local space_windows = mod.retrieveDesktopEntities("visible", screen)
            for _, window in ipairs(space_windows) do
                local window_info = {}
                local window_id = tostring(window:id())

                --TODO: check if app window is hidden

                window_info["title"] = window:title()
                window_info["app"] = window:application():name()
                window_info["screen"] = tonumber(screen_id)
                window_info["space"] = space
                if window:isFullScreen() then
                    window_info["fullscreen"] = "yes"
                elseif mod.isTile("left", window) then
                    window_info["fullscreen"] = "left"
                elseif mod.isTile("right", window) then
                    window_info["fullscreen"] = "right"
                else
                    local frame = window:frame()
                    window_info["fullscreen"] = "no"
                    window_info["frame"] = {
                        ["x"] = frame.x,
                        ["y"] = frame.y,
                        ["w"] = frame.w,
                        ["h"] = frame.h,
                    }
                end
                mod.data_wins[env_name][window_id] = window_info
            end
        end
        hs.spaces.gotoSpace(initial_space)
    end
    mod.data_wins = mod.processDataFile("write","windows")
    mod.notifyUser("save")
end

function mod.applyState()
    local env_name = mod.detectEnvironment()
    if not env_name then
        error("Undefined environment name!")
    end

    --TODO: build environment to ensure every space id exists!

    mod.data_wins = mod.processDataFile("read","windows")
    if not mod.data_wins[env_name] then
        error("State for environment has never been saved!")
    end
    local env_info = mod.data_wins[env_name]

    local all_screens = mod.retrieveDesktopEntities("screens",nil)
    for _, screen in ipairs(all_screens) do
        local screen_id = tostring(screen:id())
        local initial_space = hs.spaces.activeSpaceOnScreen(screen)
        local screen_spaces = mod.retrieveDesktopEntities("spaces", screen)

        hs.timer.usleep(1e6 * mod.screen_pause)
        for _, space in pairs(screen_spaces) do
            mod.issueVerbose(
                "go to space: " .. space .. " on screen: " .. screen_id,
                mod.mode
            )
            hs.spaces.gotoSpace(space)
            hs.timer.usleep(1e6 * mod.space_pause)

            local space_windows = mod.retrieveDesktopEntities("visible", screen)
            for _, window in ipairs(space_windows) do
                local window_id = tostring(window:id())

                if env_info[window_id] then
                    local window_info = env_info[window_id]

                    --local saved_screen = saved_info[window_id]["screen"]
                    local saved_space = window_info["space"]
                    hs.spaces.moveWindowToSpace(window, saved_space)

                    local saved_fullscreen = window_info["fullscreen"]
                    if saved_fullscreen == "yes" then
                        window:setFullScreen(true)
                    elseif saved_fullscreen == "left" then
                        mod.setTile("left", window)
                    elseif saved_fullscreen == "right" then
                        mod.setTile("right", window)
                    else
                        local saved_frame = window_info["frame"]
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
        hs.spaces.gotoSpace(initial_space)
    end
    mod.notifyUser("apply")
end

return mod