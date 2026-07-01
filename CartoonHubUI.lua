local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local localPlayer = Players.LocalPlayer

-- Module Setup
local tradeModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("TradeModule"))
local inventoryModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("InventoryModule"))
local itemModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ItemModule"))
local profileData = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ProfileData"))
local sync = require(ReplicatedStorage:WaitForChild("Database"):WaitForChild("Sync"))
local itemPopupService = require(ReplicatedStorage:WaitForChild("ClientServices"):WaitForChild("ItemPopupService"))

-- ==================== TRADE LOGIC ====================
local PLACEHOLDER_SENDER_NAME = "RandomPlayer"
local localOffer = {}
local theirOffer = {}
local localAcceptMode = "Accept"
local localConfirmStartedAt = 0
local cooldownEndsAt = 0
local cooldownSequence = 0
local otherAcceptSequence = 0
local redrawLocalTrade
local resetAcceptUi
local showIncomingTradeRequest
local installRequestAcceptBridge
local refreshMainInventoryItem

local function cleanupOldOverlays()
	local gui = tradeModule.GUI
	if not gui then
		return
	end

	for _, root in ipairs({ gui.RequestFrame, gui.TradeGUI }) do
		if root then
			for _, descendant in ipairs(root:GetDescendants()) do
				if descendant.Name == "ClientPlaceholderTradeRemove"
					or descendant.Name == "ClientPlaceholderTradeToggle"
					or descendant.Name == "ClientPlaceholderTradeAcceptBridge"
					or descendant.Name == "ClientPlaceholderTradeAcceptOverlay"
					or descendant.Name == "ClientPlaceholderTradeActionOverlay" then
					descendant:Destroy()
				end
			end
		end
	end
end

local function clearOfferSlots(offerFrame)
	if not offerFrame or not offerFrame:FindFirstChild("Container") then
		return
	end

	for index = 1, 4 do
		local slot = offerFrame.Container:FindFirstChild("NewItem" .. index)
		if slot then
			itemModule.DisplayItem(slot, nil)
			slot.Visible = false
		end
	end
end

local function copyItemData(itemId, itemType, amount)
	local source = sync[itemType] and sync[itemType][itemId]
	if not source then
		return nil
	end

	local data = {}
	for key, value in pairs(source) do
		data[key] = value
	end
	data.DataType = itemType
	data.Amount = amount or 1
	return data
end

local function getProfileOwnedTable(itemType)
	if itemType == "Weapons" or itemType == "Item" then
		return profileData.Weapons and profileData.Weapons.Owned
	elseif itemType == "Pets" then
		return profileData.Pets and profileData.Pets.Owned
	end

	local bucket = profileData[itemType]
	return bucket and bucket.Owned
end

local function applyInventoryDelta(itemId, itemType, delta)
	local owned = getProfileOwnedTable(itemType)
	if not owned then
		warn(("[IncomingTradePopup] No local owned table for %s/%s"):format(
			tostring(itemType),
			tostring(itemId)
		))
		return
	end

	local current = tonumber(owned[itemId]) or 0
	local nextAmount = current + delta
	if nextAmount > 0 then
		owned[itemId] = nextAmount
	else
		owned[itemId] = nil
	end

	local tradeInventory = tradeModule.TradeInventory
	local entry = tradeInventory
		and tradeInventory.Data
		and tradeInventory.Data[itemType]
		and tradeInventory.Data[itemType].Current
		and tradeInventory.Data[itemType].Current[itemId]

	if entry then
		entry.Amount = math.max(0, (tonumber(entry.Amount) or current) + delta)
		if entry.Frame then
			if entry.Amount <= 0 then
				entry.Frame.Visible = false
			else
				local itemData = copyItemData(itemId, itemType, entry.Amount)
				if itemData then
					itemModule.DisplayItem(entry.Frame, itemData, nil, true)
				end
				entry.Frame.Visible = true
			end
		end
	end

	task.defer(function()
		refreshMainInventoryItem(itemId, itemType)
	end)
end

local function restoreLocalOfferToInventory()
	for _, offer in ipairs(localOffer) do
		applyInventoryDelta(offer.ItemID, offer.ItemType, offer.Amount or 1)
	end
	table.clear(localOffer)
end

local function addTheirOfferToInventory(offerList)
	for _, offer in ipairs(offerList or theirOffer) do
		applyInventoryDelta(offer.ItemID, offer.ItemType, offer.Amount or 1)
	end
end

local function getInventoryCategory(itemId, itemType)
	if itemType ~= "Weapons" and itemType ~= "Item" then
		return "Current"
	end

	local data = sync.Weapons and sync.Weapons[itemId]
	if not data then
		return "Current"
	end

	if data.Event == "Christmas" or data.Event == "Halloween" then
		return data.Event
	end

	return data.Season and "Current" or "Classic"
end

local function getMainInventoryContainer(itemType, category)
	local mainInventory = inventoryModule.GUI
		and inventoryModule.GUI.MyInventory
		and inventoryModule.GUI.MyInventory.Main
	local typeFrame = mainInventory and mainInventory:FindFirstChild(itemType)
	if not typeFrame then
		return nil
	end

	local itemsContainer = typeFrame:FindFirstChild("Items")
		and typeFrame.Items:FindFirstChild("Container")
	if not itemsContainer then
		return nil
	end

	local categoryFrame = itemsContainer:FindFirstChild(category)
	if categoryFrame and categoryFrame:FindFirstChild("Container") then
		return categoryFrame.Container
	end

	local holiday = itemsContainer:FindFirstChild("Holiday")
	if holiday and holiday:FindFirstChild("Container") then
		local holidayCategory = holiday.Container:FindFirstChild(category)
		if holidayCategory and holidayCategory:FindFirstChild("Container") then
			return holidayCategory.Container
		end
	end

	return nil
end

local refreshMainInventoryQueued = false

local function clearMainInventoryContainers()
	local gui = inventoryModule.GUI and inventoryModule.GUI.MyInventory
	if not gui or not gui.Main then
		return false
	end

	local blank = inventoryModule.CreateBlankInventoryTable()
	for itemType, categories in pairs(blank) do
		local typeFrame = gui.Main:FindFirstChild(itemType)
		local itemsContainer = typeFrame
			and typeFrame:FindFirstChild("Items")
			and typeFrame.Items:FindFirstChild("Container")

		if itemsContainer then
			for categoryName in pairs(categories) do
				local categoryFrame = itemsContainer:FindFirstChild(categoryName)
				if not categoryFrame and itemsContainer:FindFirstChild("Holiday") then
					local holiday = itemsContainer.Holiday:FindFirstChild("Container")
					categoryFrame = holiday and holiday:FindFirstChild(categoryName)
				end

				local container = categoryFrame and categoryFrame:FindFirstChild("Container")
				if container then
					container:ClearAllChildren()
				end
			end
		end
	end

	return true
end

