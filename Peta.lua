local ADDON_NAME, Peta = ...
local debug = Peta.DEBUG.newDebugger(Peta.DEBUG.ERROR)
local PLAYER_LOGIN_DONE = false

-------------------------------------------------------------------------------
-- Peta Data
-------------------------------------------------------------------------------

Peta.hopefullyReliableBagFrames = {}
Peta.knownPetTokenIds = {}
Peta.hasBagBeenOpened = {}
Peta.hookedBagSlots = {}
Peta.NAMESPACE = {}
Peta.EventHandlers = {}

local EventHandlers = Peta.EventHandlers -- just for shorthand

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

local MAX_BAG_INDEX = NUM_TOTAL_BAG_FRAMES
local FORCED_TO_REOPEN = "FORCED_TO_REOPEN"

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
    debug.trace:out("",1,"PLAYER_ENTERING_WORLD", "isInitialLogin",isInitialLogin, "isReloadingUi",isReloadingUi)
end

function EventHandlers:BAG_UPDATE(bagIndex)
    if not PLAYER_LOGIN_DONE or not IsBagOpen(bagIndex) then
        return
    end

    debug.info:out("",1,"BAG_UPDATE", "bagIndex",bagIndex, "IsBagOpen(bagId)",IsBagOpen(bagId))

    -- BAG_UPDATE fires when an item:
    -- * appears in a bag
    -- * disappears from a bag
    -- * moves from one slot to another in a bag
    onBagUpdateAddCallbacksToPetTokensInBagByIndex("BAG_UPDATE", bagIndex)
end

function EventHandlers:BAG_OPEN(bagId)
    -- astonishingly, inexplicably,
    -- "Fired when a lootable container (not an equipped bag) is opened."
    debug.info:print("BAG_OPEN", bagId)
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
            GameTooltip:AddLine(Peta.L10N.TOOLTIP, 0, 1, 0)
        end
    end
end

-------------------------------------------------------------------------------
-- Pet "Local" Functions
-------------------------------------------------------------------------------

function hasThePetTaughtByThisItem(itemId)
    if Peta:isPetKnown(itemId) then
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
-- Bag and Inventory Click Hooking "Local" Functions
-------------------------------------------------------------------------------

function hookOntoTheOnShowEventForAllBagsSoTheyEnhanceTheirPetTokens()
    for bagIndex = 0, MAX_BAG_INDEX do
        local bagFrame = getBagFrameSuitableForHookingForOnShow(bagIndex)
        function showMe(bagFrame)
            local updatedBagIndex = bagFrame:GetBagID()
            debug.info:out("",1, "OnShow", "bagIndex", bagIndex, "IsBagOpen(bagIndex)", IsBagOpen(bagIndex), "updatedBagIndex",updatedBagIndex)
            addCallbacksToPetTokensInBagFrame("OnShow", bagFrame)
        end
        bagFrame:HookScript("OnShow", showMe)
    end
end

-- Manually pulling bags out of BLIZ's global deposit of ContainerFrameX bags doesn't seem to contain reliable data,
-- but the self-reported ContainerFrames provided as "self" to the event callbacks DO seem to be the real-deal
-- although even they are FUBAR the first time they open.  So many bugs, so many workarounds...
function getBagFrameSuitableForGettingItsContents(bagIndex)
    -- bagIndex: 0..n
    return Peta.hopefullyReliableBagFrames[bagIndex] -- or getBagFrameSuitableForHookingForOnShow(bagIndex) -- nope, can't trust it
end

-- I can't rely on this to actually be the on-screen bag frame :(
-- but it seems to work if I just want to react to the ON_SHOW event
function getBagFrameSuitableForHookingForOnShow(bagIndex)
    -- bagIndex: 0..n
    local bagId = bagIndex + 1
    local bagFrameId = "ContainerFrame" .. bagId
    local bagFrame = _G[bagFrameId]

    -- the values returned  by BLIZ's bagFrame:GetBagID() are based only on OPEN bags and are thus chaotic and unreliable.
    -- So, I manually set the ID myself
    bagFrame:SetBagID(bagIndex) -- TODO: is this the source of the taint errors?
    debug.trace:out("",1, "getBagFrame()", "bagIndex", bagIndex, "bagFrameId", bagFrameId, "GetBagID()", bagFrame:GetBagID())
    return bagFrame
end

