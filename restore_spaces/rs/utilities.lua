-- Initialize utilities
return function(rs,hs)

    rs.isNaN = function(value)
        return value ~= value
    end

    rs.paddedToStr = function(int)
        return string.format("%03d", int)
    end

    rs.delayExecution = function(delay)
        hs.timer.usleep(1e6 * delay)
    end

    rs.contains = function(tbl, val)
        for _, value in pairs(tbl) do
            if value == val then
                return true
            end
        end
        return false
    end

    rs.list2table = function(list_var)
        local table_var = {}
        for _, element in ipairs(list_var) do
            table_var[element] = {}
        end
        return table_var
    end

    rs.list2dict = function(list_var)
        local dict_var = {}
        for i, element in ipairs(list_var) do
            dict_var[tostring(i)] = element
        end
        return dict_var
    end

    rs.table2list = function(table_var)
        local list_var = {}
        for _, value in pairs(table_var) do
            table.insert(list_var, value)
        end
        return list_var
    end

    rs.rename_key = function(dict_var,old_key,new_key)
        dict_var[new_key] = dict_var[old_key]
        dict_var[old_key] = nil
        return dict_var
    end

    rs.packagePath = function(filepath)
        local rel_path = "/.hammerspoon/hs/restore_spaces/" .. filepath
        local abs_path = os.getenv('HOME') .. rel_path
        return abs_path
    end

    rs.recursiveKeysAreStrings = function(arg, verbose)
        verbose = verbose or rs.verbose
        local check = true
        if type(arg) == "table" then
            for key, value in pairs(arg) do
                if type(key) ~= "string" then
                    check = check and false
                end
                if type(value) == "table" then
                    local result = rs.recursiveKeysAreStrings(value, verbose)
                    check = check and result
                end
            end
        else
            rs.issueVerbose("Non-table argument: " .. arg, verbose)
            check = check and false
        end
        return check
    end

end