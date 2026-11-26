-- `legacy.lua`

-- Compatibility with the saved states and settings of earlier versions.
-- Everything here goes away in 1.0.
return function(rs,hs)

    rs.legacy = {}

    -- Window state as saved by earlier versions: only desktops were saved, so a
    -- state without `space_kind` is a desktop window
    rs.legacy.normalizeState = function(state)
        state["space_kind"] = state["space_kind"] or "desktop"
        return state
    end

    -- Recognition rules by app: `rs.window_recognition` plus the old list
    -- `rs.multitab_apps` (plain entries are "tabs", `App = {terms}` are terms),
    -- which is only read if a user still sets it
    rs.legacy.getRecognition = function()
        local rules = {}
        for app, rule in pairs(rs.window_recognition or {}) do
            rules[app] = rule
        end
        for key, value in pairs(rs.multitab_apps or {}) do
            if type(key) == "number" then
                rules[value] = rules[value] or "tabs"
            else
                rules[key] = rules[key] or value
            end
        end
        return rules
    end

end