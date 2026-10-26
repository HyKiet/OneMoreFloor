-- Conveyor Chaos: belts drag you toward the grinders at the ends. Walk against them or hop lanes.

local BELTS = 8
local BELT_W = 8
local LENGTH = 64
local HALF_Z = BELTS * BELT_W / 2
local CHEVRON_SPAN = 18

local function plan(ctx)
	local d = math.clamp(ctx.Difficulty, 0, 1.5)
	return {
		Speed = 5 + 7 * math.min(d, 1),
		Ramp = 0.18 + 0.12 * d,
		MaxSpeed = 15,
		Islands = if d >= 1.2 then 0 elseif d >= 0.7 then 2 else 4,
		ShrinkIslands = d >= 0.4,
		Flips = d >= 0.6,
		D = d,
	}
end

local function beltZ(k)
	return -HALF_Z + (k - 0.5) * BELT_W
end

-- Rebuilds the chevron arrows on a belt to point along `dir`. Clients scroll them with the belt (OMF_Slide).
local function drawChevrons(ctx, belt, speed: number)
	for _, part in belt.Chevrons do
		part:Destroy()
	end
	belt.Chevrons = {}
	local z = beltZ(belt.Index)
	local slideDir = ctx.Origin:VectorToWorldSpace(Vector3.new(belt.Dir, 0, 0))
	for c = -1, 1 do
		local tipX = c * CHEVRON_SPAN + belt.Dir * 1
		for _, yaw in { belt.Dir * 45, belt.Dir * 135 } do
			local look = (CFrame.Angles(0, math.rad(yaw), 0)).LookVector
			local centre = Vector3.new(tipX, 0.09, z) + look * 1.5
			local part = ctx:Decor({
				Name = "Chevron",
				Size = Vector3.new(0.6, 0.1, 3), -- top 0.04 above the seams so they never z-fight
				CFrame = ctx.Origin * CFrame.new(centre) * CFrame.Angles(0, math.rad(yaw), 0),
				Color = ctx.Theme.Primary,
				Material = Enum.Material.Neon,
			})
			ctx:Animate(part, "OMF_Slide", { SlideDir = slideDir, SlideSpeed = speed, SlideSpan = CHEVRON_SPAN, SlideBase = 0 })
			table.insert(belt.Chevrons, part)
		end
	end
end

local function applyVelocity(ctx, belt, speed)
	belt.Part.AssemblyLinearVelocity = ctx.Origin:VectorToWorldSpace(Vector3.new(belt.Dir * speed, 0, 0))
	for _, chevron in belt.Chevrons do
		chevron:SetAttribute("SlideSpeed", speed)
	end
end

