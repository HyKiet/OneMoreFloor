-- Shrinking Stage: the platform crumbles from the outside in while balls try to bump you off.

local TILE = 5
local RADIUS = 34

local function plan(ctx)
	local d = math.clamp(ctx.Difficulty, 0, 1.5)
	return {
		MinRadius = 12 - 4 * math.min(d, 1),
		Steps = 4 + (if d >= 0.7 then 1 else 0),
		Telegraph = 1.4 - 0.65 * math.min(d / 1.2, 1),
		Balls = d >= 0.3,
		BallInterval = math.max(3 - 1.2 * d, 1.2),
		BallSpeed = 32 + 18 * d,
	}
end

-- Rolls a heavy glowing ball across the platform from the rim.
local function launchBall(ctx, radius, speed)
	local angle = ctx.Rng:NextNumber(0, math.pi * 2)
	local from = (ctx.Origin * CFrame.Angles(0, angle, 0) * CFrame.new(0, 3, -(radius + 4))).Position
	local aim = ctx:At(ctx.Rng:NextNumber(-6, 6), 3, ctx.Rng:NextNumber(-6, 6)).Position
	ctx:Warn(CFrame.new(from), Vector3.new(6, 6, 6), 0.7, ctx.Theme.Secondary)
	ctx:After(0.7, function()
		local ball = ctx:Part({
			Name = "Bumper",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(5, 5, 5),
			CFrame = CFrame.new(from),
			Color = ctx.Theme.Secondary,
			Material = Enum.Material.Neon,
			Anchored = false,
			CastShadow = false,
			CustomPhysicalProperties = PhysicalProperties.new(4, 0.2, 0.3),
		})
		pcall(function()
			ball:SetNetworkOwner(nil)
		end)
		ball.AssemblyLinearVelocity = (aim - from).Unit * speed
		ctx:Glow(ball, ctx.Theme.Secondary, 12, 1.5)
		ctx:Fx("Burst", { Position = from, Color = ctx.Theme.Secondary, Count = 18 })
		ctx:Sound("Whoosh", ball)
		task.delay(6, function()
			ball:Destroy()
		end)
	end)
end

