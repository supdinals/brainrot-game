--!strict
-- BrainrotFactory.luau -- membuat model placeholder untuk 13 karakter dari
-- Config.Characters di ServerStorage/Brainrots saat server start, hanya bila
-- model dengan nama itu belum ada (aset asli pemilik menggantikan placeholder
-- tanpa mengubah script). Placeholder: satu Part "Body" sebagai PrimaryPart,
-- warna dan tinggi sesuai rarity, Anchored, CanCollide=false, atribut
-- Id/Rarity/IsPlaceholder=true, BillboardGui berisi nama tampilan.

local ServerStorage = game:GetService("ServerStorage")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local BrainrotFactory = {}

function BrainrotFactory.EnsurePlaceholders()
	local folder = ServerStorage:FindFirstChild("Brainrots")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Brainrots"
		folder.Parent = ServerStorage
	end

	local made = 0
	for id, info in Config.Characters do
		if folder:FindFirstChild(id) then
			continue -- aset asli (atau placeholder lama) sudah ada, jangan sentuh
		end
		local rarityInfo = Config.Rarities[info.Rarity]
		local height = rarityInfo.Height
		local width = height * 0.6

		local model = Instance.new("Model")
		model.Name = id
		model:SetAttribute("Id", id)
		model:SetAttribute("Rarity", info.Rarity)
		model:SetAttribute("IsPlaceholder", true)

		local body = Instance.new("Part")
		body.Name = "Body"
		body.Size = Vector3.new(width, height, width)
		body.Position = Vector3.new(0, height / 2, 0) -- pivot di tengah bawah
		body.Color = rarityInfo.Color
		body.Material = Enum.Material.SmoothPlastic
		body.Anchored = true
		body.CanCollide = false
		body.TopSurface = Enum.SurfaceType.Smooth
		body.BottomSurface = Enum.SurfaceType.Smooth
		body.Parent = model
		model.PrimaryPart = body

		-- Mata sederhana supaya placeholder terasa seperti karakter.
		for _, offsetX in { -width * 0.18, width * 0.18 } do
			local eye = Instance.new("Part")
			eye.Name = "Eye"
			eye.Shape = Enum.PartType.Ball
			eye.Size = Vector3.new(width * 0.16, width * 0.16, width * 0.16)
			eye.Position = Vector3.new(offsetX, height * 0.68, -width / 2 - 0.05)
			eye.Color = Color3.fromRGB(20, 20, 20)
			eye.Material = Enum.Material.SmoothPlastic
			eye.Anchored = true
			eye.CanCollide = false
			eye.Parent = model
		end

		local billboard = Instance.new("BillboardGui")
		billboard.Name = "NameBillboard"
		billboard.Size = UDim2.fromOffset(200, 50)
		billboard.StudsOffset = Vector3.new(0, height / 2 + 1.2, 0)
		billboard.AlwaysOnTop = true
		local label = Instance.new("TextLabel")
		label.Name = "NameLabel"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Text = info.DisplayName
		label.TextColor3 = rarityInfo.Color
		label.TextScaled = true
		label.Font = Enum.Font.GothamBold
		label.TextStrokeTransparency = 0.4
		label.Parent = billboard
		billboard.Adornee = body
		billboard.Parent = model

		model.Parent = folder
		made += 1
	end
	print(("[BrainrotFactory] %d placeholder karakter dibuat di ServerStorage/Brainrots."):format(made))
end

-- Kloning template karakter; mengembalikan nil bila ID tidak dikenal.
function BrainrotFactory.Clone(id: string): Model?
	local folder = ServerStorage:FindFirstChild("Brainrots")
	if not folder then
		return nil
	end
	local template = folder:FindFirstChild(id)
	if not template or not template:IsA("Model") then
		return nil
	end
	return (template :: Model):Clone()
end

return BrainrotFactory