local function refreshMainInventoryNow()
	local gui = inventoryModule.GUI and inventoryModule.GUI.MyInventory
	if not gui or not gui.Main then
		return
	end

	if not clearMainInventoryContainers() then
		return
	end

	local ok, newInventory = pcall(function()
		return inventoryModule.GenerateInventory(gui, profileData)
	end)
	if not ok then
		warn("[IncomingTradePopup] Main inventory refresh failed: " .. tostring(newInventory))
		return
	end

	inventoryModule.MyInventory = newInventory
	pcall(function()
		inventoryModule.ConnectEquipButtons()
	end)
	pcall(function()
		inventoryModule.UpdateMyEquip()
	end)
end

refreshMainInventoryItem = function()
	if refreshMainInventoryQueued then
		return
	end

	refreshMainInventoryQueued = true
	task.defer(function()
		refreshMainInventoryQueued = false
		refreshMainInventoryNow()
	end)
end

local function refreshMainInventoryItems()
	refreshMainInventoryItem()
end

local function setLocalAcceptState(mode)
	local actions = tradeModule.GUI.Actions
	local accept = actions and actions:FindFirstChild("Accept")
	if not accept then
		return
	end

	localAcceptMode = mode

	if accept:FindFirstChild("Confirm") then
		accept.Confirm.Visible = mode == "Confirm"
	end
	if accept:FindFirstChild("Cancel") then
		accept.Cancel.Visible = mode == "Waiting" or mode == "BothAccepted"
	end
	if accept:FindFirstChild("Cooldown") and mode ~= "Cooldown" then
		accept.Cooldown.Visible = false
	end

	if tradeModule.GUI.YourOffer:FindFirstChild("Accepted") then
		tradeModule.GUI.YourOffer.Accepted.Visible = mode == "Waiting" or mode == "BothAccepted"
	end
	if tradeModule.GUI.TheirOffer:FindFirstChild("Accepted") then
		tradeModule.GUI.TheirOffer.Accepted.Visible = mode == "BothAccepted"
	end
end

local function promptReceivedTheirOfferItems(offerList)
	for _, offer in ipairs(offerList or theirOffer) do
		local ok, err = pcall(function()
			itemPopupService:AddNewItem(offer.ItemID, offer.ItemType, offer.Amount or 1)
		end)
		if not ok then
			warn(("[IncomingTradePopup] Item popup failed for %s/%s: %s"):format(
				tostring(offer.ItemType),
				tostring(offer.ItemID),
				tostring(err)
			))
		end
	end
end

local function scheduleOtherSideAccept()
	otherAcceptSequence += 1
	local sequence = otherAcceptSequence
	local delaySeconds = math.random(10, 30) / 10

	task.delay(delaySeconds, function()
		if sequence ~= otherAcceptSequence or localAcceptMode ~= "Waiting" then
			return
		end

		if tradeModule.GUI.TheirOffer:FindFirstChild("Accepted") then
			tradeModule.GUI.TheirOffer.Accepted.Visible = true
		end

		task.delay(1, function()
			if sequence ~= otherAcceptSequence or localAcceptMode ~= "Waiting" then
				return
			end

			local tradeGui = tradeModule.GUI.TradeGUI
			local receivedItems = {}
			for _, offer in ipairs(theirOffer) do
				table.insert(receivedItems, {
					ItemID = offer.ItemID,
					ItemType = offer.ItemType,
					Amount = offer.Amount or 1,
				})
			end

			tradeGui.Enabled = false
			addTheirOfferToInventory(receivedItems)
			refreshMainInventoryItems(receivedItems)
			promptReceivedTheirOfferItems(receivedItems)
			tradeModule.TradeInventory = nil
			table.clear(localOffer)
			table.clear(theirOffer)
			resetAcceptUi()
			clearOfferSlots(tradeModule.GUI.YourOffer)
			clearOfferSlots(tradeModule.GUI.TheirOffer)
			installRequestAcceptBridge()
		end)
	end)
end

local function startAcceptCooldown(seconds)
	local actions = tradeModule.GUI.Actions
	local accept = actions and actions:FindFirstChild("Accept")
	local cooldown = accept and accept:FindFirstChild("Cooldown")
	local title = cooldown and cooldown:FindFirstChild("Title")
	if not cooldown then
		return
	end

	cooldownSequence += 1
	local sequence = cooldownSequence
	cooldownEndsAt = time() + seconds
	localAcceptMode = "Cooldown"

	if accept:FindFirstChild("Confirm") then
		accept.Confirm.Visible = false
	end
	if accept:FindFirstChild("Cancel") then
		accept.Cancel.Visible = false
	end
	if tradeModule.GUI.YourOffer:FindFirstChild("Accepted") then
		tradeModule.GUI.YourOffer.Accepted.Visible = false
	end

	cooldown.Visible = true

	task.spawn(function()
		while sequence == cooldownSequence do
			local remaining = math.max(0, math.ceil(cooldownEndsAt - time()))
			if title then
				title.Text = ("Please wait (%d) before accepting."):format(remaining)
			end
			if remaining <= 0 then
				break
			end
			task.wait(0.2)
		end

		if sequence == cooldownSequence then
			cooldown.Visible = false
			localAcceptMode = "Accept"
		end
	end)
end

resetAcceptUi = function()
	cooldownSequence += 1
	otherAcceptSequence += 1
	cooldownEndsAt = 0
	setLocalAcceptState("Accept")

	local actions = tradeModule.GUI.Actions
	if actions and actions:FindFirstChild("oldconfirm") then
		actions.oldconfirm.Visible = false
	end
end

local function installOfferRemoveButtons()
	local yourOffer = tradeModule.GUI.YourOffer
	if not yourOffer or not yourOffer:FindFirstChild("Container") then
		return
	end

	for index = 1, 4 do
		local slot = yourOffer.Container:FindFirstChild("NewItem" .. index)
		if slot then
			local oldOverlay = slot:FindFirstChild("ClientPlaceholderTradeRemove")
			if oldOverlay then
				oldOverlay:Destroy()
			end

			if localOffer[index] then
				local overlay = Instance.new("TextButton")
				overlay.Name = "ClientPlaceholderTradeRemove"
				overlay.BackgroundTransparency = 1
				overlay.BorderSizePixel = 0
				overlay.Text = ""
				overlay.Size = UDim2.fromScale(1, 1)
				overlay.Position = UDim2.fromScale(0, 0)
				overlay.ZIndex = slot.ZIndex + 50
				overlay.Parent = slot

				overlay.MouseButton1Click:Connect(function()
					local removed = table.remove(localOffer, index)
					if removed then
						applyInventoryDelta(removed.ItemID, removed.ItemType, removed.Amount or 1)
					end
					if redrawLocalTrade then
						redrawLocalTrade()
					end
				end)
			end
		end
	end
end

local function drawOfferSlots(offerFrame, offerList)
	clearOfferSlots(offerFrame)

	for index, offer in ipairs(offerList) do
		local slot = offerFrame
			and offerFrame:FindFirstChild("Container")
			and offerFrame.Container:FindFirstChild("NewItem" .. index)
		local itemData = copyItemData(offer.ItemID, offer.ItemType, offer.Amount)

		if slot and itemData then
			itemModule.DisplayItem(slot, itemData)
			slot.Visible = true
		end
	end
end

