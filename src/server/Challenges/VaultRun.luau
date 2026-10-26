-- Vault Run: cash keeps spawning all over the floor, and the farther from the vault, the more it's worth.
-- Grab what you dare, but be back inside the vault ring when the bars rise and the door slams shut.
-- Deeper floors add ankle-high security lasers sweeping around the vault (jump them). The lasers are fast at
-- the tip, so contact is swept maths on the server, judged on each player's state at the moment of contact.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

local SIZE = 68
local HALF = SIZE / 2
local VAULT_R = 8
local PLINTH_TOP = 0.4
local SAFE_R = VAULT_R + 0.6 -- standing on the glowing ring still counts
local BAR_R = 8.8
local BARS = 16
local BAR_TOP = 6.45
local LID_Y = 7.1 -- the round door closes like a lid on top of the bars
local LID_R = 9.4
local HINGE_X = -(LID_R + 0.05)
local OPEN = math.rad(100)
local ARM_IN = 13
local ARM_OUT = 33
local ARM_Y = 0.75
local ARM_THICK = 0.7
local FORGIVE = 0.1
local WINDOW = 0.025 -- contact is judged within this long of (contact time + the player's upstream latency)
local CLOSING = 4 -- seconds of "VAULT CLOSING!" at the end
local GOLD = Color3.fromRGB(255, 196, 64)
local TAU = math.pi * 2

-- Value zones painted on the floor (outer zones are more golden and pay more)
local ZONES = {
	{ R = 30, Tint = 0.26, Top = 0.08, Bottom = -0.4, BandBottom = -0.3 },
	{ R = 22, Tint = 0.18, Top = 0.16, Bottom = -0.5, BandBottom = -0.35 },
	{ R = 14, Tint = 0.1, Top = 0.24, Bottom = -0.6, BandBottom = -0.45 },
}
local LABELS = { { R = 11, Text = "$", Top = 0.24 }, { R = 18, Text = "$$", Top = 0.16 }, { R = 26, Text = "$$$", Top = 0.08 } }

local function plan(ctx)
	local d = math.clamp(ctx.Difficulty, 0, 1.5)
	local m = math.min(d, 1)
	return {
		Arms = if d >= 0.9 then 2 elseif d >= 0.4 then 1 else 0,
		Omega = 0.42 + 0.18 * m + 0.1 * math.max(d - 1, 0),
		Ramp = 0.012,
		D = d,
	}
end

-- Hinge frame of the round door at opening angle `a` (0 = shut, lying flat over the vault).
local function hingeAt(ctx, a: number): CFrame
	return ctx:At(HINGE_X, LID_Y, 0) * CFrame.Angles(0, 0, a)
end

local function bodySpan(ctx, player): number?
	local root = ctx:GetRoot(player)
	local humanoid = ctx:GetHumanoid(player)
	if not root or not humanoid then
		return nil
	end
	local rootY = ctx.Origin:PointToObjectSpace(root.Position).Y
	return if humanoid.RigType == Enum.HumanoidRigType.R15 then rootY - (humanoid.HipHeight + root.Size.Y / 2) else rootY - 3
end

-- Client -> server delay for a player's character. The lasers are drawn at true server time (OMF_Orbit), so
-- contact is judged on the state the player had at that moment, which reaches us this much later.
local function upstream(player: Player): number
	local ok, ping = pcall(player.GetNetworkPing, player)
	return math.clamp((if ok and typeof(ping) == "number" then ping / 2 else 0.05) + 0.02, 0.02, 0.25)
end

local function armOffset(): CFrame
	return CFrame.new(0, ARM_Y, -(ARM_IN + ARM_OUT) / 2)
end

local function coinValue(ctx, x: number, z: number): number
	local dist = math.sqrt(x * x + z * z)
	return math.floor(Config.CoinValue(ctx.Floor) * (1 + dist / 12))
end

return {
	Id = "VaultRun",
	Name = "Vault Run",
	Hint = "Grab the cash, but be inside the vault when the door slams!",
	MinFloor = 1,
	MinPlayers = 1,
	Weight = 1,
	BossOnly = false,
	Zone = 2, -- B10-B19
	Duration = 18,

	Build = function(ctx)
		local p = plan(ctx)
		local black = Color3.new(0, 0, 0)
		local dark = ctx.Theme.Floor:Lerp(black, 0.45)
		local floorColor = ctx.Theme.Floor:Lerp(GOLD, 0.34)
		local floor = ctx:Part({ Name = "Floor", Size = Vector3.new(SIZE, 2, SIZE), CFrame = ctx:At(0, -1, 0), Color = floorColor })
		ctx:Rim(HALF, HALF, GOLD, ctx.Theme.Primary)
		local flashing = { { Part = floor, Color = floorColor } }

		-- Value zones: stepped discs (0.08 apart) with a thin gold band peeking out 0.04 below each edge
		for _, zone in ZONES do
			local color = ctx.Theme.Floor:Lerp(GOLD, zone.Tint)
			local height = zone.Top - zone.Bottom
			local disc = ctx:Part({ Name = "Zone", Shape = Enum.PartType.Cylinder, Size = Vector3.new(height, zone.R * 2, zone.R * 2), CFrame = ctx:At(0, zone.Bottom + height / 2, 0, 0, 0, 90), Color = color })
			table.insert(flashing, { Part = disc, Color = color })
			local bandHeight = zone.Top - 0.04 - zone.BandBottom
			ctx:Decor({ Name = "ZoneBand", Shape = Enum.PartType.Cylinder, Size = Vector3.new(bandHeight, zone.R * 2 + 0.5, zone.R * 2 + 0.5), CFrame = ctx:At(0, zone.BandBottom + bandHeight / 2, 0, 0, 0, 90), Color = GOLD, Material = Enum.Material.Neon, Transparency = 0.25 })
		end
		ctx.State.Flashing = flashing
		-- "$ / $$ / $$$" painted on the zones, readable from the vault
		for _, label in LABELS do
			for k = 0, 3 do
				local a = math.rad(45 + k * 90)
				local x, z = math.sin(a) * label.R, math.cos(a) * label.R
				local yaw = math.deg(a) + 180
				local plate = ctx:Decor({ Name = "ZoneLabel", Size = Vector3.new(5, 0.02, 2.4), CFrame = ctx:At(x, label.Top + 0.03, z, 0, yaw, 0), Transparency = 1 })
				local gui = Instance.new("SurfaceGui")
				gui.Face = Enum.NormalId.Top
				gui.LightInfluence = 0
				gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
				gui.PixelsPerStud = 24
				gui.Parent = plate
				local text = Instance.new("TextLabel")
				text.Size = UDim2.fromScale(1, 1)
				text.BackgroundTransparency = 1
				text.Font = Enum.Font.GothamBlack
				text.Text = label.Text
				text.TextScaled = true
				text.TextColor3 = GOLD
				text.TextTransparency = 0.35
				text.Parent = gui
			end
		end

		-- The vault: a raised gold plinth with an inlaid ring and a glowing emblem
		ctx:Part({ Name = "VaultPlinth", Shape = Enum.PartType.Cylinder, Size = Vector3.new(PLINTH_TOP + 0.7, VAULT_R * 2, VAULT_R * 2), CFrame = ctx:At(0, (PLINTH_TOP - 0.7) / 2, 0, 0, 0, 90), Color = GOLD:Lerp(black, 0.2) })
		ctx:Part({ Name = "VaultInlay", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.04, 14, 14), CFrame = ctx:At(0, PLINTH_TOP + 0.02, 0, 0, 0, 90), Color = GOLD:Lerp(black, 0.5) })
		ctx:Part({ Name = "VaultFloor", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.04, 12.8, 12.8), CFrame = ctx:At(0, PLINTH_TOP + 0.07, 0, 0, 0, 90), Color = GOLD:Lerp(black, 0.1) })
		local emblem = ctx:Part({ Name = "VaultEmblem", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.06, 3.6, 3.6), CFrame = ctx:At(0, PLINTH_TOP + 0.13, 0, 0, 0, 90), Color = GOLD:Lerp(Color3.new(1, 1, 1), 0.3), Material = Enum.Material.Neon })
		ctx:Glow(emblem, GOLD, 18, 1.2)
		local ring = ctx:Decor({ Name = "VaultRing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, 16.7, 16.7), CFrame = ctx:At(0, 0.05, 0, 0, 0, 90), Color = ctx.Theme.Primary, Material = Enum.Material.Neon })
		ctx:Animate(ring, "OMF_Pulse", { PulseMin = 0, PulseMax = 0.45, PulseSpeed = 0.5 })
		local lit = { ring }

		-- Bar sockets with chasing lamps; the bars hide inside them until the vault locks
		local bars = {}
		for k = 1, BARS do
			local a = (k - 0.5) / BARS * TAU
			local x, z = math.sin(a) * BAR_R, math.cos(a) * BAR_R
			ctx:Decor({ Name = "Socket", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 0.9, 0.9), CFrame = ctx:At(x, 0.4, z, 0, 0, 90), Color = dark })
			local lamp = ctx:Decor({ Name = "SocketLamp", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.12, 0.55, 0.55), CFrame = ctx:At(x, 0.77, z, 0, 0, 90), Color = ctx.Theme.Primary, Material = Enum.Material.Neon })
			ctx:Animate(lamp, "OMF_Pulse", { PulseMin = 0, PulseMax = 0.8, PulseSpeed = 0.7, PulsePhase = -(k - 1) / BARS })
			table.insert(lit, lamp)
			local bar = ctx:Decor({ Name = "VaultBar", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 0.45, 0.45), CFrame = ctx:At(x, 0.55, z, 0, 0, 90), Color = Color3.fromRGB(215, 218, 228):Lerp(GOLD, 0.3), Material = Enum.Material.Metal })
			table.insert(bars, { Part = bar, X = x, Z = z })
		end
		ctx.State.Bars = bars
		ctx.State.Lit = lit

		-- The round vault door, standing open on a hinge beside the vault. Every piece is welded to the
		-- hinge barrel, so one tween swings the whole door shut.
		for _, zs in { -1, 1 } do
			ctx:Part({ Name = "HingePillar", Size = Vector3.new(1.2, 6.6, 1.2), CFrame = ctx:At(HINGE_X - 0.6, 3.1, zs * 3), Color = dark })
		end
		local barrel = ctx:Decor({ Name = "HingeBarrel", Shape = Enum.PartType.Cylinder, Size = Vector3.new(7.6, 1.4, 1.4), CFrame = hingeAt(ctx, OPEN) * CFrame.Angles(0, math.rad(90), 0), Color = dark })
		local lid = hingeAt(ctx, OPEN) * CFrame.new(-HINGE_X, 0, 0) -- door centre; local Y is the door's outer face
		local flat = CFrame.Angles(0, 0, math.rad(90)) -- cylinders: turn the axis to the door normal
		local function piece(props, offset: CFrame)
			props.CFrame = lid * offset
			local part = ctx:Decor(props)
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = barrel
			weld.Part1 = part
			weld.Parent = part
			part.Anchored = false
			return part
		end
		local metal = GOLD:Lerp(black, 0.3)
		piece({ Name = "Door", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.2, LID_R * 2, LID_R * 2), Color = metal }, flat)
		piece({ Name = "DoorRing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.3, LID_R * 2 - 2, LID_R * 2 - 2), Color = ctx.Theme.Primary, Material = Enum.Material.Neon }, flat)
		piece({ Name = "DoorFace", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.4, LID_R * 2 - 3.8, LID_R * 2 - 3.8), Color = GOLD:Lerp(black, 0.15) }, flat)
		piece({ Name = "DoorHub", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.1, 2.6, 2.6), Color = GOLD:Lerp(Color3.new(1, 1, 1), 0.35), Material = Enum.Material.Neon }, flat)
		for k = 0, 2 do
			local spokeLength = (LID_R - 2.6) * 2
			piece({ Name = "DoorSpoke", Size = Vector3.new(spokeLength, 0.3, 0.5), Color = dark }, CFrame.new(0, 0.8, 0) * CFrame.Angles(0, math.rad(k * 60), 0))
			for _, s in { -1, 1 } do
				piece({ Name = "SpokeKnob", Shape = Enum.PartType.Ball, Size = Vector3.new(0.8, 0.8, 0.8), Color = GOLD, Material = Enum.Material.Neon }, CFrame.Angles(0, math.rad(k * 60), 0) * CFrame.new(s * spokeLength / 2, 0.8, 0))
			end
		end
		-- locking bolts around the rim (none on the hinge side)
		for k = 0, 7 do
			local a = math.rad(22.5 + k * 45)
			if math.cos(a) > -0.8 then
				piece({ Name = "DoorBolt", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.6, 0.7, 0.7), Color = Color3.fromRGB(215, 218, 228), Material = Enum.Material.Metal }, CFrame.Angles(0, a, 0) * CFrame.new(LID_R + 0.3, 0, 0))
			end
		end
		ctx.State.Barrel = barrel

		-- Security cameras on the corners, all watching the vault
		for k, c in { { 1, 1 }, { 1, -1 }, { -1, -1 }, { -1, 1 } } do
			local x, z = c[1] * (HALF + 2.5), c[2] * (HALF + 2.5)
			ctx:Part({ Name = "CameraPole", Size = Vector3.new(0.8, 12, 0.8), CFrame = ctx:At(x, 5, z), Color = dark })
			local head = CFrame.lookAt(ctx:At(x, 11.6, z).Position, ctx:At(0, 2, 0).Position)
			ctx:Decor({ Name = "Camera", Size = Vector3.new(1.6, 1.2, 2.6), CFrame = head * CFrame.new(0, 0, -0.6), Color = Color3.fromRGB(225, 228, 235) })
			ctx:Decor({ Name = "CameraLens", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 0.9, 0.9), CFrame = head * CFrame.new(0, 0, -1.95) * CFrame.Angles(0, math.rad(90), 0), Color = ctx.Theme.Hazard, Material = Enum.Material.Neon })
			local led = ctx:Decor({ Name = "CameraLed", Size = Vector3.new(0.3, 0.3, 0.3), CFrame = head * CFrame.new(0.5, 0.75, -0.2), Color = ctx.Theme.Hazard, Material = Enum.Material.Neon })
			ctx:Animate(led, "OMF_Pulse", { PulseMin = 0, PulseMax = 1, PulseSpeed = 1.5, PulsePhase = k / 4 })
		end

		-- Security laser arms (shown during the briefing, armed shortly after the start)
		local arms = {}
		local length = ARM_OUT - ARM_IN
		for k = 1, p.Arms do
			local angle0 = (k - 1) * math.pi + math.rad(40)
			local dir = if k == 1 then 1 else -1
			local spin = { Angle0 = angle0, Dir = dir, Scale = if k == 1 then 1 else 0.85, Pieces = {} }
			local function add(props, offset: CFrame): BasePart
				props.CFrame = ctx.Origin * CFrame.Angles(0, angle0, 0) * offset
				props.CastShadow = false
				local part = ctx:Decor(props)
				table.insert(spin.Pieces, { Part = part, Offset = offset })
				return part
			end
			spin.Beam = add({ Name = "SecurityLaser", Size = Vector3.new(ARM_THICK, ARM_THICK, length), Color = ctx.Theme.Hazard, Material = Enum.Material.Neon, Transparency = 0.6 }, armOffset())
			ctx:Trail(spin.Beam, Vector3.new(0, 0, -length / 2), Vector3.new(0, 0, length / 2), ctx.Theme.Hazard, 0.2)
			local inner = add({ Name = "LaserEmitter", Size = Vector3.new(1.4, 1.6, 1.4), Color = dark }, CFrame.new(0, 0.8, -(ARM_IN - 0.5)))
			add({ Name = "LaserEmitter", Size = Vector3.new(1.4, 1.6, 1.4), Color = dark }, CFrame.new(0, 0.8, -(ARM_OUT + 0.5)))
			ctx:Glow(inner, ctx.Theme.Hazard, 10, 1.2)
			table.insert(arms, spin)
		end
		ctx.State.Arms = arms

		-- Everyone starts inside the vault, facing out at the cash
		local spawns = {}
		for k = 0, 7 do
			local a = k / 8 * TAU + math.rad(22.5)
			local pos = ctx:At(math.sin(a) * 4.5, PLINTH_TOP + 3, math.cos(a) * 4.5).Position
			table.insert(spawns, CFrame.lookAt(pos, ctx:At(math.sin(a) * 30, PLINTH_TOP + 3, math.cos(a) * 30).Position))
		end
		ctx:SetSpawns(spawns)
	end,

	Start = function(ctx)
		local p = plan(ctx)
		local duration = ctx.Duration

		-- Cash waves: anywhere outside the vault, worth more the farther out it lands
		local function wave(count: number, minR: number)
			for _ = 1, count do
				local a = ctx.Rng:NextNumber(0, TAU)
				local r = ctx.Rng:NextNumber(minR, 31)
				local x = math.clamp(math.sin(a) * r, -HALF + 3, HALF - 3)
				local z = math.clamp(math.cos(a) * r, -HALF + 3, HALF - 3)
				ctx:SpawnCoin(ctx:At(x, 3, z).Position, coinValue(ctx, x, z))
			end
		end
		wave(4, 12)
		ctx:After(4.5, function()
			wave(3, 12)
		end)
		ctx:After(9, function()
			wave(3, 14)
		end)
		ctx:After(duration - CLOSING - 0.5, function()
			wave(2, 24) -- one last temptation, far away
		end)

		-- Closing sequence
		ctx:After(duration - CLOSING, function()
			ctx:Announce("VAULT CLOSING!", ctx.Theme.Hazard)
			ctx:Sound("Alarm")
			ctx:Warn(ctx:At(0, PLINTH_TOP + 0.3, 0), Vector3.new(SAFE_R * 2, 0.2, SAFE_R * 2), CLOSING, ctx.Theme.Secondary, { Shape = "Disc" })
			for _, f in ctx.State.Flashing do
				ctx:Tween(f.Part, TweenInfo.new(0.22, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Color = f.Color:Lerp(ctx.Theme.Hazard, 0.45) })
			end
			for _, part in ctx.State.Lit do
				part.Color = ctx.Theme.Hazard
				part:SetAttribute("PulseSpeed", 3)
			end
			for k = 1, CLOSING - 1 do
				ctx:After(k, function()
					ctx:Sound("Countdown")
				end)
			end
		end)
		-- Bars shoot up, then the door swings down and slams
		ctx:After(duration - 1.5, function()
			for _, bar in ctx.State.Bars do
				ctx:Tween(bar.Part, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
					Size = Vector3.new(BAR_TOP - 0.7, 0.45, 0.45),
					CFrame = ctx:At(bar.X, (BAR_TOP + 0.7) / 2, bar.Z, 0, 0, 90),
				})
			end
			ctx:Sound("Impact")
		end)
		ctx:After(duration - 1.05, function()
			ctx:Tween(ctx.State.Barrel, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = hingeAt(ctx, 0) * CFrame.Angles(0, math.rad(90), 0) })
		end)

		-- Security lasers
		local arms = ctx.State.Arms
		if #arms == 0 then
			return
		end
		local startTime = workspace:GetServerTimeNow()
		for _, arm in arms do
			for _, piece in arm.Pieces do
				ctx:Animate(piece.Part, "OMF_Orbit", {
					OrbitCenter = ctx.Origin,
					OrbitOffset = piece.Offset,
					Angle0 = arm.Angle0,
					Omega0 = p.Omega * arm.Scale,
					Ramp = p.Ramp * arm.Scale,
					Dir = arm.Dir,
					StartTime = startTime,
				})
			end
		end
		local armed = false
		ctx:After(1, function()
			armed = true
			for _, arm in arms do
				arm.Beam.Transparency = 0
			end
			ctx:Sound("Laser")
		end)

		local pending = {}
		local stopped = false
		ctx.Trove:Connect(RunService.Heartbeat, function()
			if ctx.Ended then
				if not stopped then
					stopped = true
					local now = workspace:GetServerTimeNow()
					for _, arm in arms do
						for _, piece in arm.Pieces do
							piece.Part:SetAttribute("StopTime", now)
						end
					end
				end
				return
			end
			local t = workspace:GetServerTimeNow() - startTime
			local alive = ctx:GetAlive()
			for _, arm in arms do
				local angle = arm.Angle0 + arm.Dir * arm.Scale * (p.Omega * t + 0.5 * p.Ramp * t * t)
				local rotation = ctx.Origin * CFrame.Angles(0, angle, 0)
				for _, piece in arm.Pieces do
					piece.Part.CFrame = rotation * piece.Offset
				end
				local prev = arm.Prev or angle
				arm.Prev = angle
				if not armed then
					continue
				end
				-- Swept test in polar coordinates: did the beam sweep across the player's bearing this frame?
				local lo, hi = math.min(prev, angle), math.max(prev, angle)
				for _, player in alive do
					if pending[player] then
						continue
					end
					local pos = ctx:LocalPosition(player)
					if not pos or pos.Y < -4 then
						continue
					end
					local r = math.sqrt(pos.X * pos.X + pos.Z * pos.Z)
					if r < ARM_IN - 0.6 or r > ARM_OUT + 0.6 then
						continue
					end
					local bearing = math.atan2(-pos.X, -pos.Z) -- angle at which the beam points at the player
					local width = (ARM_THICK / 2 + 0.5) / r -- beam half thickness + body half depth
					local k = math.ceil((lo - width - bearing) / TAU)
					if bearing + k * TAU <= hi + width then
						-- judge once this player's state from the moment of contact has reached us
						pending[player] = os.clock() + upstream(player)
					end
				end
			end
			local now = os.clock()
			for player, at in pending do
				if not table.find(alive, player) then
					pending[player] = nil
				elseif now >= at - WINDOW then
					local feet = bodySpan(ctx, player)
					if not feet or feet >= ARM_Y + ARM_THICK / 2 - FORGIVE then
						pending[player] = nil -- cleared it (a later contact frame is judged again)
					elseif now > at + WINDOW then
						pending[player] = nil
						ctx:Eliminate(player, "Tripped the security laser")
					end
				end
			end
		end)
	end,

	-- When the timer ends the vault is sealed: anyone outside the ring is locked out.
	Judge = function(ctx)
		ctx:Shake(0.9, 0.4)
		ctx:Sound("Explosion")
		ctx:Impact(ctx:At(0, PLINTH_TOP + 0.2, 0).Position, GOLD, SAFE_R + 6, 10)
		for _, f in ctx.State.Flashing do
			ctx:Tween(f.Part, TweenInfo.new(0.3), { Color = f.Color })
		end
		for _, player in ctx:GetAlive() do
			local pos = ctx:LocalPosition(player)
			if not pos or pos.Y < -4 or pos.X * pos.X + pos.Z * pos.Z > SAFE_R * SAFE_R then
				ctx:Eliminate(player, "Locked out of the vault")
			end
		end
	end,
}
