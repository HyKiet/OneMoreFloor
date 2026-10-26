-- Lock-On: a satellite drone hovers over a radar floor. Every volley it paints a reticle on each player
-- that chases them with a little lag, locks (turns red), then fires a beam down through the reticle.
-- Keep moving, and when your reticle locks, get out of the circle!

local RunService = game:GetService("RunService")

local SIZE = 64
local HALF = SIZE / 2
local SCREEN_R = 29 -- radius of the radar "screen" painted on the floor
local DRONE_Y = 30
local LENS_DROP = 3 -- the lens hangs this far below the drone's pivot
local RET_Y = 0.8 -- reticles float above every floor marking
local SWEEP_SPEED = 0.9 -- radar sweep, rad/s (client-side OMF_Spin)

local function plan(ctx)
	local d = math.clamp(ctx.Difficulty, 0, 1.5)
	local m = math.min(d, 1)
	return {
		Track = 1.5 - 0.5 * m,
		Lock = 0.8 - 0.3 * m,
		Pause = 1.3 - 0.4 * m,
		Follow = 3.5 + 2.5 * m,
		Radius = 4.5 + 1.5 * m,
		Double = d >= 0.8,
		D = d,
	}
end

local function clampToFloor(v: number): number
	return math.clamp(v, -HALF + 1, HALF - 1)
end

-- Reticles -----------------------------------------------------------------------------------------

-- A reticle: a see-through neon disc, four crosshair ticks and a thin tracking line up to the drone lens.
local function newReticle(ctx, x: number, z: number, radius: number, color: Color3)
	local r = { X = x, Z = z, Radius = radius, Spin = ctx.Rng:NextNumber(0, math.pi), Pieces = {}, Ticks = {} }
	r.Disc = ctx:Decor({ Name = "Reticle", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, radius * 2, radius * 2), Color = color, Material = Enum.Material.Neon, Transparency = 0.72 })
	table.insert(r.Pieces, { Part = r.Disc, Offset = CFrame.Angles(0, 0, math.rad(90)) })
	for k = 0, 3 do
		local tick = ctx:Decor({ Name = "ReticleTick", Size = Vector3.new(0.35, 0.14, 1.8), Color = color, Material = Enum.Material.Neon })
		local offset = CFrame.Angles(0, k * math.pi / 2, 0) * CFrame.new(0, 0.1, -(radius - 0.5))
		table.insert(r.Pieces, { Part = tick, Offset = offset })
		table.insert(r.Ticks, { Part = tick, Angle = k * math.pi / 2 })
	end
	r.Line = ctx:Decor({ Name = "TrackLine", Size = Vector3.new(0.12, 0.12, 1), Color = color, Material = Enum.Material.Neon, Transparency = 0.55 })
	return r
end

local function reticleBase(ctx, r): CFrame
	return ctx:At(r.X, RET_Y, r.Z) * CFrame.Angles(0, r.Spin, 0)
end

local function placeReticle(ctx, r)
	local base = reticleBase(ctx, r)
	for _, piece in r.Pieces do
		piece.Part.CFrame = base * piece.Offset
	end
	local from = ctx.State.LensPos
	local to = base.Position
	r.Line.Size = Vector3.new(r.Line.Size.X, r.Line.Size.Y, (to - from).Magnitude)
	r.Line.CFrame = CFrame.lookAt((from + to) / 2, to)
end

local function destroyReticle(r)
	for _, piece in r.Pieces do
		piece.Part:Destroy()
	end
	r.Line:Destroy()
end

-- Locks a reticle in place: it turns hazard red, the ticks close in and the floor telegraph fills up.
local function lock(ctx, r, time: number)
	local hazard = ctx.Theme.Hazard
	r.Disc.Color = hazard
	r.Disc.Transparency = 0.6
	r.Line.Color = hazard
	r.Line.Transparency = 0.25
	r.Line.Size = Vector3.new(0.3, 0.3, r.Line.Size.Z)
	local base = reticleBase(ctx, r)
	local info = TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	for _, tick in r.Ticks do
		tick.Part.Color = hazard
		ctx:Tween(tick.Part, info, { CFrame = base * CFrame.Angles(0, tick.Angle, 0) * CFrame.new(0, 0.1, -r.Radius * 0.45) })
	end
	ctx:Warn(ctx:At(r.X, RET_Y + 0.25, r.Z), Vector3.new(r.Radius * 2, 0.2, r.Radius * 2), time, hazard, { Shape = "Disc" })
