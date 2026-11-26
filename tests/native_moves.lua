-- Run from the repository root: lua tests/native_moves.lua
-- No Hammerspoon, macOS permissions, or real windows are used.
local passed = 0
local function test(name, body)
    local ok, err = pcall(body)
    if not ok then error(name .. ": " .. tostring(err), 0) end
    passed = passed + 1
    print("PASS " .. name)
end

local function fixture(major, behavior, fallback)
    local now, queue, location = 0, {}, {1}
    local counters = {native = 0, mc = 0, sleeps = 0, frame = 0, cleaned = 0}
    local screen = {id = function() return 1 end, getUUID = function() return "screen" end,
        name = function() return "test screen" end, fullFrame = function() return {x=0,y=0,w=800,h=600} end}
    local hs = {
        host = {operatingSystemVersion = function() return {major = major, minor = 0, patch = 0} end},
        timer = {}, spaces = {},
        mouse = {absolutePosition = function() return {x = 10, y = 20} end},
        application = {applicationsForBundleID = function() return {} end},
        screen = {allScreens = function() return {screen} end},
        fnutils = {},
    }
    local rs = {mc_timeout = 0.2, mc_pause = 0.05, native_move_timeout = 0.2,
        allow_mission_control_fallback = fallback == true, fallback_space = "last", fallback_count = 0, failed_count = 0}
    local window = {id = function() return 10 end, title = function() return "test" end,
        screen = function() return screen end}
    function hs.timer.doAfter(delay, callback)
        local timer = {at = now + delay, fn = callback}
        table.insert(queue, timer)
        return timer
    end
    function hs.timer.usleep() counters.sleeps = counters.sleeps + 1; error("main loop blocked") end
    function hs.spaces.windowSpaces()
        if location == false then error("window no longer exists") end
        return location
    end
    function hs.spaces.moveWindowToSpace(w, target)
        assert(w == window)
        counters.native = counters.native + 1
        if behavior == "async" then hs.timer.doAfter(0.1, function() location = {target} end)
        elseif behavior == "sync" then location = {target}
        elseif behavior == "reject" then return nil, "unsupported"
        elseif behavior == "throw" then error("native exception")
        elseif behavior == "disappear" then hs.timer.doAfter(0.05, function() location = nil end)
        elseif behavior == "invalidated" then hs.timer.doAfter(0.05, function() location = false end)
        end
        return true
    end
    function hs.spaces.spaceDisplay() return "screen" end
    function hs.spaces.allSpaces() return {screen = {1, 2}} end
    function hs.spaces.spaceType() return "user" end
    function hs.spaces.openMissionControl() counters.mc = counters.mc + 1 end
    function hs.spaces.closeMissionControl() end
    function rs.issueVerbose() end
    dofile("restore_spaces/rs/utilities.lua")(rs, hs)
    dofile("restore_spaces/rs/spaces.lua")(rs, hs)
    local function drain()
        local turns = 0
        while #queue > 0 do
            turns = turns + 1
            assert(turns < 100, "unbounded polling")
            table.sort(queue, function(a, b) return a.at < b.at end)
            local timer = table.remove(queue, 1)
            now = timer.at
            timer.fn()
        end
    end
    local function move(target)
        local result = {}
        assert(rs.runOperation("test", function()
            result.ok, result.err = rs.moveWindowToSpace(window, target or 2)
            result.completed = true
        end))
        return result
    end
    return {rs = rs, hs = hs, window = window, counters = counters, drain = drain,
        move = move, now = function() return now end}
end

