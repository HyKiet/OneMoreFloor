-- BOSS: The Eye. A giant floating eye glares at players and fires its gaze at them; then it drifts,
-- yells HIDE! and flashes: anyone it can see is out. Break line of sight behind the stone pillars,
-- which crack under the gaze and crumble as the fight goes on.

local TweenService = game:GetService("TweenService")

local SIZE = 72
local HALF = SIZE / 2
local EYE_Y = 24 -- the eye always hovers at this height (shadow geometry is checked against it)
local SCLERA = 12
local INNER_R, OUTER_R = 14, 27
local PILLAR = Vector3.new(5, 12, 5)
local MIN_COVER = 4
local BLAST_R = 4.5
local HOVER_MIN, HOVER_MAX = 8, 13
local HOVER_CLEAR = 7 -- hover points keep this far (horizontally) from any pillar so shadows stay long

local SCLERA_COLOR = Color3.fromRGB(232, 226, 236)

local function plan(ctx)
	local d = math.clamp(ctx.Difficulty, 0, 1.5)
	local m = math.min(d, 1)
	return {
		Turn = 0.4 - 0.1 * m,
		Charge = 0.9 - 0.3 * m,
		GazePause = 0.5 - 0.2 * m,
		ThirdGaze = 0.25 + 0.6 * m, -- chance of a third gaze before each flash
		Drift = 1.1 - 0.3 * m,
		Countdown = 2.6 - 0.8 * m,
		D = d,
	}
end

-- The Eye -----------------------------------------------------------------------------------------
-- "Look" parts keep their offset from the gaze frame (iris, pupil, halo, rays); "Hang" parts keep theirs
-- from the plain position (sclera, mount, cables) so the cables stay vertical while the eye turns.

local function placeEye(ctx, pos: Vector3, aim: Vector3)
	local eye = ctx.State.Eye
	local flat = Vector3.new(aim.X - pos.X, 0, aim.Z - pos.Z)
	if flat.Magnitude < 0.5 then
		aim += ctx.Origin.LookVector * 0.6 -- never look exactly straight down (degenerate lookAt)
	end
	local look = CFrame.lookAt(pos, aim)
	local hang = CFrame.new(pos) * ctx.Origin.Rotation
	for _, piece in eye.Look do
		piece.Part.CFrame = look * piece.Offset
	end
	for _, piece in eye.Hang do
		piece.Part.CFrame = hang * piece.Offset
	end
	eye.Pos, eye.Aim = pos, aim
end

-- Glides the eye to a new position and aim point; stepped by the Heartbeat in Start (rigid motion).
local function moveEye(ctx, pos: Vector3, aim: Vector3, time: number, style: Enum.EasingStyle?)
	local eye = ctx.State.Eye
	eye.Motion = {
		FromPos = eye.Pos,
		ToPos = pos,
		FromAim = eye.Aim,
		ToAim = aim,
		Start = os.clock(),
		Time = math.max(time, 0.01),
		Style = style or Enum.EasingStyle.Sine,
	}
end

local function stepEye(ctx)
	local eye = ctx.State.Eye
	local m = eye.Motion
	if not m then
		return
	end
	local a = math.clamp((os.clock() - m.Start) / m.Time, 0, 1)
	local k = TweenService:GetValue(a, m.Style, Enum.EasingDirection.Out)
	placeEye(ctx, m.FromPos:Lerp(m.ToPos, k), m.FromAim:Lerp(m.ToAim, k))
	if a >= 1 then
		eye.Motion = nil
	end
end

