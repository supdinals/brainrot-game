-- Main.server.luau -- titik masuk server: bangun dunia, buat placeholder
-- karakter, buat semua Remote di ReplicatedStorage/Remotes, inisialisasi
-- service, dan tangani join/leave pemain. Semua remote divalidasi tipe
-- argumennya dan di-rate-limit per pemain di sini.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Services = script.Parent:WaitForChild("Services")
local WorldBuilder = require(Services:WaitForChild("WorldBuilder"))
local BrainrotFactory = require(Services:WaitForChild("BrainrotFactory"))
local AssetAudit = require(Services:WaitForChild("AssetAudit"))
local DataService = require(Services:WaitForChild("DataService"))
local EconomyService = require(Services:WaitForChild("EconomyService"))
local BaseService = require(Services:WaitForChild("BaseService"))
local ConveyorService = require(Services:WaitForChild("ConveyorService"))
local RebirthService = require(Services:WaitForChild("RebirthService"))
local StealService = require(Services:WaitForChild("StealService"))
local WaveService = require(Services:WaitForChild("WaveService"))

-- Remotes: dibuat server saat start di ReplicatedStorage/Remotes.
local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local function ensureRemote(name: string, className: string): Instance
	local existing = remotesFolder:FindFirstChild(name)
	if existing then
		return existing
	end
	local remote = Instance.new(className)
	remote.Name = name
	remote.Parent = remotesFolder
	return remote
end
ensureRemote("Collect", "RemoteEvent")
ensureRemote("BuyFromConveyor", "RemoteEvent")
ensureRemote("BuySlot", "RemoteEvent")
ensureRemote("Rebirth", "RemoteEvent")
ensureRemote("LockBase", "RemoteEvent")
ensureRemote("UpdateState", "RemoteEvent")
ensureRemote("Notify", "RemoteEvent")
ensureRemote("WaveWarning", "RemoteEvent")

local function getRemotes(): Folder
	return remotesFolder
end

-- Dunia dan aset placeholder lebih dulu, sebelum pemain masuk.
WorldBuilder.Build()
BrainrotFactory.EnsurePlaceholders()

-- Ikat service satu sama lain.
DataService.Init()
EconomyService.Bind(DataService, getRemotes)
EconomyService.SetStateProviders(function(player: Player)
	return BaseService.LockState(player)
end, function(player: Player)
	return StealService.IsCarrying(player)
end)
BaseService.Bind(DataService, EconomyService, BrainrotFactory)
BaseService.SetStealPromptHandler(function(thief: Player, owner: Player, slotIndex: number)
	StealService.TrySteal(thief, owner, slotIndex)
end)
ConveyorService.Bind(DataService, EconomyService, BaseService, BrainrotFactory)
RebirthService.Bind(DataService, EconomyService, BaseService)
StealService.Bind(DataService, EconomyService, BaseService, BrainrotFactory)
WaveService.Bind(EconomyService, BaseService, StealService, getRemotes)

-- Rate limit sederhana per pemain per remote (detik antar panggilan sah).
local lastCall: { [Player]: { [string]: number } } = {}
local RATE_LIMITS = { Collect = 1, BuyFromConveyor = 0.4, BuySlot = 0.5, Rebirth = 1, LockBase = 0.5 }
local function rateOk(player: Player, name: string): boolean
	local now = os.clock()
	lastCall[player] = lastCall[player] or {}
	local last = lastCall[player][name] or 0
	if now - last < (RATE_LIMITS[name] or 0.3) then
		return false
	end
	lastCall[player][name] = now
	return true
end

local function bindRemote(name: string, handler: (player: Player, ...any) -> ())
	local remote = remotesFolder:FindFirstChild(name)
	if remote and remote:IsA("RemoteEvent") then
		(remote :: RemoteEvent).OnServerEvent:Connect(function(player: Player, ...: any)
			if not rateOk(player, name) then
				return
			end
			handler(player, ...)
		end)
	end
end

bindRemote("Collect", function(player: Player)
	-- Collect hanya sah untuk pemilik base itu sendiri; data selalu milik pengirim.
	local gained = EconomyService.Collect(player)
	if gained > 0 then
		EconomyService.Notify(player, "collect", ("+ %d terkumpul!"):format(gained))
	end
end)
bindRemote("BuyFromConveyor", function(player: Player, target: any)
	ConveyorService.TryBuyByInstance(player, target)
end)
bindRemote("BuySlot", function(player: Player)
	RebirthService.TryBuySlot(player)
end)
bindRemote("Rebirth", function(player: Player)
	RebirthService.TryRebirth(player)
end)
bindRemote("LockBase", function(player: Player)
	if BaseService.LockBase(player) then
		EconomyService.Notify(player, "success", "Base dikunci 60 detik!")
	else
		EconomyService.Notify(player, "error", "Kunci base masih cooldown!")
	end
end)

local function onPlayerAdded(player: Player)
	local data = DataService.Load(player)
	EconomyService.SetupLeaderstats(player, data)
	BaseService.Assign(player)
	EconomyService.PushState(player)
	player.CharacterAdded:Connect(function()
		StealService.WatchCharacter(player)
		task.wait(0.4)
		BaseService.TeleportHome(player)
	end)
	if player.Character then
		StealService.WatchCharacter(player)
		BaseService.TeleportHome(player)
	end
end

local function onPlayerRemoving(player: Player)
	StealService.OnThiefGone(player, "pencuri keluar")
	StealService.OnOwnerLeft(player)
	BaseService.Release(player)
	DataService.Release(player)
	lastCall[player] = nil
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

DataService.StartAutosave()
ConveyorService.Start()
StealService.Start()
WaveService.Start()

if RunService:IsStudio() then
	AssetAudit.Run()
end

print("[Brainrot] Server siap: dunia, conveyor, pencurian, ombak, dan ekonomi aktif.")
