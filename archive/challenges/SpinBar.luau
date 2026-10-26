-- Spin Cycle: bars sweep around a round platform, faster and faster. Time your jumps.
-- Bars follow a closed-form angle(t) so clients can replay the rotation smoothly (OMF_Orbit).

local RunService = game:GetService("RunService")

local RADIUS = 36
local HUB = 4
local BAR_Y = 1.2
local BAR_THICK = 1.2
local CHASE_LIGHTS = 28

local function barOffset(): CFrame
	local length = RADIUS - HUB + 1
	return CFrame.new(0, BAR_Y, -(HUB + length / 2 - 0.5))
end

return {
	Id = "SpinBar",
	Name = "Spin Cycle",
	Hint = "Jump over the spinning bars. They keep speeding up!",
	MinFloor = 1,
	MinPlayers = 1,
	Weight = 1,
	BossOnly = false,
	Duration = 20,

	Build = function(ctx)
		local dark = ctx.Theme.Floor:Lerp(Color3.new(0, 0, 0), 0.35)
		-- Round platform with painted rings, radial spokes and a glowing rim
		ctx:Part({ Name = "Platform", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2, RADIUS * 2, RADIUS * 2), CFrame = ctx:At(0, -1, 0, 0, 0, 90) })
		ctx:RoundRim(RADIUS)
		-- larger rings sit lower so each smaller one shows on top; layers 0.04 apart (no z-fighting)
		for k = 1, 3 do
			local r = HUB + k * (RADIUS - HUB) / 3.5
			ctx:Decor({ Name = "Ring", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.02, r * 2, r * 2), CFrame = ctx:At(0, 0.03 + (3 - k) * 0.04, 0, 0, 0, 90), Color = ctx.Theme.Floor:Lerp(ctx.Theme.Primary, 0.12 + k * 0.07) })
		end
		for k = 0, 7 do
			local a = k * 45
			ctx:Decor({ Name = "Spoke", Size = Vector3.new(0.18, 0.03, RADIUS - HUB - 2), CFrame = ctx:At(0, 0.15, 0, 0, a, 0) * CFrame.new(0, 0, -(HUB + (RADIUS - HUB) / 2)), Color = ctx.Theme.Floor:Lerp(ctx.Theme.Primary, 0.3) })
		end
		-- Chase lights around the rim: each segment breathes slightly after the previous one
		for k = 1, CHASE_LIGHTS do
			local a = (k - 1) / CHASE_LIGHTS * 360
			local seg = ctx:Decor({ Name = "Chase", Size = Vector3.new(2.2, 0.25, 0.45), CFrame = ctx:At(0, 0.15, 0, 0, a, 0) * CFrame.new(0, 0, -(RADIUS + 0.5)), Color = ctx.Theme.Secondary, Material = Enum.Material.Neon })
			ctx:Animate(seg, "OMF_Pulse", { PulseMin = 0.1, PulseMax = 0.9, PulseSpeed = 0.7, PulsePhase = -(k - 1) / CHASE_LIGHTS })
		end

		-- Central hub: dark drum, neon core and a slowly turning crown
		ctx:Part({ Name = "Hub", Shape = Enum.PartType.Cylinder, Size = Vector3.new(5, HUB * 2, HUB * 2), CFrame = ctx:At(0, 2.5, 0, 0, 0, 90), Color = dark })
		local core = ctx:Decor({ Name = "HubCore", Shape = Enum.PartType.Cylinder, Size = Vector3.new(5.2, HUB * 2 - 2.5, HUB * 2 - 2.5), CFrame = ctx:At(0, 2.5, 0, 0, 0, 90), Color = ctx.Theme.Hazard, Material = Enum.Material.Neon })
		ctx:Glow(core, ctx.Theme.Hazard, 18, 1.5)
		local hubPivot = ctx:At(0, 6, 0)
		for k = 0, 3 do
			local spike = ctx:Decor({ Name = "Crown", Size = Vector3.new(1, 1.6, 1), CFrame = hubPivot * CFrame.Angles(0, math.rad(k * 90), 0) * CFrame.new(0, 0, -HUB + 0.8) * CFrame.Angles(math.rad(45), 0, math.rad(45)), Color = ctx.Theme.Secondary, Material = Enum.Material.Neon })
			ctx:Animate(spike, "OMF_Spin", { SpinPivot = hubPivot, SpinSpeed = 1.2 })
		end

		local d = math.clamp(ctx.Difficulty, 0, 1.5)
		local bars = {}
		local length = RADIUS - HUB + 1
		local function addBar(angle, dir, speedScale)
			local part = ctx:Part({
				Name = "Bar",
				Size = Vector3.new(BAR_THICK, BAR_THICK, length),
				CFrame = ctx.Origin * CFrame.Angles(0, angle, 0) * barOffset(),
				Color = ctx.Theme.Hazard,
				Material = Enum.Material.Neon,
				CanCollide = false,
				CastShadow = false,
			})
			-- the fan-shaped trail makes the sweep read even at a glance
			ctx:Trail(part, Vector3.new(0, 0, -length / 2), Vector3.new(0, 0, length / 2), ctx.Theme.Hazard, 0.2)
			table.insert(bars, { Part = part, Angle = angle, Dir = dir, Scale = speedScale })
		end
		addBar(0, 1, 1)
		if d >= 0.5 then
			addBar(math.pi, 1, 1)
		end
		if d >= 1 then
			addBar(math.pi / 2, -1, 0.75)
		end
		ctx.State.Bars = bars

		-- Spawn between the bars so nobody starts on one
		local spawns = {}
		for _, deg in { 30, 50, 70, 110, 130, 150, 210, 330 } do
			local a = math.rad(deg)
			local pos = (ctx.Origin * CFrame.Angles(0, a, 0) * CFrame.new(0, 3, -18)).Position
			table.insert(spawns, CFrame.lookAt(pos, ctx.Origin.Position + Vector3.new(0, 3, 0)))
		end
		ctx:SetSpawns(spawns)
	end,

	Start = function(ctx)
		local d = math.clamp(ctx.Difficulty, 0, 1.5)
		local base = 0.9 + 0.55 * d
		local ramp = 0.035 + 0.02 * d

		for _ = 1, 5 do
			local a = ctx.Rng:NextNumber(0, math.pi * 2)
			local r = ctx.Rng:NextNumber(HUB + 6, RADIUS - 3)
			ctx:SpawnCoin((ctx.Origin * CFrame.Angles(0, a, 0) * CFrame.new(0, 3, -r)).Position)
		end

		local startTime = workspace:GetServerTimeNow()
		local offset = barOffset()
		for _, bar in ctx.State.Bars do
			ctx:MakeHazard(bar.Part)
			ctx:Animate(bar.Part, "OMF_Orbit", {
				OrbitCenter = ctx.Origin,
				OrbitOffset = offset,
				Angle0 = bar.Angle,
				Omega0 = base * bar.Scale,
				Ramp = ramp * bar.Scale,
				Dir = bar.Dir,
				StartTime = startTime,
			})
		end
		ctx:Sound("Whoosh")

		local stopped = false
		ctx.Trove:Connect(RunService.Heartbeat, function()
			if ctx.Ended then
				if not stopped then
					stopped = true
					local now = workspace:GetServerTimeNow()
					for _, bar in ctx.State.Bars do
						bar.Part:SetAttribute("StopTime", now)
					end
				end
				return
			end
			local t = workspace:GetServerTimeNow() - startTime
			for _, bar in ctx.State.Bars do
				local angle = bar.Angle + bar.Dir * bar.Scale * (base * t + 0.5 * ramp * t * t)
				bar.Part.CFrame = ctx.Origin * CFrame.Angles(0, angle, 0) * offset
			end
		end)
	end,
}
