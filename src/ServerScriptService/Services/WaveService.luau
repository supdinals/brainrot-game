--!strict
-- WaveService.luau -- ombak periodik: interval acak 3-5 menit dari Config,
-- peringatan 15 detik lewat remote WaveWarning, lalu Part ombak besar
-- menyapu lane dari WaveStart ke WaveEnd. Pemain di luar zona aman yang
-- tersentuh: respawn di base sendiri; karakter bawaan dikembalikan sesuai
-- aturan pencurian. Deteksi sentuhan dan zona aman semua di server.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local WaveService = {}

local EconomyService: any = nil
local BaseService: any = nil
local StealService: any = nil
local getRemotes: (() -> Folder)? = nil

local rng = Random.new()
local waveActive = false

function WaveService.Bind(economyService: any, baseService: any, stealService: any, remotesGetter: () -> Folder)
	EconomyService = economyService
	BaseService = baseService
	StealService = stealService
	getRemotes = remotesGetter
end

local function broadcastWaveWarning(secondsLeft: number)
	if not getRemotes then
		return
	end
	local remote = (getRemotes()):FindFirstChild("WaveWarning")
	if remote and remote:IsA("RemoteEvent") then
		remote:FireAllClients(secondsLeft)
	end
end

local function isInSafeZone(position: Vector3): boolean
	for _, zone in CollectionService:GetTagged("SafeZone") do
		if zone:IsA("BasePart") then
			local localPos = (zone :: BasePart).CFrame:PointToObjectSpace(position)
			local half = (zone :: BasePart).Size / 2
			if math.abs(localPos.X) <= half.X and math.abs(localPos.Y) <= half.Y + 4 and math.abs(localPos.Z) <= half.Z then
				return true
			end
		end
	end
	return false
end

WaveService.IsInSafeZone = isInSafeZone

-- Sapu satu ombak: gerakkan WaveModel melintasi lane, periksa pemain tiap langkah.
local function runWave()
	local waveLane = Workspace:WaitForChild("WaveLane")
	local wave = waveLane:FindFirstChild("WaveModel")
	local startPart = waveLane:FindFirstChild("WaveStart")
	local endPart = waveLane:FindFirstChild("WaveEnd")
	if not wave or not wave:IsA("BasePart") or not startPart or not startPart:IsA("BasePart") or not endPart or not endPart:IsA("BasePart") then
		return
	end
	waveActive = true
	local startPos = (startPart :: BasePart).Position
	local endPos = (endPart :: BasePart).Position
	local distance = (endPos - startPos).Magnitude
	local duration = distance / Config.WaveSpeed
	local elapsed = 0
	local hitDone: { [Player]: boolean } = {}
	local wavePart = wave :: BasePart
	wavePart.Position = Vector3.new(startPos.X, wavePart.Position.Y, wavePart.Position.Z)

	while elapsed < duration do
		local dt = task.wait()
		elapsed += dt
		local alpha = math.clamp(elapsed / duration, 0, 1)
		local x = startPos.X + (endPos.X - startPos.X) * alpha
		wavePart.Position = Vector3.new(x, wavePart.Position.Y, wavePart.Position.Z)
		-- Periksa pemain: dekat bidang ombak dan di luar zona aman = kena.
		for _, player in Players:GetPlayers() do
			if hitDone[player] then
				continue
			end
			local character = player.Character
			local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
			if root and root:IsA("BasePart") then
				local rootPos = (root :: BasePart).Position
				if math.abs(rootPos.X - x) < 7 and math.abs(rootPos.Z - wavePart.Position.Z) < wavePart.Size.Z / 2 then
					if not isInSafeZone(rootPos) then
						hitDone[player] = true
						StealService.OnThiefGone(player, "tersapu ombak")
						EconomyService.Notify(player, "wave", "Kena ombak! Kamu kembali ke base.")
						BaseService.TeleportHome(player)
					end
				end
			end
		end
	end
	wavePart.Position = Vector3.new(startPos.X - 20, wavePart.Position.Y, wavePart.Position.Z)
	waveActive = false
end

function WaveService.Start()
	task.spawn(function()
		while true do
			local waitSeconds = rng:NextNumber(Config.WaveMinInterval, Config.WaveMaxInterval)
			task.wait(waitSeconds)
			-- Fase peringatan: hitung mundur untuk UI semua pemain.
			for secondsLeft = Config.WaveWarningSeconds, 1, -1 do
				broadcastWaveWarning(secondsLeft)
				if secondsLeft == Config.WaveWarningSeconds then
					for _, player in Players:GetPlayers() do
						EconomyService.Notify(player, "wave", "OMBAK DATANG! Cepat pulang ke base!")
					end
				end
				task.wait(1)
			end
			broadcastWaveWarning(0)
			runWave()
		end
	end)
end

function WaveService.IsWaveActive(): boolean
	return waveActive
end

return WaveService
