-- Safe Zones: glowing circles appear. When the timer hits zero, the floor outside them is electrified.

local SIZE = 76
local HALF = SIZE / 2

local function plan(ctx)
	local d = math.clamp(ctx.Difficulty, 0, 1.5)
	return {
		Rounds = 3 + (if d >= 0.4 then 1 else 0),
		Countdown = 4.2 - 1.6 * math.min(d, 1),
		Pause = 1.6,
		D = d,
	}
end

-- Picks non-overlapping circle centres within the floor.
local function pickCircles(ctx, count, radius)
	local circles = {}
	local tries = 0
	while #circles < count and tries < 200 do
		tries += 1
		local x = ctx.Rng:NextNumber(-HALF + radius + 2, HALF - radius - 2)
		local z = ctx.Rng:NextNumber(-HALF + radius + 2, HALF - radius - 2)
		local ok = true
		for _, c in circles do
			if (Vector2.new(x, z) - Vector2.new(c.X, c.Z)).Magnitude < radius * 2 + 6 then
				ok = false
				break
			end
		end
		if ok then
			table.insert(circles, { X = x, Z = z })
		end
	end
	return circles
end

return {
	Id = "SafeZones",
	Name = "Safe Zones",
	Hint = "Get inside a glowing circle before the floor gets zapped!",
	MinFloor = 1,
	MinPlayers = 1,
	Weight = 1.1,
	BossOnly = false,
	Duration = function(ctx)
		local p = plan(ctx)
		return p.Rounds * (p.Countdown + p.Pause) + 1.5
	end,

	Build = function(ctx)
		local floor = ctx:Part({ Name = "Floor", Size = Vector3.new(SIZE, 2, SIZE), CFrame = ctx:At(0, -1, 0), Color = ctx.Theme.Floor:Lerp(Color3.new(0, 0, 0), 0.1) })
		ctx.State.Floor = floor
		ctx.State.FloorColor = floor.Color
		-- "Live wire" floor: conductor lines with node studs at the crossings
		local wire = ctx.Theme.Floor:Lerp(ctx.Theme.Hazard, 0.28)
		for k = -3, 3 do
			ctx:Decor({ Name = "Wire", Size = Vector3.new(SIZE - 2, 0.05, 0.2), CFrame = ctx:At(0, 0.02, k * 10), Color = wire })
			ctx:Decor({ Name = "Wire", Size = Vector3.new(0.2, 0.05, SIZE - 2), CFrame = ctx:At(k * 10, 0.02, 0), Color = wire })
		end
		for i = -3, 3, 2 do
			for j = -3, 3, 2 do
				local node = ctx:Decor({ Name = "Node", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.08, 1.4, 1.4), CFrame = ctx:At(i * 10, 0.04, j * 10, 0, 0, 90), Color = ctx.Theme.Hazard, Material = Enum.Material.Neon })
				ctx:Animate(node, "OMF_Pulse", { PulseMin = 0.2, PulseMax = 0.85, PulseSpeed = 0.9, PulsePhase = (i + j) / 12 })
			end
		end
		ctx:Rim(HALF, HALF, ctx.Theme.Primary, ctx.Theme.Hazard)
		-- Tesla coils in the corners
		for _, c in { { 1, 1 }, { 1, -1 }, { -1, -1 }, { -1, 1 } } do
			local x, z = c[1] * (HALF + 3), c[2] * (HALF + 3)
			ctx:Decor({ Name = "Coil", Shape = Enum.PartType.Cylinder, Size = Vector3.new(10, 2.4, 2.4), CFrame = ctx:At(x, 4, z, 0, 0, 90), Color = ctx.Theme.Floor:Lerp(Color3.new(0, 0, 0), 0.3), CanCollide = true })
			for k = 1, 3 do
				ctx:Decor({ Name = "Winding", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 2.8, 2.8), CFrame = ctx:At(x, 1.5 + k * 2.2, z, 0, 0, 90), Color = ctx.Theme.Hazard:Lerp(ctx.Theme.Floor, 0.3), Material = Enum.Material.Neon })
			end
			local orb = ctx:Decor({ Name = "Orb", Shape = Enum.PartType.Ball, Size = Vector3.new(3.4, 3.4, 3.4), CFrame = ctx:At(x, 10.2, z), Color = ctx.Theme.Hazard:Lerp(Color3.new(1, 1, 1), 0.3), Material = Enum.Material.Neon })
			ctx:Animate(orb, "OMF_Pulse", { PulseMin = 0, PulseMax = 0.5, PulseSpeed = 2.2 })
		end
	end,

	Start = function(ctx)
		local p = plan(ctx)
		local floor = ctx.State.Floor
		local alive = #ctx:GetAlive()
		local area = ctx:At(0, 0.1, 0)

		for round = 1, p.Rounds do
			-- Fewer, smaller circles every round
			local radius = math.max(9 - round * 0.8 - p.D * 2, 4.5)
			local count = math.clamp(4 - round + 1 - math.floor(p.D), 1, 4)
			if alive >= 6 then
				count += 1
			end
			local circles = pickCircles(ctx, count, radius)
			local visuals = {}
			for _, c in circles do
				local pad = ctx:Decor({ Name = "SafeZone", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, radius * 2, radius * 2), CFrame = ctx:At(c.X, 0.15, c.Z, 0, 0, 90), Color = ctx.Theme.Secondary, Material = Enum.Material.Neon, Transparency = 0.45 })
				local column = ctx:Decor({ Name = "Column", Shape = Enum.PartType.Cylinder, Size = Vector3.new(40, radius * 2, radius * 2), CFrame = ctx:At(c.X, 20, c.Z, 0, 0, 90), Color = ctx.Theme.Secondary, Material = Enum.Material.Neon, Transparency = 0.9 })
				local core = ctx:Decor({ Name = "Core", Shape = Enum.PartType.Cylinder, Size = Vector3.new(40, 0.8, 0.8), CFrame = ctx:At(c.X, 20, c.Z, 0, 0, 90), Color = ctx.Theme.Secondary:Lerp(Color3.new(1, 1, 1), 0.5), Material = Enum.Material.Neon, Transparency = 0.3 })
				-- the zone itself fills up as the countdown runs out
				ctx:Warn(ctx:At(c.X, 0.32, c.Z), Vector3.new(radius * 2, 0.2, radius * 2), p.Countdown, ctx.Theme.Secondary, { Shape = "Disc" })
				ctx:Fx("Impact", { Position = ctx:At(c.X, 0.2, c.Z).Position, Color = ctx.Theme.Secondary, Radius = radius + 3, Debris = 0 })
				table.insert(visuals, pad)
				table.insert(visuals, column)
				table.insert(visuals, core)
			end
			-- Tempting coins outside the circles
			ctx:SpawnCoin(ctx:At(ctx.Rng:NextNumber(-30, 30), 3, ctx.Rng:NextNumber(-30, 30)).Position)
			ctx:Announce("GET IN A ZONE!", ctx.Theme.Secondary)
			ctx:Sound("Countdown")

			-- The floor starts crackling as the zap approaches
			ctx:After(p.Countdown * 0.5, function()
				ctx:Tween(floor, TweenInfo.new(0.15, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
					Color = ctx.State.FloorColor:Lerp(ctx.Theme.Hazard, 0.35),
				})
				local sparks = 0
				ctx:Every(0.35, function()
					sparks += 1
					ctx:Fx("Arcs", { CFrame = area, Size = Vector3.new(SIZE - 6, 0, SIZE - 6), Color = ctx.Theme.Hazard, Count = 2 + sparks })
					return sparks < math.floor(p.Countdown * 0.5 / 0.35)
				end)
			end)
			if not ctx:Wait(p.Countdown) then
				return
			end

			-- ZAP
			ctx:Announce("ZAP!", ctx.Theme.Hazard)
			ctx:Sound("Explosion")
			ctx:Shake(0.8, 0.4)
			ctx:Fx("Arcs", { CFrame = area, Size = Vector3.new(SIZE - 4, 0, SIZE - 4), Color = ctx.Theme.Hazard, Count = 14 })
			local flash = ctx:Decor({ Name = "Zap", Size = Vector3.new(SIZE, 0.4, SIZE), CFrame = ctx:At(0, 0.3, 0), Color = ctx.Theme.Hazard:Lerp(Color3.new(1, 1, 1), 0.3), Material = Enum.Material.Neon, Transparency = 0.15 })
			ctx:Tween(flash, TweenInfo.new(0.6), { Transparency = 1 })
			for _, player in ctx:GetAlive() do
				local pos = ctx:LocalPosition(player)
				local safe = false
				if pos then
					for _, c in circles do
						if (Vector2.new(pos.X, pos.Z) - Vector2.new(c.X, c.Z)).Magnitude <= radius + 0.75 then
							safe = true
							break
						end
					end
				end
				if not safe then
					ctx:Eliminate(player, "Zapped")
				end
			end

			if not ctx:Wait(0.6) then
				return
			end
			flash:Destroy()
			for _, v in visuals do
				v:Destroy()
			end
			-- Stop the flicker (a fresh tween overrides the looping one)
			ctx:Tween(floor, TweenInfo.new(0.2), { Color = ctx.State.FloorColor })
			if round < p.Rounds and not ctx:Wait(p.Pause - 0.6) then
				return
			end
		end
		ctx:Finish()
	end,
}