local function buildEye(ctx)
	local hazard = ctx.Theme.Hazard
	local look, hang = {}, {}
	local eye = { Look = look, Hang = hang }
	ctx.State.Eye = eye
	local function add(list, offset: CFrame, props): BasePart
		local part = ctx:Decor(props)
		table.insert(list, { Part = part, Offset = offset })
		return part
	end
	local r = SCLERA / 2
	local facing = CFrame.Angles(0, math.rad(90), 0) -- cylinder axis along the gaze
	local dark = ctx.Theme.Floor:Lerp(Color3.new(0, 0, 0), 0.6)

	eye.Sclera = add(hang, CFrame.new(), { Name = "Sclera", Shape = Enum.PartType.Ball, Size = Vector3.one * SCLERA, Color = SCLERA_COLOR })
	-- Iris dome, pupil and a glowing core bulge out of the front (local -Z is where it looks)
	add(look, CFrame.new(0, 0, -3.2), { Name = "Iris", Shape = Enum.PartType.Ball, Size = Vector3.one * 7, Color = hazard:Lerp(Color3.new(0, 0, 0), 0.15), Material = Enum.Material.Neon })
	eye.Pupil = add(look, CFrame.new(0, 0, -5.4), { Name = "Pupil", Shape = Enum.PartType.Ball, Size = Vector3.one * 3.6, Color = Color3.fromRGB(12, 8, 16) })
	eye.Core = add(look, CFrame.new(0, 0, -7), { Name = "Core", Shape = Enum.PartType.Ball, Size = Vector3.one * 1.4, Color = hazard:Lerp(Color3.new(1, 1, 1), 0.35), Material = Enum.Material.Neon })
	eye.PupilSize, eye.CoreSize = eye.Pupil.Size, eye.Core.Size
	-- Halo behind the eye: dark collar, neon ring and eight rays
	add(look, CFrame.new(0, 0, 4.2) * facing, { Name = "HaloCollar", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 15.5, 15.5), Color = dark })
	eye.Halo = add(look, CFrame.new(0, 0, 4.6) * facing, { Name = "Halo", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 21, 21), Color = hazard, Material = Enum.Material.Neon, Transparency = 0.35 })
	for k = 0, 7 do
		add(look, CFrame.Angles(0, 0, k * math.pi / 4) * CFrame.new(0, 12, 4.7), { Name = "HaloRay", Size = Vector3.new(0.8, 3.4, 0.3), Color = hazard, Material = Enum.Material.Neon })
	end
	-- Mount and cables disappearing up into the dark
	add(hang, CFrame.new(0, r - 0.2, 0) * CFrame.Angles(0, 0, math.rad(90)), { Name = "Mount", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.2, 3.4, 3.4), Color = dark, Material = Enum.Material.Metal })
	add(hang, CFrame.new(0, r - 0.1, 0) * CFrame.Angles(0, 0, math.rad(90)), { Name = "MountLight", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 3.7, 3.7), Color = ctx.Theme.Primary, Material = Enum.Material.Neon })
	for k = 0, 2 do
		local a = k * math.pi * 2 / 3 + 0.5
		local tilt = math.rad(10)
		local dir = Vector3.new(math.sin(tilt) * math.cos(a), math.cos(tilt), math.sin(tilt) * math.sin(a))
		local length = 44
		local centre = Vector3.new(0, r - 0.4, 0) + dir * (length / 2)
		add(hang, CFrame.lookAt(centre, centre + dir) * facing, { Name = "Cable", Shape = Enum.PartType.Cylinder, Size = Vector3.new(length, 0.35, 0.35), Color = dark, Material = Enum.Material.Metal })
	end
	eye.Light = ctx:Glow(eye.Core, hazard, 30, 2)
	placeEye(ctx, ctx:At(0, EYE_Y, -10).Position, ctx:At(0, 3, 20).Position)
end

-- Pillars --------------------------------------------------------------------------------------------