return {
	Id = "ShrinkingPlatform",
	Name = "Shrinking Stage",
	Hint = "The edge keeps crumbling away. Stay near the middle!",
	MinFloor = 1,
	MinPlayers = 1,
	Weight = 1,
	BossOnly = false,
	Duration = 22,

	Build = function(ctx)
		local tiles = {}
		local cells = math.ceil(RADIUS * 2 / TILE)
		for i = 0, cells - 1 do
			for j = 0, cells - 1 do
				local x = (i - (cells - 1) / 2) * TILE
				local z = (j - (cells - 1) / 2) * TILE
				local dist = math.sqrt(x * x + z * z)
				if dist <= RADIUS - 1 then
					-- slightly inset tiles: the thin gaps make the crumble pattern readable
					local part = ctx:Part({
						Name = "Tile",
						Size = Vector3.new(TILE - 0.25, 2, TILE - 0.25),
						CFrame = ctx:At(x, -1, z),
						Color = ctx.Theme.Floor:Lerp(ctx.Theme.Primary, 0.08 + 0.4 * (dist / RADIUS) ^ 2),
					})
					table.insert(tiles, { Part = part, Dist = dist, Gone = false })
				end
			end
		end
		ctx.State.Tiles = tiles
		-- Neon core marker that never falls, breathing gently
		local core = ctx:Decor({ Name = "Core", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, 6, 6), CFrame = ctx:At(0, 0.05, 0, 0, 0, 90), Color = ctx.Theme.Secondary, Material = Enum.Material.Neon })
		ctx:Animate(core, "OMF_Pulse", { PulseMin = 0, PulseMax = 0.6, PulseSpeed = 0.5 })
		local halo = ctx:Decor({ Name = "Halo", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.06, 9, 9), CFrame = ctx:At(0, 0.03, 0, 0, 0, 90), Color = ctx.Theme.Secondary, Material = Enum.Material.Neon, Transparency = 0.75 })
		ctx:Animate(halo, "OMF_Pulse", { PulseMin = 0.6, PulseMax = 0.95, PulseSpeed = 0.5, PulsePhase = 0.5 })

		-- Floating ring of pylons around the stage
		for k = 0, 7 do
			local a = k * 45 + 22.5
			local base = ctx:At(0, 0, 0, 0, a, 0) * CFrame.new(0, 0, -(RADIUS + 7))
			ctx:Decor({ Name = "Pylon", Size = Vector3.new(1.4, 9, 1.4), CFrame = base * CFrame.new(0, 2, 0), Color = ctx.Theme.Floor:Lerp(Color3.new(0, 0, 0), 0.3) })
			local cap = ctx:Decor({ Name = "PylonCap", Size = Vector3.new(1.6, 1.6, 1.6), CFrame = base * CFrame.new(0, 7.4, 0) * CFrame.Angles(math.rad(45), 0, math.rad(45)), Color = ctx.Theme.Primary, Material = Enum.Material.Neon })
			ctx:Animate(cap, "OMF_Spin", { SpinSpeed = 1.5 })
		end
	end,

	Start = function(ctx)
		local p = plan(ctx)
		local tiles = ctx.State.Tiles
		local current = RADIUS

		-- Coins near the rim tempt players outward
		for _ = 1, 5 do
			local a = ctx.Rng:NextNumber(0, math.pi * 2)
			ctx:SpawnCoin((ctx.Origin * CFrame.Angles(0, a, 0) * CFrame.new(0, 3, -(RADIUS - 5))).Position)
		end

		if p.Balls then
			ctx:Every(p.BallInterval, function()
				launchBall(ctx, current, p.BallSpeed)
				return nil
			end)
		end

		if not ctx:Wait(3) then
			return
		end
		local stepTime = (22 - 4) / p.Steps
		for step = 1, p.Steps do
			local target = RADIUS - (RADIUS - p.MinRadius) * step / p.Steps
			local doomed = {}
			for _, tile in tiles do
				if not tile.Gone and tile.Dist > target then
					table.insert(doomed, tile)
					tile.Part.Material = Enum.Material.Neon
					ctx:Tween(tile.Part, TweenInfo.new(p.Telegraph / 4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 3, true), {
						Color = ctx.Theme.Hazard,
					})
				end
			end
			-- Preview of the ground that will survive
			local safe = ctx:Decor({ Name = "SafePreview", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.08, target * 2, target * 2), CFrame = ctx:At(0, 0.06, 0, 0, 0, 90), Color = ctx.Theme.Secondary, Material = Enum.Material.Neon, Transparency = 0.82 })
			ctx:Sound("Warning")
			if not ctx:Wait(p.Telegraph) then
				return
			end
			safe:Destroy()
			local rubble = {}
			for k, tile in doomed do
				tile.Gone = true
				tile.Part.CanCollide = false
				local drift = ctx.Rng:NextNumber(-20, 20)
				ctx:Tween(tile.Part, TweenInfo.new(0.8 + ctx.Rng:NextNumber(0, 0.3), Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					CFrame = tile.Part.CFrame * CFrame.new(0, -30, 0) * CFrame.Angles(math.rad(drift), 0, math.rad(-drift)),
					Transparency = 1,
				})
				if k % 3 == 0 and #rubble < 24 then
					table.insert(rubble, tile.Part.Position)
				end
			end
			ctx:Fx("Chunks", { Positions = rubble, Color = ctx.Theme.Hazard, Size = 1.4 })
			current = target
			ctx:Shake(0.5, 0.3)
			ctx:Sound("Impact")
			if not ctx:Wait(math.max(stepTime - p.Telegraph, 0.5)) then
				return
			end
		end
	end,
}