redrawLocalTrade = function()
	drawOfferSlots(tradeModule.GUI.YourOffer, localOffer)
	drawOfferSlots(tradeModule.GUI.TheirOffer, theirOffer)

	resetAcceptUi()
	tradeModule.GUI.TheirOffer.Username.Text = "(" .. PLACEHOLDER_SENDER_NAME .. ")"
	installOfferRemoveButtons()
end

local function toggleLocalOffer(itemId, itemType)
	for index, offer in ipairs(localOffer) do
		if offer.ItemID == itemId and offer.ItemType == itemType then
			local removed = table.remove(localOffer, index)
			if removed then
				applyInventoryDelta(removed.ItemID, removed.ItemType, removed.Amount or 1)
			end
			redrawLocalTrade()
			return
		end
	end

	if #localOffer >= 4 then
		warn("[IncomingTradePopup] Trade offer is full.")
		return
	end

	table.insert(localOffer, {
		ItemID = itemId,
		Amount = 1,
		ItemType = itemType,
	})
	applyInventoryDelta(itemId, itemType, -1)
	redrawLocalTrade()
	startAcceptCooldown(5)
end

local function getRandomGodlyWeapon()
	local candidates = {}

	for itemId, data in pairs(sync.Weapons or {}) do
		if type(data) == "table" and data.Rarity == "Godly" and (data.ItemType == "Knife" or data.ItemType == "Gun") then
			table.insert(candidates, { ItemID = itemId, Amount = 1, ItemType = "Weapons" })
		end
	end

	if #candidates < 1 then
		return nil
	end

	return candidates[math.random(1, #candidates)]
end

local function addRandomGodlyToTheirOffer()
	if not tradeModule.GUI.TradeGUI.Enabled then
		warn("[IncomingTradePopup] Open the placeholder trade before adding their random godly.")
		return
	end

	if #theirOffer >= 4 then
		warn("[IncomingTradePopup] Their offer is full.")
		return
	end

	local item = getRandomGodlyWeapon()
	if not item then
		warn("[IncomingTradePopup] No godly knife/gun found in the item database.")
		return
	end

	table.insert(theirOffer, item)
	drawOfferSlots(tradeModule.GUI.TheirOffer, theirOffer)
	resetAcceptUi()
	tradeModule.GUI.TheirOffer.Username.Text = "(" .. PLACEHOLDER_SENDER_NAME .. ")"
	startAcceptCooldown(5)
	print(("[IncomingTradePopup] Added random godly to their offer: %s/%s"):format(
		tostring(item.ItemType),
		tostring(item.ItemID)
	))
end

local function removeLastTheirOffer()
	if not tradeModule.GUI.TradeGUI.Enabled then
		warn("[IncomingTradePopup] Open the placeholder trade before removing their item.")
		return
	end

	if #theirOffer < 1 then
		warn("[IncomingTradePopup] Their offer is already empty.")
		return
	end

	local removed = table.remove(theirOffer)
	drawOfferSlots(tradeModule.GUI.TheirOffer, theirOffer)
	resetAcceptUi()
	tradeModule.GUI.TheirOffer.Username.Text = "(" .. PLACEHOLDER_SENDER_NAME .. ")"
	startAcceptCooldown(5)
	print(("[IncomingTradePopup] Removed their last offered item: %s/%s"):format(
		tostring(removed.ItemType),
		tostring(removed.ItemID)
	))
end

local function addOverlayClickTarget(parent, itemId, itemType)
	if not parent or not parent:IsA("GuiObject") then
		return
	end

	local oldOverlay = parent:FindFirstChild("ClientPlaceholderTradeToggle")
	if oldOverlay then
		oldOverlay:Destroy()
	end

	local overlay = Instance.new("TextButton")
	overlay.Name = "ClientPlaceholderTradeToggle"
	overlay.BackgroundTransparency = 1
	overlay.BorderSizePixel = 0
	overlay.Text = ""
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.Position = UDim2.fromScale(0, 0)
	overlay.ZIndex = parent.ZIndex + 100
	overlay.Parent = parent

	overlay.MouseButton1Click:Connect(function()
		toggleLocalOffer(itemId, itemType)
	end)
end

local function addActionOverlay(parent, callback)
	if not parent or not parent:IsA("GuiObject") then
		return
	end

	local oldOverlay = parent:FindFirstChild("ClientPlaceholderTradeActionOverlay")
	if oldOverlay then
		oldOverlay:Destroy()
	end

	local overlay = Instance.new("TextButton")
	overlay.Name = "ClientPlaceholderTradeActionOverlay"
	overlay.BackgroundTransparency = 1
	overlay.BorderSizePixel = 0
	overlay.Text = ""
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.Position = UDim2.fromScale(0, 0)
	overlay.ZIndex = parent.ZIndex + 100
	overlay.Parent = parent

	overlay.MouseButton1Click:Connect(callback)
end

local function installTradeActionButtons()
	local actions = tradeModule.GUI.Actions
	if not actions then
		return
	end

	local accept = actions:FindFirstChild("Accept")
	local decline = actions:FindFirstChild("Decline")

	if accept then
		addActionOverlay(accept:FindFirstChild("ActionButton"), function()
			if localAcceptMode == "Accept" and time() >= cooldownEndsAt then
				localConfirmStartedAt = time()
				setLocalAcceptState("Confirm")
			end
		end)

		local confirmButton = accept:FindFirstChild("Confirm")
			and accept.Confirm:FindFirstChild("ActionButton")
		addActionOverlay(confirmButton, function()
			if localAcceptMode == "Confirm" and time() - localConfirmStartedAt >= 0.4 then
				setLocalAcceptState("Waiting")
				scheduleOtherSideAccept()
			end
		end)

		local cancelButton = accept:FindFirstChild("Cancel")
			and accept.Cancel:FindFirstChild("ActionButton")
		addActionOverlay(cancelButton, function()
			resetAcceptUi()
		end)
	end

	if decline then
		addActionOverlay(decline:FindFirstChild("ActionButton"), function()
			tradeModule.GUI.TradeGUI.Enabled = false
			tradeModule.TradeInventory = nil
			restoreLocalOfferToInventory()
			table.clear(theirOffer)
			resetAcceptUi()
		end)
	end
end

local function installInventoryToggleButtons()
	local tradeInventory = tradeModule.TradeInventory
	if not tradeInventory or not tradeInventory.Data then
		return
	end

	for itemType, categories in pairs(tradeInventory.Data) do
		for _, items in pairs(categories) do
			for itemId, entry in pairs(items) do
				local frame = entry.Frame
				local actionButton = frame
					and frame:FindFirstChild("Container")
					and frame.Container:FindFirstChild("ActionButton")

				if actionButton and actionButton:IsA("GuiObject") then
					addOverlayClickTarget(actionButton, itemId, itemType)
				elseif frame and frame:IsA("GuiObject") then
					addOverlayClickTarget(frame, itemId, itemType)
				end
			end
		end
	end
end

local function openTradeFrameFromAccept()
	local tradeGui = tradeModule.GUI.TradeGUI
	local tradeContainer = tradeGui.Container
	restoreLocalOfferToInventory()
	table.clear(theirOffer)
	resetAcceptUi()

	for _, categoryName in ipairs({ "Weapons", "Pets" }) do
		local category = tradeContainer.Items.Main:FindFirstChild(categoryName)
		if category and category:FindFirstChild("Items") and category.Items:FindFirstChild("Container") then
			for _, section in ipairs(category.Items.Container:GetChildren()) do
				local container = section:FindFirstChild("Container")
				if container then
					container:ClearAllChildren()
				end
			end
		end
	end

	tradeModule.TradeInventory = inventoryModule.GenerateInventory(
		tradeContainer.Items,
		profileData,
		"Trading",
		tradeModule.GUI.ItemsLayout
	)
	tradeModule.ConnectOfferButtons(tradeModule.TradeInventory)

	redrawLocalTrade()

	tradeModule.GUI.TheirOffer.Username.Text = "(" .. PLACEHOLDER_SENDER_NAME .. ")"
	tradeModule.GUI.RequestFrame.Visible = false
	tradeGui.Enabled = true

	task.defer(installInventoryToggleButtons)
	task.delay(0.5, installInventoryToggleButtons)
	installTradeActionButtons()
end

local requestFrame = tradeModule.GUI.RequestFrame
local receivingRequest = requestFrame:WaitForChild("ReceivingRequest")
local acceptButton = receivingRequest:WaitForChild("Accept")
local requestAcceptSession = 0
local requestAcceptConnection

cleanupOldOverlays()

installRequestAcceptBridge = function()
	requestAcceptSession += 1
	local session = requestAcceptSession
	local opened = false

	if requestAcceptConnection then
		requestAcceptConnection:Disconnect()
		requestAcceptConnection = nil
	end

	local oldBridge = acceptButton:FindFirstChild("ClientPlaceholderTradeAcceptBridge")
	if oldBridge then
		oldBridge:Destroy()
	end

	local oldOverlay = acceptButton:FindFirstChild("ClientPlaceholderTradeAcceptOverlay")
	if oldOverlay then
		oldOverlay:Destroy()
	end

	local bridge = Instance.new("BoolValue")
	bridge.Name = "ClientPlaceholderTradeAcceptBridge"
	bridge.Parent = acceptButton

	local overlay = Instance.new("TextButton")
	overlay.Name = "ClientPlaceholderTradeAcceptOverlay"
	overlay.BackgroundTransparency = 1
	overlay.BorderSizePixel = 0
	overlay.Text = ""
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.Position = UDim2.fromScale(0, 0)
	overlay.ZIndex = acceptButton.ZIndex + 100
	overlay.Parent = acceptButton

	local function openOnce()
		if opened or session ~= requestAcceptSession or not bridge.Parent then
			return
		end

		opened = true
		bridge:Destroy()
		if overlay.Parent then
			overlay:Destroy()
		end
		if requestAcceptConnection then
			requestAcceptConnection:Disconnect()
			requestAcceptConnection = nil
		end
		task.defer(openTradeFrameFromAccept)
	end

	overlay.MouseButton1Click:Connect(openOnce)
	requestAcceptConnection = acceptButton.MouseButton1Click:Connect(function()
		task.defer(openOnce)
	end)
end

showIncomingTradeRequest = function()
	installRequestAcceptBridge()
	tradeModule.UpdateTradeRequestWindow("ReceivingRequest", {
		Sender = {
			Name = PLACEHOLDER_SENDER_NAME,
		},
	})
end

-- ==================== WEAPON SPAWNING LOGIC ====================
local currentWeaponAmount = 1

local function findWeaponInDatabase(weaponName)
	if not weaponName or weaponName == "" then
		return nil
	end

	local searchName = tostring(weaponName):lower()

	local function search(container, itemType)
		for itemId, data in pairs(container or {}) do
			if type(data) == "table" then
				local displayName = data.ItemName or data.Name or itemId
				local idText = tostring(itemId)

				if tostring(displayName):lower() == searchName
					or tostring(displayName):lower():find(searchName, 1, true)
					or idText:lower() == searchName
					or idText:lower():find(searchName, 1, true) then
					return itemId, itemType, displayName
				end
			end
		end
	end

	local itemId, itemType, displayName = search(sync.Weapons, "Weapons")
	if itemId then
		return itemId, itemType, displayName
	end

	return search(sync.Item, "Item")
end

local function spawnWeapon(weaponNameOrId, amount)
	local itemId, itemType, displayName = findWeaponInDatabase(weaponNameOrId)

	if not itemId then
		warn("[Carti Hub] Weapon not found: " .. tostring(weaponNameOrId))
		return false
	end

	amount = tonumber(amount) or 1
	amount = math.max(1, amount)

	local owned = getProfileOwnedTable(itemType)
	if not owned then
		warn("[Carti Hub] Could not find owned table for type: " .. tostring(itemType))
		return false
	end

	local current = tonumber(owned[itemId]) or 0
	owned[itemId] = current + amount

	refreshMainInventoryNow()

	for _ = 1, math.min(amount, 10) do
		pcall(function()
			itemPopupService:AddNewItem(itemId, itemType, 1)
		end)
	end

	print(("[Carti Hub] Spawned %dx %s (%s/%s)"):format(amount, displayName or weaponNameOrId, itemType, itemId))
	return true
end

local function spawnWeaponById(itemId, itemType, amount)
	local itemData = sync[itemType] and sync[itemType][itemId]

	if not itemData then
		warn(("[Carti Hub] Weapon id not found: %s/%s"):format(tostring(itemType), tostring(itemId)))
		return false
	end

	amount = tonumber(amount) or 1
	amount = math.max(1, amount)

	local owned = getProfileOwnedTable(itemType)
	if not owned then
		warn("[Carti Hub] Could not find owned table for type: " .. tostring(itemType))
		return false
	end

	local current = tonumber(owned[itemId]) or 0
	owned[itemId] = current + amount

	refreshMainInventoryNow()

	for _ = 1, math.min(amount, 10) do
		pcall(function()
			itemPopupService:AddNewItem(itemId, itemType, 1)
		end)
	end

	local displayName = itemData.ItemName or itemData.Name or itemId
	print(("[Carti Hub] Spawned %dx %s (%s/%s)"):format(amount, displayName, itemType, itemId))
	return true
end

local function spawnAllGodlyWeapons(amount)
	amount = tonumber(amount) or 1
	amount = math.max(1, amount)

	local spawnedCount = 0
	local seen = {}

	local function collect(container, itemType)
		for itemId, data in pairs(container or {}) do
			if type(data) == "table" and data.Rarity == "Godly" and not seen[itemId] then
				seen[itemId] = true

				local owned = getProfileOwnedTable(itemType)
				if owned then
					local current = tonumber(owned[itemId]) or 0
					owned[itemId] = current + amount
					spawnedCount += 1
				end
			end
		end
	end

	collect(sync.Weapons, "Weapons")
	collect(sync.Item, "Item")
	refreshMainInventoryNow()

	print(("[Carti Hub] Spawned %dx of %d godly weapons"):format(amount, spawnedCount))
	return spawnedCount
end

local function getRarityColor(rarity)
	local rarities = sync.Rarities or sync.Rarity
	local rarityData = rarities and rarities[rarity]

	if rarityData then
		if typeof(rarityData.Color) == "Color3" then
			return rarityData.Color
		end

		if type(rarityData.Hex) == "string" then
			local hex = rarityData.Hex:gsub("#", "")
			if #hex == 6 then
				return Color3.fromRGB(
					tonumber(hex:sub(1, 2), 16),
					tonumber(hex:sub(3, 4), 16),
					tonumber(hex:sub(5, 6), 16)
				)
			end
		end
	end

	return Color3.fromRGB(200, 100, 255)
end

local function isSpawnerRarity(data)
	return data.Rarity == "Godly" or data.Rarity == "Ancient"
end

-- ==================== GUI SETUP ====================
local oldUi = (pcall(function() return CoreGui.Name end) and CoreGui or localPlayer:WaitForChild("PlayerGui")):FindFirstChild("SakaModMenu")
if oldUi then
	oldUi:Destroy()
end

local SakaUI = Instance.new("ScreenGui")
SakaUI.Name = "SakaModMenu"
SakaUI.ResetOnSpawn = false
SakaUI.Parent = (pcall(function() return CoreGui.Name end) and CoreGui) or localPlayer:WaitForChild("PlayerGui")

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 300, 0, 560)
MainFrame.Position = UDim2.new(0.8, -150, 0.5, -280)
MainFrame.BackgroundColor3 = Color3.fromRGB(45, 15, 85)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = SakaUI

-- Galaxy Gradient Background
local Gradient = Instance.new("UIGradient", MainFrame)
Gradient.Rotation = 45
Gradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(130, 50, 210)),
	ColorSequenceKeypoint.new(0.25, Color3.fromRGB(180, 70, 230)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(220, 100, 255)),
	ColorSequenceKeypoint.new(0.75, Color3.fromRGB(160, 60, 220)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(100, 35, 180))
})

Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 16)

