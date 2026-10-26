-- BOSS: The Cube. A giant cube hunts you down, slams the floor and sends shockwaves rolling out.

local RunService = game:GetService("RunService")

local SIZE = 80
local HALF = SIZE / 2
local BOSS = 14
local HOVER_Y = 26
local WAVE_MAX = 62
local WAVE_TOP = 1.4 -- the wave is a low wall: jump to clear it
local WAVE_HALF_THICK = 0.4

local function plan(ctx)
	local d = math.clamp(ctx.Difficulty, 0, 1.5)
	local m = math.min(d, 1)
	return {
		Telegraph = 1.5 - 0.7 * m,
		Pause = 2.6 - 1.1 * m,
		WaveSpeed = 20 + 12 * d,
		Double = d >= 0.8,
		D = d,
	}
end

-- Moves the boss body and its attached parts together.
local function moveBoss(ctx, cframe, info)
	local boss = ctx.State.Boss
	if info then
		ctx:Tween(boss.Body, info, { CFrame = cframe })
		for _, face in boss.Face do
			ctx:Tween(face.Part, info, { CFrame = cframe * face.Offset })
		end
	else
		boss.Body.CFrame = cframe
		for _, face in boss.Face do
			face.Part.CFrame = cframe * face.Offset
		end
	end
end

local function bossAt(ctx, x, y, z)
	-- Face points toward the cab (+Z) where players come from
	return ctx:At(x, y, z, 0, 180, 0)
end

-- An expanding ring along the floor. Jump it! The hit test is pure maths on the server
-- (nothing replicates); clients draw the ring from the same start time and speed.
local function shockwave(ctx, cx, cz, speed)
	local startTime = workspace:GetServerTimeNow()
	local r0 = BOSS / 2
	ctx:Fx("Wave", { Position = ctx:At(cx, 0, cz).Position, Color = ctx.Theme.Hazard, Speed = speed, From = r0, To = WAVE_MAX, StartTime = startTime })
	local hit = {}
	local connection
	connection = RunService.Heartbeat:Connect(function()
		local radius = r0 + (workspace:GetServerTimeNow() - startTime) * speed
		if ctx.Ended or radius > WAVE_MAX then
			connection:Disconnect()
			return
		end
		for _, player in ctx:GetAlive() do
			local pos = not hit[player] and ctx:LocalPosition(player)
			if pos then
				local character = ctx:GetCharacter(player)
				local scale = if character then character:GetScale() else 1
				local dist = Vector2.new(pos.X - cx, pos.Z - cz).Magnitude
				-- same footprint as the run's hazard hit box (2.6 x 5 x 1.6, scaled)
				if math.abs(dist - radius) < WAVE_HALF_THICK + 1 * scale and pos.Y - 2.5 * scale < WAVE_TOP then
					hit[player] = true
					ctx:Eliminate(player, "Hit by Shockwave")
				end
			end
		end
	end)
	ctx.Trove:Add(connection)
end

-- One full slam: hover over a target, telegraph, crash down, shockwave, rise.
local function slam(ctx, p, telegraph)
	local boss = ctx.State.Boss
	local alive = ctx:GetAlive()
	local x, z
	local target = if #alive > 0 then alive[ctx.Rng:NextInteger(1, #alive)] else nil
	local pos = target and ctx:LocalPosition(target)
	if pos then
		x, z = pos.X, pos.Z
	else
		x, z = ctx.Rng:NextNumber(-30, 30), ctx.Rng:NextNumber(-30, 30)
	end
	x = math.clamp(x, -HALF + BOSS / 2, HALF - BOSS / 2)
	z = math.clamp(z, -HALF + BOSS / 2, HALF - BOSS / 2)

	moveBoss(ctx, bossAt(ctx, x, HOVER_Y, z), TweenInfo.new(math.min(0.6, telegraph * 0.6), Enum.EasingStyle.Sine))
	ctx:Warn(ctx:At(x, 0.15, z), Vector3.new(BOSS + 1, 0.2, BOSS + 1), telegraph)
	-- the cube heats up while it lines up the slam
	ctx:Tween(boss.Body, TweenInfo.new(telegraph, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Color = ctx.Theme.Hazard })
	ctx:Sound("Warning")
	if not ctx:Wait(telegraph) then
		return
	end

	ctx:MakeHazard(boss.Body)
	local fall = 0.22
	moveBoss(ctx, bossAt(ctx, x, BOSS / 2, z), TweenInfo.new(fall, Enum.EasingStyle.Quad, Enum.EasingDirection.In))
	if not ctx:Wait(fall) then
		return
	end
	ctx:Shake(1.3, 0.45)
	ctx:Sound("Impact", boss.Body)
	ctx:Impact(ctx:At(x, 0.1, z).Position, ctx.Theme.Hazard, 26, 14)
	shockwave(ctx, x, z, p.WaveSpeed)
	if not ctx:Wait(0.15) then
		return
	end
	ctx:MakeHazard(boss.Body, false)
	ctx:Tween(boss.Body, TweenInfo.new(0.5), { Color = ctx.Theme.Primary })
	if not ctx:Wait(0.45) then
		return
	end
	moveBoss(ctx, bossAt(ctx, x, HOVER_Y, z), TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out))
	ctx:Wait(0.6)
