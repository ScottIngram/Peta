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
-------------------------------------------------------------------------------

local _G = _G -- but first, grab the global namespace or else we lose it
Pita.NAMESPACE = {}
setmetatable(Pita.NAMESPACE, { __index = _G }) -- inherit all member of the Global namespace
setfenv(1, Pita.NAMESPACE)

-------------------------------------------------------------------------------
-- Constants
-------------------------------------------------------------------------------

local NUM_BAGS = 6 -- NUM_TOTAL_BAG_FRAMES or Constants.InventoryConstants.NumBagSlots or 6 -- was NUM_CONTAINER_FRAMES
local BACKPACK_ID = 1
-- some useless global Bliz values:
-- NUM_CONTAINER_FRAMES = 13
-- NUM_TOTAL_BAG_FRAMES = 5
-- Constants.InventoryConstants.NumBagSlots = 4
-- Enum.BagIndex.Backpack = 0

-------------------------------------------------------------------------------
-- Event handlers
-------------------------------------------------------------------------------

local EventHandlers = {}

function EventHandlers:ADDON_LOADED(addonName)
    if addonName == ADDON_NAME then
        debug.info:print("ADDON_LOADED", addonName)
    end
end

function EventHandlers:PLAYER_LOGIN()
    debug.trace:print("PLAYER_LOGIN")
    PLAYER_LOGIN_DONE = true
    initalizeAddonStuff()
end

function EventHandlers:PLAYER_ENTERING_WORLD(isInitialLogin, isReloadingUi)
    debug.trace:print("PLAYER_ENTERING_WORLD", isInitialLogin, isReloadingUi)
end

function EventHandlers:BAG_NEW_ITEMS_UPDATED()
    debug.trace:print("BAG_NEW_ITEMS_UPDATED")
    self:Foo()
end

function EventHandlers:BAG_UPDATE(bagIndex)
    if PLAYER_LOGIN_DONE then
        debug.trace:print("BAG_UPDATE", bagIndex, "| IsBagOpen(bagId) =",IsBagOpen(bagIndex))
        addHandlerForCagingToAnyPetsInThisBag(bagIndex)
    end
end

function EventHandlers:BAG_OPEN(bagId)
    debug.info:print("BAG_OPEN", bagId)
end

-------------------------------------------------------------------------------
-- Event Handler / Listener Registration
-------------------------------------------------------------------------------

function Pita:CreateEventListener()
    debug.info:print(ADDON_NAME.." EventListener:Activate() ...")

    local targetSelfAsProxy = self
    function dispatcher(frame, eventName, ...)
        EventHandlers[eventName](targetSelfAsProxy, ...)
    end

    local eventListenerFrame = CreateFrame("Frame")
    eventListenerFrame:SetScript("OnEvent", dispatcher)

    for eventName, _ in pairs(EventHandlers) do
        debug.info:print("EventListener:activate() - registering ".. eventName)
        eventListenerFrame:RegisterEvent(eventName)
    end
end

Pita:CreateEventListener()

-------------------------------------------------------------------------------
-- Addon Lifecycle
-------------------------------------------------------------------------------

function initalizeAddonStuff()
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, addHelpTextToToolTip)

    debug.info:dump(ContainerFrame1)
    debug.info:dumpKeys(ContainerFrame1)
    hookOnShowCallbacks()
end

function hookOnShowCallbacks()
    ContainerFrame1:HookScript("OnShow", fucker)
    ContainerFrame2:HookScript("OnShow", fucker)
    ContainerFrame3:HookScript("OnShow", fucker)
    ContainerFrame4:HookScript("OnShow", fucker)
    ContainerFrame5:HookScript("OnShow", fucker)
    ContainerFrame6:HookScript("OnShow", fucker)
    if true then return end

    for bag=0, NUM_BAGS do
        local n = C_Container.GetContainerNumSlots(bag)
        for slot=1, n do
            local itemId = "ContainerFrame".. bag+1 .."Item".. slot
            local frame = _G[itemId]
            local itemLink = C_Container.GetContainerItemLink(bag, slot)
            local GetSlot, GetBag = frame:GetSlotAndBagID()
            debug.info:print("bag slots...", bag, slot,itemId,frame,itemLink, GetBag,GetSlot)
            if frame and not aSlot then
                debug.info:print("stashing bag, slot =",bag, slot)
                aSlot = frame
                anItemLink = itemLink
                theBagId = bag
                theSlotId = slot
                theItemId = itemId
            end
        end
    end

