-- `utilities.lua`

-- Initialize utilities
return function(rs,hs)

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

    rs.list2dict = function(list_var)
        local dict_var = {}
        for i, element in ipairs(list_var) do
            dict_var[tostring(i)] = element
        end
        return dict_var
    end

    rs.validateTable = function(value)
        if type(value) ~= "table" then
            local msg = "Converted non-table argument: " .. tostring(value)
            rs.issueVerbose(msg, rs.verbose)
            return { value }
        end
        return value
    end

    rs.packagePath = function(filepath)
        local rel_path = "/.hammerspoon/hs/restore_spaces/" .. filepath
        local abs_path = os.getenv('HOME') .. rel_path
        return abs_path
    end

    -- Console banner of a given level, from 1 (strongest) to 5 (weakest). Levels
    -- 1-3 frame the title with a line above and below; levels 4-5 only
    -- underline it. Levels 1-2 are centered, and level 1 is in capitals.
    rs.banner = function(level, title)
        local styles = {
            {char = "#", framed = true, centered = true, upper = true},
            {char = "=", framed = true, centered = true},
            {char = "-", framed = true},
            {char = "‾"},
            {char = "."}
        }
        local style = styles[level]
        if not style then
            error("Unknown banner level: " .. tostring(level))
        end
        title = style.upper and title:upper() or title
        local rule = string.rep(style.char, rs.banner_width)
        local margin = 0
        if style.centered then
            margin = math.max(0, (rs.banner_width - (utf8.len(title) or #title)) // 2)
        end
        local lines = {string.rep(" ", margin) .. title, rule}
        if style.framed then
            table.insert(lines, 1, rule)
        end
        return table.concat(lines, "\n")
    end

    -- Print a banner (see `rs.banner`) starting on a new line, because the
    -- console puts a timestamp before the first line of each print
    rs.printBanner = function(level, title)
        print("\n" .. rs.banner(level, title))
    end

    -- Text followed by the label of the development build in brackets, if there is
    -- one (`rs.build`): "restore_spaces [build 8]"; the text alone otherwise
    rs.tagBuild = function(text)
        if not rs.build then return text end
        return text .. " [" .. tostring(rs.build) .. "]"
    end

    -- Run `action()` between a start and an end banner (the end one reports the
    -- elapsed time and whether it failed). `summarize(success, err, seconds)`
    -- is called after the end banner (its own errors are printed, not raised);
    -- an error of `action` is raised again last.
    rs.runWithBanner = function(title, action, summarize)
        local start = hs.timer.secondsSinceEpoch()
        rs.printBanner(2, title)
        local success, err = xpcall(action, debug.traceback)
        local seconds = hs.timer.secondsSinceEpoch() - start
        rs.printBanner(2, string.format("%s: %s (%.1f s)", title,
            success and "done" or "FAILED", seconds))
        if summarize then
            local shown, summary_err = pcall(summarize, success, err, seconds)
            if not shown then
                print("(summary) could not show the summary window: " .. tostring(summary_err))
            end
        end
        if not success then
            error(err, 0)
        end
    end

    -- Number of entries of a table (also for tables with string keys, where `#` is 0)
    rs.countEntries = function(tbl)
        local count = 0
        for _ in pairs(tbl or {}) do count = count + 1 end
        return count
    end

    -- Quote a string for the shell (single quotes)
    rs.shellQuote = function(text)
        return "'" .. (tostring(text):gsub("'", "'\\''")) .. "'"
    end

    -- Poll `predicate` until it returns a truthy value or the timeout expires
    -- (`rs.mc_timeout` by default); returns its last value
    rs.waitUntil = function(predicate, timeout)
        timeout = timeout or rs.mc_timeout
        local interval = tonumber(rs.mc_pause)
        if not interval or interval <= 0 then interval = 0.05 end
        local waited = 0
        local value = predicate()
        while not value and waited < timeout do
            local delay = math.min(interval, timeout - waited)
            rs.delayExecution(delay)
            waited = waited + delay
            value = predicate()
        end
        return value
    end

end