return {
	Id = "Conveyor",
	Name = "Conveyor Chaos",
	Hint = "The belts pull you toward the grinders. Fight the current!",
	MinFloor = 3,
	MinPlayers = 1,
	Weight = 0.9,
	BossOnly = false,
	Duration = 20,

	Build = function(ctx)
		local p = plan(ctx)
		local dark = ctx.Theme.Floor:Lerp(Color3.new(0, 0, 0), 0.45)
		local belts = {}
		for k = 1, BELTS do
			local part = ctx:Part({
				Name = "Belt",
				Size = Vector3.new(LENGTH, 2, BELT_W - 0.4),
				CFrame = ctx:At(0, -1, beltZ(k)),
				Color = ctx.Theme.Floor:Lerp(ctx.Theme.Primary, if k % 2 == 0 then 0.1 else 0.2),
				Material = Enum.Material.DiamondPlate,
			})
			local belt = { Part = part, Index = k, Dir = if k % 2 == 0 then 1 else -1, Chevrons = {} }
			drawChevrons(ctx, belt, p.Speed)
			table.insert(belts, belt)
		end
		ctx.State.Belts = belts

		-- Glowing seams between belts so lanes read clearly
		for k = 0, BELTS do
			ctx:Decor({ Name = "Seam", Size = Vector3.new(LENGTH, 0.1, 0.35), CFrame = ctx:At(0, 0.05, -HALF_Z + k * BELT_W), Color = ctx.Theme.Floor:Lerp(ctx.Theme.Secondary, 0.6), Material = Enum.Material.Neon })
		end
		ctx:Decor({ Name = "Underglow", Size = Vector3.new(LENGTH + 2, 0.3, BELTS * BELT_W + 1), CFrame = ctx:At(0, -2.2, 0), Color = ctx.Theme.Secondary, Material = Enum.Material.Neon })

		-- Grinders at both ends: a hazard roller with spinning teeth under a dark hood
		local width = BELTS * BELT_W + 2
		for _, side in { -1, 1 } do
			local x = side * (LENGTH / 2 + 1.5)
			local grinder = ctx:Hazard({ Name = "Grinder", Shape = Enum.PartType.Cylinder, Size = Vector3.new(width, 3, 3), CFrame = ctx:At(x, 0, 0, 0, 90, 0), Color = ctx.Theme.Hazard:Lerp(Color3.new(0, 0, 0), 0.25) })
			ctx:Glow(grinder, ctx.Theme.Hazard, 16, 1.5)
			for t = 0, 5 do
				local a = t * 60
				local tooth = ctx:Decor({ Name = "Tooth", Size = Vector3.new(width, 0.7, 0.7), CFrame = grinder.CFrame * CFrame.Angles(math.rad(a), 0, 0) * CFrame.new(0, 1.55, 0) * CFrame.Angles(math.rad(45), 0, 0), Color = ctx.Theme.Hazard, Material = Enum.Material.Neon })
				ctx:Animate(tooth, "OMF_Spin", { SpinPivot = grinder.CFrame, SpinAxis = Vector3.new(1, 0, 0), SpinSpeed = side * 7 })
			end
			ctx:Emitter(grinder, {
				Texture = "Sparks",
				Color = ColorSequence.new(Color3.fromRGB(255, 230, 150), ctx.Theme.Hazard),
				Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 0) }),
				Speed = NumberRange.new(10, 18),
				SpreadAngle = Vector2.new(25, 60),
				EmissionDirection = Enum.NormalId.Top,
				Lifetime = NumberRange.new(0.2, 0.45),
				Acceleration = Vector3.new(0, -40, 0),
				Rate = 30,
			})
			ctx:Decor({ Name = "Hood", Size = Vector3.new(5, 1.2, width + 1), CFrame = ctx:At(side * (LENGTH / 2 + 2.2), 3.4, 0), Color = dark })
			for k = -3, 3 do
				ctx:Decor({ Name = "HoodStripe", Size = Vector3.new(5.1, 1.3, 2), CFrame = ctx:At(side * (LENGTH / 2 + 2.2), 3.4, k * 9.5, 0, 0, 0), Color = if k % 2 == 0 then Color3.fromRGB(255, 200, 40) else dark })
			end
		end

		-- Static islands to catch your breath on
		local islands = {}
		local spots = { { -12, -12 }, { 12, 12 }, { 12, -12 }, { -12, 12 } }
		for k = 1, p.Islands do
			local s = spots[k]
			local island = ctx:Part({ Name = "Island", Size = Vector3.new(7, 1.2, 7), CFrame = ctx:At(s[1], 0, s[2]), Color = ctx.Theme.Secondary, Material = Enum.Material.Neon, Transparency = 0.15 })
			ctx:Animate(island, "OMF_Pulse", { PulseMin = 0.05, PulseMax = 0.35, PulseSpeed = 0.8, PulsePhase = k / 4 })
			table.insert(islands, island)
		end
		ctx.State.Islands = islands
	end,

	Start = function(ctx)
		local p = plan(ctx)
		local belts = ctx.State.Belts
		local speed = p.Speed

		for _, belt in belts do
			applyVelocity(ctx, belt, speed)
		end
		for _ = 1, 5 do
			local k = ctx.Rng:NextInteger(1, BELTS)
			local side = if ctx.Rng:NextNumber() < 0.5 then -1 else 1
			ctx:SpawnCoin(ctx:At(side * ctx.Rng:NextNumber(18, 27), 3, beltZ(k)).Position)
		end

		if p.ShrinkIslands then
			for _, island in ctx.State.Islands do
				ctx:Tween(island, TweenInfo.new(18, Enum.EasingStyle.Linear), { Size = Vector3.new(2.5, 1.2, 2.5) })
			end
		end

		-- Speed up over time
		ctx:Every(1, function()
			speed = math.min(speed + p.Ramp, p.MaxSpeed)
			for _, belt in belts do
				applyVelocity(ctx, belt, speed)
			end
			return nil
		end)

		-- Belts reverse direction on deeper floors, with a warning flash
		if p.Flips then
			ctx:Every(math.max(5.5 - p.D * 1.5, 3), function()
				local count = if p.D >= 1 then 3 else 2
				for _ = 1, count do
					local belt = belts[ctx.Rng:NextInteger(1, BELTS)]
					for _, chevron in belt.Chevrons do
						chevron.Color = ctx.Theme.Hazard
					end
					ctx:Warn(ctx:At(0, 0.12, beltZ(belt.Index)), Vector3.new(LENGTH, 0.2, BELT_W - 0.6), 0.9, nil, { Sweep = Vector3.new(-belt.Dir, 0, 0) })
					ctx:After(0.9, function()
						belt.Dir = -belt.Dir
						drawChevrons(ctx, belt, speed)
						applyVelocity(ctx, belt, speed)
					end)
				end
				ctx:Sound("Warning")
				return nil
			end)
		end
	end,
}
