-- UIController.client.luau -- seluruh UI client (brief Bagian 14):
-- satu ScreenGui ResetOnSpawn=false, semua ukuran Scale, HUD cash +
-- pendapatan/detik di kiri atas, rebirth di kanan atas, banner ombak di
-- tengah atas, tombol kunci base di kanan tengah, tombol Collect di bawah
-- tengah, antrean notifikasi (maks 3), panel rebirth modal dengan tombol
-- konfirmasi tahan 1 detik, indikator membawa karakter, sakelar suara,
-- dan layar muat sederhana. UI HANYA menampilkan data server (UpdateState);
-- tidak ada perhitungan uang yang menentukan apa pun di client.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local FormatNumber = require(Shared:WaitForChild("FormatNumber"))
local MutationVisuals = require(script.Parent:WaitForChild("MutationVisuals"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local function remote(name: string): RemoteEvent?
	local found = remotes:WaitForChild(name, 10)
	return if found and found:IsA("RemoteEvent") then found :: RemoteEvent else nil
end

local state: any = nil
local displayedCash = 0
local soundOn = true

local gui = Instance.new("ScreenGui")
gui.Name = "BrainrotGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.Parent = player:WaitForChild("PlayerGui")

local function makeLabel(name: string, size: UDim2, position: UDim2, text: string, textSize: number, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Size = size
	label.Position = position
	label.BackgroundTransparency = 0.35
	label.BackgroundColor3 = Color3.fromRGB(18, 18, 26)
	label.Text = text
	label.TextSize = textSize
	label.TextColor3 = color
	label.Font = Enum.Font.GothamBold
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = label
	return label
end

local function makeButton(name: string, size: UDim2, position: UDim2, text: string, color: Color3): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = size
	button.Position = position
	button.BackgroundColor3 = color
	button.Text = text
	button.TextSize = 18
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.Font = Enum.Font.GothamBold
	button.AutoButtonColor = true
	button.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = button
	return button
end

-- Layar muat sederhana (hilang saat state pertama tiba).
local loading = makeLabel("Loading", UDim2.fromScale(0.5, 0.12), UDim2.new(0.25, 0, 0.44, 0), "BRAINROT - memuat data...", 22, Color3.fromRGB(255, 220, 120))
loading.TextXAlignment = Enum.TextXAlignment.Center

-- Kiri atas: Cash besar + pendapatan/detik.
local coinIcon = Config.GetIcon("Coin")
local cashLabel = makeLabel("CashLabel", UDim2.fromScale(0.24, 0.055), UDim2.new(0.09, 0, 0.02, 0),
	(if coinIcon ~= "" then "" else "Koin ") .. "0", 26, Color3.fromRGB(120, 255, 150))
local incomeLabel = makeLabel("IncomeLabel", UDim2.fromScale(0.24, 0.04), UDim2.new(0.09, 0, 0.08, 0), "+0/detik", 16, Color3.fromRGB(200, 230, 200))

-- Kanan atas: jumlah rebirth + tombol buka panel.
local rebirthLabel = makeLabel("RebirthLabel", UDim2.fromScale(0.2, 0.05), UDim2.new(0.79, 0, 0.02, 0), "Rebirth: 0", 18, Color3.fromRGB(255, 210, 110))
rebirthLabel.TextXAlignment = Enum.TextXAlignment.Center
local rebirthButton = makeButton("RebirthButton", UDim2.fromScale(0.2, 0.055), UDim2.new(0.79, 0, 0.075, 0), "REBIRTH", Color3.fromRGB(190, 130, 30))

-- Tengah atas: banner ombak (hanya saat peringatan).
local waveBanner = makeLabel("WaveBanner", UDim2.fromScale(0.44, 0.06), UDim2.new(0.28, 0, 0.02, 0), "", 22, Color3.fromRGB(255, 120, 110))
waveBanner.TextXAlignment = Enum.TextXAlignment.Center
waveBanner.Visible = false
local waveBarBack = Instance.new("Frame")
waveBarBack.Name = "WaveBarBack"
waveBarBack.Size = UDim2.fromScale(0.44, 0.018)
waveBarBack.Position = UDim2.new(0.28, 0, 0.085, 0)
waveBarBack.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
waveBarBack.Visible = false
waveBarBack.Parent = gui
local waveBar = Instance.new("Frame")
waveBar.Name = "WaveBar"
waveBar.Size = UDim2.fromScale(1, 1)
waveBar.BackgroundColor3 = Color3.fromRGB(255, 90, 80)
waveBar.BorderSizePixel = 0
waveBar.Parent = waveBarBack

-- Vignette merah tipis saat ombak mendekat.
local vignette = Instance.new("Frame")
vignette.Name = "WaveVignette"
vignette.Size = UDim2.fromScale(1, 1)
vignette.BackgroundColor3 = Color3.fromRGB(255, 40, 30)
vignette.BackgroundTransparency = 0.88
vignette.BorderSizePixel = 0
vignette.Visible = false
vignette.Parent = gui

-- Kanan tengah: tombol kunci base.
local lockButton = makeButton("LockButton", UDim2.fromScale(0.16, 0.06), UDim2.new(0.83, 0, 0.47, 0), "Kunci Base", Color3.fromRGB(70, 110, 200))

-- Bawah tengah: tombol Collect + indikator membawa + tombol beli slot.
local collectButton = makeButton("CollectButton", UDim2.fromScale(0.26, 0.065), UDim2.new(0.37, 0, 0.86, 0), "COLLECT", Color3.fromRGB(40, 170, 80))
local carryLabel = makeLabel("CarryLabel", UDim2.fromScale(0.3, 0.05), UDim2.new(0.35, 0, 0.79, 0), "Bawa ke base!", 20, Color3.fromRGB(255, 170, 90))
carryLabel.TextXAlignment = Enum.TextXAlignment.Center
carryLabel.Visible = false
local buySlotButton = makeButton("BuySlotButton", UDim2.fromScale(0.2, 0.055), UDim2.new(0.02, 0, 0.86, 0), "Beli Slot", Color3.fromRGB(120, 80, 190))

-- Sakelar suara (kiri bawah, di atas area joystick dibuat kecil dan aman).
local soundButton = makeButton("SoundButton", UDim2.fromScale(0.11, 0.045), UDim2.new(0.02, 0, 0.79, 0), "Suara: ON", Color3.fromRGB(80, 80, 95))

-- Antrean notifikasi: maks 3 toast, tiap toast tampil 3 detik.
local toastHolder = Instance.new("Frame")
toastHolder.Name = "Toasts"
toastHolder.Size = UDim2.fromScale(0.4, 0.2)
toastHolder.Position = UDim2.new(0.3, 0, 0.14, 0)
toastHolder.BackgroundTransparency = 1
toastHolder.Parent = gui
local toastLayout = Instance.new("UIListLayout")
toastLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
toastLayout.Padding = UDim.new(0, 6)
toastLayout.Parent = toastHolder
local toastCount = 0
local TOAST_COLORS = {
	steal = Color3.fromRGB(220, 60, 50),
	success = Color3.fromRGB(50, 180, 90),
	collect = Color3.fromRGB(50, 180, 90),
	wave = Color3.fromRGB(220, 170, 40),
	rebirth = Color3.fromRGB(255, 190, 40),
	error = Color3.fromRGB(120, 120, 130),
}
local function showToast(kind: string, message: string)
	if toastCount >= 3 then
		local oldest = toastHolder:FindFirstChildOfClass("TextLabel")
		if oldest then
			oldest:Destroy()
			toastCount -= 1
		end
	end
	toastCount += 1
	local toast = Instance.new("TextLabel")
	toast.Name = "Toast"
	toast.Size = UDim2.new(1, 0, 0, 36)
	toast.BackgroundColor3 = TOAST_COLORS[kind] or TOAST_COLORS.error
	toast.BackgroundTransparency = 0.15
	toast.Text = message
	toast.TextSize = 16
	toast.TextColor3 = Color3.fromRGB(255, 255, 255)
	toast.Font = Enum.Font.GothamBold
	toast.Parent = toastHolder
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = toast
	task.delay(3, function()
		if toast.Parent then
			toast:Destroy()
			toastCount -= 1
		end
	end)
end

-- Panel Rebirth (modal).
local panel = Instance.new("Frame")
panel.Name = "RebirthPanel"
panel.Size = UDim2.fromScale(0.52, 0.52)
panel.Position = UDim2.new(0.24, 0, 0.24, 0)
panel.BackgroundColor3 = Color3.fromRGB(24, 24, 34)
panel.Visible = false
panel.Parent = gui
local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 14)
panelCorner.Parent = panel
local panelTitle = Instance.new("TextLabel")
panelTitle.Name = "Title"
panelTitle.Size = UDim2.fromScale(0.9, 0.14)
panelTitle.Position = UDim2.new(0.05, 0, 0.03, 0)
panelTitle.BackgroundTransparency = 1
panelTitle.Text = "REBIRTH"
panelTitle.TextSize = 30
panelTitle.TextColor3 = Color3.fromRGB(255, 205, 80)
panelTitle.Font = Enum.Font.GothamBold
panelTitle.Parent = panel
local panelBody = Instance.new("TextLabel")
panelBody.Name = "Body"
panelBody.Size = UDim2.fromScale(0.9, 0.5)
panelBody.Position = UDim2.new(0.05, 0, 0.18, 0)
panelBody.BackgroundTransparency = 1
panelBody.Text = ""
panelBody.TextSize = 17
panelBody.TextColor3 = Color3.fromRGB(235, 235, 235)
panelBody.Font = Enum.Font.Gotham
panelBody.TextWrapped = true
panelBody.TextYAlignment = Enum.TextYAlignment.Top
panelBody.Parent = panel
local progressBack = Instance.new("Frame")
progressBack.Name = "ProgressBack"
progressBack.Size = UDim2.fromScale(0.9, 0.07)
progressBack.Position = UDim2.new(0.05, 0, 0.68, 0)
progressBack.BackgroundColor3 = Color3.fromRGB(50, 50, 62)
progressBack.Parent = panel
local progressBar = Instance.new("Frame")
progressBar.Name = "ProgressBar"
progressBar.Size = UDim2.fromScale(0, 1)
progressBar.BackgroundColor3 = Color3.fromRGB(255, 190, 50)
progressBar.BorderSizePixel = 0
progressBar.Parent = progressBack
local confirmButton = Instance.new("TextButton")
confirmButton.Name = "ConfirmHold"
confirmButton.Size = UDim2.fromScale(0.55, 0.13)
confirmButton.Position = UDim2.new(0.05, 0, 0.8, 0)
confirmButton.BackgroundColor3 = Color3.fromRGB(200, 140, 30)
confirmButton.Text = "TAHAN 1 DETIK: REBIRTH"
confirmButton.TextSize = 17
confirmButton.TextColor3 = Color3.fromRGB(255, 255, 255)
confirmButton.Font = Enum.Font.GothamBold
confirmButton.Parent = panel
local cancelButton = Instance.new("TextButton")
cancelButton.Name = "Cancel"
cancelButton.Size = UDim2.fromScale(0.3, 0.13)
cancelButton.Position = UDim2.new(0.65, 0, 0.8, 0)
cancelButton.BackgroundColor3 = Color3.fromRGB(90, 90, 105)
cancelButton.Text = "Batal"
cancelButton.TextSize = 17
cancelButton.TextColor3 = Color3.fromRGB(255, 255, 255)
cancelButton.Font = Enum.Font.GothamBold
cancelButton.Parent = panel

local function refreshPanel()
	if not state then
		return
	end
	local cost = state.RebirthCost
	local nextMultiplier = 1 + 0.5 * (state.Rebirths + 1)
	panelBody.Text = ("Syarat: kumpulkan %s koin (sekarang %s).\n\nHadiah: pengali pendapatan permanen x%.1f.\n\nYang di-reset: Cash, semua karakter non-Secret, dan jumlah slot.\nYang dipertahankan: karakter Secret dan jumlah Rebirth.")
		:format(FormatNumber.Format(cost), FormatNumber.Format(state.Cash), nextMultiplier)
	progressBar.Size = UDim2.fromScale(math.clamp(state.Cash / math.max(cost, 1), 0, 1), 1)
end

-- Anti-spam tombol: nonaktif 0,3 detik setelah ditekan.
local function debounce(button: TextButton)
	button.Active = false
	task.delay(0.3, function()
		button.Active = true
	end)
end

collectButton.MouseButton1Click:Connect(function()
	debounce(collectButton)
	local r = remote("Collect")
	if r then
		r:FireServer()
	end
end)
lockButton.MouseButton1Click:Connect(function()
	debounce(lockButton)
	local r = remote("LockBase")
	if r then
		r:FireServer()
	end
end)
buySlotButton.MouseButton1Click:Connect(function()
	debounce(buySlotButton)
	local r = remote("BuySlot")
	if r then
		r:FireServer()
	end
end)
rebirthButton.MouseButton1Click:Connect(function()
	debounce(rebirthButton)
	refreshPanel()
	panel.Visible = not panel.Visible
end)
cancelButton.MouseButton1Click:Connect(function()
	panel.Visible = false
end)
soundButton.MouseButton1Click:Connect(function()
	soundOn = not soundOn
	soundButton.Text = if soundOn then "Suara: ON" else "Suara: OFF"
end)

-- Konfirmasi rebirth tahan 1 detik (cegah salah tekan).
local holding = false
confirmButton.MouseButton1Down:Connect(function()
	holding = true
	confirmButton.Text = "TAHAN..."
	task.delay(1, function()
		if holding and panel.Visible then
			local r = remote("Rebirth")
			if r then
				r:FireServer()
			end
			panel.Visible = false
			holding = false
			confirmButton.Text = "TAHAN 1 DETIK: REBIRTH"
		end
	end)
end)
confirmButton.MouseButton1Up:Connect(function()
	holding = false
	confirmButton.Text = "TAHAN 1 DETIK: REBIRTH"
end)

local function applyState(newState: any)
	state = newState
	loading.Visible = false
	-- Angka cash berubah halus (tween angka), pop hijau saat naik.
	local from = displayedCash
	local to = newState.Cash
	displayedCash = to
	if to > from then
		cashLabel.TextColor3 = Color3.fromRGB(140, 255, 160)
		local pop = TweenService:Create(cashLabel, TweenInfo.new(0.18), { TextSize = 30 })
		pop:Play()
		pop.Completed:Connect(function()
			cashLabel.TextSize = 26
		end)
	end
	cashLabel.Text = (if coinIcon ~= "" then "" else "Koin ") .. FormatNumber.Format(to)
	incomeLabel.Text = ("+%s/detik | Menunggu: %s"):format(FormatNumber.Format(newState.IncomePerSecond), FormatNumber.Format(newState.Pending))
	rebirthLabel.Text = ("Rebirth: %d (x%.1f)"):format(newState.Rebirths, newState.RebirthMultiplier)
	carryLabel.Visible = newState.Carrying == true
	if newState.NextSlotPrice then
		buySlotButton.Text = "Beli Slot (" .. FormatNumber.Format(newState.NextSlotPrice) .. ")"
		buySlotButton.Visible = true
	else
		buySlotButton.Visible = false
	end
	collectButton.Text = "COLLECT " .. FormatNumber.Format(newState.Pending)
	local now = os.time()
	if newState.LockEndsAt and newState.LockEndsAt > now then
		lockButton.Text = ("Terkunci %ds"):format(newState.LockEndsAt - now)
	elseif newState.LockCooldownEndsAt and newState.LockCooldownEndsAt > now then
		lockButton.Text = ("Kunci: %ds"):format(newState.LockCooldownEndsAt - now)
	else
		lockButton.Text = "Kunci Base"
	end
	if panel.Visible then
		refreshPanel()
	end
end

local updateState = remote("UpdateState")
if updateState then
	updateState.OnClientEvent:Connect(applyState)
end
local notify = remote("Notify")
if notify then
	notify.OnClientEvent:Connect(function(kind: any, message: any)
		if typeof(kind) == "string" and typeof(message) == "string" then
			showToast(kind, message)
		end
	end)
end
local waveWarning = remote("WaveWarning")
if waveWarning then
	waveWarning.OnClientEvent:Connect(function(secondsLeft: any)
		if typeof(secondsLeft) ~= "number" then
			return
		end
		if secondsLeft > 0 then
			waveBanner.Visible = true
			waveBarBack.Visible = true
			vignette.Visible = true
			waveBanner.Text = ("OMBAK DATANG DALAM %d detik!"):format(secondsLeft)
			waveBar.Size = UDim2.fromScale(secondsLeft / math.max(Config.WaveWarningSeconds, 1), 1)
		else
			waveBanner.Visible = false
			waveBarBack.Visible = false
			vignette.Visible = false
		end
	end)
end

-- Efek mutasi kosmetik untuk model di dunia (conveyor, slot, bawaan).
MutationVisuals.WatchWorkspace()

-- Segarkan label kunci tiap detik (hitung mundur lokal dari state server).
task.spawn(function()
	while true do
		task.wait(1)
		if state then
			applyState(state)
		end
	end
end)