local BorderStroke = Instance.new("UIStroke", MainFrame)
BorderStroke.Color = Color3.fromRGB(220, 120, 255)
BorderStroke.Thickness = 2
BorderStroke.Transparency = 0.15

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -40, 0, 50)
Title.Position = UDim2.new(0, 15, 0, 0)
Title.BackgroundTransparency = 1
Title.Text = "Carti Hub"
Title.TextColor3 = Color3.fromRGB(255, 235, 255)
Title.Font = Enum.Font.GothamBold
Title.TextSize = 22
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = MainFrame

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 35, 0, 35)
CloseBtn.Position = UDim2.new(1, -45, 0, 8)
CloseBtn.BackgroundTransparency = 1
CloseBtn.Text = "X"
CloseBtn.TextColor3 = Color3.fromRGB(255, 210, 255)
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 22
CloseBtn.Parent = MainFrame

CloseBtn.MouseButton1Click:Connect(function()
	SakaUI:Destroy()
end)

local TabContainer = Instance.new("Frame")
TabContainer.Size = UDim2.new(1, -20, 0, 40)
TabContainer.Position = UDim2.new(0, 10, 0, 55)
TabContainer.BackgroundTransparency = 1
TabContainer.Parent = MainFrame

local TabLayout = Instance.new("UIListLayout", TabContainer)
TabLayout.FillDirection = Enum.FillDirection.Horizontal
TabLayout.SortOrder = Enum.SortOrder.LayoutOrder
TabLayout.Padding = UDim.new(0, 5)