test("Tahoe native move completes asynchronously without Mission Control", function()
    local f = fixture(26, "async")
    local r = f.move()
    assert(not r.completed, "must wait before reporting completion")
    f.drain()
    assert(r.ok and r.completed)
    assert(f.counters.native == 1 and f.counters.mc == 0 and f.counters.sleeps == 0)
end)
test("future macOS versions can use a working native API", function()
    local f = fixture(27, "sync")
    assert(f.move().ok and f.counters.native == 1 and f.counters.mc == 0)
end)
test("older synchronous native behavior remains supported", function()
    local f = fixture(14, "sync")
    assert(f.move().ok and f.counters.native == 1)
end)
test("true without movement times out and does not report success", function()
    local f = fixture(26, "noop")
    local r = f.move()
    f.drain()
    assert(r.completed and not r.ok and r.err:match("did not reach"))
    assert(f.now() >= 0.2 and f.now() < 0.3 and f.counters.mc == 0)
end)
test("native rejection is returned without UI when fallback is disabled", function()
    local f = fixture(26, "reject")
    local r = f.move()
    assert(not r.ok and r.err == "unsupported" and f.counters.mc == 0)
end)
test("native exception is contained", function()
    local f = fixture(26, "throw")
    local r = f.move()
    assert(not r.ok and r.err:match("native exception") and f.counters.mc == 0)
end)
test("closed window during an asynchronous move times out", function()
    local f = fixture(26, "disappear")
    local r = f.move()
    f.drain()
    assert(r.completed and not r.ok and f.counters.mc == 0)
end)
test("already on the destination does not submit a move", function()
    local f = fixture(26, "noop")
    assert(f.move(1).ok and f.counters.native == 0)
end)
test("invalidated window object does not abort the operation", function()
    local f = fixture(26, "invalidated")
    local r = f.move()
    f.drain()
    assert(r.completed and not r.ok and f.counters.mc == 0)
end)
test("zero polling interval cannot create an unbounded wait", function()
    local f = fixture(26, "noop")
    f.rs.mc_pause = 0
    local r = f.move()
    f.drain()
    assert(r.completed and not r.ok and f.now() >= 0.2)
end)
test("undefined target never submits a move", function()
    local f = fixture(26, "sync")
    local ok, err = f.rs.moveWindowToSpace(f.window, nil)
    assert(not ok and err == "undefined target space" and f.counters.native == 0)
end)
test("enabled fallback runs only after native verification expires", function()
    local f = fixture(26, "noop", true)
    local r = f.move()
    assert(f.counters.mc == 0)
    f.drain()
    assert(r.completed and not r.ok and f.counters.mc > 0 and f.counters.native == 1)
end)
test("operations cannot overlap while waiting", function()
    local f = fixture(26, "async")
    f.move()
    local ran = false
    local ok, err = f.rs.runOperation("second", function() ran = true end)
    assert(not ok and err:match("another") and not ran)
    f.drain()
    assert(f.rs.runOperation("third", function() ran = true end) and ran)
end)
test("errors release the operation and run cleanup exactly once", function()
    local f = fixture(26, "async")
    local cleaned = 0
    f.rs.runOperation("expected test error", function()
        f.rs.delayExecution(0.05)
        error("expected failure")
    end, function() cleaned = cleaned + 1 end)
    f.drain()
    assert(cleaned == 1)
    assert(f.rs.runOperation("after failure", function() end))
end)
test("frame restoration is skipped when the Space move failed", function()
    local f = fixture(26, "reject")
    dofile("restore_spaces/rs/plumbing.lua")(f.rs, f.hs)
    f.rs.setFrameState = function() f.counters.frame = f.counters.frame + 1 end
    f.rs.runOperation("window state", function()
        f.rs.setWindowState(f.window, {space = 2, screen = 1, frame = {}, fullscreen = "no"})
    end)
    assert(f.counters.frame == 0 and f.rs.failed_count == 1)
end)
test("frame restoration runs after native arrival", function()
    local f = fixture(26, "async")
    dofile("restore_spaces/rs/plumbing.lua")(f.rs, f.hs)
    f.rs.setFrameState = function() f.counters.frame = f.counters.frame + 1 end
    f.rs.runOperation("window state", function()
        f.rs.setWindowState(f.window, {space = 2, screen = 1, frame = {}, fullscreen = "no"})
    end)
    assert(f.counters.frame == 0)
    f.drain()
    assert(f.counters.frame == 1 and f.rs.failed_count == 0)
end)
test("apply cleanup is deferred until its asynchronous body finishes", function()
    local f = fixture(26, "async")
    dofile("restore_spaces/rs/porcelain.lua")(f.rs, f.hs)
    local events = {}
    f.rs.logSystemInfo = function() end
    f.rs.processPlistConfig = function(action) events[#events + 1] = action end
    f.rs.setEnvironmentState = function()
        f.rs.delayExecution(0.1)
        events[#events + 1] = "completed"
    end
    f.rs.applyEnvironmentState()
    assert(table.concat(events, ",") == "create")
    f.drain()
    assert(table.concat(events, ",") == "create,completed,destroy")
end)
print(string.format("%d tests passed", passed))
