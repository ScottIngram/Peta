local ADDON_NAME, ADDON_VARS = ...

local CONSTANTS = {
    ALL_MSGS = 0,
    INFO = 4,
    WARN = 6,
    ERROR = 8,
    NONE = 10,
}

ADDON_VARS.DEBUG = CONSTANTS

local Debug = {
    isSilent = false,
}

local function newInstance(isSilent)
    local newInstance = {}
    setmetatable(newInstance, { __index = Debug })
    newInstance.isSilent = isSilent
    return newInstance
end

function CONSTANTS.newDebugger(showOnlyMessagesAtOrAbove)
    local debugger = {}
    debugger.error = newInstance(showOnlyMessagesAtOrAbove > CONSTANTS.ERROR)
    debugger.warn = newInstance(showOnlyMessagesAtOrAbove > CONSTANTS.WARN)
    debugger.info = newInstance(showOnlyMessagesAtOrAbove > CONSTANTS.INFO)
    return debugger
end

function Debug:dump(...)
    if self.isSilent then return end
    DevTools_Dump(...)
end

function Debug:print(...)
    if self.isSilent then return end
    print(...)
end

local function getName(obj, default)
    if(obj and obj.GetName) then
        return obj:GetName() or default or "UNKNOWN"
    end
    return default or "UNNAMED"
end

function Debug:messengerForEvent(eventName, msg)
    return function(obj)
        if self.isSilent then return end
        print(getName(obj,eventName).." said ".. msg .."! ")
    end
end

function Debug:makeDummyStubForCallback(obj, eventName, msg)
    self:print("makeDummyStubForCallback for " .. eventName)
    obj:RegisterEvent(eventName);
    obj:SetScript("OnEvent", self:messengerForEvent(eventName,msg))

end

function Debug:run(callback)
    if self.isSilent then return end
    callback()
end

function Debug:dumpKeys(obj)
    if self.isSilent then return end
    pcall(function(object)
        for k, v in pairs(object or {}) do
            self.print(self.asString(k).." <-> ".. self.asString(v))
        end
    end, obj)
end

function Debug:asString(v)
    return ((type(v) == "string") and v) or tostring(v) or "NiL"
end
