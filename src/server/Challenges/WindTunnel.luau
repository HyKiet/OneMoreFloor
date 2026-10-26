-- Wind Tunnel: a square deck over the abyss with a giant fan beyond each edge. One fan at a time spins up
-- (blades accelerate, streamers, a sweeping warning) and blows everyone toward the opposite edge. Walk into
-- the wind or hide behind the low windbreak walls; jumping lifts you out of cover and catches more wind.
-- The wind is a per-player LinearVelocity "line" constraint along the wind (force capped, speed capped at the
-- wind speed), refreshed every 0.1 s; cover is a raycast toward the fan. Not ctx:SetPush: a plain VectorForce
-- strong enough to move a grounded humanoid flings an airborne one tens of studs (no air friction), while
-- the constraint can never carry anyone faster than the wind.

local SIZE = 50
local HALF = SIZE / 2
local WALL_H = 4.6 -- the root (~3 up) is covered, a jump is not
local WALL_T = 1.2
local WALL_L = 8
local FAN_R = 10.2 -- blade tip radius
local RING_R = 11.4 -- housing radius
local FAN_DIST = HALF + 6.5 -- fan centre from the arena centre
local FAN_Y = 6
local SHELTER = 12 -- a windbreak this close upwind covers you
local IDLE_SPIN = 0.6 -- rad/s while idle
local MAX_SPIN = 15 -- rad/s while blowing
local RAMP_IN = 0.35 -- gust strength envelope
local RAMP_OUT = 0.5
-- Grounded humanoids resist a push like strong friction up to a limit, past which they are simply carried
-- along at the wind speed. Measured in Studio with this constraint (force per unit mass, studs/s^2):
--   760 steady: idle drifts 4.9 st/s, walking into it still gains 12 st/s; 800: 5.7 / 11; 900+: carried away.
-- So the wind is gusty: a steady BASE below that limit plus short SURGEs above it (carried at the wind speed
-- for a moment). Surges 0.2 s every 1.4 s: idle 6.7 st/s, walking gains 6.6; 0.3 s every 0.9 s: idle 8.7,
-- walking only just holds. Airborne players have no ground grip and are carried at the wind speed.
local BASE_ACCEL = 760 -- keep below ~800
local SURGE_ACCEL = 1300

local FANS = {
	{ Name = "N", Out = Vector3.new(0, 0, -1) },
	{ Name = "E", Out = Vector3.new(1, 0, 0) },
	{ Name = "S", Out = Vector3.new(0, 0, 1) },
	{ Name = "W", Out = Vector3.new(-1, 0, 0) },
}

local function soft(color: Color3, maxValue: number?): Color3
	local h, s, v = color:ToHSV()
	return Color3.fromHSV(h, s, math.min(v, maxValue or 0.85))
end

local function plan(ctx)
	local d = math.clamp(ctx.Difficulty, 0, 1.5)
	local m = math.min(d, 1)
	local over = math.max(d - 1, 0)
	return {
		SurgeEvery = math.max(1.4 - 0.5 * m - 0.12 * over, 0.8), -- seconds between surges
		Surge = 0.2 + 0.1 * m, -- surge length
		Speed = 15 + 2 * m, -- wind speed: nobody (airborne included) is carried faster than this
		Telegraph = 1.6 - 0.4 * m,
		Blow = 3.0 + 0.5 * m + 0.3 * over,
		Calm = math.max(2.0 - 1.2 * m - 0.3 * over, 0.7),
		Double = d >= 0.9, -- two adjacent fans at once (diagonal wind)
		DoubleScale = 0.8, -- each fan of a pair; the diagonal sum is capped at full strength (cover from one fan still leaves the other)
		Walls = math.clamp(6 - math.round(3 * m), 3, 6),
		Duration = 20 + 2 * m,
		D = d,
	}
end

-- Fan blade angle (closed form shared with OMF_Orbit on the clients).
local function spinAt(spin, now: number): (number, number)
	local t = math.max(now - spin.StartTime, 0)
	return spin.Angle0 + spin.Omega0 * t + 0.5 * spin.Ramp * t * t, spin.Omega0 + spin.Ramp * t