local function CreateTabBtn(text, order)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(0.23, -4, 1, 0)
	btn.BackgroundColor3 = Color3.fromRGB(140, 60, 200)
	btn.Text = text
	btn.TextColor3 = Color3.fromRGB(255, 240, 255)
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 12
	btn.LayoutOrder = order
	btn.Parent = TabContainer
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)

	btn.MouseEnter:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.2), {
			BackgroundColor3 = Color3.fromRGB(200, 80, 255)
		}):Play()
	end)

	btn.MouseLeave:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.2), {
			BackgroundColor3 = Color3.fromRGB(140, 60, 200)
		}):Play()
	end)

	return btn
end

local SpawnerTabBtn = CreateTabBtn("Spawner", 1)
local TradeTabBtn = CreateTabBtn("Trade", 2)
local SettingsTabBtn = CreateTabBtn("Settings", 3)
local KeybindsTabBtn = CreateTabBtn("Keys", 4)

SpawnerTabBtn.BackgroundColor3 = Color3.fromRGB(200, 80, 255)

local function CreateTabFrame()
	local frame = Instance.new("ScrollingFrame")
	frame.Size = UDim2.new(1, -20, 1, -105)
	frame.Position = UDim2.new(0, 10, 0, 100)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.ScrollBarThickness = 4
	frame.CanvasSize = UDim2.new(0, 0, 1.45, 0)
	frame.Visible = false
	frame.Parent = MainFrame

	frame.ScrollBarImageColor3 = Color3.fromRGB(200, 100, 255)

	local list = Instance.new("UIListLayout", frame)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 10)
	return frame
end

local SpawnerFrame = CreateTabFrame(); SpawnerFrame.Visible = true
local TradeFrame = CreateTabFrame()
local SettingsFrame = CreateTabFrame()
local KeybindsFrame = CreateTabFrame()

local function CreateBox(parent, placeholder)
	local box = Instance.new("TextBox")
	box.Size = UDim2.new(1, 0, 0, 38)
	box.BackgroundColor3 = Color3.fromRGB(70, 30, 120)
	box.PlaceholderText = placeholder
	box.PlaceholderColor3 = Color3.fromRGB(200, 170, 230)
	box.Text = ""
	box.TextColor3 = Color3.fromRGB(255, 245, 255)
	box.Font = Enum.Font.Gotham
	box.TextSize = 13
	box.Parent = parent
	Instance.new("UICorner", box).CornerRadius = UDim.new(0, 8)

	local boxStroke = Instance.new("UIStroke", box)
	boxStroke.Color = Color3.fromRGB(200, 100, 255)
	boxStroke.Thickness = 1
	boxStroke.Transparency = 0.2

	return box
end

local BUTTON_COLOR = Color3.fromRGB(200, 80, 255)
local BUTTON_HOVER_COLOR = Color3.fromRGB(220, 100, 255)

local function CreateBtn(parent, text)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, 0, 0, 42)
	btn.BackgroundColor3 = BUTTON_COLOR
	btn.Text = text
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 13
	btn.Parent = parent
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)

	btn.MouseEnter:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.2), {
			BackgroundColor3 = BUTTON_HOVER_COLOR
		}):Play()
	end)

	btn.MouseLeave:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.2), {
			BackgroundColor3 = BUTTON_COLOR
		}):Play()
	end)

	return btn
end