local function addPillar(ctx, x: number, z: number)
	local stone = ctx.Theme.Floor:Lerp(Color3.fromRGB(150, 145, 160), 0.35)
	local frame = CFrame.lookAt(ctx:At(x, 0, z).Position, ctx:At(0, 0, 0).Position) -- faces the centre
	local pillar = { X = x, Z = z, Hits = 0, Decor = {} }
	pillar.Part = ctx:Part({ Name = "Pillar", Parent = ctx.State.Cover, Size = PILLAR - Vector3.new(0, 0.3, 0), CFrame = frame * CFrame.new(0, PILLAR.Y / 2 + 0.15, 0), Color = stone, Material = Enum.Material.Slate })
	local function decor(props)
		table.insert(pillar.Decor, ctx:Decor(props))
	end
	decor({ Name = "Plinth", Size = Vector3.new(PILLAR.X + 0.8, 0.7, PILLAR.Z + 0.8), CFrame = frame * CFrame.new(0, 0.25, 0), Color = stone:Lerp(Color3.new(0, 0, 0), 0.35), Material = Enum.Material.Slate, CanCollide = true })
	for _, y in { 3, 9.2 } do
		decor({ Name = "Trim", Size = Vector3.new(PILLAR.X + 0.24, 0.35, PILLAR.Z + 0.24), CFrame = frame * CFrame.new(0, y, 0), Color = ctx.Theme.Primary, Material = Enum.Material.Neon })
	end
	decor({ Name = "Cap", Size = Vector3.new(PILLAR.X + 0.6, 0.5, PILLAR.Z + 0.6), CFrame = frame * CFrame.new(0, PILLAR.Y - 0.15, 0), Color = stone:Lerp(Color3.new(0, 0, 0), 0.25), Material = Enum.Material.Slate })
	pillar.Frame = frame
	table.insert(ctx.State.Pillars, pillar)
	ctx.State.PillarByPart[pillar.Part] = pillar
end

-- Collapses a pillar into rubble (a low stump stays behind; it no longer blocks the eye).
local function crumble(ctx, pillar)
	local list = ctx.State.Pillars
	local index = table.find(list, pillar)
	if not index then
		return
	end
	table.remove(list, index)
	ctx.State.PillarByPart[pillar.Part] = nil
	local positions = {}
	for _ = 1, 12 do
		table.insert(positions, (pillar.Frame * CFrame.new(ctx.Rng:NextNumber(-2, 2), ctx.Rng:NextNumber(1, PILLAR.Y - 0.5), ctx.Rng:NextNumber(-2, 2))).Position)
	end
	ctx:Fx("Chunks", { Positions = positions, Color = pillar.Part.Color, Size = 1.7 })
	ctx:Impact((pillar.Frame * CFrame.new(0, 0.3, 0)).Position, ctx.Theme.Primary, 10, 6)
	ctx:Sound("Explosion", pillar.Part.Position)
	ctx:Shake(0.6, 0.3)
	local color = pillar.Part.Color
	pillar.Part:Destroy()
	for _, part in pillar.Decor do
		if part.Name ~= "Plinth" then
			part:Destroy()
		end
	end
	ctx:Decor({ Name = "Stump", Size = Vector3.new(PILLAR.X - 0.6, 1.4, PILLAR.Z - 0.6), CFrame = pillar.Frame * CFrame.new(0, 1.3, 0) * CFrame.Angles(math.rad(4), math.rad(17), math.rad(-3)), Color = color:Lerp(Color3.new(0, 0, 0), 0.3), Material = Enum.Material.Slate, CanCollide = true })
end

-- The gaze hit a pillar: hits crack it (a glowing zig-zag where it struck), the third one breaks it.
local function damagePillar(ctx, pillar, position: Vector3, normal: Vector3)
	pillar.Hits += 1
	if pillar.Hits >= 3 and #ctx.State.Pillars > MIN_COVER then
		crumble(ctx, pillar)
		return
	end
	local up = if math.abs(normal.Y) > 0.9 then ctx.Origin.LookVector else Vector3.yAxis
	local face = CFrame.lookAt(position + normal * 0.05, position + normal, up)
	for i, y in { 1.3, 0, -1.3 } do
		local crack = ctx:Decor({ Name = "Crack", Size = Vector3.new(0.22, 1.5, 0.06), CFrame = face * CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.rad(if i % 2 == 1 then 30 else -30)), Color = ctx.Theme.Hazard, Material = Enum.Material.Neon })
		ctx:Animate(crack, "OMF_Pulse", { PulseMin = 0, PulseMax = 0.5, PulseSpeed = 2 })
		table.insert(pillar.Decor, crack)
	end
	pillar.Part.Color = pillar.Part.Color:Lerp(ctx.Theme.Hazard:Lerp(Color3.new(0, 0, 0), 0.6), 0.35)
	ctx:Fx("Chunks", { Positions = { position, position + normal * 0.5 }, Color = pillar.Part.Color, Size = 0.9 })