end

function fucker(widget)
    debug.info:print(widget:GetBagID())
end
-------------------------------------------------------------------------------
-- Now-Local Functions - even without the "local" keyword or stupidly verbose names
-------------------------------------------------------------------------------


function addHelpTextToToolTip(tooltip, data)
    if tooltip == GameTooltip then
        if data.PitaWasHere then return end
        if Pita.knownPetTokenIds[data.id] then
            GameTooltip:AddLine(Pita.L10N.TOOLTIP,0,1,0)
        end
    end
end

function addHandlerForCagingToAnyPetsInThisBag(bagIndex)
    local bagId = bagIndex + 1
    if bagIndex > NUM_BAGS then
        debug.info:print("ignoring bag #", bagIndex)
        return
    end
    local name = C_Container.GetBagName(bagIndex) or "BLANK"
    local isOpen = IsBagOpen(bagIndex)
    local size = C_Container.GetContainerNumSlots(bagIndex)

    local bagFrameId = "ContainerFrame" .. bagId
    local bagFrame = _G[bagFrameId]
    debug.info:print("bagIndex #", bagIndex, "name:",name, "| size:",size, "| isOpen:",isOpen, "| bagFrameId:", bagFrameId, bagFrame)

    for i, bagSlotFrame in bagFrame:EnumerateValidItems() do
        local slotId, _ = bagSlotFrame:GetSlotAndBagID()
        local itemId = C_Container.GetContainerItemID(bagIndex, slotId)
        local itemInfo = C_Container.GetContainerItemInfo(bagIndex, slotId)
        debug.info:print(i, ": bagId =", bagIndex,"| slotId =",slotId,"| itemId =",itemId,itemInfo and itemInfo.hyperlink)

        if itemId then
            local petName, icon, petType, creatureID, sourceText, description,
            isWild, canBattle, tradeable, unique, obtainable,
            displayID, speciesID = C_PetJournal.GetPetInfoByItemID(itemId)
            if petName then
                debug.info:print(C_PetJournal.GetPetInfoByItemID(itemId))
                Pita.knownPetTokenIds[itemId] = true
                local isAlreadyHooked = bagSlotFrame.Pita
                local _, petGuid = C_PetJournal.FindPetIDByName(petName)
                if petGuid then
                    local numCollected, limit = C_PetJournal.GetNumCollectedInfo(speciesID)
                    debug.info:print("#### numCollected, limit, isAlreadyHooked =", numCollected, limit, isAlreadyHooked)
                    if isAlreadyHooked then
                        debug.info:print("isAlreadyHooked:",isAlreadyHooked)
                    else
                        debug.info:print("adding handlers...")
                        -- C_PetJournal.CagePetByID(petGuid)
                        -- bagSlotFrame.RegisterCallback("PreClick", init, ProfessionsFrame.CraftingPage)
                        local existingScript = bagSlotFrame:GetScript("PreClick")
                        if existingScript then debug.info:print("existingScript:", existingScript) end
                        bagSlotFrame:SetScript("PreClick", function(...) handleCagerClick(petName, existingScript, ...) end )
                        -- update the tooltip
                        local existingToolTipper = bagSlotFrame.UpdateTooltip
                        if existingToolTipper then debug.info:print("existingToolTipper:", existingToolTipper) end
                        --bagSlotFrame.Pita_OLD_TOOLTIPPER = existingToolTipper()
                        bagSlotFrame.Pita = {
                            oldToolTipper = existingToolTipper
                        }

                        -- bagSlotFrame.UpdateTooltip = function() enhanceToolTip(bagSlotFrame)  end

                    end
                elseif isAlreadyHooked then
                    -- We don't own the pet (anymore) but must have at some point because we hooked the handler
                    bagSlotFrame:SetScript("PreClick", nil)
                    bagSlotFrame.UpdateTooltip = bagSlotFrame.Pita.oldToolTipper
                    bagSlotFrame.Pita = nil
                end
            end
        end

    end
end

