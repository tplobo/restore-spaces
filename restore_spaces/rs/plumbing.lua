-- `plumbing.lua`

-- Initialize plumbing
return function(rs,hs)

    -- Verbosity of a `verbose` setting (default `rs.verbose`): false/nil and 0
    -- are silent, true is level 3, and numbers 1 (key steps) to 5 (everything)
    -- are the levels of detail of the console output
    rs.getVerbosity = function(verbose)
        if verbose == nil then verbose = rs.verbose end
        if verbose == true then return 3 end
        return tonumber(verbose) or 0
    end

    -- Print a message if the verbosity reaches `level` (default 3); the prefix is
    -- the calling function, or file:line for anonymous functions
    rs.issueVerbose = function(text, verbose, level)
        if rs.getVerbosity(verbose) >= (level or 3) then
            local info = debug.getinfo(2, "nSl")
            local where = info and info.name
            if not where and info then
                where = (info.short_src:match("[^/]*$") or "?") .. ":" .. tostring(info.currentline)
            end
            print("(" .. (where or "unknown") .. ") " .. text)
        end
    end

    rs.notifyUser = function(case,verbose)
        local text = nil
        if case == "save" then
            text = "Windows saved!"
        elseif case == "apply" then
            text = "Windows applied!"
        elseif case == "fallback" then
            text = "Some windows were moved to fallback locations!"
        elseif case == "failed" then
            text = string.format("%d window(s) could not be restored!", rs.failed_count)
        elseif case == "environment" then
            text = "Environment undefined!"
        else
            error("Unknown case: " .. case)
        end
        rs.issueVerbose(text, verbose)
        local message = {
            title="Restore Spaces",
            informativeText=text
        }
        hs.notify.new(message):send()
    end

    rs.processDataInFile = function(case, data)
        -- A missing file is normal on the first run: nothing was saved yet
        local function readFile(abs_path)
            local file = io.open(abs_path, 'r')
            if not file then
                rs.issueVerbose("no saved file yet: " .. abs_path, rs.verbose, 2)
                return {}
            end
            local json_contents = file:read('*all')
            file:close()
            local success, decoded = pcall(hs.json.decode, json_contents)
            if not (success and decoded) then
                rs.warn("could not read " .. abs_path .. "; a copy of the previous version is in "
                    .. abs_path .. ".bak", "files")
                return {}
            end
            return decoded
        end
        -- The previous version of the file is kept as `<file>.bak`
        local function writeFile(abs_path, contents)
            if not contents then
                print("No contents to write!")
                return
            end
            local previous = io.open(abs_path, 'r')
            if previous then
                local backup = io.open(abs_path .. ".bak", 'w')
                if backup then
                    backup:write(previous:read('*all'))
                    backup:close()
                end
                previous:close()
            end
            local file = io.open(abs_path, 'w')
            if not file then
                error("Failed to write " .. abs_path .. " (does its folder exist?)")
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
            contents = rs.data_wins
        elseif data == "environments" then
            contents = rs.data_envs
        else
            error("Unknown data: " .. data)
        end
        local filepath = "tmp/data_" .. data.. ".json"
        local abs_path = rs.packagePath(filepath)

        if case == "write" then
            writeFile(abs_path, contents)
        elseif case == "read" then
            contents = readFile(abs_path)
        else
            error("Unknown case: " .. case)
        end
        return contents
    end

    -- IDs of the spaces listed in `com.apple.spaces.plist`, without the hidden
    -- "dashboard" space (nil and an error message if the file cannot be read)
    rs.getPlistSpaces = function()
        local plist = hs.plist.read("~/Library/Preferences/com.apple.spaces.plist")
        local config = plist and plist["SpacesDisplayConfiguration"]
        local monitors = config and config["Management Data"] and config["Management Data"]["Monitors"]
        if not monitors then
            return nil, "Failed to read the spaces in com.apple.spaces.plist"
        end
        local plist_spaces = {}
        for _, monitor in ipairs(monitors) do
            for _, info in ipairs(monitor["Spaces"] or {}) do
                if info["uuid"] ~= "dashboard" then
                    table.insert(plist_spaces, info["id64"])
                end
            end
        end
        return plist_spaces
    end

    -- Keep only desktops (spaces of type "user"), in the given order. This drops
    -- the hidden "dashboard" space and the full-screen/split-view spaces. With
    -- `rs.use_plist_check`, desktops must also be listed in the spaces plist
    -- (which lags behind right after spaces are added or removed); if macOS
    -- reports no space types at all, the plist is used instead.
    rs.validateSpaces = function(all_spaces, verbose)
        verbose = verbose or rs.verbose
        all_spaces = all_spaces or {}
        local plist_spaces
        if rs.use_plist_check then
            local err
            plist_spaces, err = rs.getPlistSpaces()
            if not plist_spaces then error(err) end
        end

        local validated_spaces, ignored, untyped = {}, {}, 0
        for _, space in ipairs(all_spaces) do
            local space_type = hs.spaces.spaceType(space)
            if space_type == "user" and (not plist_spaces or rs.contains(plist_spaces, space)) then
                table.insert(validated_spaces, space)
            else
                table.insert(ignored, space .. ":" .. tostring(space_type))
            end
            untyped = untyped + (space_type == nil and 1 or 0)
        end
        if #all_spaces > 0 and untyped == #all_spaces then
            plist_spaces = rs.getPlistSpaces()
            for _, space in ipairs(plist_spaces and all_spaces or {}) do
                if rs.contains(plist_spaces, space) then
                    table.insert(validated_spaces, space)
                end
            end
        end
        if #ignored > 0 then
            rs.issueVerbose("ignored spaces (id:type): " .. table.concat(ignored, ", "), verbose)
        end
        return validated_spaces
    end

    -- Statistics of the running action, shown in its summary window
    rs.resetStats = function()
        rs.stats = {
            environment = nil,
            monitors = {}, order = {},
            warnings = {}, noted = {},
            times = {}, stack = {},
            tabs = {},      -- tab lists read during the action, by window ID
            reads = {},     -- how each tab list was obtained (cache, direct, accessibility, cycling)
            missing = {},   -- saved windows that `apply` did not find
            placement = nil, -- result of the check at the end of `apply`
            notes = {}, note_order = {},    -- extra sections of the summary
            realign = {checked = 0, out_of_view = 0, moved = 0, failed = 0, entries = {}}
        }
    end

    -- Add `amount` (default 1) to a counter ("spaces" or "windows") of a screen
    rs.countStat = function(screen, key, amount)
        local name = screen:name()
        if not rs.stats.monitors[name] then
            rs.stats.monitors[name] = {spaces = 0, windows = 0}
            table.insert(rs.stats.order, name)
        end
        local entry = rs.stats.monitors[name]
        entry[key] = entry[key] + (amount or 1)
    end

    -- Add a line to a section of the summary window
    rs.addNote = function(section, text)
        if not rs.stats.notes[section] then
            rs.stats.notes[section] = {}
            table.insert(rs.stats.note_order, section)
        end
        table.insert(rs.stats.notes[section], text)
    end

    -- Print a warning (whatever the verbosity) and keep it for the summary,
    -- grouped by `kind` (default "other")
    rs.warn = function(text, kind)
        kind = kind or "other"
        table.insert(rs.stats.warnings, {kind = kind, text = text})
        print("WARNING (" .. kind .. "): " .. text)
    end

    -- Run `action(...)` and add its time to the `category` of the statistics,
    -- excluding the time of the measured calls nested inside it
    rs.measure = function(category, action, ...)
        local stack = rs.stats.stack
        local start = hs.timer.secondsSinceEpoch()
        local parent = stack[#stack]
        if parent then
            parent.elapsed = parent.elapsed + start - parent.since
        end
        local frame = {since = start, elapsed = 0}
        table.insert(stack, frame)
        local results = table.pack(pcall(action, ...))
        local finish = hs.timer.secondsSinceEpoch()
        table.remove(stack)
        frame.elapsed = frame.elapsed + finish - frame.since
        if parent then parent.since = finish end
        rs.stats.times[category] = (rs.stats.times[category] or 0) + frame.elapsed
        if not results[1] then error(results[2], 0) end
        return table.unpack(results, 2, results.n)
    end

    -- Stand-in for a window or tab title in the console (titles are private data):
    -- the title itself with `rs.log_titles`, else a short fingerprint that still
    -- tells whether two lines are about the same title
    rs.redact = function(text)
        text = tostring(text)
        if rs.log_titles then return text end
        local hash = 5381
        for i = 1, #text do
            hash = (hash * 33 + text:byte(i)) % 65536
        end
        return string.format("<title %04x, %d chars>", hash, utf8.len(text) or #text)
    end

    -- hs.inspect of a window state, with its titles redacted for the console
    rs.describeState = function(state)
        if rs.log_titles then return hs.inspect(state) end
        local copy = {}
        for key, value in pairs(state) do copy[key] = value end
        if copy.title then copy.title = rs.redact(copy.title) end
        if copy.tabs then copy.tabs = rs.countEntries(copy.tabs) .. " tabs" end
        return hs.inspect(copy)
    end

    -- Record how the tabs of a window were obtained (the summary shows the titles;
    -- the console only with `rs.verbose` >= 1, and redacted unless `rs.log_titles`)
    rs.recordTabRead = function(app, title, method, count, seconds, note)
        table.insert(rs.stats.reads, {app = app, title = title, method = method,
            tabs = count or 0, seconds = seconds or 0, note = note})
        rs.issueVerbose(string.format("tabs of '%s' / '%s': %s, %d tabs, %.1f s%s", app, rs.redact(title),
            method, count or 0, seconds or 0, note and (" (" .. note .. ")") or ""), rs.verbose, 1)
    end

    -- Release check: numbers of a version such as "v0.4.1"
    local function parseVersion(text)
        local major, minor, patch = tostring(text):match("(%d+)%.(%d+)%.?(%d*)")
        if not major then return nil end
        return {tonumber(major), tonumber(minor), tonumber(patch) or 0}
    end

    local function isNewer(latest, current)
        local a, b = parseVersion(latest), parseVersion(current)
        if not (a and b) then return false end
        for i = 1, 3 do
            if a[i] ~= b[i] then return a[i] > b[i] end
        end
        return false
    end

    -- Ask GitHub (in the background, at most every 12 hours) for the latest release
    -- of `rs.repository`; only if `rs.check_updates` is on. The answer is added to
    -- the summary of the actions that end after it arrived.
    rs.checkForUpdate = function()
        local info = rs.update_info
        if not rs.check_updates or info.checking then return end
        if info.checked_at and os.time() - info.checked_at < 12 * 3600 then return end
        info.checking = true
        local url = "https://api.github.com/repos/" .. rs.repository .. "/releases/latest"
        local headers = {["Accept"] = "application/vnd.github+json", ["User-Agent"] = "restore_spaces"}
        hs.http.asyncGet(url, headers, function(status, body)
            info.checking = false
            local success, data = pcall(hs.json.decode, body or "")
            if status == 200 and success and type(data) == "table" and data.tag_name then
                info.checked_at = os.time()
                info.latest, info.url, info.error = data.tag_name, data.html_url, nil
            else
                info.checked_at = os.time() - 11 * 3600 -- try again in an hour
                info.latest, info.error = nil, "HTTP status " .. tostring(status)
            end
        end)
    end

    local function noteUpdate()
        local info = rs.update_info
        if not rs.check_updates then return end
        if info.latest and isNewer(info.latest, rs.version) then
            rs.addNote("Update", string.format("Version %s is available (installed: %s): %s",
                info.latest, rs.version, info.url or ("https://github.com/" .. rs.repository .. "/releases/latest")))
        elseif info.error then
            rs.issueVerbose("the update check failed: " .. info.error, rs.verbose, 1)
        elseif info.checking then
            rs.issueVerbose("the update check has not finished yet", rs.verbose, 2)
        end
    end

    local function escape(text)
        return (tostring(text):gsub("[&<>\"]", {
            ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;", ['"'] = "&quot;"
        }))
    end

    local function shorten(text, length)
        text = tostring(text)
        if (utf8.len(text) or #text) <= length then return text end
        local cut = utf8.offset(text, length + 1)
        return text:sub(1, (cut or length + 1) - 1) .. "…"
    end

    -- Summary of an action as HTML, with collapsible sections for the details
    local function buildSummaryHtml(title, success, err, seconds)
        local stats, body = rs.stats, {}
        local function add(text) table.insert(body, text) end
        local function list(items)
            local rows = {}
            for _, item in ipairs(items) do
                table.insert(rows, "<li>" .. escape(item) .. "</li>")
            end
            return "<ul>" .. table.concat(rows) .. "</ul>"
        end
        local function section(summary, content, open)
            add(string.format("<details%s><summary>%s</summary>%s</details>",
                open and " open" or "", escape(summary), content))
        end
        -- A collapsible list; without items it is a plain line
        local function itemsSection(summary, items, open)
            if #items == 0 then
                add('<p class="line">' .. escape(summary) .. "</p>")
            else
                section(summary, list(items), open)
            end
        end

        add('<p class="brand">' .. escape(rs.tagBuild("restore_spaces")) .. '</p>')
        add(string.format('<h1>%s <span class="%s">%s</span></h1>', escape(title),
            success and "ok" or "bad", success and "done" or "FAILED"))
        add(string.format('<p class="meta">%s%.1f s</p>',
            stats.environment and (escape(stats.environment) .. " · ") or "", seconds))

        if not success then
            local reason = (tostring(err):match("^[^\n]*"):gsub("^.-:%d+: ", ""))
            add('<p class="bad">' .. escape(reason) .. "</p>")
            section("Details of the failure", "<pre>" .. escape(err) .. "</pre>")
        end

        if #stats.order > 0 then
            local rows = {"<tr><th>Monitor</th><th>Desktops</th><th>Windows</th></tr>"}
            for _, name in ipairs(stats.order) do
                local entry = stats.monitors[name]
                table.insert(rows, string.format("<tr><td>%s</td><td>%d</td><td>%d</td></tr>",
                    escape(name), entry.spaces, entry.windows))
            end
            add("<table>" .. table.concat(rows) .. "</table>")
        end

        local groups, order = {}, {}
        for _, warning in ipairs(stats.warnings) do
            if not groups[warning.kind] then
                groups[warning.kind] = {}
                table.insert(order, warning.kind)
            end
            table.insert(groups[warning.kind], warning.text)
        end
        for _, kind in ipairs(order) do
            itemsSection(string.format("Warnings: %s (%d)", kind, #groups[kind]), groups[kind], true)
        end

        local check = stats.placement
        if check then
            local items = {}
            for _, entry in ipairs(check.wrong) do
                table.insert(items, string.format("%s - %s: on %s, expected %s", entry.app,
                    shorten(entry.title, 50), entry.actual, entry.expected))
            end
            for _, entry in ipairs(check.frames) do
                table.insert(items, string.format("%s - %s: frame %s, expected %s", entry.app,
                    shorten(entry.title, 50), entry.actual, entry.expected))
            end
            while #items > 40 do table.remove(items) end
            itemsSection(string.format("Placement check: %d of %d recognized windows are on their desktop, %d have another frame",
                check.on_space, check.checked, #check.frames), items, #check.wrong > 0)
        end

        for _, name in ipairs(stats.note_order) do
            itemsSection(name, stats.notes[name], true)
        end

        if #stats.missing > 0 then
            local items = {}
            for i, entry in ipairs(stats.missing) do
                if i > 40 then
                    table.insert(items, "...")
                    break
                end
                table.insert(items, entry.app .. " - " .. shorten(entry.title, 60))
            end
            itemsSection(string.format("Saved windows not found: %d (not open, or not recognized)", #stats.missing), items)
        end

        if #stats.reads > 0 then
            local items, total = {}, 0
            for i, entry in ipairs(stats.reads) do
                total = total + entry.seconds
                if i <= 40 then
                    table.insert(items, string.format("%s - %s: %s, %d tabs, %.1f s%s", entry.app,
                        shorten(entry.title, 50), entry.method, entry.tabs, entry.seconds,
                        entry.note and (" (" .. entry.note .. ")") or ""))
                end
            end
            if #stats.reads > 40 then table.insert(items, "...") end
            itemsSection(string.format("Tab reading: %d windows, %.1f s", #stats.reads, total), items)
        end

        local realign = stats.realign
        if realign.checked > 0 then
            local items = {}
            for i, entry in ipairs(realign.entries) do
                if i > 30 then
                    table.insert(items, "...")
                    break
                end
                local outcome = entry.moved and string.format(" -> %.0f%%", entry.after * 100)
                    or (entry.failed and " (move failed)" or "")
                table.insert(items, string.format("%s - %s (%s): %.0f%% visible%s",
                    entry.app, shorten(entry.title, 50), entry.screen, entry.visible * 100, outcome))
            end
            itemsSection(string.format("Windows out of view: %d of %d checked, %d moved",
                realign.out_of_view, realign.checked, realign.moved), items)
        end

        local names, total = {}, 0
        for name, elapsed in pairs(stats.times) do
            table.insert(names, name)
            total = total + elapsed
        end
        table.sort(names, function(a, b) return stats.times[a] > stats.times[b] end)
        local items = {}
        for _, name in ipairs(names) do
            table.insert(items, string.format("%s: %.1f s", name, stats.times[name]))
        end
        table.insert(items, string.format("other: %.1f s", math.max(0, seconds - total)))
        itemsSection("Time breakdown", items)

        -- One solid background everywhere; the border is drawn by a fixed layer, so
        -- it does not scroll with the content
        local css = [[
html,body{margin:0;height:100%}
body{box-sizing:border-box;padding:18px 20px 16px;overflow:auto;
 font:13px -apple-system,BlinkMacSystemFont,sans-serif;color:#1d1d1f;background:#f5f5f7}
html::after{content:"";position:fixed;top:0;left:0;right:0;bottom:0;border:1px solid #c9c9ce;pointer-events:none}
.brand{font-size:11px;letter-spacing:.08em;text-transform:uppercase;color:#8a8a90;margin:0 0 8px}
h1{font-size:17px;margin:0 0 2px}.ok{color:#1f8a3a}.bad{color:#c0392b}
.meta{color:#8a8a90;margin:0 0 14px}
.line{margin:8px 0;font-weight:600}
table{border-collapse:collapse;width:100%;margin-bottom:10px}
td,th{text-align:left;padding:4px 8px;border-bottom:1px solid #d6d6db}
details{margin:8px 0}summary{cursor:pointer;font-weight:600}
ul{margin:4px 0 4px 18px;padding:0}li{margin:2px 0;word-break:break-word}
pre{white-space:pre-wrap;font-size:11px}
button{margin-top:14px;padding:5px 22px;font-size:13px}
@media(prefers-color-scheme:dark){
 body{color:#e8e8ea;background:#2a2a2d}
 html::after{border-color:#4a4a50}
 td,th{border-color:#46464b}}
]]
        local script = [[
function done(){webkit.messageHandlers.restore_spaces.postMessage('close')}
document.addEventListener('keydown',function(e){if(e.key==='Escape'||e.key==='Enter'){done()}})
]]
        return "<html><head><meta charset='utf-8'><style>" .. css .. "</style></head><body>"
            .. table.concat(body) .. '<button onclick="done()">OK</button>'
            .. "<script>" .. script .. "</script></body></html>"
    end

    -- Show the summary window of an action (unless `rs.show_summary` is false):
    -- a web view without title bar, closed with its OK button (or Enter/Esc),
    -- or a plain alert if the web view fails
    rs.showSummary = function(title, success, err, seconds)
        if rs.show_summary == false then return end
        local shown, view_err = pcall(function()
            if rs.summary_view then rs.summary_view:delete() end
            rs.summary_controller = hs.webview.usercontent.new("restore_spaces")
            rs.summary_controller:setCallback(function()
                if rs.summary_view then
                    rs.summary_view:delete()
                    rs.summary_view = nil
                end
            end)
            local area = hs.screen.mainScreen():frame()
            local width, height = 600, math.min(720, area.h - 100)
            rs.summary_view = hs.webview.new(
                {x = area.x + (area.w - width) / 2, y = area.y + 50, w = width, h = height},
                {}, rs.summary_controller)
                :windowTitle("restore_spaces")
                :windowStyle(hs.webview.windowMasks.borderless)
                :shadow(true)
                :allowTextEntry(true)
                :deleteOnClose(true)
                :html(buildSummaryHtml(title, success, err, seconds))
                :bringToFront(true)
                :show()
            hs.focus()
        end)
        if not shown then
            print("(summary) web view failed: " .. tostring(view_err))
            hs.focus()
            hs.dialog.blockAlert(
                "restore_spaces: " .. title .. (success and ": done" or ": FAILED"),
                string.format("Environment: %s\nTime: %.1f s\nWarnings: %d",
                    tostring(rs.stats.environment), seconds, #rs.stats.warnings),
                "OK"
            )
        end
    end

    -- Run a public action (`save`/`apply`/`realign`...) between banners (which
    -- show the build label, if any), collecting its statistics and warnings and
    -- showing the summary window at the end
    rs.runAction = function(title, action)
        rs.resetStats()
        rs.checkForUpdate()
        rs.runWithBanner(rs.tagBuild(title), action, function(success, err, seconds)
            local reasons = {}
            for reason in pairs(rs.stats.skipped or {}) do table.insert(reasons, reason) end
            table.sort(reasons)
            for _, reason in ipairs(reasons) do
                rs.addNote("Windows not checked for visibility", string.format("%d: %s",
                    rs.stats.skipped[reason], reason))
            end
            noteUpdate()
            rs.showSummary(title, success, err, seconds)
        end)
    end

    rs.getFrameState = function(window)
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

    rs.setFrameState = function(window, frame_state, fullscreen_state)
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

            -- Log the apps that refuse the frame (minimum sizes, constraints)
            local after = window:frame()
            for _, key in ipairs({"x", "y", "w", "h"}) do
                if math.abs(after[key] - frame[key]) > 4 then
                    local app = window:application()
                    rs.warn(string.format("window %d of '%s': frame not set (%s is %.0f, wanted %.0f)",
                        window:id(), app and app:name() or "?", key, after[key], frame[key]), "frames")
                    break
                end
            end
        end
    end

    -- Windows below this fraction of visible area are reported as out of view
    local OUT_OF_VIEW = 0.5

    -- Visibility of a window along one axis: fraction inside the area, gap to
    -- the area, side of the area that cuts it (1: start side, -1: end side)
    -- and the largest fraction its size allows
    local function axisVisibility(start, size, area_start, area_size)
        size = math.max(size, 1)
        local area_end = area_start + area_size
        return {
            size = size,
            fraction = math.max(0, math.min(start + size, area_end) - math.max(start, area_start)) / size,
            gap = math.max(0, area_start - (start + size), start - area_end),
            side = (start < area_start) and 1 or ((start + size > area_end) and -1 or 0),
            max = math.min(1, area_size / size)
        }
    end

    -- Fraction of the area of `frame` inside `area` and the largest fraction
    -- its size allows (a window larger than the area can never be fully inside)
    rs.getVisibility = function(frame, area)
        local ax = axisVisibility(frame.x, frame.w, area.x, area.w)
        local ay = axisVisibility(frame.y, frame.h, area.y, area.h)
        return ax.fraction * ay.fraction, ax.max * ay.max, ax, ay
    end

    -- Top-left corner (nil if the window is fine) that makes at least `fraction`
    -- of the window's area visible with the smallest move, never resizing it.
    -- The fractions visible along x and y are searched for the cheapest
    -- combination; the top is kept below the menu bar so that the title bar
    -- stays reachable.
    rs.getRealignedPosition = function(frame, area, fraction)
        local visible, capacity, ax, ay = rs.getVisibility(frame, area)
        local target = math.min(fraction, capacity)
        if visible >= target - 1e-9 then return nil end
        local function shift(axis, wanted)
            if wanted <= axis.fraction then return 0 end
            return axis.gap + (wanted - axis.fraction) * axis.size
        end
        local best, best_a, best_b = math.huge
        local steps = 400
        for i = 0, steps do
            local a = ax.fraction + (ax.max - ax.fraction) * i / steps
            if a > 0 then
                local b = math.max(ay.fraction, target / a)
                if b <= ay.max + 1e-9 then
                    local cost = shift(ax, a) ^ 2 + shift(ay, b) ^ 2
                    if cost < best then best, best_a, best_b = cost, a, b end
                end
            end
        end
        if not best_a then return nil end
        local x = frame.x + ax.side * shift(ax, best_a)
        local y = math.max(frame.y + ay.side * shift(ay, best_b), area.y)
        return math.floor(x + 0.5), math.floor(y + 0.5)
    end

    local function realign(window, space)
        if not hs.spaces.screensHaveSeparateSpaces() then
            return nil, "'Displays have separate Spaces' is off"
        end
        local app = window:application()
        if not (app and window:isStandard() and not window:isMinimized()
                and not window:isFullScreen() and window:title() ~= "") then
            return nil, "not a regular window"
        end
        local spaces = hs.spaces.windowSpaces(window) or {}
        -- A window moved off all monitors can report no desktop (seen on macOS
        -- 27.2): then the desktop being visited decides, if it lists the window
        if #spaces == 0 and space and rs.contains(hs.spaces.windowsForSpace(space) or {}, window:id()) then
            spaces = {space}
        end
        if #spaces ~= 1 or hs.spaces.spaceType(spaces[1]) ~= "user" or (space and spaces[1] ~= space) then
            return nil, "not on a single desktop (spaces: "
                .. hs.inspect(spaces, {newline = "", indent = ""}) .. ")"
        end
        local screen = rs.getScreenByUUID(hs.spaces.spaceDisplay(spaces[1]))
        if not screen then
            return nil, "unknown screen"
        end

        local limit = rs.min_window_visibility
        local area, frame, stats = screen:frame(), window:frame(), rs.stats.realign
        local visible, capacity = rs.getVisibility(frame, area)
        local required = limit > 0 and math.min(limit, capacity) or OUT_OF_VIEW
        stats.checked = stats.checked + 1
        local lost = visible < required - 1e-9
        local entry
        if lost then
            entry = {app = app:name(), title = window:title(), screen = screen:name(), visible = visible}
            stats.out_of_view = stats.out_of_view + 1
            table.insert(stats.entries, entry)
        end
        if limit <= 0 then
            return lost and "counted" or "ok"
        end
        local x, y = rs.getRealignedPosition(frame, area, limit)
        if not x then return "ok" end

        -- A window that straddles two monitors belongs (to macOS) to the one that
        -- holds most of it: ask for more visibility until this monitor clearly has
        -- most of the window, or the window would change desktop when moved
        local want = limit
        for _ = 1, 4 do
            local placed = {x = x, y = y, w = frame.w, h = frame.h}
            local own, rival = (rs.getVisibility(placed, area)), 0
            for _, other in ipairs(hs.screen.allScreens()) do
                if other ~= screen then
                    rival = math.max(rival, (rs.getVisibility(placed, other:fullFrame())))
                end
            end
            if own >= rival + 0.1 - 1e-9 or want >= capacity then break end
            want = math.min(1, rival + 0.1)
            local better_x, better_y = rs.getRealignedPosition(frame, area, want)
            if not better_x then break end
            x, y = better_x, better_y
        end

        window:setTopLeft({x = x, y = y})
        local achieved = rs.getVisibility(window:frame(), area)
        if achieved < required - 0.02 then
            stats.failed = stats.failed + 1
            if entry then entry.failed = true end
            rs.warn(string.format("window %d of '%s' could not be moved into view (%.0f%% visible, %.0f%% wanted)",
                window:id(), app:name(), achieved * 100, required * 100), "realign")
            return nil, "the move did not stick"
        end
        stats.moved = stats.moved + 1
        if entry then
            entry.moved, entry.after = true, achieved
        end
        local owner = rs.getWindowScreen(window)
        if owner ~= screen then
            rs.warn(string.format("window %d of '%s' changed monitor ('%s' -> '%s') when it was moved into view",
                window:id(), app:name(), screen:name(), owner:name()), "realign")
        end
        return "moved"
    end

    -- Keep a window in view: at least `rs.min_window_visibility` of its area
    -- inside the usable area of the screen that owns its desktop, by moving it
    -- (with 0 it only counts the windows that are out of view). Only regular
    -- (standard, not minimized, not full-screen) windows of a single desktop
    -- are considered; `space`, if given, must be that desktop. Windows that are
    -- not checked are counted by reason (shown in the summary).
    -- Returns: "ok" | "moved" | "counted" | nil, reason
    rs.realignWindow = function(window, space)
        local status, reason = rs.measure("realigning windows", realign, window, space)
        if not status and reason then
            local key = (tostring(reason):match("^[^(]+") or tostring(reason)):gsub("%s+$", "")
            rs.stats.skipped = rs.stats.skipped or {}
            rs.stats.skipped[key] = (rs.stats.skipped[key] or 0) + 1
        end
        return status, reason
    end

end