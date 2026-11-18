--!strict
-- StealService.luau -- pencurian antar pemain, sepenuhnya di server.
-- Satu karakter hanya dalam satu status: InSlot / Carried / Returning.
-- Alur: prompt "Curi" (hold 3 detik) -> cek base tidak terkunci, jarak
-- <= Config.StealMaxDistance, pencuri tidak sedang membawa -> karakter
-- menempel ke pencuri (jalan -20%) -> pencuri tiba di base sendiri dengan
-- slot kosong -> karakter pindah kepemilikan. Mati/kena ombak/disconnect:
-- karakter kembali ke slot asal bila pemilik masih online dan slot kosong.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Types = require(Shared:WaitForChild("Types"))

type SlotData = Types.SlotData

export type CarryRecord = {
	Slot: SlotData,
	Owner: Player,
	OwnerSlotIndex: number,
	Model: Model,
	OriginalWalkSpeed: number,
}

local StealService = {}

local DataService: any = nil
local EconomyService: any = nil
local BaseService: any = nil
local BrainrotFactory: any = nil

local carrying: { [Player]: CarryRecord } = {}

function StealService.Bind(dataService: any, economyService: any, baseService: any, brainrotFactory: any)
	DataService = dataService
	EconomyService = economyService
	BaseService = baseService
	BrainrotFactory = brainrotFactory
end

function StealService.IsCarrying(player: Player): boolean
	return carrying[player] ~= nil
end

local function humanoidOf(player: Player): Humanoid?
	local character = player.Character
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return if humanoid and humanoid:IsA("Humanoid") then humanoid else nil
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root :: BasePart else nil
end

-- Kembalikan karakter bawaan ke slot asalnya (atau hilang bila tidak bisa).
function StealService.ReturnCarried(thief: Player, reason: string)
	local record = carrying[thief]
	if not record then
		return
	end
	carrying[thief] = nil
	record.Model:Destroy()
	local humanoid = humanoidOf(thief)
	if humanoid then
		humanoid.WalkSpeed = record.OriginalWalkSpeed
	end
	local owner = record.Owner
	if Players:GetPlayerByUserId(owner.UserId) == owner and BaseService.GetBase(owner) then
		local restored = BaseService.PutBackInSlot(owner, record.OwnerSlotIndex, record.Slot)
		if restored then
			EconomyService.Notify(owner, "steal", "Karaktermu kembali ke base (" .. reason .. ")")
		end
	end
	EconomyService.PushState(thief)
end

-- Coba curi: dipanggil dari ProximityPrompt di BaseService.
function StealService.TrySteal(thief: Player, owner: Player, slotIndex: number)
	if thief == owner then
		return
	end
	if carrying[thief] then
		EconomyService.Notify(thief, "error", "Kamu sudah membawa karakter!")
		return
	end
	if BaseService.IsLocked(owner) then
		EconomyService.Notify(thief, "error", "Base itu sedang dikunci!")
		return
	end
	local ownerData = DataService.Get(owner)
	if not ownerData or not ownerData.Slots[slotIndex] then
		return
	end
	-- Validasi jarak server: pencuri harus dekat dengan slot korban.
	local thiefRoot = rootOf(thief)
	local ownerBase = BaseService.GetBase(owner)
	local slotPart = if ownerBase then ownerBase:FindFirstChild("Slot_" .. slotIndex) else nil
	if thiefRoot and slotPart and slotPart:IsA("BasePart") then
		if (thiefRoot.Position - (slotPart :: BasePart).Position).Magnitude > Config.StealMaxDistance + 6 then
			return
		end
	end

	local slot: SlotData? = BaseService.RemoveFromSlot(owner, slotIndex)
	if not slot then
		return
	end
	local humanoid = humanoidOf(thief)
	local originalSpeed = if humanoid then humanoid.WalkSpeed else 16

	-- Model bawaan: kloning segar, menempel di atas kepala pencuri.
	local model = BrainrotFactory.Clone(slot.Id)
	if not model then
		BaseService.PutBackInSlot(owner, slotIndex, slot)
		return
	end
	model:SetAttribute("Mutation", slot.Mutation)
	model:SetAttribute("State", "Carried")
	model:SetAttribute("OwnerUserId", owner.UserId)
	local thiefRootNow = rootOf(thief)
	if thiefRootNow then
		model:PivotTo(thiefRootNow.CFrame * CFrame.new(0, 3.4, 0))
	end
	model.Parent = workspace

	carrying[thief] = {
		Slot = slot,
		Owner = owner,
		OwnerSlotIndex = slotIndex,
		Model = model,
		OriginalWalkSpeed = originalSpeed,
	}
	if humanoid then
		humanoid.WalkSpeed = originalSpeed * Config.StealWalkSpeedFactor
	end
	EconomyService.Notify(owner, "steal", ("DICURI! %s mengambil %s dari base-mu!"):format(thief.DisplayName, Config.Characters[slot.Id].DisplayName))
	EconomyService.Notify(thief, "success", "Bawa ke base! Karakter curian harus sampai ke slot kosong base-mu.")
	EconomyService.PushState(thief)
