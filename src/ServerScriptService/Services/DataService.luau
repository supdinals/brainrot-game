--!strict
-- DataService.luau -- kepemilikan data pemain: muat/simpan DataStore,
-- autosave 60 detik, simpan saat PlayerRemoving dan BindToClose.
-- Hanya data primitif yang disimpan (tidak ada referensi Instance).
-- Di Studio tanpa akses API, DataStore gagal secara aman dan data sesi
-- tetap berjalan di memori supaya playtest tetap bisa dilakukan.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Types = require(Shared:WaitForChild("Types"))

type PlayerData = Types.PlayerData

local DataService = {}

local store: DataStore? = nil
local sessions: { [Player]: PlayerData } = {}
local dirty: { [Player]: boolean } = {}

local function defaultData(): PlayerData
	return {
		Cash = Config.StartCash,
		Rebirths = 0,
		SlotCount = Config.StartSlots,
		Slots = {},
		LastCollect = os.time(),
		Version = Config.DataVersion,
	}
end

-- Salin data mentah dari DataStore ke bentuk PlayerData yang aman,
-- membuang field yang rusak dan mengisi yang hilang dengan default.
local function sanitize(raw: any): PlayerData
	local data = defaultData()
	if typeof(raw) ~= "table" then
		return data
	end
	if typeof(raw.Cash) == "number" and raw.Cash >= 0 then
		data.Cash = math.floor(raw.Cash)
	end
	if typeof(raw.Rebirths) == "number" and raw.Rebirths >= 0 then
		data.Rebirths = math.floor(raw.Rebirths)
	end
	if typeof(raw.SlotCount) == "number" then
		data.SlotCount = math.clamp(math.floor(raw.SlotCount), Config.StartSlots, Config.MaxSlots)
	end
	if typeof(raw.LastCollect) == "number" and raw.LastCollect > 0 then
		data.LastCollect = raw.LastCollect
	end
	if typeof(raw.Slots) == "table" then
		for key, slot in raw.Slots do
			local index = tonumber(key)
			if index and index >= 1 and index <= Config.MaxSlots and typeof(slot) == "table" then
				if typeof(slot.Id) == "string" and Config.Characters[slot.Id]
					and typeof(slot.Rarity) == "string" and Config.Rarities[slot.Rarity]
					and typeof(slot.Mutation) == "string" and Config.Mutations[slot.Mutation] then
					data.Slots[index] = {
						Id = slot.Id,
						Rarity = slot.Rarity,
						Mutation = slot.Mutation,
						PlacedAt = if typeof(slot.PlacedAt) == "number" then slot.PlacedAt else os.time(),
					}
				end
			end
		end
	end
	data.Version = Config.DataVersion
	return data
end

local function keyFor(player: Player): string
	return "player_" .. player.UserId
end

function DataService.Init()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.DataStoreName)
	end)
	if ok then
		store = result
	else
		warn("[DataService] DataStore tidak tersedia (Studio tanpa API access?): data hanya di memori sesi ini.")
	end
end

function DataService.Load(player: Player): PlayerData
	local data = defaultData()
	if store then
		local ok, raw = pcall(function()
			return (store :: DataStore):GetAsync(keyFor(player))
		end)
		if ok and raw ~= nil then
			data = sanitize(raw)
		elseif not ok then
			warn("[DataService] Gagal memuat data " .. player.Name .. ", memakai data sesi kosong.")
		end
	end
	-- Pendapatan tidak menumpuk tanpa batas saat pemain offline.
	local now = os.time()
	if now - data.LastCollect > Config.MaxStorageSeconds then
		data.LastCollect = now - Config.MaxStorageSeconds
	end
	sessions[player] = data
	dirty[player] = false
	return data
end

function DataService.Get(player: Player): PlayerData?
	return sessions[player]
end

function DataService.MarkDirty(player: Player)
	if sessions[player] then
		dirty[player] = true
	end
end

function DataService.Save(player: Player): boolean
	local data = sessions[player]
	if not data or not store then
		return false
	end
	local ok, err = pcall(function()
		(store :: DataStore):UpdateAsync(keyFor(player), function()
			return data
		end)
	end)
	if ok then
		dirty[player] = false
	else
		warn("[DataService] Gagal menyimpan data " .. player.Name .. ": " .. tostring(err))
	end
	return ok
end

function DataService.Release(player: Player)
	DataService.Save(player)
	sessions[player] = nil
	dirty[player] = nil
end

-- Autosave berkala + simpan semua saat server ditutup.
function DataService.StartAutosave()
	task.spawn(function()
		while true do
			task.wait(Config.AutosaveSeconds)
			for player in sessions do
				if dirty[player] then
					DataService.Save(player)
				end
			end
		end
	end)
	game:BindToClose(function()
		for player in sessions do
			DataService.Save(player)
		end
		if not RunService:IsStudio() then
			task.wait(2)
		end
	end)
end

return DataService