function onBagUpdateAddCallbacksToPetTokensInBagByIndex(eventName, bagIndex)
    local bagFrame = getBagFrameSuitableForGettingItsContents(bagIndex)
    local bagIndex2 = bagFrame:GetBagID()
    local isOpen = IsBagOpen(bagIndex)
    debug.info:out("#",5, "addCallbacksToPetTokensInBag()", "bagIndex", bagIndex, "bagIndex2", bagIndex2, "isOpen", isOpen)
    if isOpen then
        addCallbacksToPetTokensInBagFrame(eventName, bagFrame)
    end
end

-- BLIZZARD INTERNAL BUG:
-- When a bag is opened for the first time, its contents are in the wrong indices in bagFrame.Items
-- Thus, bagFrame:EnumerateValidItems() is unreliable too (may not return all contents).  So I can't simply
-- for i, bagSlotFrame in bagFrame:EnumerateValidItems() do
-- Instead, I must manually fetch the bagSlotFrames
-- Furthermore, the BagFrame objects get recycled and shift position
-- sometime after the initial bag open but before the user clicks / triggers those handlers.
-- Thus, the lexically scoped variables contain stale data and are useless.
-- Also the PreClick handlers may be on slots that no longer actually contain the pet tokens.
-- Solution: ignore the bag as it exists on initial open and force the UI to re-open it then re-invoke this

function addCallbacksToPetTokensInBagFrame(eventName, bagFrame)
    local bagIndex = bagFrame:GetBagID()
    local bagName = C_Container.GetBagName(bagIndex) or "BLANK"
    local bagSize = C_Container.GetContainerNumSlots(bagIndex) -- UNRELIABLE (?)
    local isOpen = IsBagOpen(bagIndex)
    local isBagNeverOpenedBefore = Peta:isBagNeverOpenedBefore(bagFrame)
    local isHeldBag = isHeldBag(bagIndex)
    debug.info:out("=",5, "addCallbacksToPetTokensInBagFrame()...", "eventName", eventName, "bagFrame",bagFrame, "bagIndex", bagIndex, "name", bagName, "size", bagSize, "isOpen", isOpen, "isHeldBag", isHeldBag, "isBagNeverOpenedBefore",isBagNeverOpenedBefore)

    if isBagNeverOpenedBefore then
        debug.info:out("=",7, "ABORT! This bag has never been opened and thus is FUBAR")
        Peta:markBagAsOpened(bagFrame)
        local delaySeconds = 1
        -- DELAYED RECURSION TO RE-OPEN THIS BAG
        C_Timer.After(delaySeconds, function()
            local force = true
            debug.info:out("=",7, "FORCING bag to reopen...", "bagIndex",bagIndex)
            OpenBag(bagIndex, force)
            addCallbacksToPetTokensInBagFrame(FORCED_TO_REOPEN, bagFrame)
        end)
        return
    end

    local isReliableBagFrame = (eventName == "OnShow") or (eventName == FORCED_TO_REOPEN)
    if isReliableBagFrame then
        -- caching this to be used in lieu of the BUGGED objects in _G["ContainerFrame1"]
        Peta.hopefullyReliableBagFrames[bagIndex] = bagFrame
        debug.trace:out("=",7, "STORING frame during OnShow", "bagIndex", bagIndex, "bagFrame",bagFrame)
    end

    local bagSlots = bagFrame.Items

    -- BLIZ BUG: I cannot rely on --> for slotId, bagSlotFrame in bagFrame:EnumerateItems() do
    for i = 1, #bagSlots do
        local slotId = i
        local slotIndex = slotId - 1
        -- the last bagSlot is stored as the first element of the array.  the first bagSlot is at the end of the array.
        local slotId = bagSize - slotIndex

        local bagSlotFrame = bagSlots[i]

        -- BLIZ BUG: when the first time a bag is opened, its bagSlotFrames are not in the right slot.
        -- So ask it which slot it thinks it's in.  And then, verify it.
        local actualSlotId = bagSlotFrame:GetSlotAndBagID()
        local isValidSlotId = actualSlotId > 0 and actualSlotId <= bagSize
        if isValidSlotId then
            local isAlreadyHooked = Peta:hasSlotBeenHooked(bagSlotFrame)
            local existingScript = bagSlotFrame:GetScript("PreClick") -- this is handleCagerClick
            local hasPetaScript = (existingScript == handleCagerClick)
            if isAlreadyHooked then
                debug.info:out("=",9, "ABORT - already hooked", "bagIndex", bagIndex, "slotId",slotId, "handleCagerClick",handleCagerClick, "existingScript",existingScript)
                --return
            end

            local itemId = C_Container.GetContainerItemID(bagIndex, actualSlotId)
            local itemLink = C_Container.GetContainerItemLink(bagIndex, actualSlotId)
            debug.info:out("=",7, "checking slot for pet...", "bagIndex", bagIndex, "slotId",slotId, "actualSlotId",actualSlotId, "itemId",itemId, "isAlreadyHooked",isAlreadyHooked, "hasPetaScript",hasPetaScript, itemLink)

            -- For debugging, add a PreClick handler to every slot.
            if debug.trace:isActive() then
                -- PRE CLICK HOOK
                function preClicker(...)
                    local updatedBagSlots = bagFrame.Items
                    local updatedBagFrame = updatedBagSlots[i]
                    local updatedSlotId = updatedBagFrame:GetSlotAndBagID()
                    local updatedItemLink = C_Container.GetContainerItemLink(bagIndex, updatedSlotId)
                    debug.trace:out("",1, "SIMPLE TEST FOR ON CLICK!", "i", i, "slotId",slotId, "actualSlotId",actualSlotId, "updatedSlotId",updatedSlotId, itemLink or "X", "-->", updatedItemLink or "X")
                end
                local success = bagSlotFrame:HookScript("PreClick", preClicker)
            end

            local petInfo = getPetFromThisBagSlot(bagIndex, actualSlotId)
            if petInfo and not isAlreadyHooked then
                Peta:markPetAsKnown(itemId)
                debug.info:out("=",7, "adding a PreClick handler for", "petInfo.itemId", petInfo.itemId)
                -- PRE CLICK HOOK
                local success = bagSlotFrame:HookScript("PreClick", handleCagerClick)
                Peta:markSlotAsHooked(bagSlotFrame)
            end
        end
    end
