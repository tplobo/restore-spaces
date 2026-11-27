-- `placement.lua`

-- Initialize placement functions (check of where the windows ended up)
return function(rs,hs)

    local function frameText(frame)
        return string.format("%.0f,%.0f %.0fx%.0f", frame.x, frame.y, frame.w, frame.h)
    end

    -- Title shortened for the summary window
    rs.shortTitle = function(text)
        text = tostring(text)
        if (utf8.len(text) or #text) <= 60 then return text end
        return text:sub(1, (utf8.offset(text, 61) or 61) - 1) .. "…"
    end

    -- Where the recognized windows are now, compared with where they should be:
    -- the space each window belongs to is asked from the system (the same answer
    -- that visiting the space would give) and its frame is read from the window.
    -- Windows saved in a full-screen space must be in one; the second window of a
    -- split view (to be set by hand) is not checked. The result goes to the
    -- summary, to the warnings (kind "placement") and, with `rs.debug_check`, to
    -- tmp/data_check.json.
    rs.checkPlacement = function(env_name, seen)
        local check = {checked = 0, on_space = 0, wrong = {}, frames = {}}
        rs.stats.placement = check
        local records = {}
        for _, info in ipairs(seen) do
            local entry = info.entry
            local record = {
                id = info.id, app = info.state["app"], title = rs.redact(info.state["title"]),
                seen_on = rs.describeSpace(info.visit_space), recognized = entry ~= nil
            }
            if entry and not entry.manual then
                local state, target = entry.state, entry.target
                local fullscreen = state["space_kind"] == "fullscreen"
                local spaces = {}
                pcall(function() spaces = hs.spaces.windowSpaces(info.window) or {} end)
                check.checked = check.checked + 1
                record.expected = fullscreen and "a full-screen space" or rs.describeSpace(target)
                record.actual = rs.describeSpace(spaces[1])
                local arrived
                if fullscreen then
                    arrived = rs.isInFullScreenSpace(info.window)
                else
                    arrived = target and rs.contains(spaces, target)
                end
                if arrived then
                    check.on_space = check.on_space + 1
                else
                    table.insert(check.wrong, {app = record.app, title = info.state["title"],
                        expected = record.expected, actual = record.actual})
                    rs.warn(string.format("window %s of '%s' is on %s, not on %s", info.id, record.app,
                        record.actual, record.expected), "placement")
                end
                if not fullscreen and state["fullscreen"] == "no" and state["frame"] then
                    local success, frame = pcall(function() return info.window:frame() end)
                    if success and frame then
                        local wanted, off = state["frame"], false
                        for _, key in ipairs({"x", "y", "w", "h"}) do
                            if math.abs(frame[key] - wanted[key]) > 12 then off = true end
                        end
                        record.frame_expected, record.frame_actual = frameText(wanted), frameText(frame)
                        if off then
                            table.insert(check.frames, {app = record.app, title = info.state["title"],
                                expected = record.frame_expected, actual = record.frame_actual})
                        end
                    end
                end
            end
            table.insert(records, record)
        end
        rs.issueVerbose(string.format("placement check: %d of %d recognized windows are on their space, %d have another frame",
            check.on_space, check.checked, #check.frames), rs.verbose, 1)

        if rs.debug_check then
            local missing = {}
            for _, entry in ipairs(rs.stats.missing) do
                table.insert(missing, {app = entry.app, title = rs.redact(entry.title)})
            end
            local path = rs.packagePath("tmp/data_check.json")
            local file = io.open(path, "w")
            if not file then error("could not write " .. path) end
            file:write(hs.json.encode({environment = env_name, build = rs.build,
                time = os.date("%Y-%m-%d %H:%M:%S"), windows = records, not_found = missing}, true))
            file:close()
            rs.addNote("Debug record", "written to " .. path)
        end
    end

end