end

-- Selesaikan pencurian: pencuri tiba di area base sendiri.
local function tryDeposit(thief: Player)
	local record = carrying[thief]
	if not record then
		return
	end
	local data = DataService.Get(thief)
	if not data or not BaseService.FirstFreeSlot(data) then
		return -- tidak ada slot kosong: tetap membawa
	end
	carrying[thief] = nil
	record.Model:Destroy()
	local humanoid = humanoidOf(thief)
	if humanoid then
		humanoid.WalkSpeed = record.OriginalWalkSpeed
	end
	local placed = BaseService.PlaceInFirstFreeSlot(thief, record.Slot.Id, record.Slot.Rarity, record.Slot.Mutation)
	if placed then
		EconomyService.Notify(thief, "success", ("Berhasil! %s sekarang milikmu."):format(Config.Characters[record.Slot.Id].DisplayName))
		if Players:GetPlayerByUserId(record.Owner.UserId) == record.Owner then
			EconomyService.Notify(record.Owner, "steal", "Karaktermu resmi berpindah ke base pencuri.")
		end
	else
		-- Slot ternyata penuh di detik terakhir: kembalikan ke pemilik asal.
		if Players:GetPlayerByUserId(record.Owner.UserId) == record.Owner then
			BaseService.PutBackInSlot(record.Owner, record.OwnerSlotIndex, record.Slot)
		end
	end
	EconomyService.PushState(thief)
end

-- Loop ringan: model bawaan mengikuti pencuri; deposit otomatis saat pencuri
-- masuk area base-nya sendiri; karakter korban yang disconnect juga ditangani.
function StealService.Start()
	task.spawn(function()
		while true do
			task.wait(0.25)
			for thief, record in carrying do
				local root = rootOf(thief)
				if not root then
					continue
				end
				record.Model:PivotTo(root.CFrame * CFrame.new(0, 3.4, 0))
				local base = BaseService.GetBase(thief)
				if base and base.PrimaryPart then
					local distance = (root.Position - base.PrimaryPart.Position).Magnitude
					if distance < 20 then
						tryDeposit(thief)
					end
				end
			end
		end
	end)
end

-- Dipanggil Main saat pemain keluar / mati / kena ombak.
function StealService.OnThiefGone(thief: Player, reason: string)
	StealService.ReturnCarried(thief, reason)
end

-- Korban keluar saat karakternya sedang dibawa: karakter hilang bersama
-- data korban (sudah terhapus dari slotnya), bersihkan bawaan pencuri.
function StealService.OnOwnerLeft(owner: Player)
	for thief, record in carrying do
		if record.Owner == owner then
			carrying[thief] = nil
			record.Model:Destroy()
			local humanoid = humanoidOf(thief)
			if humanoid then
				humanoid.WalkSpeed = record.OriginalWalkSpeed
			end
			EconomyService.Notify(thief, "error", "Pemilik karakter keluar; curianmu hilang.")
			EconomyService.PushState(thief)
		end
	end
end

-- Kematian pencuri mengembalikan karakter (didaftarkan per karakter spawn).
function StealService.WatchCharacter(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid:IsA("Humanoid") then
		(humanoid :: Humanoid).Died:Connect(function()
			StealService.ReturnCarried(player, "pencuri tumbang")
		end)
	end
end

return StealService
