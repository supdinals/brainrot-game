--!strict
-- ConveyorService.luau -- conveyor global: spawn karakter tiap
-- Config.ConveyorSpawnInterval detik, rarity diundi dari bobot Config,
-- mutasi diundi dari peluang Config, karakter berjalan di sabuk dan dibuang
-- di ujung. Pembelian lewat ProximityPrompt "Beli" ATAU remote
-- BuyFromConveyor; server memeriksa uang, slot kosong, dan karakter masih
-- ada sebelum memindahkan kepemilikan.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local ConveyorService = {}

local DataService: any = nil
local EconomyService: any = nil
local BaseService: any = nil
local BrainrotFactory: any = nil

local alive: { [Model]: boolean } = {}
local aliveCount = 0
local rng = Random.new()

function ConveyorService.Bind(dataService: any, economyService: any, baseService: any, brainrotFactory: any)
	DataService = dataService
	EconomyService = economyService
	BaseService = baseService
	BrainrotFactory = brainrotFactory
end

-- Undi rarity dari bobot spawn Config (Secret hanya bila diizinkan Config).
function ConveyorService.RollRarity(): string
	local total = 0
	for _, name in Config.RarityOrder do
		if name == "Secret" and not Config.SecretOnConveyor then
			continue
		end
		total += Config.Rarities[name].Weight
	end
	local roll = rng:NextNumber(0, total)
	local cumulative = 0
	for _, name in Config.RarityOrder do
		if name == "Secret" and not Config.SecretOnConveyor then
			continue
		end
		cumulative += Config.Rarities[name].Weight
		if roll <= cumulative then
			return name
		end
	end
	return "Common"
end

-- Undi mutasi dari peluang Config (persen).
function ConveyorService.RollMutation(): string
	local roll = rng:NextNumber(0, 100)
	local cumulative = 0
	for _, name in Config.MutationOrder do
		cumulative += Config.Mutations[name].Chance
		if roll <= cumulative then
			return name
		end
	end
	return "Normal"
end