end

function handleCagerClick(bagSlotFrame, whichMouseButtonStr, isPressed)
    local slotId, bagIndex = bagSlotFrame:GetSlotAndBagID()
    local petInfo = getPetFromThisBagSlot(bagIndex, slotId)

    if not petInfo then
        debug.info:out("",1, "handleCagerClick()... abort! NO PET at", "bagIndex",bagIndex, "slotId",slotId)
        return
    end

    local isShiftRightClick = IsShiftKeyDown() and whichMouseButtonStr == "RightButton"
    if not isShiftRightClick then
        debug.info:print("handleCagerClick()... abort!  NOT IsShiftKeyDown", IsShiftKeyDown(), "or wrong whichMouseButtonStr", whichMouseButtonStr)
        return
    end

    if not hasPet(petInfo.petGuid) then
        debug.info:print("handleCagerClick()... abort! NONE LEFT:", petInfo.petName)
        return
    end

    debug.info:print("handleCagerClick()... CAGING:", petInfo.petName)
    C_PetJournal.CagePetByID(petInfo.petGuid)
end

function isHeldBag(bagIndex)
    return bagIndex >= Enum.BagIndex.Backpack and bagIndex <= NUM_TOTAL_BAG_FRAMES;
end

-------------------------------------------------------------------------------
-- Peta Methods
-------------------------------------------------------------------------------

function Peta:isBagNeverOpenedBefore(bagFrame)
    local bagIndex = bagFrame:GetBagID()
    return not self.hasBagBeenOpened[bagIndex]
end

function Peta:markBagAsOpened(bagFrame)
    local bagIndex = bagFrame:GetBagID()
    self.hasBagBeenOpened[bagIndex] = true
end

function Peta:isPetKnown(itemId)
    return self.knownPetTokenIds[itemId] or false
end

function Peta:markPetAsKnown(itemId)
    self.knownPetTokenIds[itemId] = true
end

-- ensure the data structure is ready to store values at the given coordinates
function vivify(matrix, x, y)
    if not matrix then matrix = {} end
    if not matrix[x] then matrix[x] = {} end
    --if not matrix[x][y] then matrix[x][y] = {} end
    -- TODO: automate this so it can support any depth
end

function Peta:hasSlotBeenHooked(bagSlotFrame)
    local slotId, bagIndex = bagSlotFrame:GetSlotAndBagID()
    vivify(self.hookedBagSlots, bagIndex, slotId)
    return self.hookedBagSlots[bagIndex][slotId] and true or false
end

function Peta:markSlotAsHooked(bagSlotFrame)
    local slotId, bagIndex = bagSlotFrame:GetSlotAndBagID()
    vivify(self.hookedBagSlots, bagIndex, slotId)
    self.hookedBagSlots[bagIndex][slotId] = true
end

-------------------------------------------------------------------------------
-- OK, Go for it!
-------------------------------------------------------------------------------

createEventListener(Peta, Peta.EventHandlers)