end

-- Attacks -----------------------------------------------------------------------------------------------

local function clampToFloor(v: number): number
	return math.clamp(v, -HALF + 1, HALF - 1)
end

-- GAZE: turn to a player, charge (telegraphed on the floor), fire. Cover stops the beam.
local function gaze(ctx, p, target: Player)
	local eye = ctx.State.Eye
	local hazard = ctx.Theme.Hazard
	local pos = ctx:LocalPosition(target)
	if not pos then
		return
	end
	local x, z = clampToFloor(pos.X), clampToFloor(pos.Z)
	local aim = ctx:At(x, 1.5, z).Position
	moveEye(ctx, eye.Pos, aim, p.Turn, Enum.EasingStyle.Back)
	if not ctx:Wait(p.Turn) then
		return
	end

	ctx:Warn(ctx:At(x, 0.3, z), Vector3.new(BLAST_R * 2, 0.2, BLAST_R * 2), p.Charge, hazard, { Shape = "Disc" })
	ctx:Sound("Warning")
	-- the pupil throbs and a thin aiming line thickens while it charges
	local pulses = math.max(1, math.floor(p.Charge / 0.3))
	local half = p.Charge / (pulses * 2)
	ctx:Tween(eye.Core, TweenInfo.new(half, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, pulses - 1, true), { Size = eye.CoreSize * 1.9 })
	ctx:Tween(eye.Pupil, TweenInfo.new(half, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, pulses - 1, true), { Size = eye.PupilSize * 0.82 })
	local from = eye.Core.Position
	local line = ctx:Decor({ Name = "GazeLine", Size = Vector3.new(0.12, 0.12, (aim - from).Magnitude), CFrame = CFrame.lookAt((from + aim) / 2, aim), Color = hazard, Material = Enum.Material.Neon, Transparency = 0.65 })
	ctx:Tween(line, TweenInfo.new(p.Charge, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = Vector3.new(0.45, 0.45, line.Size.Z), Transparency = 0.2 })
	local alive = ctx:Wait(p.Charge)
	line:Destroy()
	eye.Core.Size, eye.Pupil.Size = eye.CoreSize, eye.PupilSize
	if not alive then
		return
	end

	-- Fire: the beam stops at the first pillar in its way
	local origin = eye.Core.Position
	local result = workspace:Raycast(origin, aim - origin, ctx.State.CoverParams)
	ctx:Sound("Laser")
	if result then
		ctx:Fx("Shot", { From = origin, To = result.Position, Color = hazard })
		ctx:Impact(result.Position, hazard, 7, 4)
		local pillar = ctx.State.PillarByPart[result.Instance]
		if pillar then
			damagePillar(ctx, pillar, result.Position, result.Normal)
		end
		return
	end
	local spot = ctx:At(x, 0.1, z).Position
	ctx:Fx("Shot", { From = origin, To = spot, Color = hazard })
	ctx:Impact(spot, hazard, BLAST_R + 5, 6)
	ctx:Shake(0.5, 0.25)
	local blastFrom = ctx:At(x, 1.5, z).Position
	for _, player in ctx:GetAlive() do
		local root = ctx:GetRoot(player)
		local lp = root and ctx.Origin:PointToObjectSpace(root.Position)
		if root and lp and lp.Y < 13 and Vector2.new(lp.X - x, lp.Z - z).Magnitude <= BLAST_R then
			-- a pillar between the blast and the player still shields them
			if not workspace:Raycast(blastFrom, root.Position - blastFrom, ctx.State.CoverParams) then
				ctx:Eliminate(player, "Seen by The Eye")
			end
		end
	end
