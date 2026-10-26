-- Jump Rope: two turner towers swing a giant neon rope around a long narrow deck. Jump it on every pass!
-- The rope angle follows a closed form so clients replay it smoothly (OMF_Orbit about X). The rope is fast,
-- so hits are swept maths on the server (no hazard boxes). Clients draw the rope at true server time but the
-- server sees each character a little late, so a pass is judged on the state the player had *at* the pass:
-- the check runs one upstream latency later (no blanket grace, so holding jump isn't a free pass).

local RunService = game:GetService("RunService")

local DECK_X = 24 -- deck half length (along X)
local DECK_Z = 7 -- deck half depth (along Z)
local PIVOT_Y = 9.6 -- rope axis height above the deck
local RADIUS = 9 -- lowest point skims the deck, sweeps past both long edges, passes high overhead
local ROPE_HALF = 0.45 -- rope radius (0.9 thick)
local ARM_X = 26.2 -- crank arms (the rope ends inside them)
local HUB_X = 27.5
local TOWER_X = 29.6
local FORGIVE = 0.12 -- shave off the rope's hit band so near misses survive
local WINDOW = 0.025 -- a pass is judged within this long of (pass time + the player's upstream latency)
local TAU = math.pi * 2

local function plan(ctx)
	local d = math.clamp(ctx.Difficulty, 0, 1.5)
	local m = math.min(d, 1)
	return {
		Omega = 2.0 + 0.9 * m + 0.3 * math.max(d - 1, 0),
		Ramp = 0.02 + 0.01 * m,
		Double = d >= 0.75,
		Dir = -1, -- comes down on the far side and sweeps toward the cab
		Angle0 = math.pi + 0.6, -- starts overhead: the first pass comes ~2 s in
		D = d,
	}
end

-- Rope centre at angle a (arena-local): z = -RADIUS * sin(a), y = PIVOT_Y - RADIUS * cos(a). a = 0 is the bottom.
-- On the lower half the rope crosses arena-local z at this angle:
local function crossingAngle(z: number): number
	return math.asin(math.clamp(-z / RADIUS, -1, 1))
end

-- Did the unwrapped angle move across `target` (mod 2π) between a0 and a1?
local function passed(a0: number, a1: number, target: number): boolean
	local lo, hi = math.min(a0, a1), math.max(a0, a1)
	local k = math.ceil((lo - target) / TAU)
	return target + k * TAU <= hi
end

-- Feet / head heights in arena-local space.
local function bodySpan(ctx, player): (number?, number?)
	local root = ctx:GetRoot(player)
	local humanoid = ctx:GetHumanoid(player)
	if not root or not humanoid then
		return nil, nil
	end
	local rootY = ctx.Origin:PointToObjectSpace(root.Position).Y
	local feet = if humanoid.RigType == Enum.HumanoidRigType.R15 then rootY - (humanoid.HipHeight + root.Size.Y / 2) else rootY - 3
	local head = root.Parent and root.Parent:FindFirstChild("Head")
	local top = if head and head:IsA("BasePart") then ctx.Origin:PointToObjectSpace(head.Position).Y + head.Size.Y / 2 else rootY + 2.5
	return feet, top
end

local function blocked(ctx, player, ropeY: number): boolean
	local feet, top = bodySpan(ctx, player)
	if not feet or not top then
		return false
	end
	return feet < ropeY + ROPE_HALF - FORGIVE and top > ropeY - ROPE_HALF + FORGIVE
end

-- Client -> server delay for a player's character (half the round trip, plus a frame of buffering).
local function upstream(player: Player): number
	local ok, ping = pcall(player.GetNetworkPing, player)
	return math.clamp((if ok and typeof(ping) == "number" then ping / 2 else 0.05) + 0.02, 0.02, 0.25)
end

return {
	Id = "JumpRope",
	Name = "Jump Rope",
	Hint = "Jump when the giant rope sweeps under you. It keeps speeding up!",
	MinFloor = 1,
	MinPlayers = 1,
	Weight = 1,
	BossOnly = false,
	Zone = 1, -- B1-B9
	Duration = 20,

	Build = function(ctx)
		local p = plan(ctx)
		local dark = ctx.Theme.Floor:Lerp(Color3.new(0, 0, 0), 0.45)
		ctx:Part({ Name = "Deck", Size = Vector3.new(DECK_X * 2, 2, DECK_Z * 2), CFrame = ctx:At(0, -1, 0), Color = ctx.Theme.Floor:Lerp(Color3.new(0, 0, 0), 0.1) })
		ctx:Rim(DECK_X, DECK_Z)
		-- The sweet spot: the rope is lowest along the middle. Layers 0.04 apart (no z-fighting)
		ctx:Decor({ Name = "JumpBand", Size = Vector3.new(DECK_X * 2 - 1.4, 0.02, 6), CFrame = ctx:At(0, 0.03, 0), Color = ctx.Theme.Floor:Lerp(ctx.Theme.Primary, 0.18) })
		ctx:Decor({ Name = "CentreLine", Size = Vector3.new(DECK_X * 2 - 1.4, 0.02, 0.4), CFrame = ctx:At(0, 0.08, 0), Color = ctx.Theme.Secondary, Material = Enum.Material.Neon })
		for k = -3, 4 do
			ctx:Decor({ Name = "Tick", Size = Vector3.new(0.3, 0.02, DECK_Z * 2 - 1.4), CFrame = ctx:At(k * 6 - 3, 0.13, 0), Color = ctx.Theme.Floor:Lerp(ctx.Theme.Primary, 0.32) })
		end
		-- Low kerbs along the long sides so nobody strolls off by accident
		for _, side in { -1, 1 } do
			ctx:Part({ Name = "Kerb", Size = Vector3.new(DECK_X * 2, 1.2, 0.6), CFrame = ctx:At(0, 0, side * (DECK_Z + 0.3)), Color = dark })
			ctx:Decor({ Name = "KerbLight", Size = Vector3.new(DECK_X * 2 - 1, 0.06, 0.25), CFrame = ctx:At(0, 0.62, side * (DECK_Z + 0.3)), Color = ctx.Theme.Primary, Material = Enum.Material.Neon })
		end

		-- Turner towers at both ends with neon hubs the rope cranks turn around
		for k, side in { -1, 1 } do
			ctx:Part({ Name = "Tower", Size = Vector3.new(2.6, 15, 5), CFrame = ctx:At(side * TOWER_X, 5.5, 0), Color = dark })
			local cap = ctx:Decor({ Name = "TowerCap", Size = Vector3.new(2.2, 0.8, 4.4), CFrame = ctx:At(side * TOWER_X, 13.4, 0), Color = ctx.Theme.Secondary, Material = Enum.Material.Neon })
			ctx:Animate(cap, "OMF_Pulse", { PulseMin = 0, PulseMax = 0.5, PulseSpeed = 1.3, PulsePhase = k / 2 })
			for _, zs in { -1, 1 } do
				ctx:Decor({ Name = "TowerStrip", Size = Vector3.new(0.5, 11, 0.1), CFrame = ctx:At(side * TOWER_X, 5.5, zs * 2.55), Color = ctx.Theme.Primary, Material = Enum.Material.Neon })
			end
			ctx:Decor({ Name = "HubCollar", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1, 4.6, 4.6), CFrame = ctx:At(side * 28, PIVOT_Y, 0), Color = dark })
			ctx:Decor({ Name = "Axle", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.9, 1.6, 1.6), CFrame = ctx:At(side * ARM_X, PIVOT_Y, 0), Color = dark })
			local hub = ctx:Decor({ Name = "Hub", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.8, 3, 3), CFrame = ctx:At(side * HUB_X, PIVOT_Y, 0), Color = ctx.Theme.Hazard, Material = Enum.Material.Neon })
			ctx:Glow(hub, ctx.Theme.Hazard, 14, 1.4)
		end

		-- Ropes (plus the crank arms and grips that turn with them). Everything in `spinning` follows
		-- centre * fromAxisAngle(X, angle) * offset.
		local centre = ctx:At(0, PIVOT_Y, 0)
		local ropes = {}
		local function addRope(angle0: number, hidden: boolean)
			local rope = { Angle0 = angle0, Parts = {}, Armed = not hidden }
			local function spin(name: string, props, offset: CFrame): BasePart
				props.Name = name
				props.CFrame = centre * CFrame.fromAxisAngle(Vector3.xAxis, angle0) * offset
				props.CastShadow = false
				local part = ctx:Decor(props)
				table.insert(rope.Parts, { Part = part, Offset = offset })
				return part
			end
			local length = ARM_X * 2
			rope.Rope = spin("Rope", { Shape = Enum.PartType.Cylinder, Size = Vector3.new(length, ROPE_HALF * 2, ROPE_HALF * 2), Color = ctx.Theme.Hazard, Material = Enum.Material.Neon, Transparency = if hidden then 1 else 0 }, CFrame.new(0, -RADIUS, 0))
			rope.Trail = ctx:Trail(rope.Rope, Vector3.new(-length / 2 + 1, 0, 0), Vector3.new(length / 2 - 1, 0, 0), ctx.Theme.Hazard, 0.16)
			rope.Trail.Enabled = not hidden
			for _, side in { -1, 1 } do
				-- single rope: the crank runs past the hub to a counterweight; double: two half arms
				local top = if p.Double then -0.3 else 2.6
				local armLength = top + RADIUS + 0.5
				spin("CrankArm", { Size = Vector3.new(0.6, armLength, 1), Color = dark }, CFrame.new(side * ARM_X, top - armLength / 2, 0))
				spin("Grip", { Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.2, 1.7, 1.7), Color = ctx.Theme.Secondary, Material = Enum.Material.Neon }, CFrame.new(side * ARM_X, -RADIUS, 0))
				if not p.Double then
					spin("Counterweight", { Size = Vector3.new(1.2, 1.4, 1.8), Color = ctx.Theme.Primary, Material = Enum.Material.Neon }, CFrame.new(side * ARM_X, top, 0))
				end
			end
			table.insert(ropes, rope)
		end
		addRope(p.Angle0, false)
		if p.Double then
			addRope(p.Angle0 + math.pi, true) -- appears a few seconds in, 180° behind the first
		end
		ctx.State.Ropes = ropes
		ctx.State.Centre = centre

		-- Line up along the middle of the deck, facing the side the rope comes down on
		local spawns = {}
		for k = 0, 7 do
			local x = -17.5 + k * 5
			table.insert(spawns, CFrame.lookAt(ctx:At(x, 3, 0).Position, ctx:At(x, 3, -DECK_Z * 4).Position))
		end
		ctx:SetSpawns(spawns)
	end,

	Start = function(ctx)
		local p = plan(ctx)
		local ropes = ctx.State.Ropes
		local centre = ctx.State.Centre

		local function coin()
			local z = (if ctx.Rng:NextNumber() < 0.5 then -1 else 1) * ctx.Rng:NextNumber(2.5, 5.5)
			ctx:SpawnCoin(ctx:At(ctx.Rng:NextNumber(-DECK_X + 4, DECK_X - 4), 3, z).Position)
		end
		for _ = 1, 5 do
			coin()
		end
		local extra = 0
		ctx:Every(4, function()
			coin()
			extra += 1
			return extra < 3
		end)

		-- Telegraph the first pass across the whole deck (angle = Angle0 + Dir * progress is 0 at the bottom)
		local firstPass = (-p.Dir * p.Angle0) % TAU
		local firstTime = (-p.Omega + math.sqrt(p.Omega * p.Omega + 2 * p.Ramp * firstPass)) / p.Ramp
		ctx:Warn(ctx:At(0, 0.3, 0), Vector3.new(DECK_X * 2, 0.2, DECK_Z * 2), firstTime, nil, { Sweep = Vector3.new(0, 0, 1) })
		ctx:Announce("JUMP THE ROPE!", ctx.Theme.Secondary)

		local startTime = workspace:GetServerTimeNow()
		for _, rope in ropes do
			for _, piece in rope.Parts do
				ctx:Animate(piece.Part, "OMF_Orbit", {
					OrbitCenter = centre,
					OrbitOffset = piece.Offset,
					OrbitAxis = Vector3.xAxis,
					Angle0 = rope.Angle0,
					Omega0 = p.Omega,
					Ramp = p.Ramp,
					Dir = p.Dir,
					StartTime = startTime,
				})
			end
		end
		ctx:Sound("Whoosh")

		-- The hidden second rope shows up the first time it is overhead after a few seconds
		local revealAt
		if #ropes > 1 then
			local base = (p.Dir * (math.pi - ropes[2].Angle0)) % TAU -- progress (mod 2π) with rope 2 overhead
			local soon = p.Omega * 4 + 0.5 * p.Ramp * 16
			revealAt = base + TAU * math.max(math.ceil((soon - base) / TAU), 0)
		end

		local pending = {}
		local stopped = false
		ctx.Trove:Connect(RunService.Heartbeat, function()
			if ctx.Ended then
				if not stopped then
					stopped = true
					local now = workspace:GetServerTimeNow()
					for _, rope in ropes do
						for _, piece in rope.Parts do
							piece.Part:SetAttribute("StopTime", now)
						end
					end
				end
				return
			end
			local t = workspace:GetServerTimeNow() - startTime
			local progress = p.Omega * t + 0.5 * p.Ramp * t * t
			local alive = ctx:GetAlive()
			for _, rope in ropes do
				local angle = rope.Angle0 + p.Dir * progress
				local rotation = centre * CFrame.fromAxisAngle(Vector3.xAxis, angle)
				for _, piece in rope.Parts do
					piece.Part.CFrame = rotation * piece.Offset
				end
				local prev = rope.Prev or angle
				rope.Prev = angle

				if not rope.Armed and revealAt and progress >= revealAt then
					rope.Armed = true
					rope.Rope.Transparency = 0
					rope.Trail.Enabled = true
					ctx:Announce("DOUBLE ROPE!", ctx.Theme.Hazard)
					ctx:Fx("Burst", { Position = rope.Rope.Position, Color = ctx.Theme.Hazard, Count = 30 })
				end
				if not rope.Armed then
					continue
				end
				if passed(prev, angle, 0) then
					ctx:Sound("Whoosh", rope.Rope)
				end
				-- Swept test: did the rope pass each player's z on its lower half this frame?
				for _, player in alive do
					if pending[player] then
						continue
					end
					local pos = ctx:LocalPosition(player)
					if not pos or math.abs(pos.X) > DECK_X + 1.5 or math.abs(pos.Z) > DECK_Z + 1.5 or pos.Y < -4 then
						continue
					end
					local crossing = crossingAngle(pos.Z)
					if passed(prev, angle, crossing) then
						-- judge once this player's state from the moment of the pass has reached us
						pending[player] = { Y = PIVOT_Y - RADIUS * math.cos(crossing), At = os.clock() + upstream(player) }
					end
				end
			end
			-- Resolve: clear (feet above the rope) on any frame inside the judging window survives the pass
			local now = os.clock()
			for player, pend in pending do
				if not table.find(alive, player) then
					pending[player] = nil
				elseif now >= pend.At - WINDOW then
					if not blocked(ctx, player, pend.Y) then
						pending[player] = nil
					elseif now > pend.At + WINDOW then
						pending[player] = nil
						ctx:Eliminate(player, "Tripped on the rope")
					end
				end
			end
		end)
	end,
}
