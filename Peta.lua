local ADDON_NAME, Peta = ...

---@type Debug -- IntelliJ-EmmyLua annotation
local Debug = Peta.Debug:newDebugger(Peta.Debug.WARN)

-------------------------------------------------------------------------------
-- Peta Data
-------------------------------------------------------------------------------

Peta.NAMESPACE = {}
Peta.hookedBagSlots = {}
Peta.EventHandlers = {}

-------------------------------------------------------------------------------
-- Global Functions
-------------------------------------------------------------------------------

function Peta_Foo()
    -- no global functions yet
end

-------------------------------------------------------------------------------
-- Namespace Manipulation
--
-- I want the ability to give variables and functions SIMPLE names
-- without fear of colliding with the names inside other addons.
-- Thus, I leverage Lua's "set function env" (setfenv) to
-- restrict all of my declarations to my own private "namespace"
-- Now, I can create "Local" functions without needing the local keyword
-------------------------------------------------------------------------------

local _G = _G -- but first, grab the global namespace or else we lose it
setmetatable(Peta.NAMESPACE, { __index = _G }) -- inherit all member of the Global namespace
setfenv(1, Peta.NAMESPACE)

-------------------------------------------------------------------------------
-- Constants
-------------------------------------------------------------------------------

local INCLUDE_BANK = true -- TODO: make this a config option?
local MAX_INDEX_FOR_CARRIED_BAGS = NUM_BAG_FRAMES -- Bliz blobal
local MAX_INDEX_FOR_CARRIED_AND_BANK_BAGS = NUM_CONTAINER_FRAMES -- Bliz global

---@class CAGEY -- IntelliJ-EmmyLua annotation
local CAGEY = {
    CAN_CAGE = 1,
    HAS_NONE = 2,
    UNCAGEABLE = 3,
}

-------------------------------------------------------------------------------
-- Event Handlers
-------------------------------------------------------------------------------

local EventHandlers = Peta.EventHandlers -- just for shorthand

function EventHandlers:ADDON_LOADED(addonName)
    if addonName == ADDON_NAME then
        Debug.trace:print("ADDON_LOADED", addonName)
    end
end

function EventHandlers:PLAYER_LOGIN()
    Debug.trace:print("PLAYER_LOGIN")
end

function EventHandlers:PLAYER_ENTERING_WORLD(isInitialLogin, isReloadingUi)
    Debug.trace:out("",1,"PLAYER_ENTERING_WORLD", "isInitialLogin",isInitialLogin, "isReloadingUi",isReloadingUi)
    initalizeAddonStuff()
end

-------------------------------------------------------------------------------
-- Event Handler Registration
-------------------------------------------------------------------------------

function createEventListener(targetSelfAsProxy, eventHandlers)
    Debug.info:print(ADDON_NAME .. " EventListener:Activate() ...")

    local dispatcher = function(listenerFrame, eventName, ...)
        -- ignore the listenerFrame and instead
        eventHandlers[eventName](targetSelfAsProxy, ...)
    end

    local eventListenerFrame = CreateFrame("Frame")
    eventListenerFrame:SetScript("OnEvent", dispatcher)

    for eventName, _ in pairs(eventHandlers) do
        Debug.info:print("EventListener:activate() - registering " .. eventName)
        eventListenerFrame:RegisterEvent(eventName)
    end
end

-------------------------------------------------------------------------------
-- Addon Lifecycle
-------------------------------------------------------------------------------

function initalizeAddonStuff()
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, addHelpTextToToolTip)
    hookAllBags()
    if INCLUDE_BANK then
        hookBankSlots()
    end
end

-------------------------------------------------------------------------------
-- Tooltip "Local" Functions
-------------------------------------------------------------------------------

function addHelpTextToToolTip(tooltip, data)
    if tooltip == GameTooltip then
        local itemId = data.id
        local cagey = canCageThisPet(itemId)
        if CAGEY.CAN_CAGE == cagey then
            GameTooltip:AddLine(Peta.L10N.TOOLTIP, 0, 1, 0)
        elseif CAGEY.UNCAGEABLE == cagey then
            GameTooltip:AddLine(Peta.L10N.TOOLTIP_CANNOT_CAGE, 0, 1, 0)
        end
    end
end

-------------------------------------------------------------------------------
-- Pet "Local" Functions
-------------------------------------------------------------------------------

---@return CAGEY -- IntelliJ-EmmyLua annotation
function canCageThisPet(itemId)
    local result
    local _, _, _, _, _, _, _, _, canTrade, _, _, _, speciesID = C_PetJournal.GetPetInfoByItemID(itemId)
    if speciesID then
        if canTrade then
            local numCollected, _ = C_PetJournal.GetNumCollectedInfo(speciesID)
            result = (numCollected > 0) and CAGEY.CAN_CAGE or CAGEY.HAS_NONE
        else
            result = CAGEY.UNCAGEABLE
        end
    else
        result = CAGEY.HAS_NONE
    end
    return result
