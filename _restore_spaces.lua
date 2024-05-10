local hs = {}
--hs.chooser = require 'hs.chooser'
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

-- Plumbing module (inner functions)
local mod = {}

-- Global variables (defaults)
mod.data_wins = {} -- collected info for each window
mod.data_envs = {} -- collected info for each environment

function mod.paddedToStr(int)
    return string.format("%03d", int)
end

function mod.delayExecution(delay)
    hs.timer.usleep(1e6 * delay)
end

function mod.recursiveKeysAreStrings(arg, verbose)
    verbose = verbose or mod.verbose
    local check = true
    if type(arg) == "table" then
        for key, value in pairs(arg) do
            if type(key) ~= "string" then
                check = check and false
            end
            if type(value) == "table" then
                local result = mod.recursiveKeysAreStrings(value, verbose)
                check = check and result
            end
        end
    else
        mod.issueVerbose("Non-table argument: " .. arg, verbose)
        check = check and false
    end
    return check
end

function mod.issueVerbose(text, verbose)
    verbose = verbose or mod.verbose
    if verbose then
        print(text)
    else
        -- do nothing
    end
end

function mod.notifyUser(case,verbose)
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
    mod.issueVerbose(text, verbose)
    local message = {
        title="Restore Spaces",
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
        --[[
        --TODO: fix recursive test to accept array values
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

--[[
function mod.validateSpaces(all_screens)
    local plistPath = "~/Library/Preferences/com.apple.spaces.plist"
    local plistTable = hs.plist.read(plistPath)
    
    TODO: import `plist` module
    TODO: check if spaces are are not of type `dashboard`
    
    if plistTable then
        print(hs.inspect(plistTable))
    else
        print("Failed to read plist file")
    end
--]]

function mod.retrieveEnvironmentEntities(entity, screen, verbose)
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
        --TODO: mod.validateSpaces(all_screens)
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
    mod.issueVerbose(message, verbose)

    if not all_entities then
        all_entities = {}
    end
    return all_entities
end

function mod.askEnvironmentName(envs_list, verbose)
    verbose = verbose or mod.verbose
    local text
    --[[
    --TODO: dialog with list saved names for potential overwrite
    --TODO: detectEnvironment must be changed for asynchronous operation
    local function chooseEnvironment(choice)
        if choice then
            text = "Environment name: " .. choice["text"]
            mod.issueVerbose(text, verbose)
            return choice["text"]
        else
            text = "User cancelled"
            mod.issueVerbose(text, verbose)
            return nil
        end
    end

    local chooser = hs.chooser.new(chooseEnvironment)
    local choices = {}
    for _, env_name in ipairs(all_envs) do
        table.insert(choices, {["text"] = env_name})
    end
    table.insert(choices, {["text"] = "(new environment name)"})
    chooser:choices(choices)
    chooser:show()
    --]]
    
    local prompt = "Current environment is new.\n"
    if envs_list == "" then
        prompt = prompt .. "Please give it a name:"
    else
        prompt = prompt .. "List of saved environments: \n" .. envs_list
        prompt = prompt .. "\nPlease overwrite one or give it a new name:"
    end
    local title = "Name this environment"
    local default_response = "(environment name)"
    local button, answer = hs.dialog.textPrompt(
        title,
        prompt,
        default_response,
        "OK", "Cancel")
    if button == "OK" then
        text = "Environment name: " .. answer
    else
        text = "User cancelled"
        answer = nil
    end
    mod.issueVerbose(text, verbose)
    return answer
end

function mod.getWindowState(window)
    local window_state = {}
    local window_id = tostring(window:id())

    --TODO: check if app window is hidden

    window_state["title"] = window:title()
    window_state["app"] = window:application():name()
    local fullscreen_state, frame_state = mod.getFrameState(window)
    window_state["fullscreen"] = fullscreen_state
    window_state["frame"] = frame_state
    --mod.issueVerbose("get window " .. window_id, mod.verbose)
    return window_state, window_id
end

function mod.setWindowState(window,window_state)
    if not window_state then
        window:minimize()
        return
    end
    local title = window_state["title"]
    local app = window_state["app"]
    local frame_state = window_state["frame"]
    local fullscreen_state = window_state["fullscreen"]
    local screen = window_state["screen"]
    local space = window_state["space"]

    --TODO: if the space does not exist, create a new one and
    --      use it as the new destination for every window that
    --      should be moved to it
    hs.spaces.moveWindowToSpace(window, space)
    mod.setFrameState(window, frame_state, fullscreen_state)
    --mod.issueVerbose("set window " .. window_id, mod.verbose)
end

function mod.getFrameState(window)
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

function mod.setFrameState(window, frame_state, fullscreen_state)
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

return mod