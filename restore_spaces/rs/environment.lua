
-- Initialize environment functions
return function(rs,hs)

    rs.retrieveEnvironmentEntities = function(entity, screen, verbose)
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
            all_entities = rs.validateSpaces(all_entities)
        elseif entity == "windows" then
            local all_windows = hs.window.visibleWindows()
            all_entities = hs.fnutils.filter(all_windows, isWindowOnScreen)
        else
            error("Unknown entity: " .. entity)
        end
    
        local text = "all " .. entity .. ": " .. hs.inspect(all_entities)
        rs.issueVerbose(text, verbose)
    
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

        rs.data_envs = rs.processDataInFile("read","environments")
        
        local all_screens = rs.retrieveEnvironmentEntities("screens")
        table.sort(all_screens, sortByFrame)
        
        local env = rs.detectEnvironment(all_screens)
        local env_exists, env_name = rs.validateEnvironment(env)

        if env_exists then
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
                ["space_map"] = space_map
            }
        end
        return env
    end

    rs.validateEnvironment = function(env)
        local env_exists = false
        local env_name
        for saved_name, saved_env in pairs(rs.data_envs) do
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
                while n_screen < n_saved do
                    hs.spaces.addSpaceToScreen(screen_i, close_MissionControl)
                    screen_spaces = rs.retrieveEnvironmentEntities("spaces", screen)
                    n_screen, n_saved = lengthTables(screen_spaces, saved_map)
                end
                while n_screen > n_saved do
                    local last_space_id = screen_spaces[n_screen]
                    hs.spaces.removeSpace(last_space_id, close_MissionControl)
                    screen_spaces = rs.retrieveEnvironmentEntities("spaces", screen)
                    n_screen, n_saved = lengthTables(screen_spaces, saved_map)
                end
                local screen_map = {}
                for space_i, space in ipairs(screen_spaces) do
                    local space_index = rs.paddedToStr(space_i)
                    local original_space = saved_map[space_index][1]
                    screen_map[space_index] = {original_space, space}
                end
                env[screen_index]["space_map"] = screen_map
                rs.issueVerbose("env: " .. hs.inspect(env), rs.verbose)
            end
        end
        rs.data_envs[env_name] = env
        rs.processDataInFile("write","environments")
    end

end