end

local function setSpin(fan, omega: number, ramp: number)
	local now = workspace:GetServerTimeNow()
	local angle = spinAt(fan.Spin, now)
	fan.Spin = { Angle0 = angle, Omega0 = omega, Ramp = ramp, StartTime = now }
	for _, blade in fan.Blades do
		blade:SetAttribute("Angle0", angle)
		blade:SetAttribute("Omega0", omega)
		blade:SetAttribute("Ramp", ramp)
		blade:SetAttribute("StartTime", now)
	end
end

-- Spins a fan from its current speed to `target` over `time` seconds.
local function spinTo(ctx, fan, target: number, time: number)
	local _, omega = spinAt(fan.Spin, workspace:GetServerTimeNow())
	setSpin(fan, omega, (target - omega) / time)
	fan.SpinToken = (fan.SpinToken or 0) + 1
	local token = fan.SpinToken
	ctx:After(time, function()
		if fan.SpinToken == token then
			setSpin(fan, target, 0)
		end
	end)
end

local function buildFan(ctx, def, steel: Color3, dark: Color3)
	local out = def.Out
	local pos = out * FAN_DIST + Vector3.new(0, FAN_Y, 0)
	-- hub frame: looks at the deck; local Z points back out through the fan
	local hub = ctx.Origin * CFrame.lookAt(pos, pos - out)
	local fan = { Def = def, Wind = -out, Hub = hub, Blades = {}, Spin = { Angle0 = 0, Omega0 = IDLE_SPIN, Ramp = 0, StartTime = workspace:GetServerTimeNow() } }

	-- housing ring, back plate, hub and nose
	local segments = 18
	local arc = 2 * math.pi * (RING_R + 0.6) / segments * 1.08
	for k = 0, segments - 1 do
		local a = k / segments * math.pi * 2
		ctx:Decor({ Name = "FanHousing", Size = Vector3.new(arc, 1.2, 3.2), CFrame = hub * CFrame.Angles(0, 0, a) * CFrame.new(0, RING_R + 0.6, 0), Color = dark, Material = Enum.Material.Metal })
	end
	ctx:Decor({ Name = "FanBack", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, RING_R * 2 + 0.4, RING_R * 2 + 0.4), CFrame = hub * CFrame.new(0, 0, 1.5) * CFrame.Angles(0, math.rad(90), 0), Color = ctx.Theme.Floor:Lerp(Color3.new(0, 0, 0), 0.15) })
	ctx:Decor({ Name = "FanHub", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.4, 3.6, 3.6), CFrame = hub * CFrame.new(0, 0, 0.3) * CFrame.Angles(0, math.rad(90), 0), Color = steel, Material = Enum.Material.Metal })
	fan.Nose = ctx:Decor({ Name = "FanNose", Shape = Enum.PartType.Ball, Size = Vector3.new(2.4, 2.4, 2.4), CFrame = hub * CFrame.new(0, 0, -0.9), Color = soft(ctx.Theme.Secondary, 0.75), Material = Enum.Material.Neon })

	-- blades (client-animated with OMF_Orbit about the fan axis)
	local length = FAN_R - 1.6
	for k = 0, 3 do
		local offset = CFrame.Angles(0, 0, k * math.pi / 2) * CFrame.new(0, 1.6 + length / 2, 0) * CFrame.Angles(0, math.rad(28), 0)
		local blade = ctx:Decor({ Name = "FanBlade", Size = Vector3.new(2.6, length, 0.3), CFrame = hub * offset, Color = steel:Lerp(Color3.new(1, 1, 1), 0.15), Material = Enum.Material.Metal })
		ctx:Animate(blade, "OMF_Orbit", {
			OrbitCenter = hub,
			OrbitOffset = offset,
			OrbitAxis = Vector3.zAxis,
			Angle0 = 0,
			Omega0 = IDLE_SPIN,
			Ramp = 0,
			Dir = 1,
			StartTime = fan.Spin.StartTime,
		})
		table.insert(fan.Blades, blade)
	end

	-- grille in front of the blades
	for _, o in { -7.5, -2.5, 2.5, 7.5 } do
		local chord = 2 * math.sqrt(RING_R * RING_R - o * o)
		ctx:Decor({ Name = "Grille", Size = Vector3.new(chord, 0.22, 0.22), CFrame = hub * CFrame.new(0, o, -1.3), Color = steel, Material = Enum.Material.Metal })
		ctx:Decor({ Name = "Grille", Size = Vector3.new(0.22, chord, 0.22), CFrame = hub * CFrame.new(o, 0, -1.55), Color = steel, Material = Enum.Material.Metal })
	end

	-- status ring (adornment: Primary idle, Hazard when it is about to blow)
	local anchor = ctx:Decor({ Name = "FanRingAnchor", Size = Vector3.one, CFrame = hub * CFrame.new(0, 0, -1.75), Transparency = 1 })
	local ring = Instance.new("CylinderHandleAdornment")
	ring.Adornee = anchor
	ring.Radius = RING_R + 0.25
	ring.InnerRadius = RING_R - 0.3
	ring.Height = 0.3
	ring.Color3 = soft(ctx.Theme.Primary, 0.8)
	ring.Transparency = 0.15
	ring.Parent = anchor
	fan.Ring = ring

	-- pedestal down into the abyss
	local bottom = FAN_Y - RING_R - 1.2
	local height = bottom + 20
	ctx:Decor({ Name = "FanPedestal", Size = Vector3.new(6, height, 4), CFrame = ctx:At(pos.X, bottom - height / 2, pos.Z, 0, if out.X ~= 0 then 90 else 0, 0), Color = dark, Material = Enum.Material.Metal })

	-- wind streamers: a body-height sheet of fast streaks flying across the deck
	local sheet = ctx:Decor({ Name = "WindSheet", Size = Vector3.new(FAN_R * 2, 7, 0.5), CFrame = hub * CFrame.new(0, 3.5 - FAN_Y, -2.4), Transparency = 1 })
	fan.Streamers = ctx:Emitter(sheet, {
		Texture = "Square",
		Rate = 0,
		Lifetime = NumberRange.new(0.9, 1.2),
		Speed = NumberRange.new(55, 75),
		SpreadAngle = Vector2.new(3, 3),
		EmissionDirection = Enum.NormalId.Front,
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		Size = NumberSequence.new(0.18),
		Squash = NumberSequence.new(-2.6),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.15, 0.45), NumberSequenceKeypoint.new(0.8, 0.6), NumberSequenceKeypoint.new(1, 1) }),
		Color = ColorSequence.new(Color3.fromRGB(225, 235, 245)),
		LightEmission = 0.4,
	})
	return fan
