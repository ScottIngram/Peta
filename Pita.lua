local ADDON_NAME, Pita = ...
local debug = Pita.DEBUG.newDebugger(Pita.DEBUG.INFO)
local PLAYER_LOGIN_DONE = false

-------------------------------------------------------------------------------
-- Pita Data
-------------------------------------------------------------------------------

Pita.knownPetTokenIds = {}
Pita.hasBagBeenOpened = {}
Pita.hookedBagSlots = {}

Pita.NAMESPACE = {}
Pita.EventHandlers = {}

local EventHandlers = Pita.EventHandlers -- just for shorthand

-------------------------------------------------------------------------------
-- Global Functions
-------------------------------------------------------------------------------

function Pita_Foo()
    -- no global functions yet
end

-------------------------------------------------------------------------------
-- Namespace Manipulation
-- I want the ability to give variables and functions SIMPLE names
-- without fear of colliding with the names inside other addons.
-- Thus, I leverage Lua's "set function env" (setfenv) to
-- restrict all of my declarations to my own private "namespace"
-- Now, I can create "Local" functions without needing the local keyword
-------------------------------------------------------------------------------

local _G = _G -- but first, grab the global namespace or else we lose it
setmetatable(Pita.NAMESPACE, { __index = _G }) -- inherit all member of the Global namespace
setfenv(1, Pita.NAMESPACE)

-------------------------------------------------------------------------------
-- Constants
-------------------------------------------------------------------------------

local MAX_BAG_INDEX = NUM_TOTAL_BAG_FRAMES

-------------------------------------------------------------------------------
-- Event Handlers
-------------------------------------------------------------------------------

function EventHandlers:ADDON_LOADED(addonName)
    if addonName == ADDON_NAME then
        debug.trace:print("ADDON_LOADED", addonName)
    end
end

function EventHandlers:PLAYER_LOGIN()
    debug.trace:print("PLAYER_LOGIN")
    PLAYER_LOGIN_DONE = true
    initalizeAddonStuff()
end

function EventHandlers:PLAYER_ENTERING_WORLD(isInitialLogin, isReloadingUi)
    debug.trace:print("PLAYER_ENTERING_WORLD isInitialLogin:", isInitialLogin, "| isReloadingUi:", isReloadingUi)
end

function EventHandlers:BAG_UPDATE(bagIndex)
    if not PLAYER_LOGIN_DONE or not IsBagOpen(bagIndex) then
        return
    end

    debug.trace:print("BAG_UPDATE", bagIndex, "| IsBagOpen(bagId) =", IsBagOpen(bagIndex))

    -- BAG_UPDATE fires when an item:
    -- * appears in a bag
    -- * disappears from a bag
    -- * moves from one slot to another in a bag
    addCallbacksToPetTokensInBagByIndex("BAG_UPDATE", bagIndex)
end

function EventHandlers:BAG_OPEN(bagId)
    -- astonishingly, inexplicably,
    -- "Fired when a lootable container (not an equipped bag) is opened."
    debug.trace:print("BAG_OPEN", bagId)
end

-------------------------------------------------------------------------------
-- Event Handler Registration
-------------------------------------------------------------------------------

function createEventListener(targetSelfAsProxy, eventHandlers)
    debug.info:print(ADDON_NAME .. " EventListener:Activate() ...")

    local dispatcher = function(listenerFrame, eventName, ...)
        -- ignore the listenerFrame and instead
        eventHandlers[eventName](targetSelfAsProxy, ...)
    end

    local eventListenerFrame = CreateFrame("Frame")
    eventListenerFrame:SetScript("OnEvent", dispatcher)

    for eventName, _ in pairs(eventHandlers) do
        debug.info:print("EventListener:activate() - registering " .. eventName)
        eventListenerFrame:RegisterEvent(eventName)
    end
end

createEventListener(Pita, Pita.EventHandlers)

-------------------------------------------------------------------------------
-- Addon Lifecycle
-------------------------------------------------------------------------------

function initalizeAddonStuff()
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, addHelpTextToToolTip)
    hookOntoTheOnShowEventForAllBagsSoTheyEnhanceTheirPetTokens()
end

-------------------------------------------------------------------------------
-- Tooltip "Local" Functions
-------------------------------------------------------------------------------

function addHelpTextToToolTip(tooltip, data)
    if tooltip == GameTooltip then
        local itemId = data.id
        if hasThePetTaughtByThisItem(itemId) then
            GameTooltip:AddLine(Pita.L10N.TOOLTIP, 0, 1, 0)
        end
    end
end

-------------------------------------------------------------------------------
-- Pet "Local" Functions
-------------------------------------------------------------------------------

function hasThePetTaughtByThisItem(itemId)
    if Pita:isPetKnown(itemId) then
        local _, _, _, _, _, _, _, _, _, _, _, _, speciesID = C_PetJournal.GetPetInfoByItemID(itemId)
        local numCollected, _ = C_PetJournal.GetNumCollectedInfo(speciesID)
        return numCollected > 0
    end
