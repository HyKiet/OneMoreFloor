-- Rush Hour: cross the lanes of traffic (roads, a railway, a lava river with drifting rafts) to reach the SAFE zone.
-- Cars and rafts loop through tunnel housings at both ends of their lane. Each one rides an invisible carrier tagged
-- OMF_Slide, so clients scroll it smoothly and the server never moves it: hit tests evaluate the same closed form
-- (phase += speed * dt) instead, rewound by each player's round trip so a player is judged on the traffic they saw.
-- Trains are rare and fast: one welded assembly per rail lane, moved by the server only while it passes.

local SPAN_X = 46 -- playfield half width: the tunnel housings start here
local WRAP = 53 -- carriers wrap from +WRAP to -WRAP, hidden inside the housings
local SPAN = WRAP * 2
local EDGE = 60
local LANE_W = 6
local KERB = 0.3 -- sidewalks and medians sit this high above the road
local START_D = 9
local MEDIAN_D = 4
local GOAL_D = 10
local HOUSING_H = 10
local LAVA_Y = -1.3 -- lava surface
local RAFT_TOP = 0.2
local FEET_LAVA = -0.7 -- feet this low over the river = in the lava
local BODY = 0.75 -- body half extent used by the vehicle hit tests
local SHRINK = 0.35 -- vehicle hit boxes are this much smaller than the visuals on every side
local CARRIAGE_L = 9.4
local CARRIAGE_W = 5.2
local CARRIAGE_H = 5.4

local PAINTS = {
	Color3.fromRGB(196, 52, 52),
	Color3.fromRGB(44, 108, 205),
	Color3.fromRGB(226, 172, 44),
	Color3.fromRGB(62, 164, 92),
	Color3.fromRGB(214, 216, 224),
	Color3.fromRGB(230, 116, 42),
	Color3.fromRGB(44, 170, 176),
	Color3.fromRGB(138, 72, 196),
}
local CAR_TYPES = { -- primitive sizes; with the Car prop every kind is the prop at `Scale`
	{ Name = "Sedan", L = 6.6, W = 4.4, H = 3.4, Scale = 1 },
	{ Name = "Van", L = 7.6, W = 4.6, H = 4.3, Scale = 1.1 },
	{ Name = "Truck", L = 9.6, W = 4.8, H = 5.0, Scale = 1.2 },
}
local HEADLIGHT = Color3.fromRGB(215, 205, 160)
local NEON_V = 0.8 -- brightest a neon trim may be (themes with white / gold accents would glare)

local function soft(c: Color3, v: number?): Color3
	local h, sat, val = c:ToHSV()
	return Color3.fromHSV(h, sat, math.min(val, v or NEON_V))
end
local TAILLIGHT = Color3.fromRGB(205, 28, 36)

