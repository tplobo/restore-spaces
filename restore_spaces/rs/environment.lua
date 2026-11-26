-- `environment.lua`

-- Initialize environment functions
return function(rs,hs)

    rs.retrieveEnvironmentEntities = function(entity, screen, verbose)
        local function validateScreen(arg)
            if not arg or tostring(arg):match("hs.screen") then return true
            else error("Argument is not a 'screen': " .. hs.inspect(arg))
            end
        end
    
        -- Windows whose app or screen vanished (_e.g._ the app quit) are dropped.
        -- `rs.window_selection` (internal) decides which screen a window belongs
        -- to: "frame" (where its frame is; verified up to macOS 14) or "owner"
        -- (the screen of its desktop; experimental, differs for windows whose
        -- frame is outside their desktop's screen).
        local function isWindowOnScreen(window)
            local window_screen = window:application() and window:screen()
            if not window_screen then return false end
            if screen == nil then return true end
            if rs.window_selection == "owner" then
                window_screen = rs.getWindowScreen(window)
            end
            return window_screen == screen
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
            all_entities = rs.validateSpaces(all_entities)
        elseif entity == "windows" then
            local all_windows = hs.window.visibleWindows()
            all_entities = hs.fnutils.filter(all_windows, isWindowOnScreen)
        else
            error("Unknown entity: " .. entity)
        end
    
        if rs.getVerbosity(verbose) >= 3 then
            local shown = all_entities
            if entity == "windows" then
                -- Window objects print their titles: list their IDs instead
                shown = {}
                for _, window in ipairs(all_entities or {}) do
                    table.insert(shown, window:id())
                end
            end
            rs.issueVerbose("all " .. entity .. ": " .. hs.inspect(shown), verbose)
        end
    
        if not all_entities then
            all_entities = {}
        end
        return all_entities
    end
    
    rs.askEnvironmentName = function(envs_list, verbose)
        verbose = verbose or rs.verbose
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
        rs.issueVerbose(text, verbose)
        return answer
    end

    rs.processEnvironment = function(save_flag)

        local function listKeys(table)
            local keys_list = ""
            for key, _ in pairs(table) do
                keys_list = keys_list .. "'" .. key .. "'\n"
            end
            return keys_list
        end

        rs.data_envs = rs.processDataInFile("read","environments")
        
        local all_screens = rs.getSortedScreens()
        
        local env = rs.detectEnvironment(all_screens)
        local env_exists, env_name = rs.validateEnvironment(env)

        if env_exists then
            -- On `apply`, check that windows were saved for the environment
            -- before `rebuildEnvironment` creates or removes any desktop
            if not save_flag then
                local saved_wins = rs.processDataInFile("read","windows") or {}
                if not saved_wins[env_name] then
                    error("No windows were saved for environment '" .. env_name
                        .. "': run `save` first (no desktop was changed)")
                end
            end
            rs.rebuildEnvironment(env, env_name, all_screens, save_flag)
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
            rs.issueVerbose(text, rs.verbose)
            text = "Environment name undefined!"
            if save_flag then
                local envs_list = listKeys(rs.data_envs)
                env_name = rs.askEnvironmentName(envs_list, rs.verbose)
                if not env_name then
                    error(text)
                else
                    rs.data_envs[env_name] = env
                end
                rs.data_envs = rs.processDataInFile("write","environments")
            else
                rs.notifyUser("environment")
                error(text)
            end
        end

        return env_name, env
    end

    rs.detectEnvironment = function(all_screens)
        local env = {}
        for screen_i, screen in ipairs(all_screens) do
            local screen_name = screen:name()
            local screen_spaces = rs.retrieveEnvironmentEntities("spaces", screen)
            local screen_index = rs.paddedToStr(screen_i)
            local space_map = {}
            for space_i, space in ipairs(screen_spaces) do
                local space_index = rs.paddedToStr(space_i)
                --TODO: add docstrings that explain that the first value is
                --      the original space id during `save`, and the second
                --      is the current space id during `apply`
                space_map[space_index] = {space, space}
            end
            env[screen_index] = {
                ["monitor"] = screen_name,
                ["space_map"] = space_map,
                -- Kind of every space in order ("desktop"/"fullscreen"): `save`
                -- records it, `apply` keeps the saved one (see `rebuildEnvironment`)
                ["layout"] = rs.getLayoutKinds(screen)
            }
        end
        return env
    end

    -- Whether the monitors of `env` (in order) are those of a saved environment
    -- Returns: whether it exists, its name
    rs.validateEnvironment = function(env)
        local function listMonitors(entries)
            local keys, names = {}, {}
            for key in pairs(entries) do table.insert(keys, key) end
            table.sort(keys)
            for _, key in ipairs(keys) do
                table.insert(names, entries[key]["monitor"])
            end
            return hs.inspect(names)
        end
        local current = listMonitors(env)
        for saved_name, saved_env in pairs(rs.data_envs) do
            if listMonitors(saved_env) == current then
                return true, saved_name
            end
        end
        return false, nil
    end

    rs.rebuildEnvironment = function(env, env_name, all_screens, save_flag)
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

        -- Keep the recorded over/underscan of each monitor (`rs.recordScan` updates
        -- it) and, on `apply`, the saved order of the spaces (`save` records it)
        local previous = rs.data_envs[env_name] or {}
        for screen_index, entry in pairs(env) do
            local old = previous[screen_index]
            if old and old["monitor"] == entry["monitor"] then
                entry["scan"] = old["scan"]
                if not save_flag then
                    entry["layout"] = old["layout"]
                end
            end
        end

        if save_flag then
            rs.issueVerbose("Overwriting space order and map...", rs.verbose)
        else
            rs.issueVerbose("Re-building environment...", rs.verbose)
            local saved_env = rs.data_envs[env_name]
            for screen_i, screen in ipairs(all_screens) do
                local screen_index = rs.paddedToStr(screen_i)
                local screen_spaces = rs.retrieveEnvironmentEntities("spaces", screen)
                local saved_map = saved_env[screen_index]["space_map"]
                local n_screen, n_saved = lengthTables(screen_spaces, saved_map)
                local close_MissionControl = false

                -- Create the missing desktops (through another screen if this one
                -- is at the space limit) and remove the extra ones; if macOS
                -- refuses, the process goes on without them (see the warnings)
                local add_err, remove_err
                for _ = n_screen + 1, n_saved do
                    local status, err = rs.addSpaceToScreen(screen, close_MissionControl)
                    if not status and rs.borrow_spaces then
                        rs.issueVerbose("cannot add a desktop to '" .. screen:name() .. "' ("
                            .. tostring(err) .. "); trying through another screen", rs.verbose)
                        status, err = rs.createSpaceByMoving(screen)
                    end
                    if not status then
                        add_err = err
                        break
                    end
                end
                for position = n_screen, n_saved + 1, -1 do
                    local status, err = rs.removeSpace(screen_spaces[position], close_MissionControl)
                    if not status then
                        remove_err = err
                        break
                    end
                end
                rs.closeMissionControl()
                screen_spaces = rs.retrieveEnvironmentEntities("spaces", screen)
                if #screen_spaces < n_saved then
                    rs.warn(string.format(
                        "could not create %d of the %d saved desktops of '%s' (%s); "
                        .. "the windows of the missing ones go to its %s desktop",
                        n_saved - #screen_spaces, n_saved, screen:name(),
                        tostring(add_err), rs.fallback_space))
                elseif #screen_spaces > n_saved then
                    rs.warn(string.format(
                        "could not remove %d extra desktops of '%s' (%s)",
                        #screen_spaces - n_saved, screen:name(), tostring(remove_err)))
                end

                -- Map saved desktops to current ones by position; saved desktops
                -- that could not be created share the fallback desktop
                local screen_map = {}
                for space_i, space in ipairs(screen_spaces) do
                    local space_index = rs.paddedToStr(space_i)
                    local saved_pair = saved_map[space_index]
                    if saved_pair then
                        screen_map[space_index] = {saved_pair[1], space}
                    end
                end
                local fallback = screen_spaces[rs.fallback_space == "first" and 1 or #screen_spaces]
                for saved_index, saved_pair in pairs(saved_map) do
                    if fallback and not screen_map[saved_index] then
                        screen_map[saved_index] = {saved_pair[1], fallback}
                    end
                end
                env[screen_index]["space_map"] = screen_map
                rs.issueVerbose("env: " .. hs.inspect(env), rs.verbose)
            end
        end
        rs.data_envs[env_name] = env
        rs.processDataInFile("write","environments")
    end

    -- Name of the saved environment that matches the monitors connected now
    -- (nil if there is none), without changing anything
    rs.getEnvironmentName = function()
        rs.data_envs = rs.processDataInFile("read","environments")
        local exists, env_name = rs.validateEnvironment(rs.detectEnvironment(rs.getSortedScreens()))
        return exists and env_name or nil
    end

end