local function CreateSlider(parent, text, min, max, defaultVal, step, callback)
	local container = Instance.new("Frame", parent)
	container.Size = UDim2.new(1, 0, 0, 50)
	container.BackgroundTransparency = 1

	local label = Instance.new("TextLabel", container)
	label.Size = UDim2.new(1, 0, 0, 22)
	label.BackgroundTransparency = 1
	label.Text = text .. ": " .. defaultVal
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.fromRGB(230, 200, 255)
	label.TextSize = 13

	local bg = Instance.new("Frame", container)
	bg.Size = UDim2.new(1, -10, 0, 10)
	bg.Position = UDim2.new(0, 5, 0, 28)
	bg.BackgroundColor3 = Color3.fromRGB(60, 25, 110)
	Instance.new("UICorner", bg).CornerRadius = UDim.new(1, 0)

	local fill = Instance.new("Frame", bg)
	fill.BackgroundColor3 = BUTTON_COLOR
	fill.Size = UDim2.new((defaultVal - min) / (max - min), 0, 1, 0)
	Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

	local knob = Instance.new("TextButton", fill)
	knob.Size = UDim2.new(0, 18, 0, 18)
	knob.Position = UDim2.new(1, -9, 0.5, -9)
	knob.BackgroundColor3 = Color3.fromRGB(255, 235, 255)
	knob.Text = ""
	Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

	local dragging = false
	knob.MouseButton1Down:Connect(function() dragging = true end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local mousePos = UserInputService:GetMouseLocation().X
			local startX = bg.AbsolutePosition.X
			local percent = math.clamp((mousePos - startX) / bg.AbsoluteSize.X, 0, 1)
			local rawVal = min + ((max - min) * percent)
			local val = math.floor(rawVal / step + 0.5) * step
			val = math.clamp(val, min, max)
			fill.Size = UDim2.new((val - min) / (max - min), 0, 1, 0)
			label.Text = text .. ": " .. val
			callback(val)
		end
	end)
end

-- ==================== SPAWNER GUI POPUP ====================
local SPAWNER_COLS = 5
local SPAWNER_BOX_SIZE = 94
local SPAWNER_PADDING = 6
local SPAWNER_NAME_HEIGHT = 24
local SPAWNER_RARITY_HEIGHT = 20
local SPAWNER_SLIDER_HEIGHT = 54
local spawnerWidth = (SPAWNER_BOX_SIZE + SPAWNER_PADDING) * SPAWNER_COLS + SPAWNER_PADDING + 20

local SpawnerGuiFrame = Instance.new("Frame")
SpawnerGuiFrame.Name = "WeaponSpawnerGUI"
SpawnerGuiFrame.Size = UDim2.new(0, spawnerWidth, 0, 500)
SpawnerGuiFrame.Position = UDim2.new(0.5, -(spawnerWidth / 2), 0.5, -250)
SpawnerGuiFrame.BackgroundColor3 = Color3.fromRGB(45, 15, 85)
SpawnerGuiFrame.BorderSizePixel = 0
SpawnerGuiFrame.Active = true
SpawnerGuiFrame.Draggable = true
SpawnerGuiFrame.Visible = false
SpawnerGuiFrame.Parent = SakaUI

Instance.new("UICorner", SpawnerGuiFrame).CornerRadius = UDim.new(0, 16)

local PopupStroke = Instance.new("UIStroke", SpawnerGuiFrame)
PopupStroke.Color = Color3.fromRGB(220, 120, 255)
PopupStroke.Thickness = 2
PopupStroke.Transparency = 0.15

local PopupTitle = Instance.new("TextLabel")
PopupTitle.Size = UDim2.new(1, -40, 0, 35)
PopupTitle.Position = UDim2.new(0, 15, 0, 5)
PopupTitle.BackgroundTransparency = 1
PopupTitle.Text = "Weapon Spawner"
PopupTitle.TextColor3 = Color3.fromRGB(255, 235, 255)
PopupTitle.Font = Enum.Font.GothamBold
PopupTitle.TextSize = 18
PopupTitle.TextXAlignment = Enum.TextXAlignment.Left
PopupTitle.Parent = SpawnerGuiFrame

local PopupCloseBtn = Instance.new("TextButton")
PopupCloseBtn.Size = UDim2.new(0, 28, 0, 28)
PopupCloseBtn.Position = UDim2.new(1, -38, 0, 6)
PopupCloseBtn.BackgroundTransparency = 1
PopupCloseBtn.Text = "X"
PopupCloseBtn.TextColor3 = Color3.fromRGB(255, 210, 255)
PopupCloseBtn.Font = Enum.Font.GothamBold
PopupCloseBtn.TextSize = 18
PopupCloseBtn.Parent = SpawnerGuiFrame

PopupCloseBtn.MouseButton1Click:Connect(function()
	SpawnerGuiFrame.Visible = false
end)

local WeaponScrollFrame = Instance.new("ScrollingFrame")
WeaponScrollFrame.Size = UDim2.new(1, -10, 1, -(55 + SPAWNER_SLIDER_HEIGHT))
WeaponScrollFrame.Position = UDim2.new(0, 5, 0, 45)
WeaponScrollFrame.BackgroundTransparency = 1
WeaponScrollFrame.BorderSizePixel = 0
WeaponScrollFrame.ScrollBarThickness = 4
WeaponScrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
WeaponScrollFrame.ScrollBarImageColor3 = Color3.fromRGB(200, 100, 255)
WeaponScrollFrame.Parent = SpawnerGuiFrame

local WeaponGrid = Instance.new("UIGridLayout", WeaponScrollFrame)
WeaponGrid.CellSize = UDim2.new(0, SPAWNER_BOX_SIZE, 0, SPAWNER_BOX_SIZE + SPAWNER_NAME_HEIGHT + SPAWNER_RARITY_HEIGHT)
WeaponGrid.CellPadding = UDim2.new(0, SPAWNER_PADDING, 0, SPAWNER_PADDING)
WeaponGrid.FillDirectionMaxCells = SPAWNER_COLS
WeaponGrid.SortOrder = Enum.SortOrder.LayoutOrder
WeaponGrid.HorizontalAlignment = Enum.HorizontalAlignment.Center

WeaponGrid:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	WeaponScrollFrame.CanvasSize = UDim2.new(0, 0, 0, WeaponGrid.AbsoluteContentSize.Y + 10)
end)

-- Popup slider
local PopupSliderFrame = Instance.new("Frame")
PopupSliderFrame.Size = UDim2.new(1, -16, 0, SPAWNER_SLIDER_HEIGHT)
PopupSliderFrame.Position = UDim2.new(0, 8, 1, -(SPAWNER_SLIDER_HEIGHT + 6))
PopupSliderFrame.BackgroundColor3 = Color3.fromRGB(55, 22, 95)
PopupSliderFrame.BorderSizePixel = 0
PopupSliderFrame.Parent = SpawnerGuiFrame
Instance.new("UICorner", PopupSliderFrame).CornerRadius = UDim.new(0, 10)

local PopupAmountLabel = Instance.new("TextLabel")
PopupAmountLabel.Size = UDim2.new(1, -16, 0, 20)
PopupAmountLabel.Position = UDim2.new(0, 8, 0, 4)
PopupAmountLabel.BackgroundTransparency = 1
PopupAmountLabel.Text = "Spawn Amount: " .. currentWeaponAmount
PopupAmountLabel.TextColor3 = Color3.fromRGB(255, 235, 255)
PopupAmountLabel.Font = Enum.Font.GothamBold
PopupAmountLabel.TextSize = 13
PopupAmountLabel.TextXAlignment = Enum.TextXAlignment.Left
PopupAmountLabel.Parent = PopupSliderFrame

