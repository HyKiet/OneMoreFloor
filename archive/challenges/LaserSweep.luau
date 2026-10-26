-- Laser Sweep: low laser bars sweep across the floor. Jump over them.

local RunService = game:GetService("RunService")

local SIZE = 70
local HALF = SIZE / 2
local BAR_Y = 1.1
local BAR_THICK = 0.8

-- Sends one laser across the floor along `axis` ("X" or "Z") in direction `dir` (+1/-1).
-- The beam rides between two emitter heads on the rails and lights the floor as it passes.
local function sweep(ctx, axis: string, dir: number, speed: number, telegraph: number, offset: number?)
	local start = -dir * (HALF + 1) + (offset or 0) * -dir
	local finish = dir * (HALF + 3)
	local length = SIZE + 4
	local size = if axis == "Z" then Vector3.new(length, BAR_THICK, BAR_THICK) else Vector3.new(BAR_THICK, BAR_THICK, length)
	local function at(t: number): CFrame
		return if axis == "Z" then ctx:At(0, BAR_Y, t) else ctx:At(t, BAR_Y, 0)
	end
	local along = if axis == "Z" then Vector3.new(1, 0, 0) else Vector3.new(0, 0, 1)
	local travelDir = if axis == "Z" then Vector3.new(0, 0, dir) else Vector3.new(dir, 0, 0)

	-- Telegraph: the strip it enters from fills toward its direction of travel
	local edge = -dir * (HALF - 3)
	local stripSize = if axis == "Z" then Vector3.new(SIZE, 0.2, 6) else Vector3.new(6, 0.2, SIZE)
	local stripAt = if axis == "Z" then ctx:At(0, 0.1, edge) else ctx:At(edge, 0.1, 0)
	ctx:Warn(stripAt, stripSize, telegraph, nil, { Sweep = travelDir })
	ctx:Sound("Warning")

	ctx:After(telegraph, function()
		local bar = ctx:Hazard({ Name = "Laser", Size = size, CFrame = at(start), CastShadow = false })
		local glowSize = if axis == "Z" then Vector3.new(length, 2.2, 2.2) else Vector3.new(2.2, 2.2, length)
		local glow = ctx:Decor({ Name = "LaserGlow", Size = glowSize, CFrame = at(start), Color = ctx.Theme.Hazard, Material = Enum.Material.Neon, Transparency = 0.8 })
		local heads = {}
		for _, s in { -1, 1 } do
			local offsetCF = CFrame.new(along * s * (length / 2 + 0.6))
			local head = ctx:Decor({ Name = "Emitter", Size = Vector3.new(2.4, 2.6, 2.4), CFrame = at(start) * offsetCF, Color = ctx.Theme.Secondary:Lerp(Color3.new(0, 0, 0), 0.35), Material = Enum.Material.SmoothPlastic })
			local lens = ctx:Decor({ Name = "Lens", Size = Vector3.new(1.4, 1.4, 1.4), CFrame = at(start) * CFrame.new(along * s * (length / 2 - 0.4)), Color = ctx.Theme.Hazard:Lerp(Color3.new(1, 1, 1), 0.4), Material = Enum.Material.Neon })
			table.insert(heads, { Part = head, Offset = offsetCF })
			table.insert(heads, { Part = lens, Offset = CFrame.new(along * s * (length / 2 - 0.4)) })
		end
		ctx:Glow(bar, ctx.Theme.Hazard, 14, 2.5)
		ctx:Sound("Laser", bar)

		local travel = math.abs(finish - start) / speed
		local info = TweenInfo.new(travel, Enum.EasingStyle.Linear)
		ctx:Tween(bar, info, { CFrame = at(finish) })
		ctx:Tween(glow, info, { CFrame = at(finish) })
		for _, h in heads do
			ctx:Tween(h.Part, info, { CFrame = at(finish) * h.Offset })
		end
		task.delay(travel + 0.05, function()
			bar:Destroy()
			glow:Destroy()
			for _, h in heads do
				h.Part:Destroy()
			end
		end)
	end)
end