end

-- Fires the drone's beam down onto (x, z): everyone inside the circle is out.
local function strike(ctx, x: number, z: number, radius: number)
	local hazard = ctx.Theme.Hazard
	local ground = ctx:At(x, 0.1, z).Position
	ctx:Fx("Shot", { From = ctx.State.LensPos, To = ground, Color = hazard })
	-- a short-lived beam column: a soft outer shaft and a white-hot core
	local height = DRONE_Y - LENS_DROP - 0.3
	local column = ctx:Decor({ Name = "StrikeBeam", Shape = Enum.PartType.Cylinder, Size = Vector3.new(height, radius * 2, radius * 2), CFrame = ctx:At(x, 0.1 + height / 2, z, 0, 0, 90), Color = hazard, Material = Enum.Material.Neon, Transparency = 0.5 })
	local core = ctx:Decor({ Name = "StrikeCore", Shape = Enum.PartType.Cylinder, Size = Vector3.new(height + 0.4, radius * 0.6, radius * 0.6), CFrame = ctx:At(x, 0.1 + height / 2, z, 0, 0, 90), Color = hazard:Lerp(Color3.new(1, 1, 1), 0.55), Material = Enum.Material.Neon, Transparency = 0.05 })
	local fade = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	ctx:Tween(column, fade, { Size = Vector3.new(height, 0.3, 0.3), Transparency = 1 })
	ctx:Tween(core, fade, { Size = Vector3.new(height + 0.4, 0.1, 0.1), Transparency = 1 })
	task.delay(0.4, function()
		column:Destroy()
		core:Destroy()
	end)
	ctx:Impact(ground, hazard, radius * 1.6, 4)

	for _, player in ctx:GetAlive() do
		local pos = ctx:LocalPosition(player)
		if pos and pos.Y > -6 and Vector2.new(pos.X - x, pos.Z - z).Magnitude <= radius then
			ctx:Eliminate(player, "Locked on")
		end
	end
end

-- One volley: deploy a reticle per player, chase, lock, strike (and a quick follow-up on deep floors).
local function volley(ctx, p)
	local reticles = {}
	for _, player in ctx:GetAlive() do
		-- reticles drop out of the drone at the centre and swoop toward their targets
		local r = newReticle(ctx, 0, 0, p.Radius, ctx.Theme.Secondary)
		r.Player = player
		placeReticle(ctx, r)
		table.insert(reticles, r)
	end
	if #reticles == 0 then
		ctx:Wait(0.5)
		return
	end
	local function cleanup(list)
		for _, r in list do
			destroyReticle(r)
		end
	end
	ctx:Sound("Whoosh")
	ctx:Fx("Burst", { Position = ctx.State.LensPos, Color = ctx.Theme.Secondary, Count = 16 })

	-- Track: pos += (target - pos) * min(1, Follow * dt)
	local t = 0
	while t < p.Track do
		local dt = RunService.Heartbeat:Wait()
		if ctx.Ended then
			cleanup(reticles)
			return
		end
		t += dt
		local a = math.min(1, p.Follow * dt)
		for _, r in reticles do
			local target = ctx:LocalPosition(r.Player)
			if target then
				r.X = clampToFloor(r.X + (target.X - r.X) * a)
				r.Z = clampToFloor(r.Z + (target.Z - r.Z) * a)
			end
			r.Spin += dt * 2.5
			placeReticle(ctx, r)
		end
	end

	-- Lock
	for _, r in reticles do
		lock(ctx, r, p.Lock)
	end
	ctx:Sound("Warning")
	if not ctx:Wait(p.Lock) then
		cleanup(reticles)
		return
	end

	-- Strike
	for _, r in reticles do
		strike(ctx, r.X, r.Z, r.Radius)
	end
	cleanup(reticles)
	ctx:Sound("Laser")
	ctx:Shake(0.5, 0.25)

	-- Deep floors: a quick second strike lands right where each target is now (no tracking, short lock)
	if p.Double then
		local quick = {}
		for _, player in ctx:GetAlive() do
			local pos = ctx:LocalPosition(player)
			if pos then
				local r = newReticle(ctx, clampToFloor(pos.X), clampToFloor(pos.Z), p.Radius * 0.85, ctx.Theme.Hazard)
				placeReticle(ctx, r)
				lock(ctx, r, p.Lock + 0.15)
				table.insert(quick, r)
			end
		end
		if #quick > 0 then
			ctx:Sound("Warning")
			if not ctx:Wait(p.Lock + 0.15) then
				cleanup(quick)
				return
			end
			for _, r in quick do
				strike(ctx, r.X, r.Z, r.Radius)
			end
			cleanup(quick)
			ctx:Sound("Laser")
		end
	end