end

return {
	Id = "BossSlam",
	Name = "BOSS: The Cube",
	Hint = "Dodge the slams and jump over the shockwaves!",
	MinFloor = 1,
	MinPlayers = 1,
	Weight = 1,
	BossOnly = true,
	Duration = 28,

	Build = function(ctx)
		local dark = ctx.Theme.Floor:Lerp(Color3.new(0, 0, 0), 0.4)
		ctx:Part({ Name = "Floor", Size = Vector3.new(SIZE, 2, SIZE), CFrame = ctx:At(0, -1, 0), Color = ctx.Theme.Floor:Lerp(Color3.new(0, 0, 0), 0.15) })
		ctx:Rim(HALF, HALF, ctx.Theme.Hazard, ctx.Theme.Hazard)
		-- Concentric target rings and a cross-hair on the floor
		for k = 1, 4 do
			ctx:Decor({ Name = "Ring", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.02, k * 18, k * 18), CFrame = ctx:At(0, 0.03 + (4 - k) * 0.04, 0, 0, 0, 90), Color = ctx.Theme.Floor:Lerp(ctx.Theme.Hazard, 0.12 + (5 - k) * 0.05), Material = if k % 2 == 0 then Enum.Material.Neon else Enum.Material.SmoothPlastic, Transparency = if k % 2 == 0 then 0.75 else 0 })
		end
		for _, yaw in { 0, 90 } do
			ctx:Decor({ Name = "Cross", Size = Vector3.new(0.3, 0.03, SIZE - 4), CFrame = ctx:At(0, 0.2, 0, 0, yaw, 0), Color = ctx.Theme.Floor:Lerp(ctx.Theme.Hazard, 0.3) })
		end

		-- The Cube, with an angry face and a heavy dark edge frame
		local body = ctx:Part({ Name = "TheCube", Size = Vector3.new(BOSS, BOSS, BOSS), Color = ctx.Theme.Primary, Material = Enum.Material.Neon, CanCollide = false, CastShadow = false })
		local edges = Instance.new("SelectionBox")
		edges.Adornee = body
		edges.Color3 = Color3.fromRGB(15, 12, 20)
		edges.LineThickness = 0.45
		edges.SurfaceTransparency = 1
		edges.Parent = body
		local face = {}
		local function feature(offset, size, color, material)
			local part = ctx:Decor({ Name = "Face", Size = size, Color = color, Material = material })
			table.insert(face, { Part = part, Offset = offset })
		end
		local front = -BOSS / 2 - 0.15
		feature(CFrame.new(-3, 1.5, front), Vector3.new(3.4, 3.4, 0.3), Color3.new(1, 1, 1), Enum.Material.Neon)
		feature(CFrame.new(3, 1.5, front), Vector3.new(3.4, 3.4, 0.3), Color3.new(1, 1, 1), Enum.Material.Neon)
		feature(CFrame.new(-3, 1.1, front - 0.1), Vector3.new(1.5, 1.5, 0.3), Color3.new(0, 0, 0), Enum.Material.SmoothPlastic)
		feature(CFrame.new(3, 1.1, front - 0.1), Vector3.new(1.5, 1.5, 0.3), Color3.new(0, 0, 0), Enum.Material.SmoothPlastic)
		feature(CFrame.new(-3, 4, front) * CFrame.Angles(0, 0, math.rad(-20)), Vector3.new(4, 0.8, 0.3), Color3.new(0.05, 0.05, 0.05), Enum.Material.SmoothPlastic)
		feature(CFrame.new(3, 4, front) * CFrame.Angles(0, 0, math.rad(20)), Vector3.new(4, 0.8, 0.3), Color3.new(0.05, 0.05, 0.05), Enum.Material.SmoothPlastic)
		feature(CFrame.new(0, -3, front), Vector3.new(6, 1, 0.3), Color3.new(0.05, 0.05, 0.05), Enum.Material.SmoothPlastic)
		for _, x in { -1.8, 0, 1.8 } do
			feature(CFrame.new(x, -2.55, front - 0.05), Vector3.new(0.7, 0.6, 0.3), Color3.new(1, 1, 1), Enum.Material.Neon) -- teeth
		end
		ctx:Glow(body, ctx.Theme.Hazard, 40, 2)
		local tether = Instance.new("Attachment")
		tether.Name = "Tether"
		tether.Parent = body
		ctx.State.Boss = { Body = body, Face = face }
		moveBoss(ctx, bossAt(ctx, 0, HOVER_Y, -12))

		-- Pylons around the arena, each chained to the Cube by a crackling beam
		for k, c in { { 1, 1 }, { 1, -1 }, { -1, -1 }, { -1, 1 } } do
			local x, z = c[1] * (HALF + 3), c[2] * (HALF + 3)
			ctx:Decor({ Name = "Pylon", Size = Vector3.new(3, 16, 3), CFrame = ctx:At(x, 8, z), Color = dark })
			local tip = ctx:Decor({ Name = "PylonTip", Size = Vector3.new(2.4, 2.4, 2.4), CFrame = ctx:At(x, 17.5, z) * CFrame.Angles(math.rad(45), 0, math.rad(45)), Color = ctx.Theme.Hazard, Material = Enum.Material.Neon })
			ctx:Animate(tip, "OMF_Pulse", { PulseMin = 0, PulseMax = 0.6, PulseSpeed = 1.6, PulsePhase = k / 4 })
			local a0 = Instance.new("Attachment")
			a0.Parent = tip
			local beam = Instance.new("Beam")
			beam.Attachment0 = a0
			beam.Attachment1 = tether
			beam.Color = ColorSequence.new(ctx.Theme.Hazard:Lerp(Color3.new(1, 1, 1), 0.3), ctx.Theme.Hazard)
			beam.LightEmission = 1
			beam.LightInfluence = 0
			beam.Width0 = 0.6
			beam.Width1 = 1.2
			beam.Segments = 12
			beam.CurveSize0 = (k % 2 == 0 and 6 or -6)
			beam.Transparency = NumberSequence.new(0.25)
			beam.FaceCamera = true
			beam.Parent = tip
		end
	end,

	Start = function(ctx)
		local p = plan(ctx)
		for _, c in { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } } do
			ctx:SpawnCoin(ctx:At(c[1] * (HALF - 5), 3, c[2] * (HALF - 5)).Position)
		end
		ctx:Announce("THE CUBE AWAKENS!", ctx.Theme.Hazard)
		ctx:Fx("Burst", { Position = ctx.State.Boss.Body.Position, Color = ctx.Theme.Hazard, Count = 50 })
		if not ctx:Wait(1) then
			return
		end
		while not ctx.Ended do
			slam(ctx, p, p.Telegraph)
			if ctx.Ended then
				return
			end
			-- Deep floors: a quick follow-up slam
			if p.Double and ctx.Rng:NextNumber() < 0.5 then
				slam(ctx, p, p.Telegraph * 0.75)
			end
			if not ctx:Wait(p.Pause) then
				return
			end
		end
	end,
}
