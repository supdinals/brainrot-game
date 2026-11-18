--!strict
-- RebirthService.luau -- rebirth: syarat cash dari Config, reset Cash/Slots/
-- SlotCount ke awal, karakter Secret dipertahankan (Config.KeepSecretOnRebirth),
-- multiplier permanen 1 + 0.5 * Rebirths berlaku lewat Config.IncomeOf.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Types = require(Shared:WaitForChild("Types"))

type PlayerData = Types.PlayerData

local RebirthService = {}

local DataService: any = nil
local EconomyService: any = nil
local BaseService: any = nil

function RebirthService.Bind(dataService: any, economyService: any, baseService: any)
	DataService = dataService
	EconomyService = economyService
	BaseService = baseService
end

function RebirthService.TryRebirth(player: Player): boolean
	local data: PlayerData? = DataService.Get(player)
	if not data then
		return false
	end
	local cost = Config.RebirthCost(data.Rebirths)
	if data.Cash < cost then
		EconomyService.Notify(player, "error", "Uang belum cukup untuk rebirth!")
		return false
	end

	-- Simpan karakter Secret sebelum reset (dipertahankan sesuai Config).
	local kept: { Types.SlotData } = {}
	if Config.KeepSecretOnRebirth then
		for _, slot in data.Slots do
			if slot.Rarity == "Secret" then
				table.insert(kept, slot)
			end
		end
	end

	data.Rebirths += 1
	data.Cash = Config.StartCash
	data.SlotCount = Config.StartSlots
	data.Slots = {}
	data.LastCollect = os.time()

	-- Secret yang dipertahankan masuk lagi ke slot awal sebisanya.
	for _, slot in kept do
		local placed = false
		for slotIndex = 1, data.SlotCount do
			if not data.Slots[slotIndex] then
				data.Slots[slotIndex] = slot
				placed = true
				break
			end
		end
		if not placed then
			break
		end
	end

	DataService.MarkDirty(player)
	BaseService.RenderAllSlots(player)
	EconomyService.SyncLeaderstats(player)
	EconomyService.PushState(player)
	EconomyService.Notify(player, "rebirth", ("REBIRTH! Pengali pendapatan sekarang x%.1f"):format(Config.RebirthMultiplier(data.Rebirths)))
	return true
end

-- Beli slot berikutnya: harga Config.SlotPrice(SlotCount + 1).
function RebirthService.TryBuySlot(player: Player): boolean
	local data: PlayerData? = DataService.Get(player)
	if not data then
		return false
	end
	if data.SlotCount >= Config.MaxSlots then
		EconomyService.Notify(player, "error", "Slot sudah maksimum!")
		return false
	end
	local price = Config.SlotPrice(data.SlotCount + 1)
	if not EconomyService.Spend(player, price) then
		EconomyService.Notify(player, "error", "Uang tidak cukup untuk slot baru!")
		return false
	end
	data.SlotCount += 1
	DataService.MarkDirty(player)
	BaseService.RenderAllSlots(player)
	EconomyService.PushState(player)
	EconomyService.Notify(player, "success", ("Slot %d terbuka!"):format(data.SlotCount))
	return true
end

return RebirthService