end

function hasPet(petGuid)
    debug.trace:print("hasPet():", petGuid)
    if not petGuid then return end
    local speciesID = C_PetJournal.GetPetInfoByPetID(petGuid)
    local numCollected, _ = C_PetJournal.GetNumCollectedInfo(speciesID)
    return numCollected > 0
end

function getPetFromThisBagSlot(bagIndex, slotId)
    -- bagIndex: 0..n
    -- slotId: 1..x

    local returnPetInfo
    local itemId = C_Container.GetContainerItemID(bagIndex, slotId)
    --debug.info:out(">",1, "getPetFromThisBagSlot()", "bagIndex",bagIndex, "slotId",slotId, "itemId",itemId)
    if itemId then
        local petName, _ = C_PetJournal.GetPetInfoByItemID(itemId)
        if petName then
            debug.info:out(">",2, "getPetFromThisBagSlot()", "petName",petName)
            local _, petGuid = C_PetJournal.FindPetIDByName(petName)
            debug.info:out(">",2, "getPetFromThisBagSlot()", "petGuid",petGuid)
            returnPetInfo = {
                petGuid = petGuid,
                petName = petName,
                itemId = itemId,
                bagIndex = bagIndex,
                slotId = slotId,
            }
        end
    end

    return returnPetInfo
end

-------------------------------------------------------------------------------
-- Click Handler "Local" Functions
-------------------------------------------------------------------------------

function hookOntoTheOnShowEventForAllBagsSoTheyEnhanceTheirPetTokens()
    for bagIndex = 0, MAX_BAG_INDEX do
        local bagFrame = getBagFrame(bagIndex)
        bagFrame:HookScript("OnShow", function(...) addCallbacksToPetTokensInBagFrame("OnShow", ...) end)
    end
end

function getBagFrame(bagIndex)
    local bagId = bagIndex + 1
    local bagFrameId = "ContainerFrame" .. bagId
    local bagFrame = _G[bagFrameId]
    -- because Bliz's API is fucking brain damaged
    -- the return values of bagFrame:GetBagID() are based only on OPEN bags (aka, USELESS)
    -- unless I manually set it my own damn self
    bagFrame:SetBagID(bagIndex)
    debug.trace:print("getBagFrame() bagIndex:", bagIndex, "| bagFrameId:", bagFrameId, "| GetBagID():", bagFrame:GetBagID())
    return bagFrame
end

function addCallbacksToPetTokensInBagByIndex(eventName, bagIndex)
    local bagFrame = getBagFrame(bagIndex)
    local bagIndex2 = bagFrame:GetBagID()
    local isOpen = IsBagOpen(bagIndex)
    debug.info:print("##### addCallbacksToPetTokensInBag()... bagIndex:", bagIndex, "| bagIndex2:", bagIndex2, "| isOpen:", isOpen)
    if isOpen then
        addCallbacksToPetTokensInBagFrame(eventName, bagFrame)
    end
end

-- BLIZ BUG: when a bag is opened for the first time, its contents are in the wrong indices in bagFrame.Items
-- BLIZ BUG: thus, bagFrame:EnumerateValidItems() is unreliable too (may not return all contents).  So I can't simply
-- for i, bagSlotFrame in bagFrame:EnumerateValidItems() do
-- Instead, I must manually fetch the bagSlotFrames
-- the BagFrame objects shift position between when I attach the click-handlers and when the user clicks / triggers those handlers.  Thus, the lexically scoped variables contain stale data.