return {
	Id = "LaserSweep",
	Name = "Laser Sweep",
	Hint = "Jump over the lasers sweeping across the floor!",
	MinFloor = 1,
	MinPlayers = 1,
	Weight = 1,
	BossOnly = false,
	Duration = 20,

	Build = function(ctx)
		ctx:Part({ Name = "Floor", Size = Vector3.new(SIZE, 2, SIZE), CFrame = ctx:At(0, -1, 0), Color = ctx.Theme.Floor:Lerp(Color3.new(0, 0, 0), 0.15) })
		-- Fine grid so the beams' motion reads well, brighter every other line
		for k = -3, 3 do
			local p = k * 10
			local c = ctx.Theme.Floor:Lerp(ctx.Theme.Primary, if k % 2 == 0 then 0.45 else 0.25)
			-- the two directions sit 0.04 apart so the crossings don't z-fight
			ctx:Decor({ Name = "Line", Size = Vector3.new(SIZE, 0.05, 0.25), CFrame = ctx:At(0, 0.045, p), Color = c })
			ctx:Decor({ Name = "Line", Size = Vector3.new(0.25, 0.03, SIZE), CFrame = ctx:At(p, 0.015, 0), Color = c })
		end
		ctx:Rim(HALF, HALF)
		-- Raised rails the emitters ride on
		for _, s in { { 0, HALF + 1, SIZE + 4, 1.4 }, { 0, -HALF - 1, SIZE + 4, 1.4 }, { HALF + 1, 0, 1.4, SIZE }, { -HALF - 1, 0, 1.4, SIZE } } do
			ctx:Decor({ Name = "Rail", Size = Vector3.new(s[3], 0.6, s[4]), CFrame = ctx:At(s[1], -0.3, s[2]), Color = ctx.Theme.Floor:Lerp(Color3.new(0, 0, 0), 0.4), CanCollide = true })
			ctx:Decor({ Name = "RailLight", Size = Vector3.new(math.max(s[3] - 1, 0.3), 0.1, math.max(s[4] - 1, 0.3)), CFrame = ctx:At(s[1], 0.02, s[2]), Color = ctx.Theme.Hazard:Lerp(ctx.Theme.Floor, 0.45), Material = Enum.Material.Neon })
		end
		-- Corner emitter towers with breathing caps
		for k, c in { { 1, 1 }, { 1, -1 }, { -1, -1 }, { -1, 1 } } do
			ctx:Decor({ Name = "Tower", Size = Vector3.new(2.6, 7, 2.6), CFrame = ctx:At(c[1] * (HALF + 1.5), 3.5, c[2] * (HALF + 1.5)), Color = ctx.Theme.Floor:Lerp(Color3.new(0, 0, 0), 0.3) })
			local cap = ctx:Decor({ Name = "TowerCap", Size = Vector3.new(2, 1.2, 2), CFrame = ctx:At(c[1] * (HALF + 1.5), 7.6, c[2] * (HALF + 1.5)), Color = ctx.Theme.Secondary, Material = Enum.Material.Neon })
			ctx:Animate(cap, "OMF_Pulse", { PulseMin = 0, PulseMax = 0.5, PulseSpeed = 1.2, PulsePhase = k / 4 })
		end
	end,

	Start = function(ctx)
		local d = math.clamp(ctx.Difficulty, 0, 1.5)
		local speed = 11 + 14 * d
		local telegraph = 1.1 - 0.45 * math.min(d, 1)
		local interval = math.max(3.2 - 1.6 * d, 1)

		for _ = 1, 5 do
			ctx:SpawnCoin(ctx:At(ctx.Rng:NextNumber(-28, 28), 3, ctx.Rng:NextNumber(-28, 28)).Position)
		end

		ctx:Every(interval, function(elapsed)
			local axis = if ctx.Rng:NextNumber() < 0.5 then "X" else "Z"
			local dir = if ctx.Rng:NextNumber() < 0.5 then 1 else -1
			local ramp = speed + elapsed * 0.4
			sweep(ctx, axis, dir, ramp, telegraph)
			-- Double bars: a second laser right behind the first
			if d >= 0.6 and ctx.Rng:NextNumber() < 0.5 then
				sweep(ctx, axis, dir, ramp, telegraph, 8)
			end
			-- Crossing lasers on deep floors
			if d >= 1 and ctx.Rng:NextNumber() < 0.35 then
				sweep(ctx, if axis == "X" then "Z" else "X", -dir, ramp * 0.85, telegraph)
			end
			return nil
		end)

		-- A rotating bar from the centre on harder floors (rendered smoothly by clients via OMF_Orbit)
		if d >= 0.5 then
			local length = HALF - 2
			local hub = ctx:Part({ Name = "Hub", Shape = Enum.PartType.Cylinder, Size = Vector3.new(4, 3.4, 3.4), CFrame = ctx:At(0, 2, 0, 0, 0, 90), Color = ctx.Theme.Floor:Lerp(Color3.new(0, 0, 0), 0.3) })
			hub.CanCollide = true
			local core = ctx:Decor({ Name = "HubCore", Shape = Enum.PartType.Cylinder, Size = Vector3.new(4.2, 2, 2), CFrame = ctx:At(0, 2, 0, 0, 0, 90), Color = ctx.Theme.Hazard, Material = Enum.Material.Neon })
			ctx:Glow(core, ctx.Theme.Hazard, 16, 2)
			local offset = CFrame.new(0, BAR_Y, -(length / 2 + 1.5))
			local bar = ctx:Part({ Name = "SpinLaser", Size = Vector3.new(BAR_THICK, BAR_THICK, length), CFrame = ctx.Origin * offset, Color = ctx.Theme.Hazard, Material = Enum.Material.Neon, Transparency = 0.6, CanCollide = false, CastShadow = false })
			ctx:Trail(bar, Vector3.new(0, 0, -length / 2), Vector3.new(0, 0, length / 2), ctx.Theme.Hazard, 0.18)
			local omega = 0.7 + 0.5 * d
			local startTime = workspace:GetServerTimeNow()
			ctx:Animate(bar, "OMF_Orbit", { OrbitCenter = ctx.Origin, OrbitOffset = offset, Angle0 = 0, Omega0 = omega, Ramp = 0, Dir = 1, StartTime = startTime })
			local stopped = false
			ctx.Trove:Connect(RunService.Heartbeat, function()
				if ctx.Ended then
					if not stopped then
						stopped = true
						bar:SetAttribute("StopTime", workspace:GetServerTimeNow())
					end
					return
				end
				local angle = omega * (workspace:GetServerTimeNow() - startTime)
				bar.CFrame = ctx.Origin * CFrame.Angles(0, angle, 0) * offset
			end)
			-- Arms after a short grace so nobody spawns inside it
			ctx:After(1.2, function()
				bar.Transparency = 0
				ctx:MakeHazard(bar)
			end)
		end
	end,
}