end

-- Build helpers ------------------------------------------------------------------------------------

-- The satellite drone: hull, dome, solar wings, antenna and a neon lens underneath. Everything spins
-- slowly about the vertical axis through the lens (client-side OMF_Spin), so the lens never moves.
local function buildDrone(ctx)
	local pivot = ctx:At(0, DRONE_Y, 0)
	local dark = ctx.Theme.Floor:Lerp(Color3.new(0, 0, 0), 0.5)
	local metal = ctx.Theme.Floor:Lerp(Color3.new(1, 1, 1), 0.3)
	local panel = ctx.Theme.Primary:Lerp(Color3.new(0, 0, 0), 0.65)
	local function piece(offset: CFrame, props): BasePart
		props.CFrame = pivot * offset
		local part = ctx:Decor(props)
		ctx:Animate(part, "OMF_Spin", { SpinPivot = pivot, SpinSpeed = 0.7 })
		return part
	end
	local vertical = CFrame.Angles(0, 0, math.rad(90)) -- cylinder axis pointing up

	piece(vertical, { Name = "DroneHull", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3, 7, 7), Color = dark, Material = Enum.Material.Metal })
	piece(vertical, { Name = "DroneBand", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, 7.3, 7.3), Color = ctx.Theme.Primary, Material = Enum.Material.Neon })
	piece(CFrame.new(0, 1.2, 0), { Name = "DroneDome", Shape = Enum.PartType.Ball, Size = Vector3.new(4.6, 4.6, 4.6), Color = metal })
	piece(CFrame.new(0, 4.5, 0) * vertical, { Name = "Antenna", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3, 0.2, 0.2), Color = metal })
	local tip = piece(CFrame.new(0, 6.1, 0), { Name = "AntennaTip", Shape = Enum.PartType.Ball, Size = Vector3.new(0.7, 0.7, 0.7), Color = ctx.Theme.Hazard, Material = Enum.Material.Neon })
	ctx:Animate(tip, "OMF_Pulse", { PulseMin = 0, PulseMax = 0.95, PulseSpeed = 1.5 })
	-- Solar wings
	piece(CFrame.new(), { Name = "WingArm", Size = Vector3.new(16, 0.4, 0.8), Color = metal })
	for _, s in { -1, 1 } do
		piece(CFrame.new(s * 11, 0, 0), { Name = "SolarPanel", Size = Vector3.new(6, 0.25, 3.6), Color = panel })
		for _, dz in { -1.1, 0, 1.1 } do
			piece(CFrame.new(s * 11, 0.16, dz), { Name = "PanelLine", Size = Vector3.new(5.6, 0.1, 0.25), Color = ctx.Theme.Primary, Material = Enum.Material.Neon })
		end
	end
	-- Running lights around the hull
	for k = 0, 3 do
		local light = piece(CFrame.Angles(0, k * math.pi / 2 + math.pi / 4, 0) * CFrame.new(0, -0.9, -3.45), { Name = "HullLight", Size = Vector3.new(0.6, 0.5, 0.5), Color = ctx.Theme.Secondary, Material = Enum.Material.Neon })
		ctx:Animate(light, "OMF_Pulse", { PulseMin = 0, PulseMax = 0.8, PulseSpeed = 1.1, PulsePhase = k / 4 })
	end
	-- Lens
	piece(CFrame.new(0, -1.6, 0) * vertical, { Name = "LensRing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 4, 4), Color = ctx.Theme.Secondary, Material = Enum.Material.Neon })
	local lens = piece(CFrame.new(0, -2, 0), { Name = "Lens", Shape = Enum.PartType.Ball, Size = Vector3.new(2.4, 2.4, 2.4), Color = ctx.Theme.Hazard, Material = Enum.Material.Neon })
	ctx:Glow(lens, ctx.Theme.Hazard, 22, 2)
	ctx.State.LensPos = ctx:At(0, DRONE_Y - LENS_DROP, 0).Position
end

-- Corner radar pylons with a dish aimed at the floor and a blinking beacon.
local function buildPylons(ctx)
	local dark = ctx.Theme.Floor:Lerp(Color3.new(0, 0, 0), 0.4)
	local metal = ctx.Theme.Floor:Lerp(Color3.new(1, 1, 1), 0.3)
	for k, c in { { 1, 1 }, { 1, -1 }, { -1, -1 }, { -1, 1 } } do
		local pos = ctx:At(c[1] * (HALF + 2.5), 2, c[2] * (HALF + 2.5)).Position
		local frame = CFrame.lookAt(pos, ctx:At(0, 2, 0).Position) -- local -Z faces the centre
		ctx:Decor({ Name = "Pylon", Size = Vector3.new(2.6, 12, 2.6), CFrame = frame, Color = dark, CanCollide = true })
		ctx:Decor({ Name = "PylonLight", Size = Vector3.new(0.6, 10, 0.2), CFrame = frame * CFrame.new(0, -0.5, -1.38), Color = ctx.Theme.Primary, Material = Enum.Material.Neon })
		local dishPos = (frame * CFrame.new(0, 4.6, -1.9)).Position
		local facing = (frame * CFrame.Angles(math.rad(-30), 0, 0)).LookVector -- toward the centre, tipped down
		local dish = CFrame.lookAt(dishPos, dishPos + facing) * CFrame.Angles(0, math.rad(90), 0)
		ctx:Decor({ Name = "Dish", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 4, 4), CFrame = dish, Color = metal })
		ctx:Decor({ Name = "DishFeed", Shape = Enum.PartType.Ball, Size = Vector3.new(0.7, 0.7, 0.7), CFrame = dish * CFrame.new(0.55, 0, 0), Color = ctx.Theme.Secondary, Material = Enum.Material.Neon })
		local beacon = ctx:Decor({ Name = "Beacon", Shape = Enum.PartType.Ball, Size = Vector3.new(1.6, 1.6, 1.6), CFrame = frame * CFrame.new(0, 6.7, 0), Color = ctx.Theme.Hazard, Material = Enum.Material.Neon })
		ctx:Animate(beacon, "OMF_Pulse", { PulseMin = 0, PulseMax = 0.95, PulseSpeed = 1.2, PulsePhase = k / 4 })
	end
end

return {
	Id = "LockOn",
	Name = "Lock-On",
	Hint = "Targeting reticles chase you. When one locks, get out of the circle!",
	MinFloor = 4,
	MinPlayers = 1,
	Weight = 1,
	BossOnly = false,
	Duration = 20,

	Build = function(ctx)
		local base = ctx.Theme.Floor:Lerp(Color3.new(0, 0, 0), 0.25)
		local screen = ctx.Theme.Floor:Lerp(ctx.Theme.Primary, 0.1):Lerp(Color3.new(0, 0, 0), 0.35)
		local line = ctx.Theme.Floor:Lerp(ctx.Theme.Primary, 0.55)
		ctx:Part({ Name = "Floor", Size = Vector3.new(SIZE, 2, SIZE), CFrame = ctx:At(0, -1, 0), Color = base })
		ctx:Rim(HALF, HALF, ctx.Theme.Primary, ctx.Theme.Secondary)

		-- Radar screen: each range ring is a bright disc with a slightly smaller screen disc on top.
		-- Larger rings sit lower; every layer is 0.04 above the previous one (no z-fighting).
		for k, r in { SCREEN_R, 22, 15, 8 } do
			local y = 0.03 + (k - 1) * 0.08
			ctx:Decor({ Name = "RangeRing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.02, r * 2, r * 2), CFrame = ctx:At(0, y, 0, 0, 0, 90), Color = line, Material = if k == 1 then Enum.Material.Neon else Enum.Material.SmoothPlastic })
			ctx:Decor({ Name = "Screen", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.02, r * 2 - (if k == 1 then 0.9 else 0.5), r * 2 - (if k == 1 then 0.9 else 0.5)), CFrame = ctx:At(0, y + 0.04, 0, 0, 0, 90), Color = screen })
		end
		ctx:Decor({ Name = "CentreDot", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.02, 1.6, 1.6), CFrame = ctx:At(0, 0.345, 0, 0, 0, 90), Color = ctx.Theme.Primary, Material = Enum.Material.Neon })
		-- Crosshair lines (the two directions sit 0.04 apart where they cross)
		ctx:Decor({ Name = "Crosshair", Size = Vector3.new(0.25, 0.03, SCREEN_R * 2 - 1), CFrame = ctx:At(0, 0.385, 0), Color = line })
		ctx:Decor({ Name = "Crosshair", Size = Vector3.new(SCREEN_R * 2 - 1, 0.03, 0.25), CFrame = ctx:At(0, 0.425, 0), Color = line })
		-- Bearing ticks just outside the screen
		for k = 0, 23 do
			local long = k % 3 == 0
			ctx:Decor({ Name = "Bearing", Size = Vector3.new(0.25, 0.06, if long then 1.8 else 1.1), CFrame = ctx:At(0, 0.03, 0, 0, k * 15, 0) * CFrame.new(0, 0, -(SCREEN_R + 0.6 + (if long then 0.9 else 0.55))), Color = if long then ctx.Theme.Primary else line, Material = if long then Enum.Material.Neon else Enum.Material.SmoothPlastic })
		end

		-- Rotating radar sweep: a bright arm with a fading sector trailing behind it (two flat wedges).
		local pivot = ctx:At(0, 0, 0)
		local armLength = SCREEN_R - 0.5
		local function sweepPart(props)
			local part = ctx:Decor(props)
			ctx:Animate(part, "OMF_Spin", { SpinPivot = pivot, SpinSpeed = SWEEP_SPEED })
		end
		-- A WedgePart turned on its side is a flat right triangle; its sharp corner sits on the centre and
		-- its long leg along the arm, so the sector trails the arm as it turns (+angle moves +Z toward +X).
		for k, width in { 10, 4 } do
			local y = 0.48 + (k - 1) * 0.04
			sweepPart({ Name = "SweepSector", ClassName = "WedgePart", Size = Vector3.new(0.03, width, armLength), CFrame = ctx:At(-width / 2, y, armLength / 2, 0, 0, 90), Color = ctx.Theme.Primary, Material = Enum.Material.Neon, Transparency = if k == 1 then 0.85 else 0.7 })
		end
		sweepPart({ Name = "SweepArm", Size = Vector3.new(0.35, 0.05, armLength), CFrame = ctx:At(0, 0.58, armLength / 2), Color = ctx.Theme.Primary:Lerp(Color3.new(1, 1, 1), 0.3), Material = Enum.Material.Neon, Transparency = 0.1 })

		buildPylons(ctx)
		buildDrone(ctx)

		local spawns = {}
		for i = 0, 7 do
			local a = i / 8 * math.pi * 2 + math.pi / 8
			local pos = ctx:At(math.cos(a) * 14, 3, math.sin(a) * 14).Position
			table.insert(spawns, CFrame.lookAt(pos, ctx:At(0, 3, 0).Position))
		end
		ctx:SetSpawns(spawns)
	end,

	Start = function(ctx)
		local p = plan(ctx)
		local function coin()
			local a = ctx.Rng:NextNumber(0, math.pi * 2)
			local r = ctx.Rng:NextNumber(6, SCREEN_R - 3)
			ctx:SpawnCoin(ctx:At(math.cos(a) * r, 3, math.sin(a) * r).Position)
		end
		for _ = 1, 4 do
			coin()
		end
		if not ctx:Wait(0.6) then
			return
		end
		local count = 0
		while not ctx.Ended do
			volley(ctx, p)
			if ctx.Ended then
				return
			end
			count += 1
			if count % 2 == 0 then
				coin()
			end
			if not ctx:Wait(p.Pause) then
				return
			end
		end
	end,
}