end

function getPetFromThisBagSlot(bagSlotFrame)
    local returnPetInfo
    local slotId, bagIndex = bagSlotFrame:GetSlotAndBagID()
    local itemId = C_Container.GetContainerItemID(bagIndex, slotId)
    --Debug.info:out(">",1, "getPetFromThisBagSlot()", "bagIndex",bagIndex, "slotId",slotId, "itemId",itemId)
    if itemId then
        local petName, _, _, _, _, _, _, _, canTrade = C_PetJournal.GetPetInfoByItemID(itemId)

        if not petName then
            -- Oh GOODY. Bliz's GetPetInfoByItemID() provides zilch from a caged pet.  Thanks Bliz!
            petName = squeezeBloodFromStone(bagIndex, slotId)
            canTrade = petName and true -- assume that any pet in a cage can be caged... but, this is Bliz API, so wtf knows.
        end

        if petName then
            Debug.info:out(">",2, "getPetFromThisBagSlot()", "petName",petName)
            local _, petGuid = C_PetJournal.FindPetIDByName(petName)
            Debug.info:out(">",2, "getPetFromThisBagSlot()", "petGuid",petGuid)
            returnPetInfo = {
                petGuid = petGuid,
                petName = petName,
                itemId = itemId,
                bagIndex = bagIndex,
                slotId = slotId,
                canTrade = canTrade,
            }
        end
    end

    return returnPetInfo
end

function squeezeBloodFromStone(bagIndex, slotId)
    Debug.trace:dump( C_Container.GetContainerItemInfo(bagIndex, slotId) )

    local d = C_Container.GetContainerItemInfo(bagIndex, slotId)
    -- Now I get to parse the hyperlink text because inexplicably,
    -- Bliz's GetContainerItemInfo() doesn't include name (the mind boggles)
    -- and adding insult to injury, C_Item.GetItemNameByID() only provides "Pet Cage" [facepalm]
    local str = d.hyperlink
    if not str then return nil end

    -- verify this is a pet cage
    local isPet = string.find(str, "battlepet") and true or false
    Debug.info:out("#",3,"squeezeBloodFromStone()", "isPet",isPet)
    if not isPet then return nil end

    -- assume the name is inside [Brackets].
    local start = string.find(str, "[[]") -- search patterns are funky!  google "regular expression"
    local stop = string.find(str, "]")
    Debug.info:out("#",3,"squeezeBloodFromStone()", "start",start, "stop",stop)
    if not (start and stop) then return nil end

    -- move the indices to strip the brackets off the [Name] so it just leaves the name
    start = start + 1
    stop = stop - 1
    if (start >= stop) then return nil end -- the Bliz API could have given me bulshit data such as an empty name []

    local name = string.sub(str, start, stop)
    Debug.trace:out("#",3,"squeezeBloodFromStone()", "name",name)
    return name
end

function hasPet(petGuid)
    Debug.trace:print("hasPet():", petGuid)
    if not petGuid then return false end
    local speciesID = C_PetJournal.GetPetInfoByPetID(petGuid)
    local numCollected, _ = C_PetJournal.GetNumCollectedInfo(speciesID)
    return numCollected > 0
end

-------------------------------------------------------------------------------
-- Bag and Inventory Click Hooking "Local" Functions
-------------------------------------------------------------------------------

function hookAllBags()
    local maxBagIndex = (INCLUDE_BANK) and MAX_INDEX_FOR_CARRIED_AND_BANK_BAGS or MAX_INDEX_FOR_CARRIED_BAGS
    for i = 0, maxBagIndex do
        local unreliableBagFrame = getUnreliableBagFrame(i)
        if not unreliableBagFrame then return end

        -- HOOK FUNC
        function showMe(bagFrame)
            local bagIndex = bagFrame:GetBagID()
            Debug.info:out("",1, "OnShow", "i", i, "IsBagOpen(i)", IsBagOpen(i), "-- bagIndex", bagIndex, "IsBagOpen(bagIndex)", IsBagOpen(bagIndex))
            if isValidBagFrame(bagFrame) then
                hookBagSlots(bagFrame)
            else
                -- Bliz API provided an uninitialized bag frame.
                -- force the bag to reopen itself
                --OpenBag(bagIndex, true) -- THIS!  This is the cause of taint!  FUCK YOU! FUCK YOU! FUCK YOU!
                --securecallfunction(OpenBag, bagIndex, force) -- not so "secure" is it?!  THIS CAUSES TAINT TOO

                Debug.info:out("=",7, "FORCING bag to reopen...", "bagIndex",bagIndex)
                OpenBag(bagIndex) -- this does NOT cause taint.  Hallelujah

                -- RECURSIVE HOOK FUNC
                local delaySeconds = 1
                C_Timer.After(delaySeconds, function()
                    showMe(bagFrame)
                end)

            end
        end

        unreliableBagFrame:HookScript("OnShow", showMe)
    end
