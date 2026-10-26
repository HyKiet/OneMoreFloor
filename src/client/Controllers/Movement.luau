-- Double jump while the server sets the DoubleJump attribute on the local player (Ghost Boots relic).

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Movement = {}

local player = Players.LocalPlayer

local function hookCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if not humanoid or not root then
		return
	end
	local canDouble = false
	local used = false

	humanoid.StateChanged:Connect(function(_, new)
		if new == Enum.HumanoidStateType.Landed or new == Enum.HumanoidStateType.Running then
			canDouble = false
			used = false
		elseif new == Enum.HumanoidStateType.Freefall then
			task.delay(0.12, function()
				if humanoid:GetState() == Enum.HumanoidStateType.Freefall then
					canDouble = true
				end
			end)
		end
	end)

	local connection
	connection = UserInputService.JumpRequest:Connect(function()
		if not character.Parent then
			connection:Disconnect()
			return
		end
		if not player:GetAttribute("DoubleJump") or used or not canDouble then
			return
		end
		if humanoid:GetState() ~= Enum.HumanoidStateType.Freefall then
			return
		end
		used = true
		canDouble = false
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
		local jumpVelocity
		if humanoid.UseJumpPower then
			jumpVelocity = humanoid.JumpPower
		else
			jumpVelocity = math.sqrt(2 * workspace.Gravity * humanoid.JumpHeight)
		end
		local v = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(v.X, jumpVelocity * 1.05, v.Z)
	end)
end

function Movement.Start()
	if player.Character then
		task.spawn(hookCharacter, player.Character)
	end
	player.CharacterAdded:Connect(hookCharacter)
end

return Movement