local PopupSliderTrack = Instance.new("Frame")
PopupSliderTrack.Size = UDim2.new(1, -22, 0, 10)
PopupSliderTrack.Position = UDim2.new(0, 11, 0, 32)
PopupSliderTrack.BackgroundColor3 = Color3.fromRGB(30, 12, 55)
PopupSliderTrack.BorderSizePixel = 0
PopupSliderTrack.Parent = PopupSliderFrame
Instance.new("UICorner", PopupSliderTrack).CornerRadius = UDim.new(1, 0)

local PopupSliderFill = Instance.new("Frame")
PopupSliderFill.Size = UDim2.new(0, 0, 1, 0)
PopupSliderFill.BackgroundColor3 = BUTTON_COLOR
PopupSliderFill.BorderSizePixel = 0
PopupSliderFill.Parent = PopupSliderTrack
Instance.new("UICorner", PopupSliderFill).CornerRadius = UDim.new(1, 0)

local PopupSliderKnob = Instance.new("TextButton")
PopupSliderKnob.Size = UDim2.new(0, 18, 0, 18)
PopupSliderKnob.Position = UDim2.new(0, -9, 0.5, -9)
PopupSliderKnob.BackgroundColor3 = Color3.fromRGB(255, 235, 255)
PopupSliderKnob.Text = ""
PopupSliderKnob.Parent = PopupSliderFill
Instance.new("UICorner", PopupSliderKnob).CornerRadius = UDim.new(1, 0)

local popupDraggingAmount = false

local function setPopupSpawnAmountFromPercent(percent)
	local minAmount = 1
	local maxAmount = 50
	percent = math.clamp(percent, 0, 1)

	local value = math.floor(minAmount + ((maxAmount - minAmount) * percent) + 0.5)
	value = math.clamp(value, minAmount, maxAmount)

	currentWeaponAmount = value
	PopupAmountLabel.Text = "Spawn Amount: " .. value
	PopupSliderFill.Size = UDim2.new((value - minAmount) / (maxAmount - minAmount), 0, 1, 0)
end

PopupSliderKnob.MouseButton1Down:Connect(function()
	popupDraggingAmount = true
end)

PopupSliderTrack.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		local percent = (UserInputService:GetMouseLocation().X - PopupSliderTrack.AbsolutePosition.X) / PopupSliderTrack.AbsoluteSize.X
		setPopupSpawnAmountFromPercent(percent)
		popupDraggingAmount = true
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		popupDraggingAmount = false
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if popupDraggingAmount and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
		local percent = (UserInputService:GetMouseLocation().X - PopupSliderTrack.AbsolutePosition.X) / PopupSliderTrack.AbsoluteSize.X
		setPopupSpawnAmountFromPercent(percent)
	end
end)

-- Initial slider position
setPopupSpawnAmountFromPercent((currentWeaponAmount - 1) / 49)

local function AddWeaponBox(itemId, itemType, weaponName, rarity)
	local rarityColor = getRarityColor(rarity)
	local itemData = sync[itemType] and sync[itemType][itemId]

	local container = Instance.new("TextButton")
	container.Name = tostring(itemId)
	container.Size = UDim2.fromOffset(SPAWNER_BOX_SIZE, SPAWNER_BOX_SIZE + SPAWNER_NAME_HEIGHT + SPAWNER_RARITY_HEIGHT)
	container.BackgroundColor3 = Color3.fromRGB(45, 20, 75)
	container.BorderSizePixel = 0
	container.Text = ""
	container.AutoButtonColor = false
	container.Parent = WeaponScrollFrame
	Instance.new("UICorner", container).CornerRadius = UDim.new(0, 8)

	local stroke = Instance.new("UIStroke", container)
	stroke.Color = rarityColor
	stroke.Thickness = 2
	stroke.Transparency = 0.05

	local thumbnail = Instance.new("ImageLabel")
	thumbnail.Size = UDim2.new(1, -8, 0, 70)
	thumbnail.Position = UDim2.new(0, 4, 0, 4)
	thumbnail.BackgroundColor3 = Color3.fromRGB(25, 10, 45)
	thumbnail.BorderSizePixel = 0
	thumbnail.Image = itemData and itemData.Image or ""
	thumbnail.ScaleType = Enum.ScaleType.Fit
	thumbnail.Parent = container
	Instance.new("UICorner", thumbnail).CornerRadius = UDim.new(0, 6)

	local rarityLabel = Instance.new("TextLabel")
	rarityLabel.Size = UDim2.new(1, -4, 0, SPAWNER_RARITY_HEIGHT)
	rarityLabel.Position = UDim2.new(0, 2, 0, 75)
	rarityLabel.BackgroundTransparency = 1
	rarityLabel.Text = rarity or "Unknown"
	rarityLabel.TextColor3 = rarityColor
	rarityLabel.Font = Enum.Font.GothamBold
	rarityLabel.TextSize = 13
	rarityLabel.TextTruncate = Enum.TextTruncate.AtEnd
	rarityLabel.Parent = container

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, -4, 0, SPAWNER_NAME_HEIGHT)
	nameLabel.Position = UDim2.new(0, 2, 0, 94)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = weaponName or itemId
	nameLabel.TextColor3 = Color3.fromRGB(255, 235, 255)
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 12
	nameLabel.TextWrapped = false
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Parent = container

	container.MouseButton1Click:Connect(function()
		spawnWeaponById(itemId, itemType, currentWeaponAmount)
	end)

	container.MouseEnter:Connect(function()
		TweenService:Create(container, TweenInfo.new(0.15), {
			BackgroundColor3 = rarityColor:Lerp(Color3.fromRGB(20, 10, 35), 0.45),
		}):Play()
	end)

	container.MouseLeave:Connect(function()
		TweenService:Create(container, TweenInfo.new(0.15), {
			BackgroundColor3 = Color3.fromRGB(45, 20, 75),
		}):Play()
	end)
end

local didPopulateWeaponSpawner = false

local function populateWeaponSpawner()
	if didPopulateWeaponSpawner then
		return
	end

	didPopulateWeaponSpawner = true

	local weapons = {}
	local seen = {}

	local function collect(container, itemType)
		for itemId, data in pairs(container or {}) do
			if type(data) == "table" and isSpawnerRarity(data) and not seen[itemId] then
				seen[itemId] = true

				table.insert(weapons, {
					itemId = itemId,
					itemType = itemType,
					name = data.ItemName or data.Name or itemId,
					rarity = data.Rarity or "Unknown",
				})
			end
		end
	end

	collect(sync.Weapons, "Weapons")
	collect(sync.Item, "Item")

	table.sort(weapons, function(a, b)
		if a.rarity == b.rarity then
			return a.name < b.name
		end

		if a.rarity == "Ancient" and b.rarity ~= "Ancient" then
			return true
		end

		return false
	end)

	for index, weapon in ipairs(weapons) do
		AddWeaponBox(weapon.itemId, weapon.itemType, weapon.name, weapon.rarity)
		local child = WeaponScrollFrame:FindFirstChild(tostring(weapon.itemId))
		if child then
			child.LayoutOrder = index
		end
	end
end