end

-- I can't rely on Bliz's global structures to actually have the on-screen bag frame :(
-- but it seems to work if I just want to react to the OnShow event
function getUnreliableBagFrame(bagIndex)
    -- bagIndex: 0..n
    local bagId = bagIndex + 1
    local bagFrameId = "ContainerFrame" .. bagId
    local unreliableBagFrame = _G[bagFrameId]
    return unreliableBagFrame
end

-- I can't rely on Bliz's API to provide me with a valid bag with the proper contents :(
-- check #1 - verify that all slots in this bag think they are in the same bag
function isValidBagFrame(bagFrame)
    local supposedBagIndex
    for i, bagSlotFrame in bagFrame:EnumerateValidItems() do
        local slotId, reportedBagIndex = bagSlotFrame:GetSlotAndBagID()
        if (not supposedBagIndex) then supposedBagIndex = reportedBagIndex end
        if (supposedBagIndex ~= reportedBagIndex) then
            return false
        end
    end
    return true
end

function hookBagSlots(bagFrame)
    local bagIndex = bagFrame:GetBagID()
    local bagName = C_Container.GetBagName(bagIndex) or "BLANK"
    local bagSize = C_Container.GetContainerNumSlots(bagIndex) -- UNRELIABLE (?)
    local isOpen = IsBagOpen(bagIndex)
    local isHeldBag = isHeldBag(bagIndex)
    Debug.info:out("=",5, "hookBagToAddHooks()...", "bagFrame",bagFrame, "bagIndex", bagIndex, "name", bagName, "size", bagSize, "isOpen", isOpen, "isHeldBag", isHeldBag)

    for i, bagSlotFrame in bagFrame:EnumerateValidItems() do
        local slotId, bagIndex = bagSlotFrame:GetSlotAndBagID()
        Debug.info:out("=",7, "hookBagSlots()...", "i",i, "bagIndex",bagIndex, "slotId",slotId)
        hookSlot(bagSlotFrame)
    end
end

function hookBankSlots()
    for i=1, NUM_BANKGENERIC_SLOTS, 1 do
        local bankSlotFrame = BankSlotsFrame["Item"..i];
        hookSlot(bankSlotFrame)
    end
end

function hookSlot(slotFrame)
    if not Peta.hookedBagSlots[slotFrame] then
        Peta.hookedBagSlots[slotFrame] = true
        slotFrame:HookScript("PreClick", handleCagerClick)
    end
end

function handleCagerClick(bagSlotFrame, whichMouseButtonStr, isPressed)
    local petInfo = getPetFromThisBagSlot(bagSlotFrame)
    if not petInfo then
        local slotId, bagIndex = bagSlotFrame:GetSlotAndBagID()
        Debug.info:out("",1, "handleCagerClick()... abort! NO PET at", "bagIndex",bagIndex, "slotId",slotId)
        return
    end

    local isShiftRightClick = IsShiftKeyDown() and whichMouseButtonStr == "RightButton"
    if not isShiftRightClick then
        Debug.info:print("handleCagerClick()... abort!  NOT IsShiftKeyDown", IsShiftKeyDown(), "or wrong whichMouseButtonStr", whichMouseButtonStr)
        return
    end

    if not petInfo.canTrade then
        Debug.info:print("handleCagerClick()... abort! untradable pet:", petInfo.petName)
        UIErrorsFrame:AddMessage(Peta.L10N.TOOLTIP_CANNOT_CAGE, 1.0, 0.1, 0.0)
        return
    end

    if not hasPet(petInfo.petGuid) then
        Debug.info:print("handleCagerClick()... abort! NONE LEFT:", petInfo.petName)
        UIErrorsFrame:AddMessage(Peta.L10N.MSG_HAS_NONE, 1.0, 0.1, 0.0)
        return
    end

    Debug.info:print("handleCagerClick()... CAGING:", petInfo.petName)
    C_PetJournal.CagePetByID(petInfo.petGuid)
end

function isHeldBag(bagIndex)
    return bagIndex >= Enum.BagIndex.Backpack and bagIndex <= NUM_TOTAL_BAG_FRAMES;
end

-------------------------------------------------------------------------------
-- OK, Go for it!
-------------------------------------------------------------------------------

createEventListener(Peta, Peta.EventHandlers)