end

-- Picks a hover point 8-13 studs from the centre, clear of every pillar and away from the current spot.
local function pickHover(ctx): (number, number)
	local current = ctx.Origin:PointToObjectSpace(ctx.State.Eye.Pos)
	local fallback
	for _ = 1, 40 do
		local a = ctx.Rng:NextNumber(0, math.pi * 2)
		local r = ctx.Rng:NextNumber(HOVER_MIN, HOVER_MAX)
		local x, z = math.cos(a) * r, math.sin(a) * r
		local clear = true
		for _, pillar in ctx.State.Pillars do
			if Vector2.new(x - pillar.X, z - pillar.Z).Magnitude < HOVER_CLEAR then
				clear = false
				break
			end
		end
		if clear then
			fallback = fallback or { x, z }
			if Vector2.new(x - current.X, z - current.Z).Magnitude >= 8 then
				return x, z
			end
		end
	end
	if fallback then
		return fallback[1], fallback[2]
	end
	return 0, 0
end

-- True when the eye at `origin` has a clear line to both the player's root and head.
local function canSee(ctx, origin: Vector3, player: Player): boolean
	local root = ctx:GetRoot(player)
	if not root then
		return false
	end
	local character = root.Parent
	local head = character and character:FindFirstChild("Head")
	local headPos = if head and head:IsA("BasePart") then head.Position else root.Position + Vector3.new(0, 1.5, 0)
	local params = ctx.State.CoverParams
	return workspace:Raycast(origin, root.Position - origin, params) == nil and workspace:Raycast(origin, headPos - origin, params) == nil
end

