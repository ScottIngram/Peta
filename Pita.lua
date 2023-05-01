local ADDON_NAME, Pita = ...

-- I want the ability to give variables and functions SIMPLE names
-- without fear of colliding with the names inside other addons.
-- Thus, I leverage Lua's "set function env" (setfenv) to
-- restrict all of my declarations to the Pita "namespace"

local G = _G -- but first, grab the global namespace or else we lose it
setfenv(1, Pita)

local debug = Pita.DEBUG.newDebugger(Pita.DEBUG.ALL_MSGS)

-------------------------------------------------------------------------------
-- Local Functions
-------------------------------------------------------------------------------

function foo()

end

-------------------------------------------------------------------------------
-- Global Functions
-------------------------------------------------------------------------------

function Pita_Foo()

end

-------------------------------------------------------------------------------
-- Pita Methods
-------------------------------------------------------------------------------

function Pita:Foo()
    debug.info:print("Foo()")
    self:Bar()
end

function Pita:Bar()
    debug.info:print("Bar()")
    debug.warn:print(Pita.L10N.TOOLTIP)
    --local fullpath = debug.getinfo(1,"S").source:sub(2)

end

-------------------------------------------------------------------------------
-- Event handlers
-------------------------------------------------------------------------------

function Pita:PLAYER_LOGIN()
    debug.info:print("PLAYER_LOGIN")
end

function Pita:PLAYER_ENTERING_WORLD(isInitialLogin, isReloadingUi)
    debug.info:print("PLAYER_ENTERING_WORLD", isInitialLogin, isReloadingUi)
end

function Pita:BAG_NEW_ITEMS_UPDATED()
    debug.info:print("BAG_NEW_ITEMS_UPDATED")
    self:Foo()
end

function Pita:BAG_UPDATE(bagId)
    debug.info:print("BAG_UPDATE", bagId)
end

-------------------------------------------------------------------------------
-- Event Handler / Listener Registration
-------------------------------------------------------------------------------

function Pita:CreateEventListener()
    local handlers = {
        PLAYER_LOGIN          = self.PLAYER_LOGIN,
        PLAYER_ENTERING_WORLD = self.PLAYER_ENTERING_WORLD,
        BAG_NEW_ITEMS_UPDATED = self.BAG_NEW_ITEMS_UPDATED,
        BAG_UPDATE            = self.BAG_UPDATE,
    }

    function activate()
        debug.info:print(ADDON_NAME.." EventListener:Activate() ...")

        function dispatcher(frame, eventName, ...)
            handlers[eventName](self, ...)
        end

        local eventListenerFrame = G.CreateFrame("Frame")
        eventListenerFrame:SetScript("OnEvent", dispatcher)

        for eventName, _ in G.pairs(handlers) do
            debug.info:print("EventListener:activate() - registering ".. eventName)
            eventListenerFrame:RegisterEvent(eventName)
        end
    end

    activate()
end

Pita:CreateEventListener()
