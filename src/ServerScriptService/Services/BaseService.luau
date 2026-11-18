--!strict
-- BaseService.luau -- kepemilikan base: assign base kosong saat join, lepas
-- saat keluar, render model karakter di slot dari data pemain, prompt "Curi"
-- pada karakter di slot, pad Collect (sentuh = collect, rate-limited), dan
-- kunci base (LockGate + cooldown). Semua keputusan di server.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Types = require(Shared:WaitForChild("Types"))

type PlayerData = Types.PlayerData
type SlotData = Types.SlotData

local BaseService = {}

local DataService: any = nil
local EconomyService: any = nil
local BrainrotFactory: any = nil
local onStealPrompt: ((thief: Player, owner: Player, slotIndex: number) -> ())? = nil

local baseByPlayer: { [Player]: Model } = {}
local playerByBase: { [Model]: Player } = {}
local lockEndsAt: { [Player]: number } = {}
local lockCooldownEndsAt: { [Player]: number } = {}
local lastPadCollect: { [Player]: number } = {}

function BaseService.Bind(dataService: any, economyService: any, brainrotFactory: any)
	DataService = dataService
	EconomyService = economyService
	BrainrotFactory = brainrotFactory
end

function BaseService.SetStealPromptHandler(handler: (thief: Player, owner: Player, slotIndex: number) -> ())
	onStealPrompt = handler
end

function BaseService.GetBase(player: Player): Model?
	return baseByPlayer[player]
end

function BaseService.GetOwner(base: Model): Player?
	return playerByBase[base]
end

function BaseService.IsLocked(player: Player): boolean
	local ends = lockEndsAt[player]
	return ends ~= nil and os.time() < ends
end

function BaseService.LockState(player: Player): (number, number)
	return lockEndsAt[player] or 0, lockCooldownEndsAt[player] or 0
end

local function slotLabelText(data: PlayerData, slotIndex: number): string
	if slotIndex > data.SlotCount then
		return "Beli slot: " .. Config.SlotPrice(slotIndex)
	end
	return "Slot kosong"
end

local function refreshSlotLabels(player: Player)
	local base = baseByPlayer[player]
	local data: PlayerData? = DataService.Get(player)
	if not base or not data then
		return
	end
	for slotIndex = 1, Config.MaxSlots do
		local slotPart = base:FindFirstChild("Slot_" .. slotIndex)
		if slotPart then
			local billboard = slotPart:FindFirstChild("SlotLabel")
			local label = if billboard then billboard:FindFirstChild("Text") else nil
			if label and label:IsA("TextLabel") and not data.Slots[slotIndex] then
				label.Text = slotLabelText(data, slotIndex)
			end
		end
	end
end

