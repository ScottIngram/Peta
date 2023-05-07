local ADDON_NAME, ADDON_VARS = ...

local ERR_MSG = "DEBUGGER SYNTAX ERROR: invoke via:func() not via.func()"
local CONSTANTS = {
    ALL_MSGS = 0,
    TRACE = 2,
    INFO = 4,
    WARN = 6,
    ERROR = 8,
    NONE = 10,
}
ADDON_VARS.DEBUG = CONSTANTS
local Debug = { }

local function isDebuggerObj(zelf)
    return zelf and zelf.DEBUGGER
end

local function newInstance(isSilent)
    local newInstance = {
        isSilent = isSilent,
        DEBUGGER = true
    }
    setmetatable(newInstance, { __index = Debug })
    return newInstance
end

function CONSTANTS.newDebugger(showOnlyMessagesAtOrAbove)
    local debugger = { }
    debugger.error = newInstance(showOnlyMessagesAtOrAbove > CONSTANTS.ERROR)
    debugger.warn = newInstance(showOnlyMessagesAtOrAbove > CONSTANTS.WARN)
    debugger.info = newInstance(showOnlyMessagesAtOrAbove > CONSTANTS.INFO)
    debugger.trace = newInstance(showOnlyMessagesAtOrAbove > CONSTANTS.TRACE)
    return debugger
end

function Debug:dump(...)
    assert(isDebuggerObj(self), ERR_MSG)
    if self.isSilent then return end
    DevTools_Dump(...)
end

function Debug:print(...)
    assert(isDebuggerObj(self), ERR_MSG)
    if self.isSilent then return end
    print(...)
end

local function getName(obj, default)
    assert(isDebuggerObj(self), ERR_MSG)
    if(obj and obj.GetName) then
        return obj:GetName() or default or "UNKNOWN"
    end
    return default or "UNNAMED"
end

function Debug:messengerForEvent(eventName, msg)
    assert(isDebuggerObj(self), ERR_MSG)
    return function(obj)
        if self.isSilent then return end
        print(getName(obj,eventName).." said ".. msg .."! ")
    end
end

function Debug:makeDummyStubForCallback(obj, eventName, msg)
    assert(isDebuggerObj(self), ERR_MSG)
    self:print("makeDummyStubForCallback for " .. eventName)
    obj:RegisterEvent(eventName);
    obj:SetScript("OnEvent", self:messengerForEvent(eventName,msg))

end

function Debug:run(callback)
    assert(isDebuggerObj(self), ERR_MSG)
    if self.isSilent then return end
    callback()
end

function Debug:dumpKeys(object)
    assert(isDebuggerObj(self), ERR_MSG)
    if self.isSilent then return end
   --function(object)
        local keys = {}
        for k, v in pairs(object or {}) do
            table.insert(keys,self:asString(k))
        end
        table.sort(keys)
        for i, k in ipairs(keys) do
            self:print(k.." <-> ".. self:asString(object[k]))
        end
    --end
end

function Debug:asString(v)
    assert(isDebuggerObj(self), ERR_MSG)
    return ((type(v) == "string") and v) or tostring(v) or "NiL"
end
