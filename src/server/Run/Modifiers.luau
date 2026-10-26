-- Applies movement stats (relics/upgrades) and server-side curses to a run member's character.

local Modifiers = {}

local BASE_WALK = 16
local BASE_JUMP = 50
local GRAVITY_FORCE_NAME = "OMF_Gravity"

-- Removes the gravity force and restores scale/speed defaults.
function Modifiers.Clear(character: Model?)
	if not character then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root then
		local force = root:FindFirstChild(GRAVITY_FORCE_NAME)
		if force then
			force:Destroy()
		end
		local attachment = root:FindFirstChild(GRAVITY_FORCE_NAME .. "Att")
		if attachment then
			attachment:Destroy()
		end
	end
	if character:GetAttribute("OMF_Scaled") then
		character:SetAttribute("OMF_Scaled", nil)
		pcall(function()
			character:ScaleTo(1)
		end)
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = BASE_WALK
		humanoid.UseJumpPower = true
		humanoid.JumpPower = BASE_JUMP
	end
end

-- stats: from EconomyService.RunStats; curses: set of active curse ids (empty outside challenges).
function Modifiers.Apply(character: Model?, stats: { [string]: number }, curses: { [string]: boolean })
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root then
		return
	end

	-- Scale first so mass is right for the gravity force.
	local scale = 1
	if curses.Tiny then
		scale = 0.6
	elseif curses.Giant then
		scale = 1.4
	end
	local currentlyScaled = character:GetAttribute("OMF_Scaled")
	if scale ~= 1 then
		pcall(function()
			character:ScaleTo(scale)
		end)
		character:SetAttribute("OMF_Scaled", true)
	elseif currentlyScaled then
		pcall(function()
			character:ScaleTo(1)
		end)
		character:SetAttribute("OMF_Scaled", nil)
	end

	local walk = BASE_WALK * (1 + (stats.WalkSpeed or 0))
	if curses.Speedy then
		walk *= 1.5
	elseif curses.Sluggish then
		walk *= 0.7
	end
	humanoid.WalkSpeed = walk
	humanoid.UseJumpPower = true
	humanoid.JumpPower = BASE_JUMP * (1 + (stats.Jump or 0))

	-- Personal gravity: 1 = normal. A VectorForce cancels (or adds) part of workspace gravity.
	local gravity = 1 - math.clamp(stats.Gravity or 0, 0, 0.6)
	if curses.Moon then
		gravity *= 0.4
	elseif curses.Heavy then
		gravity *= 1.4
	end
	gravity = math.clamp(gravity, 0.25, 1.6)

	local force = root:FindFirstChild(GRAVITY_FORCE_NAME) :: VectorForce?
	if math.abs(gravity - 1) < 0.01 then
		if force then
			force:Destroy()
		end
		return
	end
	if not force then
		local attachment = Instance.new("Attachment")
		attachment.Name = GRAVITY_FORCE_NAME .. "Att"
		attachment.Parent = root
		force = Instance.new("VectorForce")
		force.Name = GRAVITY_FORCE_NAME
		force.Attachment0 = attachment
		force.RelativeTo = Enum.ActuatorRelativeTo.World
		force.ApplyAtCenterOfMass = true
		force.Parent = root
	end
	local mass = root.AssemblyMass
	force.Force = Vector3.new(0, mass * workspace.Gravity * (1 - gravity), 0)
end

return Modifiers
