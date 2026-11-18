--!strict
-- Config.luau -- SATU-SATUNYA tempat angka balance game Brainrot.
-- Semua service membaca angka dari sini; tidak ada angka ekonomi yang
-- di-hardcode di script lain. Karakter, rarity, mutasi, slot, rebirth,
-- conveyor, pencurian, kunci base, ombak, dan ikon UI terdaftar di sini.

local Config = {}

-- Rarity: pendapatan/detik, harga beli, bobot spawn conveyor, warna placeholder.
Config.Rarities = {
	Common = { Income = 1, Price = 50, Weight = 60, Color = Color3.fromRGB(150, 150, 150), Height = 3 },
	Rare = { Income = 5, Price = 400, Weight = 25, Color = Color3.fromRGB(60, 120, 255), Height = 3.5 },
	Epic = { Income = 25, Price = 3000, Weight = 10, Color = Color3.fromRGB(160, 60, 220), Height = 4 },
	Legendary = { Income = 150, Price = 25000, Weight = 4, Color = Color3.fromRGB(255, 190, 40), Height = 4.5 },
	Mythic = { Income = 1000, Price = 250000, Weight = 0.9, Color = Color3.fromRGB(230, 40, 40), Height = 5 },
	Secret = { Income = 8000, Price = 0, Weight = 0.1, Color = Color3.fromRGB(255, 255, 255), Height = 6 },
}
Config.RarityOrder = { "Common", "Rare", "Epic", "Legendary", "Mythic", "Secret" }

-- Mutasi: diundi server saat karakter muncul di conveyor.
Config.Mutations = {
	Normal = { Chance = 80, Multiplier = 1 },
	Gold = { Chance = 12, Multiplier = 1.5 },
	Diamond = { Chance = 5, Multiplier = 2.5 },
	Rainbow = { Chance = 2.5, Multiplier = 5 },
	Void = { Chance = 0.5, Multiplier = 10 },
}
Config.MutationOrder = { "Normal", "Gold", "Diamond", "Rainbow", "Void" }

-- 13 karakter orisinal (nama model di ServerStorage/Brainrots = kunci tabel ini).
Config.Characters = {
	SendalJepitJoget = { DisplayName = "Sendal Jepit Joget", Rarity = "Common" },
	GalonGaib = { DisplayName = "Galon Gaib", Rarity = "Common" },
	CicakKebut = { DisplayName = "Cicak Kebut", Rarity = "Common" },
	TahuBulatTornado = { DisplayName = "Tahu Bulat Tornado", Rarity = "Rare" },
	KucingKulkas = { DisplayName = "Kucing Kulkas", Rarity = "Rare" },
	OjolOrbit = { DisplayName = "Ojol Orbit", Rarity = "Rare" },
	BaksoBazooka = { DisplayName = "Bakso Bazooka", Rarity = "Epic" },
	GentengGalau = { DisplayName = "Genteng Galau", Rarity = "Epic" },
	KopiKopyok = { DisplayName = "Kopi Kopyok", Rarity = "Epic" },
	NasiGorengNuklir = { DisplayName = "Nasi Goreng Nuklir", Rarity = "Legendary" },
	KasurKosmik = { DisplayName = "Kasur Kosmik", Rarity = "Legendary" },
	WartegWarp = { DisplayName = "Warteg Warp", Rarity = "Mythic" },
	SiPalingAbsurd = { DisplayName = "Si Paling Absurd", Rarity = "Secret" },
}

-- Ekonomi dasar.
Config.StartCash = 100
Config.StartSlots = 4
Config.MaxSlots = 10
Config.MaxStorageSeconds = 3600 -- pendapatan berhenti menumpuk setelah 1 jam
Config.SlotBasePrice = 5000 -- harga slot ke-n (n>=5): SlotBasePrice * SlotPriceGrowth^(n-5)
Config.SlotPriceGrowth = 3

-- Rebirth: syarat cash rebirth ke-n (n mulai 0): RebirthBaseCost * RebirthCostGrowth^n.
Config.RebirthBaseCost = 100000
Config.RebirthCostGrowth = 5
Config.RebirthMultiplierPer = 0.5 -- multiplier = 1 + 0.5 * Rebirths
Config.KeepSecretOnRebirth = true

-- Conveyor.
Config.ConveyorSpawnInterval = 3 -- detik antar spawn
Config.ConveyorSpeed = 6 -- studs/detik gerakan karakter di sabuk
Config.ConveyorMaxAlive = 8 -- karakter bersamaan maksimum di sabuk
Config.SecretOnConveyor = true -- Secret ikut undian dengan bobot sangat kecil

-- Pencurian dan kunci base.
Config.StealHoldDuration = 3 -- detik menahan ProximityPrompt "Curi"
Config.StealMaxDistance = 12 -- studs
Config.StealWalkSpeedFactor = 0.8 -- pembawa karakter berjalan 20% lebih lambat
Config.LockDuration = 60 -- detik base terkunci
Config.LockCooldown = 120 -- detik cooldown setelah kunci dibuka

-- Ombak.
Config.WaveMinInterval = 180 -- 3 menit
Config.WaveMaxInterval = 300 -- 5 menit
Config.WaveWarningSeconds = 15
Config.WaveSpeed = 22 -- studs/detik sapuan ombak

-- Data.
Config.DataStoreName = "BrainrotData_v1"
Config.DataVersion = 1
Config.AutosaveSeconds = 60

-- Dunia (dipakai WorldBuilder): jumlah base di pool dan jarak antar base.
Config.BaseCount = 10
Config.BaseSpacing = 70

-- Ikon UI: diisi pemilik dengan rbxassetid. Kosong = fallback teks di UI.
Config.Icons = {
	Coin = "",
	Lock = "",
	Rebirth = "",
	Steal = "",
	Wave = "",
	RarityBadge = {
		Common = "", Rare = "", Epic = "", Legendary = "", Mythic = "", Secret = "",
	},
}

-- Harga slot ke-n (n adalah nomor slot yang akan dibuka, 5..10).
function Config.SlotPrice(n: number): number
	return Config.SlotBasePrice * (Config.SlotPriceGrowth ^ (n - 5))
end

-- Syarat cash untuk rebirth berikutnya bila pemain sudah punya `rebirths` rebirth.
function Config.RebirthCost(rebirths: number): number
	return Config.RebirthBaseCost * (Config.RebirthCostGrowth ^ rebirths)
end

-- Pengali pendapatan permanen dari jumlah rebirth.
function Config.RebirthMultiplier(rebirths: number): number
	return 1 + Config.RebirthMultiplierPer * rebirths
end

-- Pendapatan/detik satu karakter: rarity * mutasi * rebirth.
function Config.IncomeOf(rarity: string, mutation: string, rebirths: number): number
	local r = Config.Rarities[rarity]
	local m = Config.Mutations[mutation]
	if not r or not m then
		return 0
	end
	return r.Income * m.Multiplier * Config.RebirthMultiplier(rebirths)
end

-- Helper ikon: nama sederhana ("Coin") atau "RarityBadge/<Rarity>".
function Config.GetIcon(name: string): string
	if string.sub(name, 1, 12) == "RarityBadge/" then
		return Config.Icons.RarityBadge[string.sub(name, 13)] or ""
	end
	local icon = (Config.Icons :: any)[name]
	if typeof(icon) == "string" then
		return icon
	end
	return ""
end

return Config