-- FLASH: drift to a new spot, count down, flash. Anyone in plain sight is out. Then a pillar crumbles.
local function flash(ctx, p)
	local eye = ctx.State.Eye
	local hazard = ctx.Theme.Hazard
	local x, z = pickHover(ctx)
	local pos = ctx:At(x, EYE_Y, z).Position
	ctx:Announce("HIDE!", hazard)
	ctx:Sound("Alarm")
	moveEye(ctx, pos, ctx:At(-x * 0.4, 0, -z * 0.4).Position, p.Drift, Enum.EasingStyle.Sine)
	if not ctx:Wait(p.Drift) then
		return
	end

	-- Charge: the white of the eye heats up and the light swells while it slowly scans the arena
	local hot = Color3.new(1, 1, 1):Lerp(hazard, 0.18)
	eye.Sclera.Material = Enum.Material.Neon
	local ramp = TweenInfo.new(p.Countdown, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	ctx:Tween(eye.Sclera, ramp, { Color = hot })
	ctx:Tween(eye.Light, ramp, { Brightness = 7, Range = 60 })
	ctx:Tween(eye.Halo, ramp, { Transparency = 0 })
	local scan = ctx.Rng:NextNumber(0, math.pi * 2)
	moveEye(ctx, pos, ctx:At(math.cos(scan) * 16, 0, math.sin(scan) * 16).Position, p.Countdown, Enum.EasingStyle.Sine)
	ctx:Sound("Countdown")
	for n = 3, 1, -1 do
		ctx:Announce(`HIDE! {n}`, hazard)
		if not ctx:Wait(p.Countdown / 3) then
			return
		end
	end

	-- FLASH
	ctx.Run:FireEffect("Flash", { Color = hot, Duration = 0.8 })
	ctx:Sound("Explosion")
	ctx:Shake(0.9, 0.4)
	local bulb = ctx:Decor({ Name = "FlashBulb", Shape = Enum.PartType.Ball, Size = Vector3.one * SCLERA, CFrame = CFrame.new(pos), Color = hot, Material = Enum.Material.Neon, Transparency = 0.2 })
	ctx:Tween(bulb, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.one * 64, Transparency = 1 })
	task.delay(0.5, function()
		bulb:Destroy()
	end)
	for _, player in ctx:GetAlive() do
		if canSee(ctx, pos, player) then
			local root = ctx:GetRoot(player)
			if root then
				ctx:Fx("Shot", { From = pos, To = root.Position, Color = hazard })
			end
			ctx:Eliminate(player, "Seen by The Eye")
		end
	end

	-- Cool down
	eye.Sclera.Material = Enum.Material.SmoothPlastic
	local cool = TweenInfo.new(0.6)
	ctx:Tween(eye.Sclera, cool, { Color = SCLERA_COLOR })
	ctx:Tween(eye.Light, cool, { Brightness = 2, Range = 30 })
	ctx:Tween(eye.Halo, cool, { Transparency = 0.35 })
	if not ctx:Wait(0.5) then
		return
	end
	-- the blast weakens the temple: one random pillar comes down (never fewer than MIN_COVER)
	local pillars = ctx.State.Pillars
	if #pillars > MIN_COVER then
		crumble(ctx, pillars[ctx.Rng:NextInteger(1, #pillars)])
	end
	ctx:SpawnCoin(ctx:At(ctx.Rng:NextNumber(-28, 28), 3, ctx.Rng:NextNumber(-28, 28)).Position)
end

-- Cycles through living players so consecutive gazes spread across the group.
local function nextTarget(ctx): Player?
	local queue = ctx.State.Queue
	while true do
		if #queue == 0 then
			local alive = ctx:GetAlive()
			if #alive == 0 then
				return nil
			end
			for i = #alive, 2, -1 do
				local j = ctx.Rng:NextInteger(1, i)
				alive[i], alive[j] = alive[j], alive[i]
			end
			for _, player in alive do
				table.insert(queue, player)
			end
		end
		local player = table.remove(queue, 1)
		if table.find(ctx:GetAlive(), player) then
			return player
		end
	end
end

return {
	Id = "BossEye",
	Name = "BOSS: The Eye",
	Hint = "Hide behind the pillars when The Eye flashes, and dodge its gaze!",
	MinFloor = 10,
	MinPlayers = 1,
	Weight = 1,
	BossOnly = true,
	Duration = 28,

	Build = function(ctx)
		local floorColor = ctx.Theme.Floor:Lerp(Color3.new(0, 0, 0), 0.3)
		ctx:Part({ Name = "Floor", Size = Vector3.new(SIZE, 2, SIZE), CFrame = ctx:At(0, -1, 0), Color = floorColor, Material = Enum.Material.Slate })
		ctx:Rim(HALF, HALF, ctx.Theme.Hazard, ctx.Theme.Primary)

		-- Temple floor: two courts (bright ring + slightly lighter fill) and an eye mosaic in the middle.
		-- Larger discs sit lower; every layer is 0.04 above the one below it.
		local layers = {
			{ OUTER_R + 1.5, ctx.Theme.Primary, Enum.Material.Neon },
			{ OUTER_R + 1.1, floorColor:Lerp(ctx.Theme.Primary, 0.06), Enum.Material.SmoothPlastic },
			{ INNER_R + 1.5, ctx.Theme.Primary:Lerp(floorColor, 0.35), Enum.Material.SmoothPlastic },
			{ INNER_R + 1.1, floorColor:Lerp(ctx.Theme.Hazard, 0.08), Enum.Material.SmoothPlastic },
			{ 6, ctx.Theme.Hazard:Lerp(floorColor, 0.55), Enum.Material.SmoothPlastic },
			{ 2.6, Color3.fromRGB(14, 10, 18), Enum.Material.SmoothPlastic },
		}
		for k, layer in layers do
			local r = layer[1]
			ctx:Decor({ Name = "Court", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.02, r * 2, r * 2), CFrame = ctx:At(0, 0.03 + (k - 1) * 0.04, 0, 0, 0, 90), Color = layer[2], Material = layer[3] })
		end
		ctx:Decor({ Name = "Glint", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.02, 1.2, 1.2), CFrame = ctx:At(1.1, 0.03 + #layers * 0.04, -1.1, 0, 0, 90), Color = Color3.new(1, 1, 1), Material = Enum.Material.Neon })

		-- Corner obelisks, each with a watching neon eye
		for k, c in { { 1, 1 }, { 1, -1 }, { -1, -1 }, { -1, 1 } } do
			local pos = ctx:At(c[1] * (HALF + 3.5), 7, c[2] * (HALF + 3.5)).Position
			local frame = CFrame.lookAt(pos, ctx:At(0, 7, 0).Position)
			ctx:Decor({ Name = "Obelisk", Size = Vector3.new(3.2, 26, 3.2), CFrame = frame, Color = floorColor:Lerp(Color3.new(0, 0, 0), 0.3), Material = Enum.Material.Slate, CanCollide = true })
			ctx:Decor({ Name = "ObeliskSlit", Size = Vector3.new(0.5, 16, 0.2), CFrame = frame * CFrame.new(0, -2, -1.65), Color = ctx.Theme.Primary, Material = Enum.Material.Neon })
			local glow = ctx:Decor({ Name = "ObeliskEye", Shape = Enum.PartType.Ball, Size = Vector3.new(1.4, 1.4, 1.4), CFrame = frame * CFrame.new(0, 9.5, -1.5), Color = ctx.Theme.Hazard, Material = Enum.Material.Neon })
			ctx:Animate(glow, "OMF_Pulse", { PulseMin = 0, PulseMax = 0.7, PulseSpeed = 0.5, PulsePhase = k / 4 })
		end

		-- Cover pillars (the only thing the eye's rays test against)
		local cover = Instance.new("Folder")
		cover.Name = "Cover"
		cover.Parent = ctx.Folder
		ctx.State.Cover = cover
		ctx.State.Pillars = {}
		ctx.State.PillarByPart = {}
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { cover }
		ctx.State.CoverParams = params
		for k = 0, 4 do
			local a = math.rad(k * 72 + 90)
			addPillar(ctx, math.cos(a) * INNER_R, math.sin(a) * INNER_R)
			local b = math.rad(k * 72 + 126)
			addPillar(ctx, math.cos(b) * OUTER_R, math.sin(b) * OUTER_R)
		end

		buildEye(ctx)
		ctx.State.Queue = {}

		local spawns = {}
		for i = 0, 7 do
			local a = i / 8 * math.pi * 2 + math.pi / 8
			local pos = ctx:At(math.cos(a) * 20, 3, math.sin(a) * 20).Position
			table.insert(spawns, CFrame.lookAt(pos, ctx:At(0, 3, 0).Position))
		end
		ctx:SetSpawns(spawns)
	end,

	Start = function(ctx)
		local p = plan(ctx)
		ctx:Heartbeat(function()
			stepEye(ctx)
		end)
		-- coins in the gaps between the pillar rings
		for k = 0, 4 do
			if k ~= 2 then
				local a = math.rad(k * 72 + 108)
				ctx:SpawnCoin(ctx:At(math.cos(a) * 20.5, 3, math.sin(a) * 20.5).Position)
			end
		end
		ctx:Announce("THE EYE OPENS!", ctx.Theme.Hazard)
		ctx:Fx("Burst", { Position = ctx.State.Eye.Core.Position, Color = ctx.Theme.Hazard, Count = 50 })
		ctx:Sound("Alarm")
		if not ctx:Wait(1.2) then
			return
		end
		while not ctx.Ended do
			local gazes = 2 + (if ctx.Rng:NextNumber() < p.ThirdGaze then 1 else 0)
			for _ = 1, gazes do
				local target = nextTarget(ctx)
				if target then
					gaze(ctx, p, target)
				end
				if not ctx:Wait(p.GazePause) then
					return
				end
			end
			flash(ctx, p)
			if not ctx:Wait(0.8) then
				return
			end
		end
	end,
}
