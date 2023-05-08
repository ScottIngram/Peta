local ADDON_NAME, Pita = ...
local debug = Pita.DEBUG.newDebugger(Pita.DEBUG.ALL_MSGS)
local PLAYER_LOGIN_DONE = false

-------------------------------------------------------------------------------
-- Pita Data
-------------------------------------------------------------------------------

Pita.knownPetTokenIds = {}

-------------------------------------------------------------------------------
-- Global Functions
-------------------------------------------------------------------------------

function Pita_Foo()

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
Pita.NAMESPACE = {}
setmetatable(Pita.NAMESPACE, { __index = _G }) -- inherit all member of the Global namespace
setfenv(1, Pita.NAMESPACE)

-------------------------------------------------------------------------------
-- Constants
-------------------------------------------------------------------------------

local MAX_BAG_ID = NUM_TOTAL_BAG_FRAMES + 1
local MAX_BAG_INDEX = NUM_TOTAL_BAG_FRAMES

-------------------------------------------------------------------------------
-- Event handlers
-------------------------------------------------------------------------------

local EventHandlers = {}

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
-- Event Handler & Listener Registration
-------------------------------------------------------------------------------

function Pita:CreateEventListener()
    debug.info:print(ADDON_NAME .. " EventListener:Activate() ...")

    local targetSelfAsProxy = self
    local dispatcher = function(frame, eventName, ...)
        EventHandlers[eventName](targetSelfAsProxy, ...)
    end

    local eventListenerFrame = CreateFrame("Frame")
    eventListenerFrame:SetScript("OnEvent", dispatcher)

    for eventName, _ in pairs(EventHandlers) do
        debug.info:print("EventListener:activate() - registering " .. eventName)
        eventListenerFrame:RegisterEvent(eventName)
    end
end

Pita:CreateEventListener()

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
    if Pita.knownPetTokenIds[itemId] then
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
    --debug.trace:print("getPetFromThisBagSlot() itemId:", itemId)
    if itemId then
        local petName, _ = C_PetJournal.GetPetInfoByItemID(itemId)
        if petName then
            debug.trace:print("getPetFromThisBagSlot() petName:", petName)
            local _, petGuid = C_PetJournal.FindPetIDByName(petName)
            debug.trace:print("getPetFromThisBagSlot() petGuid:", petGuid)
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

Pita.bagFramesFromOrignalOnShowEvent = {}

function hookOntoTheOnShowEventForAllBagsSoTheyEnhanceTheirPetTokens()
    for bagIndex = 0, MAX_BAG_INDEX do
        local bagFrame = getBagFrame(bagIndex)
        Pita.bagFramesFromOrignalOnShowEvent[bagIndex] = bagFrame
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

Pita.neoBagFrames = {}
local prevBagFrame = "NONE"
local prevDaddy = "NADA"
local prevToken = "ZILCH"

