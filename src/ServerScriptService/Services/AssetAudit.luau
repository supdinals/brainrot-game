--!strict
-- AssetAudit.luau -- audit aset untuk Studio (bukan game live): memeriksa
-- kelengkapan model karakter, base, conveyor, lane ombak, dan ikon, lalu
-- mencetak laporan OK / PERINGATAN / ERROR ke Output. Dipanggil Main saat
-- server start di Studio supaya masalah aset terlihat sejak awal.

local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local AssetAudit = {}

local function report(status: string, message: string)
	print(("[AssetAudit][%s] %s"):format(status, message))
end

function AssetAudit.Run()
	local errors = 0
	local warnings = 0

	-- Karakter: tiap entri Config harus punya model yang sehat.
	local folder = ServerStorage:FindFirstChild("Brainrots")
	if not folder then
		report("ERROR", "Folder ServerStorage/Brainrots tidak ada")
		errors += 1
	else
		for id, info in Config.Characters do
			local model = folder:FindFirstChild(id)
			if not model then
				report("ERROR", "Model karakter hilang: " .. id)
				errors += 1
				continue
			end
			if not (model:IsA("Model") and model.PrimaryPart) then
				report("ERROR", id .. ": PrimaryPart tidak ada")
				errors += 1
				continue
			end
			local primary = model.PrimaryPart
			if primary.CanCollide then
				report("PERINGATAN", id .. ": PrimaryPart CanCollide masih true")
				warnings += 1
			end
			if not primary.Anchored then
				report("PERINGATAN", id .. ": PrimaryPart belum Anchored")
				warnings += 1
			end
			for _, descendant in model:GetDescendants() do
				if descendant:IsA("Script") or descendant:IsA("LocalScript") or descendant:IsA("ModuleScript") then
					report("ERROR", id .. ": ada script di dalam model (" .. descendant.Name .. ") - tanya pemilik, jangan hapus sendiri")
					errors += 1
				end
			end
			local expected = Config.Rarities[info.Rarity].Height
			local height = primary.Size.Y
			if math.abs(height - expected) > expected * 0.6 then
				report("PERINGATAN", id .. ": tinggi model di luar rentang wajar rarity-nya")
				warnings += 1
			end
			report("OK", id .. " (" .. info.Rarity .. ")")
		end
		for _, child in folder:GetChildren() do
			if not Config.Characters[child.Name] then
				report("PERINGATAN", "Model tidak terdaftar di Config.Characters: " .. child.Name)
				warnings += 1
			end
		end
	end

	-- Lokasi dunia wajib (konvensi nama panduan aset Bagian 3).
	local bases = Workspace:FindFirstChild("Bases")
	if not bases then
		report("ERROR", "Workspace/Bases tidak ada")
		errors += 1
	else
		for index = 1, Config.BaseCount do
			local base = bases:FindFirstChild("Base_" .. index)
			if not base then
				report("ERROR", "Base_" .. index .. " hilang")
				errors += 1
				continue
			end
			for slotIndex = 1, 10 do
				if not base:FindFirstChild("Slot_" .. slotIndex) then
					report("ERROR", ("Base_%d kehilangan Slot_%d"):format(index, slotIndex))
					errors += 1
				end
			end
			if not base:FindFirstChild("CollectPad") then
				report("ERROR", "Base_" .. index .. " kehilangan CollectPad")
				errors += 1
			end
			if not base:FindFirstChild("LockGate") then
				report("ERROR", "Base_" .. index .. " kehilangan LockGate")
				errors += 1
			end
		end
		report("OK", "Pool base lengkap: " .. Config.BaseCount .. " base")
	end

	local conveyor = Workspace:FindFirstChild("Conveyor")
	if conveyor and conveyor:FindFirstChild("Belt") and conveyor:FindFirstChild("SpawnPoint") and conveyor:FindFirstChild("EndPoint") then
		report("OK", "Conveyor lengkap (Belt, SpawnPoint, EndPoint)")
	else
		report("ERROR", "Conveyor tidak lengkap")
		errors += 1
	end

	local waveLane = Workspace:FindFirstChild("WaveLane")
	if waveLane and waveLane:FindFirstChild("WaveStart") and waveLane:FindFirstChild("WaveEnd") then
		report("OK", "WaveLane lengkap (WaveStart, WaveEnd)")
	else
		report("ERROR", "WaveLane tidak lengkap")
		errors += 1
	end

	-- Ikon yang masih kosong (UI memakai fallback teks, bukan error).
	for name in { Coin = true, Lock = true, Rebirth = true, Steal = true, Wave = true } do
		if Config.GetIcon(name) == "" then
			report("PERINGATAN", "Ikon masih kosong (fallback teks dipakai): " .. name)
			warnings += 1
		end
	end

	print(("[AssetAudit] Selesai: %d ERROR, %d PERINGATAN"):format(errors, warnings))
	return errors, warnings
end

return AssetAudit
