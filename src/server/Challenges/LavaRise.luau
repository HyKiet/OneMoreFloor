-- The Floor Is Lava: lava floods the room. Climb the floating steps before it reaches you.

local FLOOR = 64
local LAVA_COLOR = Color3.fromRGB(215, 55, 12) -- deep: neon + bloom lifts it, brighter values blow out to flat yellow
local CRUST_COLOR = Color3.fromRGB(255, 150, 40)
local SLAG_COLOR = Color3.fromRGB(40, 14, 10)
local LAVA_BOTTOM_DEPTH = 6 -- the pool's bottom sits this far below the floor surface

local function plan(ctx)
	local d = math.clamp(ctx.Difficulty, 0, 1.5)
	local m = math.min(d, 1)
	return {
		LavaTop = 16 + 18 * m, -- final lava height
		Rise = 2.6 + 1.4 * m, -- vertical gap between steps
		Gap = 2.5 + 3.5 * m, -- horizontal gap between steps (edge to edge)
		Block = 6 - 1.5 * m,
		Paths = if d >= 1 then 3 else 4,
		Delay = 2.5,
	}
end

return {
	Id = "LavaRise",
	Name = "The Floor Is Lava",
	Hint = "The lava is rising! Climb the steps to the top before it reaches you.",
	MinFloor = 1,
	MinPlayers = 1,
	Weight = 1,
	BossOnly = false,
	Zone = 3, -- B20+
	Duration = 24,

	Build = function(ctx)
		local p = plan(ctx)
		ctx:Part({ Name = "Floor", Size = Vector3.new(FLOOR, 2, FLOOR), CFrame = ctx:At(0, -1, 0), Color = ctx.Theme.Floor:Lerp(Color3.new(0, 0, 0), 0.25) })
		-- Scorched cracks glowing faintly on the floor
		for _ = 1, 9 do
			local a = ctx.Rng:NextNumber(0, 180)
			ctx:Decor({ Name = "Crack", Size = Vector3.new(0.3, 0.05, ctx.Rng:NextNumber(6, 14)), CFrame = ctx:At(ctx.Rng:NextNumber(-24, 24), 0.02, ctx.Rng:NextNumber(-24, 24), 0, a, 0), Color = LAVA_COLOR:Lerp(ctx.Theme.Floor, 0.35), Material = Enum.Material.Neon })
		end

		-- Spiral staircases of floating blocks, one per path, each ending in a summit pad
		local summitY = p.LavaTop + 4
		local radius = 24
		local steps = math.ceil(summitY / p.Rise)
		local dTheta = (p.Block + p.Gap) / radius
		local coinSpots = {}
		local offset = ctx.Rng:NextNumber(0, math.pi * 2)
		for path = 1, p.Paths do
			local theta = offset + (path - 1) * (math.pi * 2 / p.Paths)
			local colour = ctx.Theme.Primary:Lerp(ctx.Theme.Secondary, (path - 1) / math.max(p.Paths - 1, 1))
			for step = 1, steps do
				local h = math.min(step * p.Rise, summitY)
				local r = radius + math.sin(step * 1.3 + path) * 2.5
				local x, z = math.sin(theta) * r, math.cos(theta) * r
				local isSummit = step == steps
				local size = if isSummit then 9 else p.Block
				ctx:Part({
					Name = if isSummit then "Summit" else "Step",
					Size = Vector3.new(size, 1.5, size),
					CFrame = ctx:At(x, h - 0.75, z, 0, math.deg(theta), 0),
					Color = if isSummit then ctx.Theme.Secondary else ctx.Theme.Floor:Lerp(colour, 0.45),
					Material = if isSummit then Enum.Material.Neon else Enum.Material.SmoothPlastic,
				})
				-- Neon lip on each step so they read against the lava glow
				if not isSummit then
					ctx:Decor({ Name = "Lip", Size = Vector3.new(size + 0.2, 0.25, size + 0.2), CFrame = ctx:At(x, h - 1.6, z, 0, math.deg(theta), 0), Color = colour, Material = Enum.Material.Neon })
				else
					-- A beacon column marks each summit from anywhere in the room
					local column = ctx:Decor({ Name = "Beacon", Shape = Enum.PartType.Cylinder, Size = Vector3.new(60, 3, 3), CFrame = ctx:At(x, h + 30, z, 0, 0, 90), Color = ctx.Theme.Secondary, Material = Enum.Material.Neon, Transparency = 0.75 })
					ctx:Animate(column, "OMF_Pulse", { PulseMin = 0.6, PulseMax = 0.9, PulseSpeed = 0.8, PulsePhase = path / p.Paths })
				end
				if step % 3 == 0 and not isSummit then
					table.insert(coinSpots, ctx:At(x, h + 3, z).Position)
				end
				theta += dTheta
			end
		end
		ctx.State.CoinSpots = coinSpots

		-- The lava itself: a shallow pool just under the floor that grows upward (its bottom stays put)
		local lava = ctx:Hazard({
			Name = "Lava",
			Size = Vector3.new(FLOOR + 8, LAVA_BOTTOM_DEPTH - 1.5, FLOOR + 8),
			CFrame = ctx:At(0, (-1.5 - LAVA_BOTTOM_DEPTH) / 2, 0),
			Color = LAVA_COLOR,
			Material = Enum.Material.Neon,
			Transparency = 0.05,
			CastShadow = false,
		})
		ctx.State.Lava = lava
		-- A bright crust sheet rides the surface, carrying the light, embers and bubbles
		local crust = ctx:Decor({ Name = "Crust", Size = Vector3.new(FLOOR + 8, 0.2, FLOOR + 8), CFrame = ctx:At(0, -1.4, 0), Color = CRUST_COLOR, Material = Enum.Material.Neon, Transparency = 0.8 })
		ctx:Animate(crust, "OMF_Pulse", { PulseMin = 0.72, PulseMax = 0.9, PulseSpeed = 0.4 })
		ctx:Glow(crust, LAVA_COLOR, 50, 2.2)
		ctx:Emitter(crust, {
			Texture = "Sparks",
			Color = ColorSequence.new(CRUST_COLOR, LAVA_COLOR),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) }),
			Speed = NumberRange.new(5, 12),
			EmissionDirection = Enum.NormalId.Top,
			SpreadAngle = Vector2.new(20, 20),
			Lifetime = NumberRange.new(0.8, 1.8),
			Acceleration = Vector3.new(0, 2, 0),
			Rate = 35,
		})
		ctx:Emitter(crust, {
			Texture = "Glow",
			Color = ColorSequence.new(CRUST_COLOR),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 2.5), NumberSequenceKeypoint.new(1, 0) }),
			Speed = NumberRange.new(0.5, 1),
			EmissionDirection = Enum.NormalId.Top,
			Lifetime = NumberRange.new(0.6, 1),
			Transparency = NumberSequence.new(0.4),
			Rate = 12,
		})
		ctx.State.Crust = crust
		-- Heat haze a little above the surface
		local haze = ctx:Decor({ Name = "Haze", Size = Vector3.new(FLOOR + 8, 0.2, FLOOR + 8), CFrame = ctx:At(0, 1.2, 0), Color = LAVA_COLOR, Material = Enum.Material.Neon, Transparency = 0.97 })
		ctx.State.Haze = haze
		-- Dark cooled-slag plates drifting on the surface give the lava texture and depth
		local slag = {}
		for _ = 1, 12 do
			local w, l = ctx.Rng:NextNumber(4, 10), ctx.Rng:NextNumber(3, 7)
			local x, z = ctx.Rng:NextNumber(-30, 30), ctx.Rng:NextNumber(-30, 30)
			local plate = ctx:Decor({ Name = "Slag", Size = Vector3.new(w, 0.3, l), CFrame = ctx:At(x, -1.35, z, 0, ctx.Rng:NextNumber(0, 180), 0), Color = SLAG_COLOR })
			table.insert(slag, { Part = plate, X = x, Z = z, Yaw = ctx.Rng:NextNumber(0, 180), Drift = ctx.Rng:NextNumber(-25, 25) })
		end
		ctx.State.Slag = slag
	end,

	Start = function(ctx)
		local p = plan(ctx)
		for k, pos in ctx.State.CoinSpots do
			if k <= 6 then
				ctx:SpawnCoin(pos)
			end
		end
		ctx:Announce("THE LAVA IS RISING!", LAVA_COLOR)
		ctx:Sound("Alarm")
		if not ctx:Wait(p.Delay) then
			return
		end
		local riseTime = 24 - p.Delay - 2
		local height = p.LavaTop + LAVA_BOTTOM_DEPTH
		local info = TweenInfo.new(riseTime, Enum.EasingStyle.Linear)
		ctx:Tween(ctx.State.Lava, info, {
			Size = Vector3.new(FLOOR + 8, height, FLOOR + 8),
			CFrame = ctx:At(0, p.LavaTop - height / 2, 0),
		})
		ctx:Tween(ctx.State.Crust, info, { CFrame = ctx:At(0, p.LavaTop + 0.1, 0) })
		ctx:Tween(ctx.State.Haze, info, { CFrame = ctx:At(0, p.LavaTop + 2.6, 0) })
		for _, s in ctx.State.Slag do
			ctx:Tween(s.Part, info, { CFrame = ctx:At(s.X, p.LavaTop + 0.15, s.Z, 0, s.Yaw + s.Drift, 0) })
		end
		ctx:Every(4, function()
			ctx:Shake(0.35, 0.5)
			return nil
		end)
	end,
}
