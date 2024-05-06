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

function mod.processDataInFile(case, data)
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
        local file = io.open(abs_path, 'w')
        if not file then
            print("Failed to open file: " .. abs_path)
            return
        end
        local json_contents = hs.json.encode(contents, true) -- true: prettyprint
        file:write(json_contents)
        file:close()
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

    if case == "write" then
        writeFile(abs_path, contents)
    elseif case == "read" then
        contents = readFile(abs_path)
    else
        error("Unknown case: " .. case)
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

--TODO: rename to retrieveEnvironmentEntities
function mod.retrieveEnvironmentEntities(entity, screen, mode)
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
        --TODO: how to return only visible spaces?
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

    local isFullHeight = frame.h == screen_frame.h
    if not isFullHeight then
        return false
    end

    local isLeftEdge = frame.x == 0
    local isRightEdge = frame.x + frame.w == screen_frame.w
    local isLessThanScreenWidth = frame.w < screen_frame.w
    -- check if tiled by using "y"
    if side == "left" then
        return isLeftEdge and isLessThanScreenWidth
    elseif side == "right" then
        return isRightEdge and isLessThanScreenWidth
    else
        error("Unknown side: " .. side)
        return nil
    end
    --TODO: extract ratio to re-apply it later
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

    mod.data_envs = mod.processDataInFile("read","environments")
    
    local all_screens = mod.retrieveEnvironmentEntities("screens")
    table.sort(all_screens, sortByFrame)

    local env = {}
    for index, screen in ipairs(all_screens) do
        local screen_name = screen:name()
        local screen_spaces = hs.spaces.spacesForScreen(screen:id())
        --TODO: store list of spaces instead of just number
        --TODO: what happens if space ids are not the same?
        local screen_index = tostring(index)
        env[screen_index] = {
            ["monitor"] = screen_name,
            ["spaces"] = screen_spaces
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

    mod.data_envs = mod.processDataInFile("write","environments")
    return env_name
end

--[[
function mod.buildEnvironment()
    --TODO: increase number of spaces if needed, but not decrease
end
--]]

function mod.getWindowState(window, mode)
    local window_state = {}
    local window_id = tostring(window:id())

    --TODO: check if app window is hidden

    window_state["title"] = window:title()
    -- copilot, when a window is is Fullscreen or Tiled mode (left or right), the function `saveState` creates multiple entries in `data_wins`, with ... please modify the function to check, in each space, if a window fo
    window_state["app"] = window:application():name()
    if window:isFullScreen() then
        window_state["fullscreen"] = "yes"
    elseif mod.isTile("left", window) then
        window_state["fullscreen"] = "left"
    elseif mod.isTile("right", window) then
        window_state["fullscreen"] = "right"
    else
        local frame = window:frame()
        window_state["fullscreen"] = "no"
        window_state["frame"] = {
            ["x"] = frame.x,
            ["y"] = frame.y,
            ["w"] = frame.w,
            ["h"] = frame.h,
        }
    end
    mod.issueVerbose(
        hs.inspect(window_state),
        "verbose" --mod.mode
    )
    return window_state, window_id
end

function mod.saveEnvironmentState()
    local env_name = mod.detectEnvironment()
    if not env_name then
        error("Undefined environment name!")
    end

    mod.data_wins = mod.processDataInFile("read","windows")
    if not mod.data_wins[env_name] then
        mod.data_wins[env_name] = {}
    end

    local all_screens = mod.retrieveEnvironmentEntities("screens",nil)
    for _, screen in ipairs(all_screens) do
        local screen_id = tostring(screen:id())

        local initial_space = hs.spaces.activeSpaceOnScreen(screen)
        local screen_spaces = mod.retrieveEnvironmentEntities("spaces", screen)
        local screen_windows = mod.retrieveEnvironmentEntities("windows", screen)

        hs.timer.usleep(1e6 * mod.screen_pause)
        for _, space in pairs(screen_spaces) do
            mod.issueVerbose(
                "go to space: " .. space .. " on screen: " .. screen_id,
                mod.mode
            )
            hs.spaces.gotoSpace(space)
            hs.timer.usleep(1e6 * mod.space_pause)
            
            local space_windows = mod.retrieveEnvironmentEntities("visible", screen)
            for _, window in ipairs(space_windows) do
                local window_state, window_id = mod.getWindowState(window, mod.mode)
                window_state["screen"] = tonumber(screen_id)
                window_state["space"] = space
                mod.data_wins[env_name][window_id] = window_state
            end
        end
        hs.spaces.gotoSpace(initial_space)
    end
    mod.data_wins = mod.processDataInFile("write","windows")
    mod.notifyUser("save")
end

function mod.setWindowState(window, env_info, mode)
    local window_id = tostring(window:id())
    if env_info[window_id] then
        local window_state = env_info[window_id]

        --local saved_screen = saved_info[window_id]["screen"]
        local saved_space = window_state["space"]
        --TODO: if the space does not exist, create a new one and
        --      use it as the new destination for every window that
        --      should be moved to it
        hs.spaces.moveWindowToSpace(window, saved_space)

        local saved_fullscreen = window_state["fullscreen"]
        if saved_fullscreen == "yes" then
            window:setFullScreen(true)
        elseif saved_fullscreen == "left" then
            mod.setTile("left", window)
        elseif saved_fullscreen == "right" then
            mod.setTile("right", window)
        else
            local saved_frame = window_state["frame"]
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
    mod.issueVerbose("set window " .. window_id, mod.mode)
end

function mod.applyEnvironmentState()
    local env_name = mod.detectEnvironment()
    if not env_name then
        error("Undefined environment name!")
    end

    --TODO: build environment to ensure every space id exists or has an
    --      equivalent, by creating a mapping between old and new space
    --      ids and save it in the environment JSON
    --TODO: open apps if they are not open
    --TODO: close apps if they are not saved?

    mod.data_wins = mod.processDataInFile("read","windows")
    if not mod.data_wins[env_name] then
        error("State for environment has never been saved!")
    end
    local env_info = mod.data_wins[env_name]

    local all_screens = mod.retrieveEnvironmentEntities("screens",nil)
    for _, screen in ipairs(all_screens) do
        local screen_id = tostring(screen:id())
        local initial_space = hs.spaces.activeSpaceOnScreen(screen)
        local screen_spaces = mod.retrieveEnvironmentEntities("spaces", screen)

        hs.timer.usleep(1e6 * mod.screen_pause)
        for _, space in pairs(screen_spaces) do
            mod.issueVerbose(
                "go to space: " .. space .. " on screen: " .. screen_id,
                mod.mode
            )
            hs.spaces.gotoSpace(space)
            hs.timer.usleep(1e6 * mod.space_pause)

            local space_windows = mod.retrieveEnvironmentEntities("visible", screen)
            for _, window in ipairs(space_windows) do
                mod.setWindowState(window, env_info, mod.mode)
            end
        end
        hs.spaces.gotoSpace(initial_space)
    end
    mod.notifyUser("apply")
end

return mod