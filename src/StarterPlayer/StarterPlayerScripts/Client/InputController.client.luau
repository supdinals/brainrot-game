-- InputController.client.luau -- pintasan keyboard PC (mobile memakai
-- tombol sentuh di UIController): C = Collect, L = Kunci base, B = Beli slot.
-- Memakai ContextActionService supaya tidak bertabrakan dengan script kamera
-- bawaan Roblox yang juga membaca tombol arah.

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remotes = ReplicatedStorage:WaitForChild("Remotes")

local function fire(remoteName: string)
	local remote = remotes:FindFirstChild(remoteName)
	if remote and remote:IsA("RemoteEvent") then
		(remote :: RemoteEvent):FireServer()
	end
end

local function bind(actionName: string, remoteName: string, key: Enum.KeyCode)
	ContextActionService:BindAction(actionName, function(_, inputState: Enum.UserInputState)
		if inputState == Enum.UserInputState.Begin then
			fire(remoteName)
		end
		return Enum.ContextActionResult.Pass
	end, false, key)
end

bind("BrainrotCollect", "Collect", Enum.KeyCode.C)
bind("BrainrotLock", "LockBase", Enum.KeyCode.L)
bind("BrainrotBuySlot", "BuySlot", Enum.KeyCode.B)