function addCallbacksToPetTokensInBagFrame(eventName, bagFrame)
    local bagIndex = bagFrame:GetBagID()
    local bagName = C_Container.GetBagName(bagIndex) or "BLANK"
    local bagSize = C_Container.GetContainerNumSlots(bagIndex) -- UNRELIABLE (?)
    local isOpen = IsBagOpen(bagIndex)
    local isBagNeverOpenedBefore = Pita:isBagNeverOpenedBefore(bagFrame)
    local isHeldBag = isHeldBag(bagIndex)
    debug.info:out("=",5, "addCallbacksToPetTokensInBagFrame()...", "eventName", eventName, "bagIndex", bagIndex, "name", bagName, "size", bagSize, "isOpen", isOpen, "isBagNeverOpenedBefore",isBagNeverOpenedBefore)

    if isBagNeverOpenedBefore then
        debug.info:out("=",7, "ABORT! This bag has never been opened and thus is FUBAR")
        Pita:markBagAsOpened(bagFrame)
        local delaySeconds = 1
        -- DELAYED RE-OPEN CALLBACK
        C_Timer.After(delaySeconds, function()
            local force = true
            debug.info:out("=",7, "FORCING bag to reopen...", "bagIndex",bagIndex)
            OpenBag(bagIndex, force)
            addCallbacksToPetTokensInBagFrame("FORCED_TO_REOPEN", bagFrame)
        end)
        return
    end

    local bagSlots = bagFrame.Items

    --for slotId, bagSlotFrame in bagFrame:EnumerateItems() do
    for i = 1, #bagSlots do
        local slotId = i
        local slotIndex = slotId - 1
        -- the last bagSlot is stored as the first element of the array.  the first bagSlot is at the end of the array.
        local slotId = bagSize - slotIndex

        local bagSlotFrame = bagSlots[i]

        -- BLIZ BUG: when the first time a bag is opened, its bagSlotFrames are not in the right slot.
        -- So ask it which slot it thinks it's in.  And then, verify it.
        local actualSlotId = bagSlotFrame:GetSlotAndBagID()
        local isValidSlotId = actualSlotId > 0
        if isValidSlotId then
            local itemLink = C_Container.GetContainerItemLink(bagIndex, actualSlotId)
            local itemId = C_Container.GetContainerItemID(bagIndex, actualSlotId)

            -- For debugging, add a PreClick handler to every slot.
            if debug.trace:isActive() then
                -- PRE CLICK HOOK
                local success = bagSlotFrame:HookScript("PreClick", function(...)
                    local updatedBagSlots = bagFrame.Items
                    local updatedBagFrame = updatedBagSlots[i]
                    local updatedSlotId = updatedBagFrame:GetSlotAndBagID()
                    local updatedItemLink = C_Container.GetContainerItemLink(bagIndex, updatedSlotId)
                    debug.trace:print("SIMPLE TEST FOR ON CLICK! i:", i, "| slotId:",slotId, "| actualSlotId:",actualSlotId, "| updatedSlotId:",updatedSlotId, itemLink or "X", "-->", updatedItemLink or "X")
                end)
            end

            debug.info:out("=",7, "snafu", "bagIndex", bagIndex, "slotId",slotId, "actualSlotId",actualSlotId, "itemId",itemId, itemLink)

            local petInfo = getPetFromThisBagSlot(bagIndex, actualSlotId)
            if petInfo then
                Pita:markPetAsKnown(itemId)
                debug.info:out("=",7, "adding a PreClick handler for", "petInfo.itemId", petInfo.itemId)
                -- PRE CLICK HOOK
                local success = bagSlotFrame:HookScript("PreClick", function(...) handleCagerClick(petInfo.petName, bagIndex, actualSlotId, ...) end)
            end
        end
    end
end

function handleCagerClick(petName, bagIndex, slotId, bagFrame, whichMouseButtonStr, isPressed)
    local petInfo = getPetFromThisBagSlot(bagIndex, slotId)
    local isSameName = petInfo and petInfo.petName and petInfo.petName == petName
    if not isSameName then
        debug.warn:print("handleCagerClick()... this slot (", bagIndex, slotId, ") has no pet named", petName)
        return
    end

    local isShiftRightClick = IsShiftKeyDown() and whichMouseButtonStr == "RightButton"
    if not isShiftRightClick then
        debug.info:print("handleCagerClick()... abort!  NOT IsShiftKeyDown", IsShiftKeyDown(), "or wrong whichMouseButtonStr", whichMouseButtonStr)
        return
    end

    if not hasPet(petInfo.petGuid) then
        debug.info:print("handleCagerClick()... NONE LEFT:", petName)
        return
    end

    debug.info:print("handleCagerClick()... CAGING:", petName)
    C_PetJournal.CagePetByID(petInfo.petGuid)
end

function isHeldBag(bagIndex)
    return bagIndex >= Enum.BagIndex.Backpack and bagIndex <= NUM_TOTAL_BAG_FRAMES;
end

-------------------------------------------------------------------------------
-- Pita Methods
-------------------------------------------------------------------------------

function Pita:isBagNeverOpenedBefore(bagFrame)
    local bagIndex = bagFrame:GetBagID()
    return not self.hasBagBeenOpened[bagIndex]
end

function Pita:markBagAsOpened(bagFrame)
    local bagIndex = bagFrame:GetBagID()
    self.hasBagBeenOpened[bagIndex] = true
end

function Pita:isPetKnown(itemId)
    return self.knownPetTokenIds[itemId] or false
end

function Pita:markPetAsKnown(itemId)
    self.knownPetTokenIds[itemId] = true
end

function vivify(matrix, x, y)
    if not matrix then matrix = {} end
    if not matrix[x] then matrix[x] = {} end
    if not matrix[x][y] then matrix[x][y] = {} end
    -- TODO: automate this so it can support any depth
end

function Pita:hasSlotBeenHooked(bagSlotFrame)
    local slotId, bagId = bagSlotFrame:GetSlotAndBagID()
    vivify(self.hookedBagSlots, bagId, slotId)
    return self.hookedBagSlots[bagId][slotId] or false
end

function Pita:markSlotAsHooked(bagSlotFrame)
    vivify(self.hookedBagSlots, bagId, slotId)
    self.hookedBagSlots[bagId][slotId] = true
end
