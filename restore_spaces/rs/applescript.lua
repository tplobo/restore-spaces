-- Initialize applescript functions
return function(rs,hs)

    rs.getPlistInfo = function(info)
        local plist_path = rs.packagePath(rs.config_path .. ".plist")
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

    rs.processPlistConfig = function(case)
        local plist_path = rs.getPlistInfo("path")

        if case == 'create' then
            local json_path = rs.packagePath(rs.config_path .. ".json")
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

            if not plist_path then
                error("PLIST path cannot be 'nil'")
            end
            local success, err = os.remove(plist_path)
            if not success then
                error("Failed to delete PLIST file: " .. err)
            end

        else
            error("Unknown routine to 'processPlistConfig' in case: " .. case)
        end

    end

    rs.buildTabList = function(output,report_delimiter)
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


    rs.runApplescript = function(app)
        local script_path = "scp/getVisibleTabs.applescript"
        local abs_path = rs.packagePath(script_path)
        local osascript = "/usr/bin/osascript"
        local plist_path = rs.getPlistInfo("path")

        local args = app .. " " .. plist_path
        local command = osascript .. " " .. abs_path .. " " .. args
        local output, status, exitType, rc = hs.execute(command,true)
        
        local msg =  "Status: "..tostring(status)..", exit: "..tostring(exitType)
        msg = msg ..", rc: "..tostring(rc)
        rs.issueVerbose(msg,rs.verbose)
        rs.issueVerbose(hs.inspect(output),rs.verbose)

        local report_delimiter = rs.getPlistInfo("reportDelimiter")
        local tab_list = rs.buildTabList(output,report_delimiter)
        return tab_list
    end

    rs.getAppTabsInSpace = function(app,id2title)
        local app_tabs = id2title
        local tab_list = rs.runApplescript(app)
        for _, window_tabs in ipairs(tab_list) do
            local first_tab = window_tabs[1]
            for id, title in pairs(id2title) do
                if first_tab == title then
                    app_tabs[id] = rs.list2dict(window_tabs)
                end
            end
        end
        return app_tabs
    end

    rs.compareTabs = function(window_tabs,stored_tabs)
        if (stored_tabs == nil) or next(stored_tabs) == nil then
            return false
        end

    local  all_matches = {}
        for _, tab_title in pairs(window_tabs) do
            if rs.contains(stored_tabs,tab_title) then
                table.insert(all_matches, true)
            end
        end
        local window_ratio = #all_matches / #window_tabs
        local stored_ratio = #all_matches / #stored_tabs

        local tab_limit
        if #window_tabs <= rs.multitab_comparison["critical_tab_count"] then
            tab_limit = rs.multitab_comparison["small_similarity_threshold"]
        else
            tab_limit = rs.multitab_comparison["large_similarity_threshold"]
        end

        local window_check = window_ratio >= tab_limit
        if rs.isNaN(window_ratio) then
            window_check = false
        end
        local stored_check = stored_ratio >= tab_limit
        if rs.isNaN(stored_ratio) then
            stored_check = false
        end
        local match = window_check and stored_check
        return match
    end

end