local function plan(ctx)
	local d = math.clamp(ctx.Difficulty, 0, 1.5)
	local m = math.min(d, 1)
	local over = math.max(d - 1, 0)
	local layout
	if d < 0.25 then
		layout = "RRR|RR"
	elseif d < 0.42 then
		layout = "RRR|T|RR"
	elseif d < 0.5 then
		layout = "RRR|T|RRR"
	elseif d < 0.75 then
		layout = "RRR|T|RR|VV"
	elseif d < 1.2 then
		layout = "RR|T|RRR|VVV"
	else
		layout = "RR|TT|RRR|VVV"
	end
	local lanes = #string.gsub(layout, "|", "")
	return {
		Layout = layout,
		Lanes = lanes,
		Duration = math.clamp(19 + 0.6 * lanes + 0.8 * #string.gsub(layout, "[^V]", ""), 22, 28),
		CarSpeed = 12 + 14 * m + 6 * over,
		GapTime = 1.7 - 0.85 * m - 0.2 * over, -- clear seconds between two cars at any point
		Rush = 1.25, -- traffic speed-up near the end
		TrainSpeed = 55 + 20 * m,
		TrainCars = if d >= 0.7 then 4 else 3,
		TrainWarn = 2.1 - 0.6 * m,
		TrainEvery = 6.5 - 2 * m,
		RaftSpeed = 5 + 4 * m + 2 * over,
		RaftGapMax = 11 - 3 * m,
		D = d,
	}
end

-- Round trip + a frame: the server's copy of a player is ~ping/2 old, and what they saw was ~ping/2 old too.
local function lagFor(player: Player): number
	local ok, ping = pcall(player.GetNetworkPing, player)
	return math.clamp((if ok and typeof(ping) == "number" then ping else 0.08) + 0.03, 0.03, 0.35)
end

-- Distance a lane's carriers have scrolled by server time t (piecewise: the rush-hour ramp changes speed).
local function travelled(lane, t: number): number
	local segs = lane.Segments
	for k = #segs, 1, -1 do
		local s = segs[k]
		if t >= s.T or k == 1 then
			return s.P + s.V * (t - s.T)
		end
	end
	return 0
end

-- Arena-local x of a mover at server time t (same formula as the client's OMF_Slide).
local function moverX(lane, mover, t: number): number
	return lane.Dir * ((mover.Phase0 + travelled(lane, t)) % SPAN - WRAP)
end

local function setCarriageVisible(carriage, visible: boolean)
	if carriage.Visible == visible then
		return
	end
	carriage.Visible = visible
	for _, entry in carriage.Parts do
		entry.Part.Transparency = if visible then entry.T else 1
	end
end

local function weldTo(root: BasePart, part: BasePart)
	part.Anchored = false
	part.Massless = true
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = part
	weld.Parent = part
end

-- Optional art: a clone of ServerStorage.Assets.Props[name] as a Model (pivot = bottom centre, front facing -Z).
local function propModel(ctx, name: string): Model?
	local prop = ctx:Prop(name)
	if not prop then
		return nil
	end
	if prop:IsA("Model") then
		return prop
	elseif prop:IsA("BasePart") then
		local model = Instance.new("Model")
		model.Name = name
		model.Parent = ctx.Folder
		prop.Parent = model
		model.PrimaryPart = prop
		return model
	end
	prop:Destroy()
	return nil
end

-- Size of a prop (x width, y height, z length), or nil when the place doesn't have it.
local function propSize(ctx, name: string): Vector3?
	local model = propModel(ctx, name)
	if not model then
		return nil
	end
	local ok, size = pcall(model.GetExtentsSize, model)
	model:Destroy()
	return if ok then size else nil
end

-- Scales a prop, poses its pivot at `cf`, recolours the parts named Body / Nose and welds it to `root`.
local function mountProp(model: Model, scale: number, cf: CFrame, root: BasePart, paint: Color3?, nose: Color3?): { BasePart }
	if math.abs(scale - 1) > 1e-3 then
		pcall(function()
			model:ScaleTo(model:GetScale() * scale)
		end)
	end
	model:PivotTo(cf)
	local parts = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
			if d.Name == "Body" and paint then
				d.Color = paint
			elseif d.Name == "Nose" and nose then
				d.Color = nose
			end
			weldTo(root, d)
			table.insert(parts, d)
		end
	end
	return parts
end

-- Invisible carrier for a looping mover, parked at the lane centre (the client scrolls it from there).
local function carrier(ctx, lane, size: Vector3, centreY: number, collide: boolean): BasePart
	local look = ctx.Origin:VectorToWorldSpace(Vector3.new(lane.Dir, 0, 0))
	local pos = ctx:At(0, centreY, lane.Z).Position
	return ctx:Part({
		Name = "Carrier",
		Size = size,
		CFrame = CFrame.lookAt(pos, pos + look),
		Transparency = 1,
		CanCollide = collide,
		CanQuery = collide,
		CanTouch = false,
		CastShadow = false,
	})
end

-- One car (carrier-local -Z is the front). `kind` carries the real size, which is also the hit box.
local function buildCar(ctx, lane, kind, paint: Color3): BasePart
	local L, W, H = kind.L, kind.W, kind.H
	local root = carrier(ctx, lane, Vector3.new(W, H, L), H / 2, false)
	local base = root.CFrame * CFrame.new(0, -H / 2, 0) -- ground under the car centre
	if kind.Prop then
		local model = propModel(ctx, "Car")
		if model then
			mountProp(model, kind.Scale, base, root, paint, paint:Lerp(Color3.new(0, 0, 0), 0.25))
			return root
		end
	end
	local function piece(props, offset: CFrame)
		props.CFrame = base * offset
		props.CastShadow = false
		local part = ctx:Decor(props)
		weldTo(root, part)
		return part
	end
	local dark = Color3.fromRGB(22, 24, 30)
	local glass = Color3.fromRGB(34, 44, 62)
	if kind.Name == "Truck" then
		piece({ Name = "Cab", Size = Vector3.new(W, 3.0, 2.6), Color = paint }, CFrame.new(0, 0.6 + 1.5, -L / 2 + 1.3))
		piece({ Name = "Windscreen", Size = Vector3.new(W - 0.6, 0.9, 0.1), Color = glass, Material = Enum.Material.Glass, Transparency = 0.1 }, CFrame.new(0, 2.85, -L / 2 - 0.05))
		piece({ Name = "Cargo", Size = Vector3.new(W, H - 0.7, L - 2.9), Color = ctx.Theme.Floor:Lerp(Color3.new(1, 1, 1), 0.55) }, CFrame.new(0, 0.6 + (H - 0.7) / 2, 1.45))
		piece({ Name = "CargoStripe", Size = Vector3.new(W + 0.1, 0.3, L - 3.3), Color = paint }, CFrame.new(0, 2.1, 1.45))
	elseif kind.Name == "Van" then
		piece({ Name = "Body", Size = Vector3.new(W, H - 0.6, L), Color = paint }, CFrame.new(0, 0.6 + (H - 0.6) / 2, 0))
		piece({ Name = "Windows", Size = Vector3.new(W + 0.1, 0.9, L - 1.6), Color = glass, Material = Enum.Material.Glass, Transparency = 0.1 }, CFrame.new(0, H - 1.0, 0.4))
		piece({ Name = "Windscreen", Size = Vector3.new(W - 0.6, 0.9, 0.1), Color = glass, Material = Enum.Material.Glass, Transparency = 0.1 }, CFrame.new(0, H - 1.0, -L / 2 - 0.05))
	else
		piece({ Name = "Body", Size = Vector3.new(W, 1.5, L), Color = paint }, CFrame.new(0, 0.55 + 0.75, 0))
		piece({ Name = "Cabin", Size = Vector3.new(W - 0.6, H - 2.05, L * 0.5), Color = glass, Material = Enum.Material.Glass, Transparency = 0.1 }, CFrame.new(0, 2.05 + (H - 2.05) / 2 - 0.01, 0.35))
		piece({ Name = "Roof", Size = Vector3.new(W - 0.5, 0.2, L * 0.5 - 0.3), Color = paint }, CFrame.new(0, H - 0.08, 0.35))
	end
	for _, z in { -L / 2 + 1.35, L / 2 - 1.35 } do
		piece({ Name = "Wheels", Shape = Enum.PartType.Cylinder, Size = Vector3.new(W + 0.2, 1.3, 1.3), Color = dark }, CFrame.new(0, 0.65, z))
	end
	piece({ Name = "Headlights", Size = Vector3.new(W - 0.9, 0.28, 0.1), Color = HEADLIGHT, Material = Enum.Material.Neon }, CFrame.new(0, 1.25, -L / 2 - 0.06))
	piece({ Name = "Taillights", Size = Vector3.new(W - 0.9, 0.28, 0.1), Color = TAILLIGHT, Material = Enum.Material.Neon }, CFrame.new(0, 1.25, L / 2 + 0.06))
	return root
end

-- A raft of three logs. The carrier itself is the floor players stand on.
local function buildRaft(ctx, lane, length: number): BasePart
	local root = carrier(ctx, lane, Vector3.new(5, 1, length), RAFT_TOP - 0.5, true)
	root.Material = Enum.Material.Wood
	local model = propModel(ctx, "Log")
	if model then
		local ok, ext = pcall(model.GetExtentsSize, model)
		if ok then
			mountProp(model, length / math.max(ext.Z, 0.05), root.CFrame * CFrame.new(0, -1.2, 0), root)
			return root
		end
		model:Destroy()
	end
	local wood = Color3.fromRGB(118, 78, 46)
	local function piece(props, offset: CFrame)
		props.CFrame = root.CFrame * offset
		props.CastShadow = false
		local part = ctx:Decor(props)
		weldTo(root, part)
		return part
	end
	for k, x in { -1.62, 0, 1.62 } do
		local len = length - (if k == 2 then 0 else 0.6)
		piece({ Name = "Log", Shape = Enum.PartType.Cylinder, Size = Vector3.new(len, 1.75, 1.75), Color = wood:Lerp(Color3.new(0, 0, 0), (k - 1) * 0.08), Material = Enum.Material.Wood }, CFrame.new(x, -0.42, 0) * CFrame.Angles(0, math.rad(90), 0))
	end
	for _, z in { -length / 2 + 1.2, length / 2 - 1.2 } do
		piece({ Name = "Strap", Size = Vector3.new(5.2, 0.3, 0.5), Color = Color3.fromRGB(60, 44, 32), Material = Enum.Material.Wood }, CFrame.new(0, 0.38, z))
	end
	return root
end

-- A train for one rail lane: an engine plus carriages welded to an invisible root at the engine's centre.
-- Uses the TrainEngine / TrainCar props when the place has them, else primitive carriages.
local function buildTrain(ctx, lane, p)
	local look = ctx.Origin:VectorToWorldSpace(Vector3.new(lane.Dir, 0, 0))
	local pos = ctx:At(0, -20, lane.Z).Position -- parked out of sight under the arena
	local root = ctx:Part({ Name = "TrainRoot", Size = Vector3.new(1, 1, 1), CFrame = CFrame.lookAt(pos, pos + look), Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false })
	local body = ctx.Theme.Floor:Lerp(Color3.new(1, 1, 1), 0.62)
	local engineSize, carSize = propSize(ctx, "TrainEngine"), propSize(ctx, "TrainCar")
	local useProps = engineSize ~= nil and carSize ~= nil
	local carriages = {}
	local offset = 0 -- each carriage centre behind the engine centre (root-local +Z is backwards)
	local width, height = CARRIAGE_W, CARRIAGE_H
	for j = 0, p.TrainCars - 1 do
		local size = if useProps then (if j == 0 then engineSize else carSize) :: Vector3 else Vector3.new(CARRIAGE_W, CARRIAGE_H, CARRIAGE_L)
		if j > 0 then
			offset += carriages[j].Length / 2 + 0.6 + size.Z / 2
		end
		local centre = root.CFrame * CFrame.new(0, 0, offset)
		local carriage = { Parts = {}, Offset = offset, Length = size.Z, Visible = true }
		local base = centre * CFrame.new(0, -CARRIAGE_H / 2, 0)
		local model = if useProps then propModel(ctx, if j == 0 then "TrainEngine" else "TrainCar") else nil
		if model then
			width, height = math.min(width, size.X), math.min(height, size.Y)
			for _, part in mountProp(model, 1, base, root, body, ctx.Theme.Hazard) do
				table.insert(carriage.Parts, { Part = part, T = part.Transparency })
			end
		else
			local function piece(props, cf: CFrame)
				props.CFrame = base * cf
				props.CastShadow = false
				local part = ctx:Decor(props)
				weldTo(root, part)
				table.insert(carriage.Parts, { Part = part, T = part.Transparency })
				return part
			end
			piece({ Name = "Carriage", Size = Vector3.new(CARRIAGE_W, 4.4, CARRIAGE_L), Color = body, Material = Enum.Material.Metal }, CFrame.new(0, 0.9 + 2.2, 0))
			piece({ Name = "Windows", Size = Vector3.new(CARRIAGE_W + 0.1, 1.1, CARRIAGE_L - 1.4), Color = Color3.fromRGB(30, 36, 52), Material = Enum.Material.Glass, Transparency = 0.05 }, CFrame.new(0, 3.75, 0))
			piece({ Name = "Stripe", Size = Vector3.new(CARRIAGE_W + 0.16, 0.24, CARRIAGE_L - 0.4), Color = soft(ctx.Theme.Hazard, 0.85), Material = Enum.Material.Neon }, CFrame.new(0, 2.3, 0))
			piece({ Name = "Roof", Size = Vector3.new(CARRIAGE_W - 0.7, 0.4, CARRIAGE_L - 0.8), Color = body:Lerp(Color3.new(0, 0, 0), 0.35), Material = Enum.Material.Metal }, CFrame.new(0, 5.49, 0))
			for _, z in { -CARRIAGE_L / 2 + 1.6, CARRIAGE_L / 2 - 1.6 } do
				piece({ Name = "Bogie", Shape = Enum.PartType.Cylinder, Size = Vector3.new(CARRIAGE_W - 0.2, 1.2, 1.2), Color = Color3.fromRGB(26, 26, 30) }, CFrame.new(0, 0.6, z))
			end
			if j == 0 then
				piece({ Name = "Headlight", Size = Vector3.new(2.6, 0.5, 0.1), Color = HEADLIGHT, Material = Enum.Material.Neon }, CFrame.new(0, 1.9, -CARRIAGE_L / 2 - 0.06))
				piece({ Name = "Nose", Size = Vector3.new(CARRIAGE_W - 0.8, 1.1, 0.1), Color = ctx.Theme.Hazard:Lerp(Color3.new(0, 0, 0), 0.35) }, CFrame.new(0, 3.75, -CARRIAGE_L / 2 - 0.06))
			end
		end
		table.insert(carriages, carriage)
	end
	for _, carriage in carriages do
		setCarriageVisible(carriage, false)
	end
	local last = carriages[#carriages]
	return {
		Root = root,
		Carriages = carriages,
		Front = carriages[1].Length / 2, -- front end ahead of the root
		Back = last.Offset + last.Length / 2, -- rear end behind the root
		LastOffset = last.Offset,
		Width = width,
		Height = height,
	}
end

return {
	Id = "RushHour",
	Name = "Rush Hour",
	Hint = "Cross the busy lanes and reach the far side before time runs out!",
	MinFloor = 1,
	MinPlayers = 1,
	Weight = 1,
	BossOnly = false,
	Zone = 1, -- B1-B9
	Duration = function(ctx)
		return plan(ctx).Duration
	end,

	Build = function(ctx)
		local p = plan(ctx)
		local rng = ctx.Rng
		local black = Color3.new(0, 0, 0)
		local white = Color3.new(1, 1, 1)
		local asphalt = ctx.Theme.Floor:Lerp(Color3.fromRGB(64, 66, 74), 0.45) -- neutral road, darker than the kerbs but never black
		local pavement = ctx.Theme.Floor:Lerp(white, 0.3)
		local housing = ctx.Theme.Floor:Lerp(ctx.Theme.Primary, 0.2)

		-- Z layout, from the cab side (+Z) to the goal (-Z)
		local medians = #string.gsub(p.Layout, "[^|]", "")
		local total = START_D + GOAL_D + p.Lanes * LANE_W + medians * MEDIAN_D
		local top = total / 2
		local z = top
		local lanes = {}
		local strips = {} -- { Kind, Near, Far }
		table.insert(strips, { Kind = "Start", Near = z, Far = z - START_D })
		z -= START_D
		local laneIndex = 0
		for k = 1, #p.Layout do
			local c = string.sub(p.Layout, k, k)
			if c == "|" then
				table.insert(strips, { Kind = "Median", Near = z, Far = z - MEDIAN_D })
				z -= MEDIAN_D
			else
				laneIndex += 1
				table.insert(lanes, { Kind = c, Z = z - LANE_W / 2, Near = z, Far = z - LANE_W, Index = laneIndex })
				z -= LANE_W
			end
		end
		table.insert(strips, { Kind = "Goal", Near = z, Far = z - GOAL_D })
		local goalEdge = z
		ctx.State.GoalEdge = goalEdge
		ctx.State.Lanes = lanes
		ctx.State.Top = top

		-- Ground: sidewalks / medians (raised kerb), asphalt per road group, ballast per rail lane, lava per river
		local function stripPart(s, color: Color3, material: Enum.Material, topY: number, bottomY: number, name: string)
			local depth = s.Near - s.Far
			return ctx:Part({ Name = name, Size = Vector3.new(SPAN_X * 2, topY - bottomY, depth), CFrame = ctx:At(0, (topY + bottomY) / 2, (s.Near + s.Far) / 2), Color = color, Material = material })
		end
		for _, s in strips do
			local color = if s.Kind == "Goal" then ctx.Theme.Floor:Lerp(ctx.Theme.Secondary, 0.32) else pavement
			stripPart(s, color, if s.Kind == "Goal" then Enum.Material.SmoothPlastic else Enum.Material.Pavement, KERB, -2.8, s.Kind)
			-- glowing kerb lines on the edges that face traffic
			for _, edge in { s.Near, s.Far } do
				if (edge == s.Near and s.Kind ~= "Start") or (edge == s.Far and s.Kind ~= "Goal") then
					local inward = if edge == s.Near then -0.2 else 0.2
					ctx:Decor({ Name = "KerbLine", Size = Vector3.new(SPAN_X * 2, 0.06, 0.3), CFrame = ctx:At(0, KERB + 0.02, edge + inward), Color = soft(if s.Kind == "Goal" then ctx.Theme.Secondary else ctx.Theme.Primary, 0.7), Material = Enum.Material.Neon })
				end
			end
		end
		-- group consecutive lanes of the same kind
		local groups = {}
		for _, lane in lanes do
			local last = groups[#groups]
			if last and last.Kind == lane.Kind and math.abs(last.Far - lane.Near) < 0.01 then
				last.Far = lane.Far
				table.insert(last.Lanes, lane)
			else
				table.insert(groups, { Kind = lane.Kind, Near = lane.Near, Far = lane.Far, Lanes = { lane } })
			end
		end
		local lavaLit = false
		for _, g in groups do
			if g.Kind == "R" then
				stripPart(g, asphalt, Enum.Material.Asphalt, 0, -1.2, "Road")
				-- dashed dividers between lanes of the same group, solid edge lines along the kerbs
				for k = 1, #g.Lanes - 1 do
					local lz = g.Lanes[k].Far
					for x = -SPAN_X + 4, SPAN_X - 4, 8 do
						ctx:Decor({ Name = "Dash", Size = Vector3.new(4, 0.04, 0.28), CFrame = ctx:At(x, 0.01, lz), Color = Color3.fromRGB(196, 196, 186) })
					end
				end
				for _, edge in { g.Near - 0.45, g.Far + 0.45 } do
					ctx:Decor({ Name = "EdgeLine", Size = Vector3.new(SPAN_X * 2, 0.04, 0.22), CFrame = ctx:At(0, 0.01, edge), Color = Color3.fromRGB(214, 176, 60) })
				end
			elseif g.Kind == "T" then
				stripPart(g, ctx.Theme.Floor:Lerp(Color3.fromRGB(96, 88, 80), 0.5), Enum.Material.Slate, 0, -1.2, "Ballast")
				for _, lane in g.Lanes do
					for x = -SPAN_X + 2, SPAN_X - 2, 4 do
						ctx:Decor({ Name = "Sleeper", Size = Vector3.new(0.9, 0.16, 4.6), CFrame = ctx:At(x, 0.04, lane.Z), Color = Color3.fromRGB(84, 62, 44), Material = Enum.Material.Wood })
					end
					for _, rz in { -1.55, 1.55 } do
						ctx:Decor({ Name = "Rail", Size = Vector3.new(SPAN_X * 2, 0.25, 0.25), CFrame = ctx:At(0, 0.23, lane.Z + rz), Color = Color3.fromRGB(150, 152, 160), Material = Enum.Material.Metal })
					end
				end
			else -- "V": lava river
				local depth = g.Near - g.Far
				local lava = ctx:Decor({ Name = "LavaRiver", Size = Vector3.new(SPAN_X * 2, 2.4, depth), CFrame = ctx:At(0, LAVA_Y - 1.2, (g.Near + g.Far) / 2), Color = ctx.Theme.Hazard:Lerp(Color3.fromRGB(255, 120, 30), 0.35), Material = Enum.Material.CrackedLava })
				ctx:Hazard({ Name = "Lava", Size = Vector3.new(SPAN_X * 2, 1, depth), CFrame = ctx:At(0, LAVA_Y - 2.6, (g.Near + g.Far) / 2), Transparency = 1 })
				for _, edge in { g.Near - 0.15, g.Far + 0.15 } do
					ctx:Decor({ Name = "LavaGlow", Size = Vector3.new(SPAN_X * 2, 0.08, 0.3), CFrame = ctx:At(0, LAVA_Y + 0.03, edge), Color = soft(ctx.Theme.Hazard:Lerp(Color3.fromRGB(255, 150, 40), 0.5)), Material = Enum.Material.Neon })
				end
				ctx:Emitter(lava, { Texture = "Sparks", Rate = 10, Lifetime = NumberRange.new(0.6, 1.2), Speed = NumberRange.new(3, 7), SpreadAngle = Vector2.new(20, 20), Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) }), Color = ColorSequence.new(Color3.fromRGB(255, 160, 60)), Acceleration = Vector3.new(0, -8, 0) })
				if not lavaLit then
					lavaLit = true
					local glowAt = ctx:Decor({ Name = "LavaLight", Size = Vector3.new(1, 1, 1), CFrame = ctx:At(0, LAVA_Y + 2, (g.Near + g.Far) / 2), Transparency = 1 })
					ctx:Glow(glowAt, Color3.fromRGB(255, 120, 50), 40, 1.2)
				end
			end
		end

		-- Tunnel housings along both sides, with a dark mouth over every lane
		local zMid = (top + (goalEdge - GOAL_D)) / 2
		for _, side in { -1, 1 } do
			local hx = side * (SPAN_X + EDGE) / 2
			ctx:Part({ Name = "Housing", Size = Vector3.new(EDGE - SPAN_X, HOUSING_H + 4, total), CFrame = ctx:At(hx, (HOUSING_H - 4) / 2, zMid), Color = housing, Material = Enum.Material.Concrete })
			ctx:Decor({ Name = "HousingTrim", Size = Vector3.new(0.3, 0.12, total), CFrame = ctx:At(side * (SPAN_X + 0.1), HOUSING_H + 0.02, zMid), Color = soft(ctx.Theme.Primary), Material = Enum.Material.Neon })
			ctx:Decor({ Name = "WindowBand", Size = Vector3.new(0.08, 0.4, total - 1), CFrame = ctx:At(side * (SPAN_X - 0.04), 8, zMid), Color = soft(ctx.Theme.Primary:Lerp(housing, 0.35), 0.6), Material = Enum.Material.Neon })
			for _, lane in lanes do
				local bottom = if lane.Kind == "V" then LAVA_Y else 0
				local height = if lane.Kind == "V" then 2.8 elseif lane.Kind == "T" then 6.4 else 5.6
				local trim = soft(if lane.Kind == "R" then ctx.Theme.Primary elseif lane.Kind == "T" then ctx.Theme.Hazard else Color3.fromRGB(255, 140, 50))
				ctx:Decor({ Name = "Mouth", Size = Vector3.new(0.08, height, LANE_W - 0.4), CFrame = ctx:At(side * (SPAN_X - 0.04), bottom + height / 2, lane.Z), Color = Color3.fromRGB(10, 10, 14) })
				ctx:Decor({ Name = "MouthTrim", Size = Vector3.new(0.1, 0.25, LANE_W - 0.2), CFrame = ctx:At(side * (SPAN_X - 0.09), bottom + height + 0.25, lane.Z), Color = trim, Material = Enum.Material.Neon })
			end
		end

		-- Railings behind the start and the goal
		for _, rz in { top - 0.3, goalEdge - GOAL_D + 0.3 } do
			ctx:Part({ Name = "Railing", Size = Vector3.new(SPAN_X * 2, 3, 0.6), CFrame = ctx:At(0, KERB + 1.5, rz), Color = housing })
			ctx:Decor({ Name = "RailingLight", Size = Vector3.new(SPAN_X * 2, 0.1, 0.2), CFrame = ctx:At(0, KERB + 3.02, rz), Color = soft(ctx.Theme.Secondary:Lerp(housing, 0.45), 0.55), Material = Enum.Material.Neon })
		end

		-- SAFE gantry over the goal
		local gz = goalEdge - 1
		ctx:Part({ Name = "Gantry", Size = Vector3.new(SPAN_X * 2, 1, 1), CFrame = ctx:At(0, 10, gz), Color = housing:Lerp(black, 0.15), Material = Enum.Material.Metal })
		ctx:Decor({ Name = "GantryLight", Size = Vector3.new(SPAN_X * 2, 0.14, 0.3), CFrame = ctx:At(0, 9.44, gz), Color = soft(ctx.Theme.Secondary), Material = Enum.Material.Neon })
		for _, hx in { -6, 6 } do
			ctx:Decor({ Name = "Hanger", Size = Vector3.new(0.2, 1, 0.2), CFrame = ctx:At(hx, 9.0, gz), Color = housing })
		end
		local board = ctx:Part({ Name = "SafeSign", Size = Vector3.new(16, 3.6, 0.5), CFrame = ctx:At(0, 6.7, gz), Color = ctx.Theme.Floor:Lerp(black, 0.4) })
		ctx:Sign(board, "SAFE", { Face = Enum.NormalId.Back, TextColor3 = soft(ctx.Theme.Secondary:Lerp(white, 0.15), 0.95) })
		for _, s in { { 0, 1.95, 16.4, 0.3 }, { 0, -1.95, 16.4, 0.3 }, { 8.05, 0, 0.3, 3.6 }, { -8.05, 0, 0.3, 3.6 } } do
			ctx:Decor({ Name = "SignTrim", Size = Vector3.new(s[3], s[4], 0.3), CFrame = ctx:At(s[1], 6.7 + s[2], gz + 0.15), Color = soft(ctx.Theme.Secondary), Material = Enum.Material.Neon })
		end
		ctx:Glow(board, ctx.Theme.Secondary, 22, 1.4)

		-- Crossing signals on the medians either side of each rail group
		ctx.State.Signals = {}
		for _, g in groups do
			if g.Kind == "T" then
				local lamps = {}
				for _, sz in { g.Near + 1.2, g.Far - 1.2 } do
					for _, sx in { -24, 24 } do
						ctx:Part({ Name = "SignalPost", Size = Vector3.new(0.4, 5.2, 0.4), CFrame = ctx:At(sx, KERB + 2.6, sz), Color = Color3.fromRGB(40, 40, 46), Material = Enum.Material.Metal })
						ctx:Decor({ Name = "LampBar", Size = Vector3.new(2.6, 0.5, 0.3), CFrame = ctx:At(sx, KERB + 4.3, sz), Color = Color3.fromRGB(26, 26, 30) })
						for _, rot in { 35, -35 } do
							ctx:Decor({ Name = "Crossbuck", Size = Vector3.new(3.2, 0.42, 0.12), CFrame = ctx:At(sx, KERB + 5.6, sz) * CFrame.Angles(0, 0, math.rad(rot)), Color = Color3.fromRGB(222, 222, 214) })
						end
						for k, lx in { -0.85, 0.85 } do
							local lamp = ctx:Decor({ Name = "SignalLamp", Shape = Enum.PartType.Ball, Size = Vector3.new(0.75, 0.75, 0.75), CFrame = ctx:At(sx + lx, KERB + 4.3, sz + 0.25), Color = Color3.fromRGB(70, 20, 22) })
							table.insert(lamps, { Part = lamp, Phase = k })
						end
					end
				end
				local light = ctx:Glow(lamps[1].Part, ctx.Theme.Hazard, 30, 2)
				light.Enabled = false
				for _, lane in g.Lanes do
					ctx.State.Signals[lane] = { Lamps = lamps, Light = light }
				end
			end
		end

		-- Movers --------------------------------------------------------------
		-- Car sizes double as hit boxes: with the Car prop every kind is that mesh at its own scale
		local carKinds = CAR_TYPES
		local carProp = propSize(ctx, "Car")
		if carProp then
			carKinds = {}
			for _, kind in CAR_TYPES do
				table.insert(carKinds, { Name = kind.Name, L = carProp.Z * kind.Scale, W = carProp.X * kind.Scale, H = carProp.Y * kind.Scale, Scale = kind.Scale, Prop = true })
			end
		end
		local startTime = workspace:GetServerTimeNow()
		local dir = if rng:NextNumber() < 0.5 then 1 else -1
		for _, lane in lanes do
			lane.Dir = dir
			dir = -dir
			lane.Movers = {}
			lane.Segments = { { T = startTime, P = 0, V = 0 } }
			local worldDir = ctx.Origin:VectorToWorldSpace(Vector3.new(lane.Dir, 0, 0))
			if lane.Kind == "R" then
				local v = p.CarSpeed * rng:NextNumber(0.88, 1.12)
				lane.Segments[1].V = v
				-- the slowest speed the rush ramp will reach decides the gap; the fastest decides how many fit
				local count = rng:NextInteger(2, 3)
				local kinds
				local need
				repeat
					kinds = {}
					for k = 1, count do
						local r = rng:NextNumber()
						kinds[k] = carKinds[if r < 0.6 then 1 elseif r < 0.84 then 2 else 3]
					end
					need = 0
					for k = 1, count do
						local nextKind = kinds[k % count + 1]
						need += (kinds[k].L + nextKind.L) / 2 + 2 * BODY + p.GapTime * v * p.Rush
					end
					if need > SPAN then
						count -= 1
					end
				until need <= SPAN or count <= 1
				local extra = math.max(SPAN - need, 0)
				local weights, sum = {}, 0
				for k = 1, count do
					weights[k] = rng:NextNumber(0.3, 1)
					sum += weights[k]
				end
				local phase = rng:NextNumber(0, SPAN)
				for k = 1, count do
					local kind = kinds[k]
					local paint = PAINTS[rng:NextInteger(1, #PAINTS)]
					local root = buildCar(ctx, lane, kind, paint)
					local mover = { Carrier = root, Phase0 = phase % SPAN, Len = kind.L, Width = kind.W, Top = kind.H }
					table.insert(lane.Movers, mover)
					local nextKind = kinds[k % count + 1]
					phase += (kind.L + nextKind.L) / 2 + 2 * BODY + p.GapTime * v * p.Rush + extra * weights[k] / sum
				end
			elseif lane.Kind == "V" then
				local v = p.RaftSpeed * rng:NextNumber(0.9, 1.1)
				lane.Segments[1].V = v
				local lengths, gaps = {}, {}
				local used = 0
				while true do
					local len = rng:NextNumber(8, 11)
					local gap = rng:NextNumber(4, p.RaftGapMax)
					if used + len + gap > SPAN then
						break
					end
					table.insert(lengths, len)
					table.insert(gaps, gap)
					used += len + gap
				end
				local spare = (SPAN - used) / math.max(#gaps, 1)
				local phase = rng:NextNumber(0, SPAN)
				for k, len in lengths do
					local root = buildRaft(ctx, lane, len)
					root.AssemblyLinearVelocity = worldDir * v -- carries whoever stands on it
					table.insert(lane.Movers, { Carrier = root, Phase0 = (phase + len / 2) % SPAN, Len = len })
					phase += len + gaps[k] + spare
				end
			else -- "T"
				lane.Train = buildTrain(ctx, lane, p)
			end
			for _, mover in lane.Movers do
				ctx:Animate(mover.Carrier, "OMF_Slide", {
					SlideDir = worldDir,
					SlideSpeed = lane.Segments[1].V,
					SlideSpan = SPAN,
					SlideBase = 1,
					SlidePhase = mover.Phase0,
				})
			end
		end

		-- Two rows on the start sidewalk, facing the traffic
		local spawns = {}
		for row = 0, 1 do
			for col = 0, 3 do
				local x = -10.5 + col * 7
				local sz = top - 3 - row * 3.5
				table.insert(spawns, CFrame.lookAt(ctx:At(x, KERB + 3, sz).Position, ctx:At(x, KERB + 3, sz - 20).Position))
			end
		end
		ctx:SetSpawns(spawns)
	end,

	Start = function(ctx)
		local p = plan(ctx)
		local rng = ctx.Rng
		local lanes = ctx.State.Lanes
		local goalEdge = ctx.State.GoalEdge
		local arrived = {}
		ctx.State.Arrived = arrived
		ctx.State.MoverX = moverX -- (lane, mover, serverTime) -> arena-local x; used by test bots too

		ctx:Announce("CROSS!", ctx.Theme.Secondary)

		-- Coins: most out on the roads, one on the tracks, one over the lava
		local roadLanes, otherLanes = {}, {}
		for _, lane in lanes do
			table.insert(if lane.Kind == "R" then roadLanes else otherLanes, lane)
		end
		for _ = 1, math.min(#roadLanes, 3) do
			local lane = roadLanes[rng:NextInteger(1, #roadLanes)]
			ctx:SpawnCoin(ctx:At(rng:NextNumber(-36, 36), 2.6, lane.Z).Position)
		end
		for _, lane in otherLanes do
			if rng:NextNumber() < 0.4 then
				ctx:SpawnCoin(ctx:At(rng:NextNumber(-30, 30), if lane.Kind == "V" then 2.8 else 2.6, lane.Z).Position)
			end
		end

		-- Trains: telegraph (lights, alarm, sweep along the lane), then a fast pass
		local function signalLoop(lane)
			local signal = ctx.State.Signals[lane]
			if not signal then
				return
			end
			signal.Users = (signal.Users or 0) + 1
			if signal.Users > 1 then
				return
			end
			signal.Light.Enabled = true
			task.spawn(function()
				local k = 0
				while not ctx.Ended and signal.Users > 0 do
					k += 1
					for _, lamp in signal.Lamps do
						local lit = (lamp.Phase + k) % 2 == 0
						lamp.Part.Material = if lit then Enum.Material.Neon else Enum.Material.SmoothPlastic
						lamp.Part.Color = if lit then soft(ctx.Theme.Hazard, 0.85) else Color3.fromRGB(70, 20, 22)
					end
					task.wait(0.32)
				end
				for _, lamp in signal.Lamps do
					lamp.Part.Material = Enum.Material.SmoothPlastic
					lamp.Part.Color = Color3.fromRGB(70, 20, 22)
				end
				signal.Light.Enabled = false
			end)
		end
		local function signalStop(lane)
			local signal = ctx.State.Signals[lane]
			if signal then
				signal.Users = math.max((signal.Users or 1) - 1, 0)
			end
		end
		for n, lane in lanes do
			if lane.Kind ~= "T" then
				continue
			end
			local passTime = (2 * WRAP + lane.Train.LastOffset) / p.TrainSpeed -- engine in to last carriage out
			task.spawn(function()
				local delay = rng:NextNumber(0.8, 2.2) + (n % 2) * 1.4
				while ctx:Wait(delay) do
					if ctx:Remaining() < p.TrainWarn + 1 then
						return
					end
					signalLoop(lane)
					ctx:Sound("Alarm", ctx.State.Signals[lane] and ctx.State.Signals[lane].Lamps[1].Part)
					ctx:Warn(ctx:At(0, 0.42, lane.Z), Vector3.new(SPAN_X * 2, 0.2, LANE_W - 0.4), p.TrainWarn, ctx.Theme.Hazard, { Sweep = Vector3.new(lane.Dir, 0, 0) })
					if not ctx:Wait(p.TrainWarn) then
						return
					end
					lane.Pass = { T0 = workspace:GetServerTimeNow() }
					ctx:Sound("Whoosh", ctx:At(-lane.Dir * (SPAN_X - 4), 3, lane.Z).Position)
					if not ctx:Wait(passTime + 0.2) then
						return
					end
					signalStop(lane)
					delay = p.TrainEvery * rng:NextNumber(0.8, 1.2) - p.TrainWarn
				end
			end)
		end

		-- Rush hour: traffic speeds up for the last stretch
		local function setSpeed(lane, v: number)
			local now = workspace:GetServerTimeNow()
			table.insert(lane.Segments, { T = now, P = travelled(lane, now), V = v })
			for _, mover in lane.Movers do
				mover.Carrier:SetAttribute("SlideSpeed", v)
			end
		end
		ctx:After(math.max(ctx.Duration - 8, 6), function()
			ctx:Announce("RUSH HOUR!", ctx.Theme.Hazard)
			ctx:Sound("Go")
			for step = 1, 4 do
				ctx:After((step - 1) * 0.5, function()
					for _, lane in lanes do
						if lane.Kind == "R" then
							setSpeed(lane, lane.Segments[1].V * (1 + (p.Rush - 1) * step / 4))
						end
					end
				end)
			end
		end)

		-- Hit tests (closed form, rewound by each player's lag), trains, the river and arrivals
		ctx:Heartbeat(function()
			local now = workspace:GetServerTimeNow()
			-- move passing trains
			for _, lane in lanes do
				local pass = lane.Pass
				if lane.Kind == "T" and pass and not pass.Done then
					local train = lane.Train
					local front = -WRAP + p.TrainSpeed * (now - pass.T0) -- engine centre
					local look = ctx.Origin:VectorToWorldSpace(Vector3.new(lane.Dir, 0, 0))
					local done = front - train.LastOffset > WRAP
					local at = if done then ctx:At(0, -20, lane.Z).Position else ctx:At(lane.Dir * front, CARRIAGE_H / 2, lane.Z).Position
					train.Root.CFrame = CFrame.lookAt(at, at + look)
					-- a carriage shows only between the housings (it switches while fully hidden inside one)
					for _, carriage in train.Carriages do
						local c = front - carriage.Offset
						setCarriageVisible(carriage, not done and c >= -WRAP and c <= WRAP)
					end
					pass.Done = done
				end
			end

			for _, player in ctx:GetAlive() do
				local pos = ctx:LocalPosition(player)
				if not pos then
					continue
				end
				local feet = ctx:FeetY(player) or pos.Y - 3
				local t = now - lagFor(player)
				if pos.Z <= goalEdge - 0.6 and feet > -2 then
					if not arrived[player] then
						arrived[player] = true
						local root = ctx:GetRoot(player)
						if root then
							ctx:Fx("Burst", { Position = root.Position, Color = ctx.Theme.Secondary, Count = 24 })
						end
						ctx.Run:FireEffectTo(player, "Sound", { Name = "ElevatorDing" })
					end
					continue
				end
				for _, lane in lanes do
					local dz = math.abs(pos.Z - lane.Z)
					if dz > LANE_W / 2 + 1.5 then
						continue
					end
					if lane.Kind == "R" then
						for _, car in lane.Movers do
							local x = moverX(lane, car, t)
							if math.abs(pos.X - x) < car.Len / 2 - SHRINK + BODY and dz < car.Width / 2 - SHRINK + BODY and feet < car.Top - 0.3 then
								ctx:Eliminate(player, "Hit by a car")
								break
							end
						end
					elseif lane.Kind == "T" then
						local pass = lane.Pass
						local train = lane.Train
						if pass and t >= pass.T0 and dz < train.Width / 2 - SHRINK + BODY and feet < train.Height - 0.3 then
							local front = -WRAP + p.TrainSpeed * (t - pass.T0)
							local u = lane.Dir * pos.X
							if u < front + train.Front - SHRINK + BODY and u > front - train.Back + SHRINK - BODY then
								ctx:Eliminate(player, "Hit by a train")
							end
						end
					elseif dz <= LANE_W / 2 and feet < FEET_LAVA then
						ctx:Eliminate(player, "Fell in the lava")
					end
				end
			end
		end)

		-- Everyone across: finish early
		ctx:Every(0.25, function()
			local alive = ctx:GetAlive()
			if #alive == 0 then
				return false
			end
			for _, player in alive do
				if not arrived[player] then
					return
				end
				local pos = ctx:LocalPosition(player)
				if not pos or pos.Z > goalEdge - 0.6 then
					return
				end
			end
			ctx:Finish()
			return false
		end)
	end,

	-- Time's up: anyone still out in the traffic is stuck there.
	Judge = function(ctx)
		local goalEdge = ctx.State.GoalEdge
		for _, player in ctx:GetAlive() do
			local pos = ctx:LocalPosition(player)
			if not pos or pos.Z > goalEdge - 0.6 or pos.Y < -4 then
				ctx:Eliminate(player, "Stuck in traffic")
			end
		end
	end,
}
