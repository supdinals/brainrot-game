--!strict
-- EconomyService.luau -- uang pemain: pendapatan berbasis timestamp
-- (TANPA loop per detik), collect, tambah/kurang cash, leaderstats, dan
-- pengiriman state ke client lewat remote UpdateState. Semua angka dari
-- Config; client hanya menerima tampilan, tidak pernah menghitung uang.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Types = require(Shared:WaitForChild("Types"))

type PlayerData = Types.PlayerData

local EconomyService = {}

local DataService: any = nil
local getRemotes: (() -> Folder)? = nil
local lockStateProvider: ((player: Player) -> (number, number))? = nil
local carryingProvider: ((player: Player) -> boolean)? = nil

function EconomyService.Bind(dataService: any, remotesGetter: () -> Folder)
	DataService = dataService
	getRemotes = remotesGetter
end

-- Dipakai StealService/BaseService agar UpdateState bisa membawa status kunci.
function EconomyService.SetStateProviders(
	lockProvider: (player: Player) -> (number, number),
	carryProvider: (player: Player) -> boolean
)
	lockStateProvider = lockProvider
	carryingProvider = carryProvider
end

-- Total pendapatan/detik dari semua slot terisi.
function EconomyService.IncomePerSecond(data: PlayerData): number
	local total = 0
	for _, slot in data.Slots do
		total += Config.IncomeOf(slot.Rarity, slot.Mutation, data.Rebirths)
	end
	return total
end

-- Uang yang menunggu di base: income * detik sejak LastCollect, dibatasi Config.
function EconomyService.PendingIncome(data: PlayerData, now: number?): number
	local current = now or os.time()
	local elapsed = math.clamp(current - data.LastCollect, 0, Config.MaxStorageSeconds)
	return math.floor(EconomyService.IncomePerSecond(data) * elapsed)
end

-- Ambil pendapatan: hitung dari timestamp, tambah ke Cash, reset LastCollect.
function EconomyService.Collect(player: Player): number
	local data: PlayerData? = DataService.Get(player)
	if not data then
		return 0
	end
	local gained = EconomyService.PendingIncome(data)
	if gained > 0 then
		data.Cash += gained
		DataService.MarkDirty(player)
	end
	data.LastCollect = os.time()
	EconomyService.SyncLeaderstats(player)
	EconomyService.PushState(player)
	return gained
end

function EconomyService.CanAfford(data: PlayerData, price: number): boolean
	return data.Cash >= price
end

function EconomyService.Spend(player: Player, price: number): boolean
	local data: PlayerData? = DataService.Get(player)
	if not data or data.Cash < price then
		return false
	end
	data.Cash -= price
	DataService.MarkDirty(player)
	EconomyService.SyncLeaderstats(player)
	return true
end

function EconomyService.AddCash(player: Player, amount: number)
	local data: PlayerData? = DataService.Get(player)
	if not data then
		return
	end
	data.Cash += amount
	DataService.MarkDirty(player)
	EconomyService.SyncLeaderstats(player)
end

function EconomyService.SetupLeaderstats(player: Player, data: PlayerData)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local cash = Instance.new("IntValue")
	cash.Name = "Cash"
	cash.Value = data.Cash
	cash.Parent = leaderstats
	local rebirths = Instance.new("IntValue")
	rebirths.Name = "Rebirths"
	rebirths.Value = data.Rebirths
	rebirths.Parent = leaderstats
	leaderstats.Parent = player
end

function EconomyService.SyncLeaderstats(player: Player)
	local data: PlayerData? = DataService.Get(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not data or not leaderstats then
		return
	end
	local cash = leaderstats:FindFirstChild("Cash")
	if cash and cash:IsA("IntValue") then
		cash.Value = data.Cash
	end
	local rebirths = leaderstats:FindFirstChild("Rebirths")
	if rebirths and rebirths:IsA("IntValue") then
		rebirths.Value = data.Rebirths
	end
end

-- Kirim seluruh state publik milik pemain itu sendiri ke client-nya.
function EconomyService.PushState(player: Player)
	local data: PlayerData? = DataService.Get(player)
	if not data or not getRemotes then
		return
	end
	local lockEndsAt, lockCooldownEndsAt = 0, 0
	if lockStateProvider then
		lockEndsAt, lockCooldownEndsAt = lockStateProvider(player)
	end
	local nextSlotPrice: number? = nil
	if data.SlotCount < Config.MaxSlots then
		nextSlotPrice = Config.SlotPrice(data.SlotCount + 1)
	end
	local slotsCopy: { [number]: any } = {}
	for index, slot in data.Slots do
		slotsCopy[index] = { Id = slot.Id, Rarity = slot.Rarity, Mutation = slot.Mutation, PlacedAt = slot.PlacedAt }
	end
	local state: Types.PublicState & { Slots: any } = {
		Cash = data.Cash,
		Rebirths = data.Rebirths,
		SlotCount = data.SlotCount,
		IncomePerSecond = EconomyService.IncomePerSecond(data),
		Pending = EconomyService.PendingIncome(data),
		NextSlotPrice = nextSlotPrice,
		RebirthCost = Config.RebirthCost(data.Rebirths),
		RebirthMultiplier = Config.RebirthMultiplier(data.Rebirths),
		LockEndsAt = lockEndsAt,
		LockCooldownEndsAt = lockCooldownEndsAt,
		Carrying = if carryingProvider then carryingProvider(player) else false,
		Slots = slotsCopy,
	}
	local updateState = (getRemotes()):FindFirstChild("UpdateState")
	if updateState and updateState:IsA("RemoteEvent") then
		updateState:FireClient(player, state)
	end
end

function EconomyService.Notify(player: Player, kind: string, message: string)
	if not getRemotes then
		return
	end
	local notify = (getRemotes()):FindFirstChild("Notify")
	if notify and notify:IsA("RemoteEvent") then
		notify:FireClient(player, kind, message)
	end
end

return EconomyService
