--local hs = {}
--hs.chooser = require 'hs.chooser'
hs.application = require 'hs.application'
hs.fnutils = require 'hs.fnutils'
hs.inspect = require 'hs.inspect'
hs.hotkey = require 'hs.hotkey'
hs.notify = require 'hs.notify'
hs.window = require 'hs.window'
hs.screen = require 'hs.screen'
hs.dialog = require 'hs.dialog'
hs.timer = require 'hs.timer'
hs.plist = require 'hs.plist'
hs.json = require 'hs.json'

-- Use default `spaces` module:
hs.spaces = require 'hs.spaces'
-- Use development `spaces` module (https://github.com/asmagill/hs._asm.spaces)
--hs.spaces = require 'hs.spaces_v04.spaces'

-- Plumbing module (inner functions)
local mod = {}

-- Global variables (defaults)
mod.data_wins = {} -- collected info for each window
mod.data_envs = {} -- collected info for each environment
mod.config_path = "scp/scp_config"
mod.multitab_apps = {"Google Chrome", "Firefox", "Safari"}
mod.spaces_fixed_after_macOS14_5 = true

function mod.isNaN(value)
    return value ~= value
end

function mod.paddedToStr(int)
    return string.format("%03d", int)
end

function mod.delayExecution(delay)
    hs.timer.usleep(1e6 * delay)
end

function mod.contains(tbl, val)
    for _, value in pairs(tbl) do
        if value == val then
            return true
        end
    end
    return false
end

function mod.list2table(list_var)
    local table_var = {}
    for _, element in ipairs(list_var) do
        table_var[element] = {}
    end
    return table_var
end

function mod.list2dict(list_var)
    local dict_var = {}
    for i, element in ipairs(list_var) do
        dict_var[tostring(i)] = element
    end
    return dict_var
end

function mod.table2list(table_var)
    local list_var = {}
    for _, value in pairs(table_var) do
        table.insert(list_var, value)
    end
    return list_var
end

function mod.rename_key(dict_var,old_key,new_key)
    dict_var[new_key] = dict_var[old_key]
    dict_var[old_key] = nil
    return dict_var
end

function mod.packagePath(filepath)
    local rel_path = "/.hammerspoon/hs/restore_spaces/" .. filepath
    local abs_path = os.getenv('HOME') .. rel_path
    return abs_path
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
        local info = debug.getinfo(2, "n")
        local calling_function = info and info.name or "unknown"
        print("(" .. calling_function .. ") " .. text)
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

function mod.getPlistInfo(info)
    local plist_path = mod.packagePath(mod.config_path .. ".plist")
    if info == "path" then
        return plist_path
    else
        local key = info
        local plistTable = hs.plist.read(plist_path)
        if not plistTable then
            error("Failed to read plist file at: " .. plist_path)
        end
        if plistTable[key] ~= nil then
            local value = plistTable[key]
            return value
        else
            -- Key does not exist, handle accordingly
            return nil, "Key '" .. key .. "' does not exist in the plist file."
        end
    end
end

function mod.processPlistConfig(case)
    local plist_path = mod.getPlistInfo("path")

    if case == 'create' then
        local json_path = mod.packagePath(mod.config_path .. ".json")
        local json_file = io.open(json_path, "r")
        if not json_file then
            error("Unable to locate: " .. json_path)
        end
        local json_contents = json_file:read("*a")
        json_file:close()
        
        local json_table, _, err = hs.json.decode(json_contents)
        if not json_table then
            error("Failed to parse JSON: " .. err)
        end

        local success = hs.plist.write(plist_path, json_table, true)
        if not success then
            error("Failed to create PLIST file")
        end

    elseif case == 'destroy' then

        local success, err = os.remove(plist_path)
        if not success then
            error("Failed to delete PLIST file: " .. err)
        end

    else
        error("Unknown routine to 'processPlistConfig' in case: " .. case)
    end

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
        contents = mod.data_wins
    elseif data == "environments" then
        contents = mod.data_envs
    else
        error("Unknown data: " .. data)
    end
    local filepath = "tmp/data_" .. data.. ".json"
    local abs_path = mod.packagePath(filepath)

    if case == "write" then
        writeFile(abs_path, contents)
    elseif case == "read" then
        contents = readFile(abs_path)
    else
        error("Unknown case: " .. case)
    end
    return contents
end

function mod.validateSpaces(all_spaces, verbose)
    verbose = verbose or mod.verbose
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
            mod.issueVerbose(text, verbose)
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

function mod.retrieveEnvironmentEntities(entity, screen, verbose)
    local function validateScreen(arg)
        if not arg or tostring(arg):match("hs.screen") then return true
        else error("Argument is not a 'screen': " .. hs.inspect(arg))
        end
    end

    local function isWindowOnScreen(window)
        return screen == nil or window:screen() == screen
    end

    validateScreen(screen)

    local all_entities
    if entity == "screens" then
        if screen then
            all_entities = {screen}
        else
            all_entities = hs.screen.allScreens()
        end
    elseif entity == "spaces" then
        if screen then
            all_entities = hs.spaces.spacesForScreen(screen:id())
        else
            all_entities = {}
            local all_screens = hs.screen.allScreens()
            for _, scr in ipairs(all_screens) do
                local screen_spaces = hs.spaces.spacesForScreen(scr:id())
                if not screen_spaces then 
                    screen_spaces = {} 
                else
                    for _, space in ipairs(screen_spaces) do
                        table.insert(all_entities, space)
                    end
                end
            end
        end
        all_entities = mod.validateSpaces(all_entities)
    elseif entity == "windows" then
        local all_windows = hs.window.visibleWindows()
        all_entities = hs.fnutils.filter(all_windows, isWindowOnScreen)
    else
        error("Unknown entity: " .. entity)
    end

    local text = "all " .. entity .. ": " .. hs.inspect(all_entities)
    mod.issueVerbose(text, verbose)

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

function mod.buildTabList(output,report_delimiter)
    local applescript_delimiter = ", "
    local window_delimiter = report_delimiter .. report_delimiter
    local start_pattern = window_delimiter .. applescript_delimiter
    local end_pattern = applescript_delimiter .. window_delimiter
    local list_delimiter = report_delimiter

    local newline_pattern = "\n+$"
    local processed_string = string.gsub(output, newline_pattern, end_pattern)

    local tab_lists = {}
    local window_pattern = start_pattern .. "(.-)" .. end_pattern
    local tab_pattern = "([^" .. list_delimiter .. "]+)"
    for window_string in processed_string:gmatch(window_pattern) do
        local tab_titles = {}
        for tab_string in window_string:gmatch(tab_pattern) do
            table.insert(tab_titles, tab_string)
        end
        if #tab_titles > 0 then
            table.insert(tab_lists, tab_titles)
        end
    end

    return tab_lists
end

function mod.getWindowState(window)
    --TODO: Change "WindowState" to "AppState"
    local window_state = {}
    local window_id = tostring(window:id())

    --TODO: check if app window is hidden

    local fullscreen_state, frame_state = mod.getFrameState(window)
    window_state["fullscreen"] = fullscreen_state
    window_state["frame"] = frame_state
    window_state["title"] = window:title()
    window_state["app"] = window:application():name()
    if mod.contains(mod.multitab_apps, window_state["app"]) then
        window_state["multitab"] = true
        window_state["tabs"] = {}
    else
        window_state["multitab"] = false
        window_state["tabs"] = nil
    end

    --mod.issueVerbose("get window " .. window_id, mod.verbose)
    return window_state, window_id
end

function mod.setWindowState(window,window_state,space_map)
    print("SETWINDOWSTATE START: window "..tostring(window))
    print("window state "..hs.inspect(window_state))
    print("space map "..hs.inspect(space_map))
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
    print("space "..tostring(space))
    if space_map then
        for _, pair in pairs(space_map) do
            local old_space = pair[1]
            local new_space = pair[2]
            if old_space == space then
                target_space = new_space
                print("old space "..tostring(old_space))
                print("new space "..tostring(new_space))
                break
            end
        end
    else
        target_space = space
    end
    target_space = tonumber(target_space)

    if mod.spaces_fixed_after_macOS14_5 then
        hs.spaces.moveWindowToSpace(window, target_space)
    else
        -- solution by `cunha`
        -- (see: https://github.com/Hammerspoon/hammerspoon/pull/3638#issuecomment-2252826567)
        local target_screen, _ = hs.spaces.spaceDisplay(target_space)
        hs.spaces.moveWindowToSpace(window, target_space)
        window:focus()
        mod.delayExecution(0.4)
        window:moveToScreen(target_screen)
        window:focus()
    end
    --print("window id "..tostring(window:id()))
    --print("target space "..tostring(target_space))

    mod.setFrameState(window, frame_state, fullscreen_state)
    --mod.issueVerbose("set window " .. window_id, mod.verbose)
    print("SETWINDOWSTATE END: window: " .. type(window))
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

function mod.processEnvironment(save_flag)
    local function sortByFrame(a, b)
        return a:frame().x < b:frame().x
    end
    local function listKeys(table)
        local keys_list = ""
        for key, _ in pairs(table) do
            keys_list = keys_list .. "'" .. key .. "'\n"
        end
        return keys_list
    end

    mod.data_envs = mod.processDataInFile("read","environments")
    
    local all_screens = mod.retrieveEnvironmentEntities("screens")
    table.sort(all_screens, sortByFrame)
    
    local env = mod.detectEnvironment(all_screens)
    local env_exists, env_name = mod.validateEnvironment(env)

    if env_exists then
        mod.rebuildEnvironment(env, env_name, all_screens, save_flag)
        --[[
        -- FOR TESTING ONLY:
        local envs_list = listKeys(mod.data_envs)
        env_name = mod.askEnvironmentName(envs_list, mod.verbose)
        if not env_name then
            error("Undefined environment name: !")
        else
            mod.data_envs[env_name] = env
        end
        --]]
    else
        local text = "Environment does not exist."
        mod.issueVerbose(text, mod.verbose)
        text = "Environment name undefined!"
        if save_flag then
            local envs_list = listKeys(mod.data_envs)
            env_name = mod.askEnvironmentName(envs_list, mod.verbose)
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

function mod.detectEnvironment(all_screens)
    local env = {}
    for screen_i, screen in ipairs(all_screens) do
        local screen_name = screen:name()
        local screen_spaces = mod.retrieveEnvironmentEntities("spaces", screen)
        local screen_index = mod.paddedToStr(screen_i)
        local space_map = {}
        for space_i, space in ipairs(screen_spaces) do
            local space_index = mod.paddedToStr(space_i)
            --TODO: add docstrings that explain that the first value is
            --      the original space id during `save`, and the second
            --      is the current space id during `apply`
            space_map[space_index] = {space, space}
        end
        env[screen_index] = {
            ["monitor"] = screen_name,
            ["space_map"] = space_map
        }
    end
    return env
end

function mod.validateEnvironment(env)
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
    return env_exists, env_name
end

function mod.rebuildEnvironment(env, env_name, all_screens, save_flag)
    local function lengthTables(...)
        local args = {...}
        local all_counts = {}
        for i, arg in ipairs(args) do
            local count = 0
            for _ in pairs(arg) do count = count + 1 end
            all_counts[i] = count
        end
        return table.unpack(all_counts)
    end

    if save_flag then
        mod.issueVerbose("Overwriting space order and map...", mod.verbose)
    else
        mod.issueVerbose("Re-building environment...", mod.verbose)
        local saved_env = mod.data_envs[env_name]
        for screen_i, screen in ipairs(all_screens) do
            local screen_index = mod.paddedToStr(screen_i)
            local screen_spaces = mod.retrieveEnvironmentEntities("spaces", screen)
            local saved_map = saved_env[screen_index]["space_map"]
            local n_screen, n_saved = lengthTables(screen_spaces, saved_map)
            local close_MissionControl = false
            while n_screen < n_saved do
                hs.spaces.addSpaceToScreen(screen_i, close_MissionControl)
                screen_spaces = mod.retrieveEnvironmentEntities("spaces", screen)
                n_screen, n_saved = lengthTables(screen_spaces, saved_map)
            end
            while n_screen > n_saved do
                local last_space_id = screen_spaces[n_screen]
                hs.spaces.removeSpace(last_space_id, close_MissionControl)
                screen_spaces = mod.retrieveEnvironmentEntities("spaces", screen)
                n_screen, n_saved = lengthTables(screen_spaces, saved_map)
            end
            local screen_map = {}
            for space_i, space in ipairs(screen_spaces) do
                local space_index = mod.paddedToStr(space_i)
                local original_space = saved_map[space_index][1]
                screen_map[space_index] = {original_space, space}
            end
            env[screen_index]["space_map"] = screen_map
            mod.issueVerbose("env: " .. hs.inspect(env), mod.verbose)
        end
    end
    mod.data_envs[env_name] = env
    mod.processDataInFile("write","environments")
end

return mod