-- Gambar ulang satu slot: hapus model lama, taruh model karakter bila terisi,
-- lengkap dengan billboard info dan ProximityPrompt "Curi" untuk pemain lain.
function BaseService.RenderSlot(player: Player, slotIndex: number)
	local base = baseByPlayer[player]
	local data: PlayerData? = DataService.Get(player)
	if not base or not data then
		return
	end
	local slotPart = base:FindFirstChild("Slot_" .. slotIndex)
	if not slotPart or not slotPart:IsA("BasePart") then
		return
	end
	local old = slotPart:FindFirstChild("Occupant")
	if old then
		old:Destroy()
	end
	local slot: SlotData? = data.Slots[slotIndex]
	if not slot then
		refreshSlotLabels(player)
		return
	end
	local model = BrainrotFactory.Clone(slot.Id)
	if not model then
		warn("[BaseService] Template karakter tidak ditemukan: " .. slot.Id)
		return
	end
	model.Name = "Occupant"
	model:SetAttribute("Mutation", slot.Mutation)
	model:SetAttribute("OwnerUserId", player.UserId)
	model:SetAttribute("SlotIndex", slotIndex)
	model:SetAttribute("State", "InSlot")
	local info = Config.Characters[slot.Id]
	local income = Config.IncomeOf(slot.Rarity, slot.Mutation, data.Rebirths)
	local pivot = (slotPart :: BasePart).CFrame * CFrame.new(0, (slotPart :: BasePart).Size.Y / 2 + 0.1, 0)
	model:PivotTo(pivot)
	model.Parent = slotPart

	-- Billboard info di atas karakter yang terpasang.
	local primary = model.PrimaryPart
	if primary then
		local billboard = Instance.new("BillboardGui")
		billboard.Name = "InfoBillboard"
		billboard.Size = UDim2.fromOffset(220, 64)
		billboard.StudsOffset = Vector3.new(0, 3.4, 0)
		billboard.AlwaysOnTop = true
		billboard.Adornee = primary
		local label = Instance.new("TextLabel")
		label.Name = "Info"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 0.35
		label.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
		label.Text = ("%s [%s]\n%s - %d/detik"):format(info.DisplayName, slot.Rarity, slot.Mutation, income)
		label.TextColor3 = Config.Rarities[slot.Rarity].Color
		label.TextScaled = true
		label.Font = Enum.Font.GothamBold
		label.Parent = billboard
		billboard.Parent = model

		-- Prompt curi: hanya server yang memutuskan hasil akhirnya.
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "StealPrompt"
		prompt.ActionText = "Curi"
		prompt.ObjectText = info.DisplayName
		prompt.HoldDuration = Config.StealHoldDuration
		prompt.MaxActivationDistance = Config.StealMaxDistance
		prompt.RequiresLineOfSight = false
		prompt.Parent = primary
		prompt.Triggered:Connect(function(thief: Player)
			if thief ~= player and onStealPrompt then
				onStealPrompt(thief, player, slotIndex)
			end
		end)
	end
	refreshSlotLabels(player)
end

function BaseService.RenderAllSlots(player: Player)
	local data: PlayerData? = DataService.Get(player)
	if not data then
		return
	end
	for slotIndex = 1, Config.MaxSlots do
		BaseService.RenderSlot(player, slotIndex)
	end
end

function BaseService.FirstFreeSlot(data: PlayerData): number?
	for slotIndex = 1, data.SlotCount do
		if not data.Slots[slotIndex] then
			return slotIndex
		end
	end
	return nil
end

-- Taruh karakter ke slot kosong pertama; false bila base penuh.
function BaseService.PlaceInFirstFreeSlot(player: Player, id: string, rarity: string, mutation: string): boolean
	local data: PlayerData? = DataService.Get(player)
	if not data then
		return false
	end
	local slotIndex = BaseService.FirstFreeSlot(data)
	if not slotIndex then
		return false
	end
	data.Slots[slotIndex] = { Id = id, Rarity = rarity, Mutation = mutation, PlacedAt = os.time() }
	DataService.MarkDirty(player)
	BaseService.RenderSlot(player, slotIndex)
	EconomyService.PushState(player)
	return true
end

function BaseService.RemoveFromSlot(player: Player, slotIndex: number): SlotData?
	local data: PlayerData? = DataService.Get(player)
	if not data then
		return nil
	end
	local slot = data.Slots[slotIndex]
	if not slot then
		return nil
	end
	data.Slots[slotIndex] = nil
	DataService.MarkDirty(player)
	BaseService.RenderSlot(player, slotIndex)
	EconomyService.PushState(player)
	return slot
end

function BaseService.PutBackInSlot(player: Player, slotIndex: number, slot: SlotData): boolean
	local data: PlayerData? = DataService.Get(player)
	if not data or data.Slots[slotIndex] then
		return false
	end
	data.Slots[slotIndex] = slot
	DataService.MarkDirty(player)
	BaseService.RenderSlot(player, slotIndex)
	EconomyService.PushState(player)
	return true
end