function addCallbacksToPetTokensInBagFrame(eventName, bagFrame)
    --debug.info:dumpKeys(bagFrame)
    debug.info:print("===== bagFrame:", bagFrame, "| prevBagFrame:", prevBagFrame)
    prevBagFrame = bagFrame
    --debug.info:dumpKeys(bagFrame)

    local daddy = bagFrame.GetParent and bagFrame:GetParent()
    debug.info:print("===== daddy:", daddy, "| prevDaddy:", prevDaddy)
    prevDaddy = daddy
    if daddy then
        debug.info:dumpKeys(daddy)
    end

    local bagIndex = bagFrame:GetBagID()
    local argBagFrameName = bagFrame:GetName()

    local shownBagFrame = ContainerFrameUtil_GetShownFrameForID(bagIndex)
    debug.info:print("===== shownBagFrame:", shownBagFrame, "| bagFrame:", bagFrame)

    -- by the time this method is called (as a result of either OnShow or ON_BAG_UPDATE)
    --
    local neoBagFrame = Pita.neoBagFrames[bagIndex]
    if eventName == "OnShow" then
        Pita.neoBagFrames[bagIndex] = bagFrame
        neoBagFrame = bagFrame
    else
        local areSame = neoBagFrame == bagFrame
        debug.info:print(">>>>>", bagIndex, ": replacing 'bad?' self:", bagFrame, " with ", neoBagFrame, " areSame:", areSame)
        bagFrame = neoBagFrame or bagFrame
    end

    local neoBagFrameName = neoBagFrame and neoBagFrame:GetName()

    local name = C_Container.GetBagName(bagIndex) or "BLANK"
    local bagSize = C_Container.GetContainerNumSlots(bagIndex) -- UNRELIABLE (?)
    local isOpen = IsBagOpen(bagIndex)
    local ogBagFrame = Pita.bagFramesFromOrignalOnShowEvent[bagIndex]
    local ogBagFrameName = ogBagFrame and ogBagFrame:GetName()
    debug.info:print("===== eventName:", eventName, "| bagIndex:", bagIndex, "| name:", name, "| size:", bagSize, "| isOpen:", isOpen)
    debug.info:print("===== bagFrame:", bagFrame, "| ogBagFrame:", ogBagFrame, "| neoBagFrame:", neoBagFrame, "| argBagFrameName:", argBagFrameName, "| ogBagFrameName:", ogBagFrameName, "| neoBagFrameName:", neoBagFrameName)

    local bagSlots = bagFrame.Items
    local xSlots = {}

    --[[
    -- desperation maneuver: combine the recent bagFrames with the original OnShow bagFrames
    if false and bagFrame ~= ogBagFrame then
        local ogBagSlots = ogBagFrame.Items
        local both = {} -- table.insert(bagSlots, table.unpack(ogBagSlots))
        for i,v in ipairs (bagSlots) do
            table.insert(both, v)
            xSlots[v:GetSlotAndBagID()] = v
            table.insert(xSlots, v)
        end
        for i,v in ipairs (ogBagSlots) do
            table.insert(both, v)
        end
        debug.info:print("===== combined bagFrame:",#bagSlots, "| ogBagFrame:",#ogBagSlots, "| both:",#both)
        bagSlots = both
    end
    ]]

    -- bagFrame:EnumerateValidItems() is BUGGED and unreliable, so I can't simply
    -- for i, bagSlotFrame in bagFrame:EnumerateValidItems() do
    -- Instead, I must manually fetch the bagSlotFrames

    --testIterator("ONE", bagFrame)
    --testIterator("TWO", bagFrame)

    --for slotId, bagSlotFrame in bagFrame:EnumerateItems() do
    for i = 1, #bagSlots do
        local slotId = i
        local slotIndex = slotId - 1
        -- the last bagSlot is stored as the first element of the array.  the first bagSlot is at the end of the array.
        local slotId = bagSize - slotIndex
        --local bagSlotFrameId = "ContainerFrame".. bagId .."Item".. slotId
        --local bagSlotFrame = _G[bagSlotFrameId] -- BIG FAT FAIL

        local bagSlotFrame = bagSlots[i]

        -- BLIZ BUG: when the first time a bag is opened, its bagSlotFrames are not in the right slot.
        -- So ask it which slot it thinks it's in.  And then, verify it.
        local actualSlotId = bagSlotFrame:GetSlotAndBagID()
        local isValidSlotId = actualSlotId > 0
        if isValidSlotId then
            local itemLink = C_Container.GetContainerItemLink(bagIndex, actualSlotId)
            local itemId = C_Container.GetContainerItemID(bagIndex, actualSlotId)
            local success = bagSlotFrame:HookScript("PreClick", function(...)

                local updatedBagSlots = bagFrame.Items
                local updatedBagFrame = updatedBagSlots[i]
                local updatedSlotId = updatedBagFrame:GetSlotAndBagID()
                local updatedItemLink = C_Container.GetContainerItemLink(bagIndex, updatedSlotId)
                debug.error:print("SIMPLE TEST FOR ON CLICK! i:", i, "| slotId:",slotId, "| actualSlotId:",actualSlotId, "| updatedSlotId:",updatedSlotId, itemLink or "X", "-->", updatedItemLink or "X")
            end)

            --local isSame = xSlots[actualSlotId] == bagSlotFrame
            debug.info:print("XXXXX bagIndex:", bagIndex, "| i:",i, "| slotId:", slotId, "| actualSlotId:", actualSlotId, "| itemId:", itemId, "| itemLink:", itemLink) --, "| isSame:",isSame)--, "| bagSlotFrameMaybe:", bagSlotFrameMaybe)

            local petInfo = getPetFromThisBagSlot(bagIndex, actualSlotId)
            if petInfo then
                Pita.knownPetTokenIds[itemId] = true
                debug.info:print("XXXXXXXXXX adding handlers to bagSlotFrame:", bagSlotFrame, "| prevSlotFrame:",prevToken, "| bagIndex:", bagIndex, "| actualSlotId:", actualSlotId)
                prevToken = bagSlotFrame
                local success = bagSlotFrame:HookScript("PreClick", function(...) handleCagerClick(petInfo.petName, bagIndex, actualSlotId, ...) end)
            end
        end


        --[[
        if itemId then
            local petName, _, _, _, _, _, _, _, _, _, _, _, speciesID = C_PetJournal.GetPetInfoByItemID(itemId)
            if petName then
                Pita.knownPetTokenIds[itemId] = true
                local _, petGuid = C_PetJournal.FindPetIDByName(petName)
                if petGuid then
                    debug.info:print("########## adding handlers to bagSlotFrame:",bagSlotFrame, "| bagIndex:",bagIndex, "| actualSlotId:", actualSlotId)
                    local success = bagSlotFrame:HookScript("PreClick", function(...) handleCagerClick(petName, bagIndex, actualSlotId, ...) end)
                    debug.info:print("########## success:",success)
                end
            end
        end
        ]]

    end
end

function testIterator(header, bagFrame)
    local first, last
    for i, v in bagFrame:EnumerateItems() do
        if not first then
            first = { i = i, v = v, slotId=select(1,v:GetSlotAndBagID()) }
        end
        last = { i = i, v = v, slotId=select(1,v:GetSlotAndBagID()) }
    end
    debug.info:print(header, ".......... testIterator() ... FIRST: i", first.i, "slotId", first.slotId, first.v, "--- LAST: i", last.i, "slotId:", last.slotId, last.v)
end

function handleCagerClick(petName, bagIndex, slotId, bagFrame, whichMouseButtonStr, isPressed)
    local petInfo = getPetFromThisBagSlot(bagIndex, slotId)
    local isSameName = petInfo and petInfo.petName and petInfo.petName == petName
    if not isSameName then
        debug.info:print("handleCagerClick()... this slot (", bagIndex, slotId, ") has no pet named", petName)
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

local function isHeldBag(bagIndex)
    return bagIndex >= Enum.BagIndex.Backpack and bagIndex <= NUM_TOTAL_BAG_FRAMES;
end

-------------------------------------------------------------------------------
-- Pita Methods
-------------------------------------------------------------------------------

function Pita:Foo()
    debug.trace:print("Foo()")
    self:Bar()
end

function Pita:Bar()
    debug.trace:print("Bar()")
end

