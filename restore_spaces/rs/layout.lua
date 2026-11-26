-- `layout.lua`

-- Initialize layout functions (kind and order of the spaces of a monitor)
return function(rs,hs)

    -- Screens from left to right (then top to bottom): the order in which the
    -- environments number their monitors
    rs.getSortedScreens = function()
        local screens = hs.screen.allScreens()
        table.sort(screens, function(a, b)
            local first, second = a:frame(), b:frame()
            if first.x ~= second.x then return first.x < second.x end
            return first.y < second.y
        end)
        return screens
    end

    -- Spaces of a screen in Mission Control order, as a list of
    -- {id, kind, slot, anchor}: `kind` is "desktop" or "fullscreen" (full-screen
    -- and split-view spaces), `slot` the position among all of them, and `anchor`
    -- the number of desktops up to and including this one (for a full-screen
    -- space: the desktop it follows). The hidden "dashboard" space is left out.
    rs.getSpaceLayout = function(screen)
        local ids = {}
        for _, id in ipairs(hs.spaces.allSpaces()[screen:getUUID()] or {}) do
            if hs.spaces.spaceType(id) ~= "system" then
                table.insert(ids, id)
            end
        end
        local desktop = {}
        for _, id in ipairs(rs.validateSpaces(ids, 0)) do
            desktop[id] = true
        end

        local layout, desktops = {}, 0
        for _, id in ipairs(ids) do
            local space_type = hs.spaces.spaceType(id)
            local kind
            if desktop[id] then
                kind, desktops = "desktop", desktops + 1
            elseif space_type ~= nil and space_type ~= "user" then
                kind = "fullscreen"
            end
            if kind then
                table.insert(layout, {id = id, kind = kind, slot = #layout + 1, anchor = desktops})
            end
        end
        return layout
    end

    -- Kinds of the spaces of a screen, in order (the format saved in the
    -- environments file)
    rs.getLayoutKinds = function(screen)
        local kinds = {}
        for _, item in ipairs(rs.getSpaceLayout(screen)) do
            table.insert(kinds, item.kind)
        end
        return kinds
    end

    -- Short text of a list of kinds: "F F D D D" (D: desktop, F: full screen)
    rs.describeLayout = function(kinds)
        local letters = {}
        for _, kind in ipairs(kinds or {}) do
            table.insert(letters, kind == "desktop" and "D" or "F")
        end
        return table.concat(letters, " ")
    end

end