-- Pilih karakter acak dari rarity hasil undian.
function ConveyorService.RollCharacterId(rarity: string): string?
	local pool: { string } = {}
	for id, info in Config.Characters do
		if info.Rarity == rarity then
			table.insert(pool, id)
		end
	end
	if #pool == 0 then
		return nil
	end
	return pool[rng:NextInteger(1, #pool)]
end

local function buildConveyorBillboard(model: Model, id: string, rarity: string, mutation: string)
	local primary = model.PrimaryPart
	if not primary then
		return
	end
	local info = Config.Characters[id]
	local price = Config.Rarities[rarity].Price
	local income = Config.Rarities[rarity].Income * Config.Mutations[mutation].Multiplier
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "ShopBillboard"
	billboard.Size = UDim2.fromOffset(240, 84)
	billboard.StudsOffset = Vector3.new(0, 3.8, 0)
	billboard.AlwaysOnTop = true
	billboard.Adornee = primary
	local label = Instance.new("TextLabel")
	label.Name = "ShopInfo"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 0.3
	label.BackgroundColor3 = Color3.fromRGB(16, 16, 22)
	local priceText = if rarity == "Secret" then "LANGKA!" else ("Harga %d"):format(price)
	label.Text = ("%s [%s]\nMutasi %s - %.0f/detik\n%s"):format(info.DisplayName, rarity, mutation, income, priceText)
	label.TextColor3 = Config.Rarities[rarity].Color
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Parent = billboard
	billboard.Parent = model
end

local function spawnOne()
	if aliveCount >= Config.ConveyorMaxAlive then
		return
	end
	local conveyor = Workspace:WaitForChild("Conveyor")
	local spawnPoint = conveyor:FindFirstChild("SpawnPoint")
	if not spawnPoint or not spawnPoint:IsA("BasePart") then
		return
	end
	local rarity = ConveyorService.RollRarity()
	local mutation = ConveyorService.RollMutation()
	local id = ConveyorService.RollCharacterId(rarity)
	if not id then
		return
	end
	local model = BrainrotFactory.Clone(id)
	if not model then
		return
	end
	model:SetAttribute("Mutation", mutation)
	model:SetAttribute("Rarity", rarity)
	model:SetAttribute("State", "OnConveyor")
	model:SetAttribute("ConveyorId", id)
	model:PivotTo((spawnPoint :: BasePart).CFrame * CFrame.new(0, 0.2, 0))
	buildConveyorBillboard(model, id, rarity, mutation)

	local primary = model.PrimaryPart
	if primary then
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "BuyPrompt"
		prompt.ActionText = "Beli"
		prompt.ObjectText = Config.Characters[id].DisplayName
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt.Parent = primary
		prompt.Triggered:Connect(function(player: Player)
			ConveyorService.TryBuy(player, model)
		end)
	end
	model.Parent = conveyor
	alive[model] = true
	aliveCount += 1
end

local function despawn(model: Model)
	if alive[model] then
		alive[model] = nil
		aliveCount -= 1
	end
	model:Destroy()
end

-- Beli karakter conveyor: validasi penuh di server.
function ConveyorService.TryBuy(player: Player, model: Model): boolean
	if not alive[model] or model.Parent == nil then
		return false
	end
	local id = model:GetAttribute("ConveyorId")
	local rarity = model:GetAttribute("Rarity")
	local mutation = model:GetAttribute("Mutation")
	if typeof(id) ~= "string" or typeof(rarity) ~= "string" or typeof(mutation) ~= "string" then
		return false
	end
	if not Config.Characters[id] then
		return false
	end
	-- Jarak: pemain harus dekat dengan karakter yang dibeli.
	local character = player.Character
	local primary = model.PrimaryPart
	if character and primary then
		local root = character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") and (root.Position - primary.Position).Magnitude > 16 then
			return false
		end
	end
	local data = DataService.Get(player)
	if not data then
		return false
	end
	if not BaseService.FirstFreeSlot(data) then
		EconomyService.Notify(player, "error", "Slot penuh! Beli slot dulu.")
		return false
	end
	local price = Config.Rarities[rarity].Price
	if not EconomyService.Spend(player, price) then
		EconomyService.Notify(player, "error", "Uang tidak cukup!")
		return false
	end
	despawn(model)
	local placed = BaseService.PlaceInFirstFreeSlot(player, id, rarity, mutation)
	if not placed then
		EconomyService.AddCash(player, price) -- kembalikan bila ternyata gagal taruh
		return false
	end
	EconomyService.Notify(player, "success", ("Membeli %s [%s]!"):format(Config.Characters[id].DisplayName, rarity))
	return true
end

-- Beli lewat remote: client mengirim instance conveyor, server memvalidasi.
function ConveyorService.TryBuyByInstance(player: Player, instance: any): boolean
	if typeof(instance) ~= "Instance" or not instance:IsA("Model") then
		return false
	end
	return ConveyorService.TryBuy(player, instance :: Model)
end

function ConveyorService.Start()
	task.spawn(function()
		while true do
			task.wait(Config.ConveyorSpawnInterval)
			spawnOne()
		end
	end)
	-- Gerakkan semua karakter di sabuk ke arah EndPoint; buang yang sampai.
	RunService.Heartbeat:Connect(function(dt: number)
		local conveyor = Workspace:FindFirstChild("Conveyor")
		local endPoint = if conveyor then conveyor:FindFirstChild("EndPoint") else nil
		if not endPoint or not endPoint:IsA("BasePart") then
			return
		end
		local endX = (endPoint :: BasePart).Position.X
		for model in alive do
			local primary = model.PrimaryPart
			if not primary then
				despawn(model)
				continue
			end
			local step = Config.ConveyorSpeed * dt
			model:PivotTo(model:GetPivot() * CFrame.new(step, 0, 0))
			if primary.Position.X >= endX then
				despawn(model)
			end
		end
	end)
end

return ConveyorService