end

return {
	Id = "WindTunnel",
	Name = "Wind Tunnel",
	Hint = "Giant fans blow you toward the edge! Walk into the wind and hide behind the walls.",
	MinFloor = 1,
	MinPlayers = 1,
	Weight = 1,
	BossOnly = false,
	Zone = 2, -- B10-B19
	Duration = function(ctx)
		return plan(ctx).Duration
	end,

	Build = function(ctx)
		local p = plan(ctx)
		ctx.State.Plan = p
		local black = Color3.new(0, 0, 0)
		local dark = ctx.Theme.Floor:Lerp(black, 0.2)
		local steel = ctx.Theme.Floor:Lerp(Color3.fromRGB(165, 170, 185), 0.45)

		-- Deck with a faint grid
		ctx:Part({ Name = "Deck", Size = Vector3.new(SIZE, 2, SIZE), CFrame = ctx:At(0, -1, 0), Color = ctx.Theme.Floor:Lerp(black, 0.05) })
		ctx:Rim(HALF, HALF)
		for k = -2, 2 do
			ctx:Decor({ Name = "GridLine", Size = Vector3.new(0.25, 0.02, SIZE - 1), CFrame = ctx:At(k * 10, 0.03, 0), Color = ctx.Theme.Floor:Lerp(ctx.Theme.Primary, 0.22) })
			ctx:Decor({ Name = "GridLine", Size = Vector3.new(SIZE - 1, 0.02, 0.25), CFrame = ctx:At(0, 0.08, k * 10), Color = ctx.Theme.Floor:Lerp(ctx.Theme.Primary, 0.22) })
		end

		-- Windbreaks: scattered on a 3x3 grid of cells (never the middle one), mixed orientations
		local cells = {}
		for i = -1, 1 do
			for j = -1, 1 do
				if i ~= 0 or j ~= 0 then
					table.insert(cells, { i * 15, j * 15 })
				end
			end
		end
		local yaws = { 0, 90, 45, 135, 0, 90 }
		for k = #cells, 2, -1 do
			local r = ctx.Rng:NextInteger(1, k)
			cells[k], cells[r] = cells[r], cells[k]
		end
		local walls = {}
		for k = 1, p.Walls do
			local c = cells[k]
			local x = c[1] + ctx.Rng:NextNumber(-2, 2)
			local z = c[2] + ctx.Rng:NextNumber(-2, 2)
			local yaw = yaws[k]
			local base = ctx:At(x, 0, z, 0, yaw, 0)
			local wall = ctx:Part({ Name = "Windbreak", Size = Vector3.new(WALL_L, WALL_H, WALL_T), CFrame = base * CFrame.new(0, WALL_H / 2, 0), Color = steel, Material = Enum.Material.Metal })
			table.insert(walls, wall)
			ctx:Decor({ Name = "WindbreakCap", Size = Vector3.new(WALL_L + 0.2, 0.3, WALL_T + 0.2), CFrame = base * CFrame.new(0, WALL_H + 0.15, 0), Color = soft(ctx.Theme.Secondary, 0.6), Material = Enum.Material.Neon }) -- yellow / white accents glare above ~0.6
			for _, s in { -1, 1 } do
				ctx:Part({ Name = "WindbreakFoot", Size = Vector3.new(1, 0.8, 3), CFrame = base * CFrame.new(s * (WALL_L / 2 - 0.8), 0.4, 0), Color = dark })
				ctx:Decor({ Name = "WindbreakStripe", Size = Vector3.new(0.3, WALL_H - 1, WALL_T + 0.08), CFrame = base * CFrame.new(s * (WALL_L / 2 - 1.8), WALL_H / 2, 0), Color = dark })
			end
		end
		ctx.State.Walls = walls

		-- Fans
		local fans = {}
		for _, def in FANS do
			table.insert(fans, buildFan(ctx, def, steel, ctx.Theme.Floor:Lerp(ctx.Theme.Primary, 0.25):Lerp(Color3.new(1, 1, 1), 0.2)))
		end
		ctx.State.Fans = fans

		-- Windsock in the middle: points downwind while a fan blows, droops when calm
		ctx:Decor({ Name = "SockPole", Size = Vector3.new(0.35, 10, 0.35), CFrame = ctx:At(0, 5, 0), Color = dark, Material = Enum.Material.Metal })
		local pivot = ctx:At(0, 9.6, 0).Position
		local droop = CFrame.lookAt(pivot, pivot + Vector3.new(0.35, -1, 0.2))
		local sockRoot = ctx:Decor({ Name = "SockHoop", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.25, 2, 2), CFrame = droop * CFrame.Angles(0, math.rad(90), 0), Color = steel, Material = Enum.Material.Metal })
		local stripes = { soft(ctx.Theme.Hazard, 0.8), Color3.fromRGB(215, 215, 220), soft(ctx.Theme.Hazard, 0.8) }
		for k = 1, 3 do
			local r = 1.85 - k * 0.32
			local seg = ctx:Decor({ Name = "Sock", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.3, r, r), CFrame = droop * CFrame.new(0, 0, -(k - 0.4) * 1.3) * CFrame.Angles(0, math.rad(90), 0), Color = stripes[k] })
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = sockRoot
			weld.Part1 = seg
			weld.Parent = seg
			seg.Anchored = false
		end
		ctx.State.Sock = { Root = sockRoot, Pivot = pivot, Droop = droop }

		-- Start in the middle around the windsock
		local spawns = {}
		for k = 0, 7 do
			local a = k / 8 * math.pi * 2
			local pos = ctx:At(math.sin(a) * 5, 3, math.cos(a) * 5).Position
			table.insert(spawns, CFrame.lookAt(pos, pos + (pos - ctx:At(0, 3, 0).Position)))
		end
		ctx:SetSpawns(spawns)
	end,

	Start = function(ctx)
		local p = ctx.State.Plan
		local fans = ctx.State.Fans
		local sock = ctx.State.Sock
		local duration = ctx.Duration
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = ctx.State.Walls
		local active = {} -- { Fan, Start, End, Scale }

		local function edgeCoin()
			local side = ctx.Rng:NextInteger(1, 4)
			local along = ctx.Rng:NextNumber(-HALF + 4, HALF - 4)
			local inset = HALF - 2.5
			local x, z
			if side == 1 then
				x, z = along, -inset
			elseif side == 2 then
				x, z = inset, along
			elseif side == 3 then
				x, z = along, inset
			else
				x, z = -inset, along
			end
			ctx:SpawnCoin(ctx:At(x, 3, z).Position)
		end
		for _ = 1, 4 do
			edgeCoin()
		end

		-- One wind constraint per player (removed with the arena)
		local winds: { [Player]: any } = {}
		local function windFor(player: Player)
			local root = ctx:GetRoot(player)
			if not root then
				return nil
			end
			local entry = winds[player]
			if entry and entry.Root == root and entry.Constraint.Parent then
				return entry
			end
			if entry then
				entry.Attachment:Destroy()
			end
			local attachment = Instance.new("Attachment")
			attachment.Name = "OMF_WindAtt"
			attachment.Parent = root
			local constraint = Instance.new("LinearVelocity")
			constraint.Name = "OMF_Wind"
			constraint.Attachment0 = attachment
			constraint.RelativeTo = Enum.ActuatorRelativeTo.World
			constraint.VelocityConstraintMode = Enum.VelocityConstraintMode.Line
			constraint.LineDirection = Vector3.xAxis
			constraint.LineVelocity = 0
			constraint.ForceLimitsEnabled = true
			constraint.ForceLimitMode = Enum.ForceLimitMode.Magnitude
			constraint.MaxForce = 0
			constraint.Enabled = false
			constraint.Parent = attachment
			ctx.Trove:Add(attachment)
			entry = { Root = root, Attachment = attachment, Constraint = constraint }
			winds[player] = entry
			return entry
		end

		-- Push loop: every fan that blows on you adds its wind unless a windbreak covers you
		ctx:Every(0.1, function()
			local now = os.clock()
			for i = #active, 1, -1 do
				local gust = active[i]
				if now > gust.End then
					table.remove(active, i)
				else
					-- gusty wind: a short surge every SurgeEvery seconds once the gust is up to strength
					local t = now - gust.Start - RAMP_IN
					local surging = t > 0 and now < gust.End - RAMP_OUT and t % p.SurgeEvery >= p.SurgeEvery - p.Surge
					if surging ~= gust.Surging then
						gust.Surging = surging
						gust.Fan.Streamers.Rate = if surging then 140 else 55
					end
				end
			end
			for _, player in ctx:GetAlive() do
				local entry = windFor(player)
				if not entry then
					continue
				end
				local root = entry.Root
				local push = Vector3.zero
				local surging = false
				for _, gust in active do
					local strength = math.clamp((now - gust.Start) / RAMP_IN, 0, 1) * math.clamp((gust.End - now) / RAMP_OUT, 0, 1)
					if strength > 0 then
						local wind = ctx.Origin:VectorToWorldSpace(gust.Fan.Wind)
						if not workspace:Raycast(root.Position, -wind * SHELTER, params) then
							push += wind * (gust.Scale * strength)
							surging = surging or gust.Surging
						end
					end
				end
				local amount = math.min(push.Magnitude, 1)
				local constraint = entry.Constraint
				if amount < 0.02 then
					constraint.Enabled = false
					constraint.MaxForce = 0
				else
					constraint.LineDirection = push.Unit
					constraint.LineVelocity = p.Speed
					constraint.MaxForce = (if surging then SURGE_ACCEL else BASE_ACCEL) * amount * root.AssemblyMass
					constraint.Enabled = true
				end
			end
			return nil
		end)

		local function pointSock(dir: Vector3?)
			local target
			if dir then
				local world = ctx.Origin:VectorToWorldSpace(dir.Unit + Vector3.new(0, -0.12, 0))
				target = CFrame.lookAt(sock.Pivot, sock.Pivot + world)
			else
				target = sock.Droop
			end
			ctx:Tween(sock.Root, TweenInfo.new(if dir then 0.6 else 1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = target * CFrame.Angles(0, math.rad(90), 0) })
		end

		-- Gust schedule
		task.spawn(function()
			if not ctx:Wait(0.6) then
				return
			end
			local last: { number } = {}
			local count = 0
			while not ctx.Ended do
				if ctx:Elapsed() + p.Telegraph + 1.5 > duration then
					break
				end
				count += 1
				-- choose one fan (never the last one) or, deeper, sometimes an adjacent pair
				local picks
				local options = {}
				for k = 1, 4 do
					if not table.find(last, k) then
						table.insert(options, k)
					end
				end
				local k = options[ctx.Rng:NextInteger(1, #options)]
				if p.Double and count >= 2 and ctx.Rng:NextNumber() < 0.55 then
					local neighbour = if ctx.Rng:NextNumber() < 0.5 then k % 4 + 1 else (k + 2) % 4 + 1
					picks = { k, neighbour }
				else
					picks = { k }
				end
				last = picks
				local scale = if #picks > 1 then p.DoubleScale else 1

				-- Telegraph: blades spin up, ring turns hazard, streamers start, the warning sweeps downwind
				local windSum = Vector3.zero
				for _, index in picks do
					local fan = fans[index]
					windSum += fan.Wind
					spinTo(ctx, fan, MAX_SPIN, p.Telegraph)
					fan.Ring.Color3 = ctx.Theme.Hazard
					fan.Streamers.Rate = 12
					ctx:Tween(fan.Nose, TweenInfo.new(0.25, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Color = soft(ctx.Theme.Hazard, 0.85) })
					ctx:Warn(ctx:At(0, 0.3, 0), Vector3.new(SIZE, 0.2, SIZE), p.Telegraph, ctx.Theme.Hazard, { Sweep = fan.Wind })
					ctx:Sound("Warning", fan.Nose)
				end
				ctx:Announce(if #picks > 1 then "CROSSWIND!" else "GUST!", ctx.Theme.Hazard)
				if not ctx:Wait(p.Telegraph) then
					return
				end

				-- Blow
				local now = os.clock()
				for _, index in picks do
					local fan = fans[index]
					fan.Streamers.Rate = 55
					table.insert(active, { Fan = fan, Start = now, End = now + p.Blow, Scale = scale })
					ctx:Sound("Whoosh", fan.Nose)
				end
				pointSock(windSum)
				ctx:Shake(0.25, p.Blow)
				if not ctx:Wait(p.Blow) then
					return
				end

				-- Calm: fans wind down, a coin appears somewhere risky
				for _, index in picks do
					local fan = fans[index]
					spinTo(ctx, fan, IDLE_SPIN, 1.4)
					fan.Ring.Color3 = soft(ctx.Theme.Primary, 0.8)
					fan.Streamers.Rate = 0
					ctx:Tween(fan.Nose, TweenInfo.new(0.3), { Color = soft(ctx.Theme.Secondary, 0.75) })
				end
				pointSock(nil)
				edgeCoin()
				if not ctx:Wait(p.Calm) then
					return
				end
			end
		end)
	end,
}
