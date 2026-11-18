--!strict
-- MutationVisuals.luau -- efek kosmetik mutasi di CLIENT saja (tidak pernah
-- menyentuh logika uang/kepemilikan). Apply(model, mutation) bekerja pada
-- model apa pun: menerapkan tampilan ke semua BasePart turunannya, menyimpan
-- warna/material asli, dan Clear(model) memulihkannya.
-- Gold: metal emas. Diamond: biru muda + Highlight. Rainbow: hue cycling.
-- Void: hitam pekat + partikel ungu. Normal: tanpa efek.

local RunService = game:GetService("RunService")

local MutationVisuals = {}

type SavedProps = { Color: Color3, Material: Enum.Material }
local saved: { [Model]: { [BasePart]: SavedProps } } = {}
local rainbowConnections: { [Model]: RBXScriptConnection } = {}

local function baseParts(model: Model): { BasePart }
	local parts: { BasePart } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Name ~= "Eye" then
			table.insert(parts, descendant :: BasePart)
		end
	end
	return parts
end

function MutationVisuals.Clear(model: Model)
	local connection = rainbowConnections[model]
	if connection then
		connection:Disconnect()
		rainbowConnections[model] = nil
	end
	local highlight = model:FindFirstChild("MutationHighlight")
	if highlight then
		highlight:Destroy()
	end
	local props = saved[model]
	if props then
		for part, original in props do
			if part.Parent then
				part.Color = original.Color
				part.Material = original.Material
			end
		end
		saved[model] = nil
	end
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("ParticleEmitter") and descendant.Name == "MutationParticles" then
			descendant:Destroy()
		end
	end
end

function MutationVisuals.Apply(model: Model, mutation: string)
	MutationVisuals.Clear(model)
	if mutation == "Normal" then
		return
	end
	local parts = baseParts(model)
	local props: { [BasePart]: SavedProps } = {}
	for _, part in parts do
		props[part] = { Color = part.Color, Material = part.Material }
	end
	saved[model] = props

	if mutation == "Gold" then
		for _, part in parts do
			part.Material = Enum.Material.Metal
			part.Color = Color3.fromRGB(255, 196, 48)
		end
	elseif mutation == "Diamond" then
		for _, part in parts do
			part.Color = Color3.fromRGB(150, 225, 255)
			part.Material = Enum.Material.Glass
		end
		local highlight = Instance.new("Highlight")
		highlight.Name = "MutationHighlight"
		highlight.FillColor = Color3.fromRGB(140, 220, 255)
		highlight.FillTransparency = 0.65
		highlight.OutlineColor = Color3.fromRGB(220, 245, 255)
		highlight.Parent = model
	elseif mutation == "Rainbow" then
		local hue = 0
		rainbowConnections[model] = RunService.RenderStepped:Connect(function(dt: number)
			if not model.Parent then
				MutationVisuals.Clear(model)
				return
			end
			hue = (hue + dt * 0.25) % 1
			local color = Color3.fromHSV(hue, 0.75, 1)
			for _, part in baseParts(model) do
				part.Color = color
			end
		end)
	elseif mutation == "Void" then
		for _, part in parts do
			part.Color = Color3.fromRGB(12, 8, 20)
			part.Material = Enum.Material.SmoothPlastic
		end
		local primary = model.PrimaryPart
		if primary then
			local emitter = Instance.new("ParticleEmitter")
			emitter.Name = "MutationParticles"
			emitter.Color = ColorSequence.new(Color3.fromRGB(150, 60, 255))
			emitter.Size = NumberSequence.new(0.35)
			emitter.Rate = 14
			emitter.Lifetime = NumberRange.new(0.8, 1.4)
			emitter.Speed = NumberRange.new(1, 2.4)
			emitter.Parent = primary
		end
	end
end

-- Terapkan efek ke semua model ber-atribut Mutation yang sudah ada di dunia
-- dan yang muncul kemudian (conveyor, slot, bawaan curian).
function MutationVisuals.WatchWorkspace()
	local function consider(instance: Instance)
		if instance:IsA("Model") then
			local mutation = instance:GetAttribute("Mutation")
			if typeof(mutation) == "string" and mutation ~= "Normal" then
				MutationVisuals.Apply(instance, mutation)
			end
		end
	end
	for _, descendant in workspace:GetDescendants() do
		consider(descendant)
	end
	workspace.DescendantAdded:Connect(consider)
end

return MutationVisuals
