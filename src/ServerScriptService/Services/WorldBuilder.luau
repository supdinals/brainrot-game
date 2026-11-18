--!strict
-- WorldBuilder.luau -- membangun seluruh dunia dari kode saat server start:
-- tanah bertema jalanan Indonesia, pool base (Workspace/Bases/Base_1..N dengan
-- Slot_1..Slot_10, CollectPad, LockGate), conveyor (Workspace/Conveyor),
-- lane ombak (Workspace/WaveLane), zona aman (Workspace/SafeZones, tag
-- "SafeZone"), spawn location, dan pencahayaan. Tidak ada aset dari luar:
-- semua Part dibuat di sini supaya place bisa dibangun penuh lewat Rojo.

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local WorldBuilder = {}

local function makePart(name: string, size: Vector3, position: Vector3, color: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Position = position
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

-- Satu base: lantai warung, dinding rendah, 10 slot berjajar 2 baris,
-- CollectPad di tengah, LockGate di pintu masuk, papan nama pemilik.
local function buildBase(index: number, center: Vector3): Model
	local base = Instance.new("Model")
	base.Name = "Base_" .. index
	base:SetAttribute("BaseIndex", index)
	base:SetAttribute("OwnerUserId", 0)

	local floor = makePart("Floor", Vector3.new(36, 1, 28), center + Vector3.new(0, 0.5, 0), Color3.fromRGB(196, 168, 120), Enum.Material.WoodPlanks)
	floor.Parent = base

	-- Dinding belakang dan samping (depan terbuka untuk gerbang).
	local back = makePart("BackWall", Vector3.new(36, 6, 1), center + Vector3.new(0, 3.5, -13.5), Color3.fromRGB(140, 96, 60), Enum.Material.Wood)
	back.Parent = base
	local left = makePart("LeftWall", Vector3.new(1, 6, 28), center + Vector3.new(-17.5, 3.5, 0), Color3.fromRGB(140, 96, 60), Enum.Material.Wood)
	left.Parent = base
	local right = makePart("RightWall", Vector3.new(1, 6, 28), center + Vector3.new(17.5, 3.5, 0), Color3.fromRGB(140, 96, 60), Enum.Material.Wood)
	right.Parent = base

	-- Atap warung sederhana.
	local roof = makePart("Roof", Vector3.new(38, 0.6, 30), center + Vector3.new(0, 8, 0), Color3.fromRGB(178, 60, 44), Enum.Material.Metal)
	roof.Parent = base

	-- Slot_1..Slot_10: dua baris lima, penanda posisi karakter.
	for slotIndex = 1, 10 do
		local row = if slotIndex <= 5 then 0 else 1
		local col = (slotIndex - 1) % 5
		local slotPos = center + Vector3.new(-12 + col * 6, 1.1, -6 + row * 9)
		local slot = makePart("Slot_" .. slotIndex, Vector3.new(4.4, 0.2, 4.4), slotPos, Color3.fromRGB(90, 90, 96), Enum.Material.SmoothPlastic)
		slot:SetAttribute("SlotIndex", slotIndex)
		slot.Parent = base
		local billboard = Instance.new("BillboardGui")
		billboard.Name = "SlotLabel"
		billboard.Size = UDim2.fromOffset(140, 36)
		billboard.StudsOffset = Vector3.new(0, 2.2, 0)
		billboard.AlwaysOnTop = false
		local label = Instance.new("TextLabel")
		label.Name = "Text"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Text = "Slot kosong"
		label.TextColor3 = Color3.fromRGB(230, 230, 230)
		label.TextScaled = true
		label.Font = Enum.Font.Gotham
		label.Parent = billboard
		billboard.Parent = slot
	end

	-- Pad Collect: pemain menginjaknya untuk mengambil pendapatan.
	local pad = makePart("CollectPad", Vector3.new(6, 0.4, 6), center + Vector3.new(0, 1.2, 9), Color3.fromRGB(60, 200, 90), Enum.Material.Neon)
	pad:SetAttribute("IsCollectPad", true)
	pad.Parent = base
	local padBillboard = Instance.new("BillboardGui")
	padBillboard.Name = "PadLabel"
	padBillboard.Size = UDim2.fromOffset(160, 40)
	padBillboard.StudsOffset = Vector3.new(0, 3, 0)
	local padLabel = Instance.new("TextLabel")
	padLabel.Name = "Text"
	padLabel.Size = UDim2.fromScale(1, 1)
	padLabel.BackgroundTransparency = 1
	padLabel.Text = "COLLECT"
	padLabel.TextColor3 = Color3.fromRGB(120, 255, 150)
	padLabel.TextScaled = true
	padLabel.Font = Enum.Font.GothamBold
	padLabel.Parent = padBillboard
	padBillboard.Parent = pad

	-- Gerbang kunci: muncul (CanCollide) hanya saat base dikunci.
	local gate = makePart("LockGate", Vector3.new(20, 7, 0.8), center + Vector3.new(0, 3.5, 14), Color3.fromRGB(255, 170, 40), Enum.Material.Metal)
	gate.Transparency = 1
	gate.CanCollide = false
	gate:SetAttribute("IsLockGate", true)
	gate.Parent = base

	-- Papan nama base di atas gerbang.
	local sign = makePart("SignPost", Vector3.new(14, 2.4, 0.4), center + Vector3.new(0, 8.6, 14), Color3.fromRGB(50, 50, 60), Enum.Material.SmoothPlastic)
	sign.Parent = base
	local signGui = Instance.new("SurfaceGui")
	signGui.Name = "SignGui"
	signGui.Face = Enum.NormalId.Front
	local signLabel = Instance.new("TextLabel")
	signLabel.Name = "OwnerLabel"
	signLabel.Size = UDim2.fromScale(1, 1)
	signLabel.BackgroundTransparency = 1
	signLabel.Text = "Base " .. index
	signLabel.TextColor3 = Color3.fromRGB(255, 220, 120)
	signLabel.TextScaled = true
	signLabel.Font = Enum.Font.GothamBold
	signLabel.Parent = signGui
	signGui.Parent = sign

	-- Titik spawn pemilik base.
	local spawnPoint = makePart("SpawnPoint", Vector3.new(4, 0.4, 4), center + Vector3.new(10, 1.2, 9), Color3.fromRGB(80, 160, 255), Enum.Material.SmoothPlastic)
	spawnPoint.Transparency = 0.4
	spawnPoint.CanCollide = false
	spawnPoint.Parent = base

	base.PrimaryPart = floor
	base.Parent = Workspace:WaitForChild("Bases")
	return base
end

function WorldBuilder.Build()
	-- Folder dunia.
	for _, folderName in { "Bases", "Conveyor", "WaveLane", "SafeZones" } do
		if not Workspace:FindFirstChild(folderName) then
			local folder = Instance.new("Folder")
			folder.Name = folderName
			folder.Parent = Workspace
		end
	end

	-- Tanah: jalan aspal memanjang dengan trotoar, diapit deretan base.
	local ground = makePart("Ground", Vector3.new(760, 2, 260), Vector3.new(0, -1, 0), Color3.fromRGB(96, 140, 78), Enum.Material.Grass)
	ground.Parent = Workspace
	local road = makePart("JalanRaya", Vector3.new(760, 0.3, 26), Vector3.new(0, 0.15, 0), Color3.fromRGB(52, 52, 58), Enum.Material.Asphalt)
	road.Parent = Workspace

	-- Pool base: setengah di sisi utara jalan, setengah di selatan.
	local basesFolder = Workspace:WaitForChild("Bases")
	for index = 1, Config.BaseCount do
		local side = if index % 2 == 1 then -1 else 1
		local column = math.ceil(index / 2)
		local x = (column - (Config.BaseCount / 4) - 0.5) * Config.BaseSpacing
		local center = Vector3.new(x, 0, side * 62)
		if side == 1 then
			center = Vector3.new(x, 0, 62)
		end
		buildBase(index, center)
		-- Zona aman menutupi seluruh area base.
		local zone = makePart("SafeZone_" .. index, Vector3.new(44, 16, 36), center + Vector3.new(0, 8, 0), Color3.fromRGB(80, 255, 140), Enum.Material.SmoothPlastic)
		zone.Transparency = 1
		zone.CanCollide = false
		zone.CanQuery = false
		CollectionService:AddTag(zone, "SafeZone")
		zone.Parent = Workspace:WaitForChild("SafeZones")
	end
	-- Zona aman tambahan di sepanjang conveyor supaya pembeli tidak tersapu.
	local conveyorZone = makePart("SafeZone_Conveyor", Vector3.new(210, 16, 20), Vector3.new(0, 8, 0), Color3.fromRGB(80, 255, 140), Enum.Material.SmoothPlastic)
	conveyorZone.Transparency = 1
	conveyorZone.CanCollide = false
	conveyorZone.CanQuery = false
	CollectionService:AddTag(conveyorZone, "SafeZone")
	conveyorZone.Parent = Workspace:WaitForChild("SafeZones")

	-- Conveyor di tengah jalan: sabuk panjang, titik spawn barat, titik akhir timur.
	local conveyor = Workspace:WaitForChild("Conveyor")
	local belt = makePart("Belt", Vector3.new(200, 1.4, 10), Vector3.new(0, 0.7, 0), Color3.fromRGB(40, 40, 48), Enum.Material.DiamondPlate)
	belt.Parent = conveyor
	local spawnPoint = makePart("SpawnPoint", Vector3.new(2, 2, 2), Vector3.new(-98, 2.6, 0), Color3.fromRGB(255, 255, 255), Enum.Material.Neon)
	spawnPoint.Transparency = 1
	spawnPoint.CanCollide = false
	spawnPoint.Parent = conveyor
	local endPoint = makePart("EndPoint", Vector3.new(2, 2, 2), Vector3.new(98, 2.6, 0), Color3.fromRGB(255, 255, 255), Enum.Material.Neon)
	endPoint.Transparency = 1
	endPoint.CanCollide = false
	endPoint.Parent = conveyor
	-- Papan besar di atas conveyor.
	local board = makePart("ConveyorSign", Vector3.new(40, 4, 0.5), Vector3.new(0, 11, -6), Color3.fromRGB(50, 50, 60), Enum.Material.SmoothPlastic)
	board.Parent = conveyor
	local boardGui = Instance.new("SurfaceGui")
	boardGui.Face = Enum.NormalId.Front
	local boardLabel = Instance.new("TextLabel")
	boardLabel.Size = UDim2.fromScale(1, 1)
	boardLabel.BackgroundTransparency = 1
	boardLabel.Text = "CONVEYOR BRAINROT - BELI DI SINI!"
	boardLabel.TextColor3 = Color3.fromRGB(255, 230, 120)
	boardLabel.TextScaled = true
	boardLabel.Font = Enum.Font.GothamBold
	boardLabel.Parent = boardGui
	boardGui.Parent = board

	-- Lane ombak sejajar jalan di sisi selatan, menyapu dari barat ke timur.
	local waveLane = Workspace:WaitForChild("WaveLane")
	local waveStart = makePart("WaveStart", Vector3.new(2, 2, 2), Vector3.new(-320, 4, 30), Color3.fromRGB(255, 255, 255), Enum.Material.Neon)
	waveStart.Transparency = 1
	waveStart.CanCollide = false
	waveStart.Parent = waveLane
	local waveEnd = makePart("WaveEnd", Vector3.new(2, 2, 2), Vector3.new(320, 4, 30), Color3.fromRGB(255, 255, 255), Enum.Material.Neon)
	waveEnd.Transparency = 1
	waveEnd.CanCollide = false
	waveEnd.Parent = waveLane

	-- Model ombak: dinding air besar yang digerakkan WaveService.
	local wave = makePart("WaveModel", Vector3.new(10, 14, 190), Vector3.new(-340, 7, 30), Color3.fromRGB(50, 130, 255), Enum.Material.Glass)
	wave.Transparency = 0.35
	wave.CanCollide = false
	wave:SetAttribute("IsWave", true)
	wave.Parent = waveLane

	-- SpawnLocation global (fallback sebelum pemain dapat base).
	local spawnLocation = Instance.new("SpawnLocation")
	spawnLocation.Name = "MainSpawn"
	spawnLocation.Size = Vector3.new(8, 1, 8)
	spawnLocation.Position = Vector3.new(0, 0.6, 20)
	spawnLocation.Color = Color3.fromRGB(255, 210, 80)
	spawnLocation.Material = Enum.Material.Neon
	spawnLocation.Anchored = true
	spawnLocation.Neutral = true
	spawnLocation.Parent = Workspace

	-- Dekorasi sederhana tema Indonesia: tiang lampu di sepanjang jalan.
	for x = -330, 330, 60 do
		local pole = makePart("TiangLampu", Vector3.new(0.6, 12, 0.6), Vector3.new(x, 6, 16), Color3.fromRGB(70, 70, 76), Enum.Material.Metal)
		pole.Parent = Workspace
		local lamp = makePart("Lampu", Vector3.new(2, 1, 2), Vector3.new(x, 12.4, 16), Color3.fromRGB(255, 240, 170), Enum.Material.Neon)
		lamp.Parent = Workspace
	end

	-- Pencahayaan siang cerah.
	Lighting.ClockTime = 13
	Lighting.Brightness = 2.4
	Lighting.Ambient = Color3.fromRGB(140, 140, 150)
	Lighting.GlobalShadows = true

	print(("[WorldBuilder] Dunia selesai: %d base, conveyor, lane ombak, zona aman."):format(Config.BaseCount))
end

return WorldBuilder
