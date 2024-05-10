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

local mod = {}

-- Global variables (defaults)
mod.mode = "quiet" -- "quiet" or "verbose"
mod.space_pause = 0.3 -- in seconds (<0.3 breaks the spaces module)
mod.screen_pause = 0.4 -- in seconds (<0.4 breaks the spaces module)
mod.data_wins = {} -- collected info for each window
mod.data_envs = {} -- collected info for each environment
--TODO: mod.max_spaces = 0 (maximum number of spaces saved per screen)

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
    elseif case == "environment" then
        text = "Environment undefined!"
    else
        error("Unknown case: " .. case)
    end
    mod.issueVerbose(text, mode)
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
    mod.issueVerbose(message, mode)

    if not all_entities then
        all_entities = {}
    end
    return all_entities
end

function mod.askEnvironmentName(envs_list, mode)
    mode = mode or mod.mode
    local text
    --[[
    --TODO: dialog with list saved names for potential overwrite
    --TODO: detectEnvironment must be changed for asynchronous operation
    local function chooseEnvironment(choice)
        if choice then
            text = "Environment name: " .. choice["text"]
            mod.issueVerbose(text, mode)
            return choice["text"]
        else
            text = "User cancelled"
            mod.issueVerbose(text, mode)
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
    mod.issueVerbose(text, mode)
    return answer
end

function mod.detectEnvironment(save_flag)
    local function sortByFrame(a, b)
        return a:frame().x < b:frame().x
    end
    local function listKeys(table)
        local keys_list = ""
        for key, _ in pairs(table) do
            keys_list = keys_list .. "'" .. key .. "'\n"
        end
        --keys_list = keys_list:sub(1, -3) -- remove last comma and space
        return keys_list
    end

    mod.data_envs = mod.processDataInFile("read","environments")
    
    local all_screens = mod.retrieveEnvironmentEntities("screens")
    table.sort(all_screens, sortByFrame)
    
    local env = {}
    for index, screen in ipairs(all_screens) do
        local screen_name = screen:name()
        local screen_spaces = mod.retrieveEnvironmentEntities("spaces", screen)
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
        text = "Environment detected: '" .. env_name .. "'"
        mod.issueVerbose(text, mod.mode)
        --[[
        -- FOR TESTING ONLY:
        local envs_list = listKeys(mod.data_envs)
        env_name = mod.askEnvironmentName(envs_list, mod.mode)
        if not env_name then
            error("Undefined environment name: !")
        else
            mod.data_envs[env_name] = env
        end
        --]]
    else
        text = "Environment does not exist."
        mod.issueVerbose(text, mod.mode)
        text = "Environment name undefined!"
        if save_flag then
            local envs_list = listKeys(mod.data_envs)
            env_name = mod.askEnvironmentName(envs_list, mod.mode)
            if not env_name then
                error(text)
            else
                mod.data_envs[env_name] = env
            end
            mod.data_envs = mod.processDataInFile("write","environments")
        else
            mod.notifyUser("environment")
            error(text)
        end
    end
    return env_name, env
end

--[]
function mod.buildEnvironment(env_name)
    mod.data_envs = mod.processDataInFile("read","environments")
    local saved_env = mod.data_envs[env_name]
    if not saved_env then
        error("Environment '" .. env_name .. "' does not exist.")
    end

    local space_map = {}

    local all_screens = mod.retrieveEnvironmentEntities("screens",nil)
    for screen_index, screen in ipairs(all_screens) do
        local screen_id = tostring(screen_index)

        local screen_name = screen:name()
        local saved_name = saved_env[screen_id]["monitor"]
        if screen_name ~= saved_name then
            error(
                "Environment mismatch: " .. screen_name .. " ≠ " .. saved_name
            )
        end

        local screen_spaces = mod.retrieveEnvironmentEntities("spaces", screen)
        local saved_spaces = saved_env[screen_id]["spaces"]
        while #screen_spaces < #saved_spaces do
            hs.spaces.addSpaceToScreen(screen_index)
            screen_spaces = mod.retrieveEnvironmentEntities("spaces", screen)
        end
        while #screen_spaces > #saved_spaces do
            --TODO: do not decrease number of spaces (only increase)?
            local last_space_id = screen_spaces[#screen_spaces]
            hs.spaces.removeSpace(last_space_id)
            screen_spaces = mod.retrieveEnvironmentEntities("spaces", screen)
        end

        for i, space_id in ipairs(saved_spaces) do
            space_map[space_id] = screen_spaces[i]
        end

    end
    mod.data_envs[env_name]["space_map"] = space_map
    print("env: " .. hs.inspect(mod.data_envs[env_name]))
    --mod.processDataInFile("write", "environments")

    mod.issueVerbose(
        "new space_map: " .. hs.inspect(space_map),
        "verbose" --mod.mode
    )
    return space_map
end
--]]

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

function mod.getWindowState(window)
    local window_state = {}
    local window_id = tostring(window:id())

    --TODO: check if app window is hidden

    window_state["title"] = window:title()
    window_state["app"] = window:application():name()
    local fullscreen_state, frame_state = mod.getFrameState(window)
    window_state["fullscreen"] = fullscreen_state
    window_state["frame"] = frame_state
    --mod.issueVerbose("get window " .. window_id, mod.mode)
    return window_state, window_id
end

function mod.saveEnvironmentState()
    local save_new_env = true
    local env_name = mod.detectEnvironment(save_new_env)
    if not env_name then
        error("Undefined environment name!")
    end
    local env_state = {}

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
                local window_state, window_id = mod.getWindowState(window)
                window_state["screen"] = tonumber(screen_id)
                window_state["space"] = space

                if window_state["title"] == "" then
                    print("App:", window_state["app"])
                    print("Window ID:", window_id)
                    mod.issueVerbose(
                        (
                            "ignored (no title): " ..
                            "\tapp (" .. window_state["app"] .. ")" ..
                            "\twindow id (" .. window_id .. ")"
                        ),
                        mod.mode
                    )
                else
                    mod.issueVerbose(
                        hs.inspect(window_state),
                        mod.mode
                    )
                    env_state[window_id] = window_state
                end
            end
        end
        hs.spaces.gotoSpace(initial_space)
    end
    mod.data_wins[env_name] = env_state
    mod.data_wins = mod.processDataInFile("write","windows")
    mod.notifyUser("save")
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
    --mod.issueVerbose("set window " .. window_id, mod.mode)
end

function mod.applyEnvironmentState()
    local save_new_env = false
    local env_name = mod.detectEnvironment(save_new_env)
    if not env_name then
        error("Undefined environment name!")
    end

    --mod.buildEnvironment(env_name)

    --TODO: build environment to ensure every space id exists or has an
    --      equivalent, by creating a mapping between old and new space
    --      ids and save it in the environment JSON
    --TODO: open apps if they are not open
    --TODO: close apps if they are not saved?

    mod.data_wins = mod.processDataInFile("read","windows")
    if not mod.data_wins[env_name] then
        error("State for environment has never been saved!")
    end
    local env_state = mod.data_wins[env_name]

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
                local window_state, window_id = mod.getWindowState(window)
                window_state = env_state[window_id]
                mod.issueVerbose(
                    hs.inspect(window_state),
                    mod.mode
                )
                
                mod.setWindowState(window,window_state)
            end
        end
        hs.spaces.gotoSpace(initial_space)
    end
    mod.notifyUser("apply")
end

return mod