-- ==================== SPAWNER TAB BUTTONS ====================
local SpecificWeaponBox = CreateBox(SpawnerFrame, "Spawn Weapon (e.g. Harvester)")
local SpawnSpecificBtn = CreateBtn(SpawnerFrame, "SPAWN WEAPON")

CreateSlider(SpawnerFrame, "Weapon Amount", 1, 500, 1, 1, function(val)
	currentWeaponAmount = val
	setPopupSpawnAmountFromPercent((val - 1) / 499)
end)

local SpawnGodliesBtn = CreateBtn(SpawnerFrame, "SPAWN ALL GODLIES")
local OpenSpawnerGuiBtn = CreateBtn(SpawnerFrame, "OPEN SPAWNER GUI")

SpawnSpecificBtn.MouseButton1Click:Connect(function()
	local weaponName = SpecificWeaponBox.Text

	if weaponName and weaponName ~= "" then
		local success = spawnWeapon(weaponName, currentWeaponAmount)
		if success then
			SpecificWeaponBox.Text = ""
			SpecificWeaponBox.PlaceholderText = "Spawned. Type another..."
			task.delay(2, function()
				SpecificWeaponBox.PlaceholderText = "Spawn Weapon (e.g. Harvester)"
			end)
		else
			SpecificWeaponBox.PlaceholderText = "Not found. Try again..."
			task.delay(2, function()
				SpecificWeaponBox.PlaceholderText = "Spawn Weapon (e.g. Harvester)"
			end)
		end
	else
		SpecificWeaponBox.PlaceholderText = "Type a weapon name first."
		task.delay(2, function()
			SpecificWeaponBox.PlaceholderText = "Spawn Weapon (e.g. Harvester)"
		end)
	end
end)

SpecificWeaponBox.FocusLost:Connect(function(enterPressed)
	if enterPressed and SpecificWeaponBox.Text ~= "" then
		spawnWeapon(SpecificWeaponBox.Text, currentWeaponAmount)
	end
end)

SpawnGodliesBtn.MouseButton1Click:Connect(function()
	local count = spawnAllGodlyWeapons(currentWeaponAmount)
	if count > 0 then
		SpawnGodliesBtn.Text = "SPAWNED " .. count .. " GODLIES"
		task.delay(2, function()
			SpawnGodliesBtn.Text = "SPAWN ALL GODLIES"
		end)
	end
end)

OpenSpawnerGuiBtn.MouseButton1Click:Connect(function()
	populateWeaponSpawner()
	SpawnerGuiFrame.Visible = not SpawnerGuiFrame.Visible
end)

-- Trade Tab
local OpponentBox = CreateBox(TradeFrame, "Partner Name (Blank = Random)")
local StartTradeBtn = CreateBtn(TradeFrame, "START TRADE")
local AddRandomBtn = CreateBtn(TradeFrame, "ADD RANDOM THEIR GODLY")
local RemoveLastBtn = CreateBtn(TradeFrame, "REMOVE LAST THEIR ITEM")

StartTradeBtn.MouseButton1Click:Connect(showIncomingTradeRequest)
AddRandomBtn.MouseButton1Click:Connect(addRandomGodlyToTheirOffer)
RemoveLastBtn.MouseButton1Click:Connect(removeLastTheirOffer)

-- Settings Tab
local TradeReqToggleBtn = CreateBtn(SettingsFrame, "TRADE REQUEST: OFF")
local AutoTradeToggleBtn = CreateBtn(SettingsFrame, "AUTO TRADE: OFF")
CreateSlider(SettingsFrame, "Friend Joined Delay (Sec)", 30, 300, 30, 10, function(val) end)
local FriendJoinToggleBtn = CreateBtn(SettingsFrame, "FRIEND JOINED: OFF")

-- Keybinds Tab
local function CreateBindBtn(parent, displayName, bindName)
	local btn = CreateBtn(parent, displayName .. ": None")
	return btn
end

CreateBindBtn(KeybindsFrame, "Toggle UI", "ToggleUI")
CreateBindBtn(KeybindsFrame, "Start Trade", "StartTrade")
CreateBindBtn(KeybindsFrame, "Friend Joined", "FriendJoined")
CreateBindBtn(KeybindsFrame, "Spawn All", "SpawnAllWeapons")
CreateBindBtn(KeybindsFrame, "Add Random", "AddRandomWeapon")
CreateBindBtn(KeybindsFrame, "Remove Last", "RemoveLastOffer")

local function SwitchTab(activeBtn, activeFrame)
	SpawnerFrame.Visible = false
	TradeFrame.Visible = false
	SettingsFrame.Visible = false
	KeybindsFrame.Visible = false

	SpawnerTabBtn.BackgroundColor3 = Color3.fromRGB(140, 60, 200)
	TradeTabBtn.BackgroundColor3 = Color3.fromRGB(140, 60, 200)
	SettingsTabBtn.BackgroundColor3 = Color3.fromRGB(140, 60, 200)
	KeybindsTabBtn.BackgroundColor3 = Color3.fromRGB(140, 60, 200)

	activeFrame.Visible = true
	activeBtn.BackgroundColor3 = BUTTON_HOVER_COLOR
end

SpawnerTabBtn.MouseButton1Click:Connect(function() SwitchTab(SpawnerTabBtn, SpawnerFrame) end)
TradeTabBtn.MouseButton1Click:Connect(function() SwitchTab(TradeTabBtn, TradeFrame) end)
SettingsTabBtn.MouseButton1Click:Connect(function() SwitchTab(SettingsTabBtn, SettingsFrame) end)
KeybindsTabBtn.MouseButton1Click:Connect(function() SwitchTab(KeybindsTabBtn, KeybindsFrame) end)

-- ==================== KEYBINDS ====================
if _G.ClientPlaceholderTradeKeybindConnection then
	_G.ClientPlaceholderTradeKeybindConnection:Disconnect()
end

_G.ClientPlaceholderTradeKeybindConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or UserInputService:GetFocusedTextBox() then
		return
	end

	if input.KeyCode == Enum.KeyCode.Z then
		showIncomingTradeRequest()
	elseif input.KeyCode == Enum.KeyCode.Y then
		addRandomGodlyToTheirOffer()
	elseif input.KeyCode == Enum.KeyCode.B then
		removeLastTheirOffer()
	end
end)

-- Global exports
_G.CartiHubStartTradeRequest = showIncomingTradeRequest
_G.CartiHubAddRandomTheirGodly = addRandomGodlyToTheirOffer
_G.CartiHubRemoveLastTheirOffer = removeLastTheirOffer
_G.CartiHubSpawnWeapon = spawnWeapon
_G.CartiHubSpawnWeaponById = spawnWeaponById
_G.CartiHubSpawnAllGodlies = spawnAllGodlyWeapons
_G.CartiHubPopulateWeaponSpawner = populateWeaponSpawner
_G.CartiHubAddWeaponBox = AddWeaponBox

print("[Carti Hub] Loaded.")
print("[Carti Hub] Z=Trade Request | Y=Add Their Godly | B=Remove Their Item")
print("[Carti Hub] Spawner GUI shows Godly and Ancient weapons only, 5 per row, with rarity colors.")