-- Kunci base selama Config.LockDuration; false bila masih cooldown/terkunci.
function BaseService.LockBase(player: Player): boolean
	local now = os.time()
	if BaseService.IsLocked(player) then
		return false
	end
	if (lockCooldownEndsAt[player] or 0) > now then
		return false
	end
	lockEndsAt[player] = now + Config.LockDuration
	lockCooldownEndsAt[player] = now + Config.LockDuration + Config.LockCooldown
	local base = baseByPlayer[player]
	if base then
		local gate = base:FindFirstChild("LockGate")
		if gate and gate:IsA("BasePart") then
			gate.Transparency = 0.25
			gate.CanCollide = true
		end
	end
	task.delay(Config.LockDuration, function()
		if baseByPlayer[player] == base then
			local gate = if base then base:FindFirstChild("LockGate") else nil
			if gate and gate:IsA("BasePart") then
				gate.Transparency = 1
				gate.CanCollide = false
			end
			EconomyService.PushState(player)
		end
	end)
	EconomyService.PushState(player)
	return true
end

local function onPadTouched(player: Player, hit: BasePart)
	local character = hit.Parent
	if not character or not character:IsA("Model") then
		return
	end
	if Players:GetPlayerFromCharacter(character) ~= player then
		return
	end
	local now = os.clock()
	if now - (lastPadCollect[player] or 0) < 1 then
		return -- rate limit pad: 1x per detik
	end
	lastPadCollect[player] = now
	local gained = EconomyService.Collect(player)
	if gained > 0 then
		EconomyService.Notify(player, "collect", ("+ %d terkumpul!"):format(gained))
	end
end

-- Assign base kosong ke pemain, sambungkan pad, gambar slot dari datanya.
function BaseService.Assign(player: Player): Model?
	local basesFolder = Workspace:WaitForChild("Bases")
	for index = 1, Config.BaseCount do
		local base = basesFolder:FindFirstChild("Base_" .. index)
		if base and base:IsA("Model") and not playerByBase[base] then
			baseByPlayer[player] = base
			playerByBase[base] = player
			base:SetAttribute("OwnerUserId", player.UserId)
			local sign = base:FindFirstChild("SignPost")
			local signGui = if sign then sign:FindFirstChild("SignGui") else nil
			local signLabel = if signGui then signGui:FindFirstChild("OwnerLabel") else nil
			if signLabel and signLabel:IsA("TextLabel") then
				signLabel.Text = "Base " .. player.DisplayName
			end
			local pad = base:FindFirstChild("CollectPad")
			if pad and pad:IsA("BasePart") then
				(pad :: BasePart).Touched:Connect(function(hit: BasePart)
					onPadTouched(player, hit)
				end)
			end
			BaseService.RenderAllSlots(player)
			return base
		end
	end
	warn("[BaseService] Pool base habis untuk " .. player.Name)
	return nil
end

-- Teleport karakter pemain ke SpawnPoint base-nya sendiri.
function BaseService.TeleportHome(player: Player)
	local base = baseByPlayer[player]
	local character = player.Character
	if not base or not character then
		return
	end
	local spawnPoint = base:FindFirstChild("SpawnPoint")
	if spawnPoint and spawnPoint:IsA("BasePart") then
		character:PivotTo((spawnPoint :: BasePart).CFrame * CFrame.new(0, 3, 0))
	end
end

function BaseService.Release(player: Player)
	local base = baseByPlayer[player]
	if base then
		for slotIndex = 1, Config.MaxSlots do
			local slotPart = base:FindFirstChild("Slot_" .. slotIndex)
			local occupant = if slotPart then slotPart:FindFirstChild("Occupant") else nil
			if occupant then
				occupant:Destroy()
			end
		end
		local gate = base:FindFirstChild("LockGate")
		if gate and gate:IsA("BasePart") then
			gate.Transparency = 1
			gate.CanCollide = false
		end
		local sign = base:FindFirstChild("SignPost")
		local signGui = if sign then sign:FindFirstChild("SignGui") else nil
		local signLabel = if signGui then signGui:FindFirstChild("OwnerLabel") else nil
		if signLabel and signLabel:IsA("TextLabel") then
			signLabel.Text = "Base kosong"
		end
		base:SetAttribute("OwnerUserId", 0)
		playerByBase[base] = nil
	end
	baseByPlayer[player] = nil
	lockEndsAt[player] = nil
	lockCooldownEndsAt[player] = nil
	lastPadCollect[player] = nil
end

return BaseService