function handleCagerClick(petName, existingScript, widget, whichMouseButtonStr, isPressed)
    debug.info:print("handleCagerClick:", petGuid, whichMouseButtonStr, isPressed)
    if IsShiftKeyDown() and whichMouseButtonStr == "RightButton" then
        local _, petGuid = C_PetJournal.FindPetIDByName(petName)
        debug.info:print("CAGING:",petGuid)
        C_PetJournal.CagePetByID(petGuid)
    end
end

function enhanceToolTip(bagSlotFrame)

    local existingToolTipper = bagSlotFrame.Pita.oldToolTipper
    existingToolTipper(bagSlotFrame)
    local line3 = GameTooltipTextLeft3:GetText()
    local doneDid = string.find(line3, Pita.L10N.TOOLTIP, 1, true)
    if doneDid then
        return
    end

    --debug.info:print("enhanceToolTip()... existingToolTipper:",existingToolTipper)
    local text = "|cff00FF00"..Pita.L10N.TOOLTIP.."|r"

    existingToolTipper(bagSlotFrame)
    --GameTooltip:AddLine(Pita.L10N.TOOLTIP,0,1,0)
    local line3 = GameTooltipTextLeft3:GetText()
    GameTooltipTextLeft3:SetText(line3  .. "\rPita: " .. Pita.L10N.TOOLTIP)
    GameTooltip:Show()
end

function foo()
    local theBagId, theSlotId, theItemId
    local aSlot
    local anItemLink
    -- Add hook for each bag item.
    for bag=0, NUM_BAGS do
        local n = C_Container.GetContainerNumSlots(bag)
        for slot=1, n do
            local itemId = "ContainerFrame".. bag+1 .."Item".. slot
            local frame = _G[itemId]
            local itemLink = C_Container.GetContainerItemLink(bag, slot)
            local GetSlot, GetBag = frame:GetSlotAndBagID()
            debug.info:print("bag slots...", bag, slot,itemId,frame,itemLink, GetBag,GetSlot)
            if frame and not aSlot then
                debug.info:print("stashing bag, slot =",bag, slot)
                aSlot = frame
                anItemLink = itemLink
                theBagId = bag
                theSlotId = slot
                theItemId = itemId
            end
        end
    end

    -- debug.info:dumpKeys(aSlot)

    debug.info:print("HasItem =",aSlot:HasItem())
    debug.info:print("theItemId, theBagId, theSlotId =",theItemId, theBagId, theSlotId)
    local slot, bagID = aSlot:GetSlotAndBagID()
    debug.info:print("aSlot:GetSlotAndBagID()", slot, bagID)
    debug.info:print("aSlot:GetItemLocation() ->")
    debug.info:dump(aSlot:GetItemLocation())

    debug.info:print("anItemLink =",anItemLink)
    debug.info:print("aSlot:GetItem(anItemLink) =",aSlot:GetItem(anItemLink))
    debug.info:print("aSlot:GetItemID() =",aSlot:GetItemID())
    debug.info:print("aSlot:GetItemID(anItemLink) =",aSlot:GetItemID(anItemLink))
    debug.info:print("aSlot:GetItemInfo() =",aSlot:GetItemInfo())
    debug.info:print("aSlot:GetItemInfo(anItemLink) =",aSlot:GetItemInfo(anItemLink))
    debug.info:print("GetItemButtonCount",aSlot:GetItemButtonCount())
    debug.info:print("GetBagID",aSlot:GetBagID())

    debug.info:print("C_Container.GetContainerItemInfo(bagID, slot) ->")
    local itemInfo = C_Container.GetContainerItemInfo(bagID, slot)
    debug.info:dump(itemInfo)
    debug.info:print(itemInfo.hyperlink)

    local itemID = C_Container.GetContainerItemID(bagID, slot)
    debug.info:print("C_Container.GetContainerItemID(bagID, slot) =",itemID)
    --local petName = "foo"
    --debug.info:print("FindPetIDByName() =",C_PetJournal.FindPetIDByName(petName))

    debug.info:print("C_PetJournal.GetPetInfoByItemID(itemID) ->")
    debug.info:dump(C_PetJournal.GetPetInfoByItemID(itemID))
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
    debug.warn:print("TOOLTIP =", Pita.L10N.TOOLTIP)
    foo()
end

