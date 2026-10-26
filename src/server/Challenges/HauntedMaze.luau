-- Haunted Maze: find the glowing exit of a walled maze while ghosts hunt you through the corridors.
-- The maze is a seeded recursive backtracker with a few extra walls knocked out (loops to shake a ghost).
-- Walls are low enough for the camera to see over them, and an electric fence plus an invisible barrier on top
-- makes jumping over them impossible. Ghosts glide cell to cell along BFS shortest paths toward the nearest
-- player in range (else they wander). Their hit box is a small box judged against where the ghost was one
-- round trip ago, so a ghost you saw miss you did miss you.

local CELL = 10
local WALL_H = 5
local WALL_T = 1
local POST = 1.3
local POST_H = 6.1
local WIRE_Y = 5.7
local BARRIER_H = 12 -- invisible, collidable: nobody gets over a wall
local PAD_D = 9 -- start / exit pads outside the maze
local GHOST_Y = 2.9
local GHOST_HIT = 1.9 -- ghost core half size + body half depth
local GHOST_TOP = 4.9 -- feet above this clear a ghost (a well-timed jump)
local GHOST_MARGIN = 1.6 -- ghosts keep this far from the walls of their cell
local CALM = Color3.fromRGB(206, 226, 255)
local BEACON = Color3.fromRGB(80, 235, 170)

-- Caps a neon colour's brightness (gold / white theme accents glare at full value).
local function soft(c: Color3, v: number): Color3
	local h, sat, val = c:ToHSV()
	return Color3.fromHSV(h, sat, math.min(val, v))
end

local DIRS = {
	{ Key = "PX", Back = "NX", DI = 1, DJ = 0 },
	{ Key = "NX", Back = "PX", DI = -1, DJ = 0 },
	{ Key = "PZ", Back = "NZ", DI = 0, DJ = 1 },
	{ Key = "NZ", Back = "PZ", DI = 0, DJ = -1 },
}

local function plan(ctx)
	local d = math.clamp(ctx.Difficulty, 0, 1.5)
	local z2 = math.clamp((d - 0.36) / 0.64, 0, 1) -- 0 at the top of zone 2, 1 at B26
	local over = math.max(d - 1, 0)
	return {
		N = if d < 0.55 then 7 elseif d < 0.85 then 8 else 9,
		Ghosts = if d < 0.5 then 1 elseif d < 0.7 then 2 elseif d < 0.9 then 3 else 4,
		Speed = 7 + 4 * z2 + 1.5 * over,
		Hunt = 3 + math.floor(2 * z2 + 0.5), -- hunting range in cells (path distance)
		Knock = 0.15, -- share of the remaining inner walls knocked out
		Wake = 2, -- seconds before the ghosts start moving
		Coins = 3 + math.floor(math.min(d, 1) * 2),
		D = d,
	}
end

local function bfs(maze, si: number, sj: number)
	local N = maze.N
	local dist = {}
	for i = 1, N do
		dist[i] = {}
	end
	dist[si][sj] = 0
	local queue = { si, sj }
	local head = 1
	while head < #queue do
		local i, j = queue[head], queue[head + 1]
		head += 2
		local cell = maze.Open[i][j]
		for _, dir in DIRS do
			if cell[dir.Key] then
				local ni, nj = i + dir.DI, j + dir.DJ
				if ni >= 1 and ni <= N and nj >= 1 and nj <= N and dist[ni][nj] == nil then
					dist[ni][nj] = dist[i][j] + 1
					table.insert(queue, ni)
					table.insert(queue, nj)
				end
			end
		end
	end
	return dist
end

-- Seeded maze. Cells (i, j): i along +X, j along +Z (row N is on the cab side, row 1 at the far end).
local function generate(ctx, p)
	local rng = ctx.Rng
	local N = p.N
	local open, seen = {}, {}
	for i = 1, N do
		open[i], seen[i] = {}, {}
		for j = 1, N do
			open[i][j] = { PX = false, NX = false, PZ = false, NZ = false }
		end
	end
	-- recursive backtracker (iterative)
	local si, sj = rng:NextInteger(1, N), rng:NextInteger(1, N)
	local stack = { { si, sj } }
	seen[si][sj] = true
	while #stack > 0 do
		local top = stack[#stack]
		local options = {}
		for _, dir in DIRS do
			local ni, nj = top[1] + dir.DI, top[2] + dir.DJ
			if ni >= 1 and ni <= N and nj >= 1 and nj <= N and not seen[ni][nj] then
				table.insert(options, dir)
			end
		end
		if #options == 0 then
			table.remove(stack)
		else
			local dir = options[rng:NextInteger(1, #options)]
			local ni, nj = top[1] + dir.DI, top[2] + dir.DJ
			open[top[1]][top[2]][dir.Key] = true
			open[ni][nj][dir.Back] = true
			seen[ni][nj] = true
			table.insert(stack, { ni, nj })
		end
	end
	-- knock out a share of the remaining inner walls so there are loops
	local walls = {}
	for i = 1, N do
		for j = 1, N do
			if i < N and not open[i][j].PX then
				table.insert(walls, { i, j, DIRS[1] })
			end
			if j < N and not open[i][j].PZ then
				table.insert(walls, { i, j, DIRS[3] })
			end
		end
	end
	for _ = 1, math.floor(#walls * p.Knock + 0.5) do
		local w = table.remove(walls, rng:NextInteger(1, #walls))
		open[w[1]][w[2]][w[3].Key] = true
		open[w[1] + w[3].DI][w[2] + w[3].DJ][w[3].Back] = true
	end

	local maze = { N = N, Open = open, Half = N * CELL / 2 }
	-- entrance on the cab side; exit on the far side, a path of roughly 2.4 N cells away and not straight ahead
	local entrance = rng:NextInteger(math.max(1, math.floor(N / 2) - 1), math.min(N, math.ceil(N / 2) + 1))
	local dist = bfs(maze, entrance, N)
	local target = N * 2.4
	local best, bestScore = 1, math.huge
	for i = 1, N do
		local score = math.abs(dist[i][1] - target) + rng:NextNumber() * 2
		if math.abs(i - entrance) < math.floor(N / 3) then
			score += 4
		end
		if score < bestScore then
			best, bestScore = i, score
		end
	end
	maze.Entrance, maze.Exit = entrance, best
	maze.FromEntrance = dist
	maze.FromExit = bfs(maze, best, 1)
	-- the solution: walk downhill on the exit distance field
	local path = { { entrance, N } }
	local ci, cj = entrance, N
	while maze.FromExit[ci][cj] > 0 do
		for _, dir in DIRS do
			local ni, nj = ci + dir.DI, cj + dir.DJ
			if open[ci][cj][dir.Key] and ni >= 1 and ni <= N and nj >= 1 and nj <= N and maze.FromExit[ni][nj] == maze.FromExit[ci][cj] - 1 then
				ci, cj = ni, nj
				break
			end
		end
		table.insert(path, { ci, cj })
	end
	maze.Path = path
	return maze
end

local function getMaze(ctx)
	if not ctx.State.Maze then
		ctx.State.Maze = generate(ctx, plan(ctx))
	end
	return ctx.State.Maze
end

local function centreOf(maze, i: number, j: number): (number, number)
	return -maze.Half + (i - 0.5) * CELL, -maze.Half + (j - 0.5) * CELL
end

local function cellOf(maze, x: number, z: number): (number?, number?)
	local i = math.floor((x + maze.Half) / CELL) + 1
	local j = math.floor((z + maze.Half) / CELL) + 1
	if i < 1 or i > maze.N or j < 1 or j > maze.N then
		return nil, nil
	end
	return i, j
end

-- Round trip + a frame (see RushHour): the ghost a player saw is that old by the time we judge them.
local function lagFor(player: Player): number
	local ok, ping = pcall(player.GetNetworkPing, player)
	return math.clamp((if ok and typeof(ping) == "number" then ping else 0.08) + 0.03, 0.03, 0.35)
end

local function buildGhost(ctx, x: number, z: number, k: number)
	local root = ctx:Part({ Name = "Ghost", Size = Vector3.new(1, 1, 1), CFrame = ctx:At(x, GHOST_Y, z), Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false })
	local ghost = { Root = root, X = x, Z = z, Yaw = 0, Phase = k * 1.7, Mode = "Wander", History = {}, Body = {}, Eyes = {} }
	local function piece(props, offset: CFrame)
		props.CFrame = root.CFrame * offset
		props.CastShadow = false
		local part = ctx:Decor(props)
		part.Anchored = false
		part.Massless = true
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = part
		weld.Parent = part
		return part
	end
	local prop = ctx:Prop("Ghost")
	if prop and (prop:IsA("Model") or prop:IsA("BasePart")) then
		local model = prop
		if prop:IsA("BasePart") then
			model = Instance.new("Model")
			model.Parent = ctx.Folder
			prop.Parent = model
			model.PrimaryPart = prop
		end
		local ok = pcall(function()
			local ext = (model :: Model):GetExtentsSize()
			;(model :: Model):ScaleTo((model :: Model):GetScale() * 4.4 / math.max(ext.Y, 0.05))
			;(model :: Model):PivotTo(root.CFrame * CFrame.new(0, -GHOST_Y + 0.6, 0))
		end)
		if ok then
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") then
					d.CanCollide = false
					d.CanQuery = false
					d.CanTouch = false
					d.Anchored = false
					d.Massless = true
					local weld = Instance.new("WeldConstraint")
					weld.Part0 = root
					weld.Part1 = d
					weld.Parent = d
					if d.Name == "Eyes" or d.Name == "Eye" then
						table.insert(ghost.Eyes, d)
					elseif d.Name == "Body" then
						d.Color = CALM
						table.insert(ghost.Body, d)
					end
				end
			end
			ghost.Head = root
			ctx:Emitter(root, { Texture = "Glow", Rate = 5, Lifetime = NumberRange.new(0.6, 1), Speed = NumberRange.new(0.2, 0.6), Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.6), NumberSequenceKeypoint.new(1, 0) }), Transparency = NumberSequence.new(0.75, 1), Color = ColorSequence.new(CALM), LightEmission = 0.6 })
		else
			model:Destroy()
		end
	end
	if not ghost.Head then
		local head = piece({ Name = "GhostHead", Shape = Enum.PartType.Ball, Size = Vector3.new(3.2, 3.2, 3.2), Color = CALM, Transparency = 0.18 }, CFrame.new(0, 0.7, 0))
		table.insert(ghost.Body, head)
		table.insert(ghost.Body, piece({ Name = "GhostBody", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.3, 3.1, 3.1), Color = CALM, Transparency = 0.18 }, CFrame.new(0, -0.55, 0) * CFrame.Angles(0, 0, math.rad(90))))
		for n = 0, 5 do
			local a = n / 6 * math.pi * 2 + 0.3
			table.insert(ghost.Body, piece({ Name = "GhostHem", Shape = Enum.PartType.Ball, Size = Vector3.new(1.05, 1.05, 1.05), Color = CALM, Transparency = 0.25 }, CFrame.new(math.sin(a) * 1.15, -1.75, math.cos(a) * 1.15)))
		end
		for _, ex in { -0.6, 0.6 } do
			table.insert(ghost.Eyes, piece({ Name = "Eye", Shape = Enum.PartType.Ball, Size = Vector3.new(0.62, 0.8, 0.5), Color = Color3.fromRGB(18, 16, 30) }, CFrame.new(ex, 0.95, -1.38)))
		end
		piece({ Name = "Mouth", Shape = Enum.PartType.Ball, Size = Vector3.new(0.6, 0.45, 0.4), Color = Color3.fromRGB(18, 16, 30) }, CFrame.new(0, 0.05, -1.45))
		ctx:Emitter(head, { Texture = "Glow", Rate = 5, Lifetime = NumberRange.new(0.6, 1), Speed = NumberRange.new(0.2, 0.6), Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.6), NumberSequenceKeypoint.new(1, 0) }), Transparency = NumberSequence.new(0.75, 1), Color = ColorSequence.new(CALM), LightEmission = 0.6 })
		ghost.Head = head
	end
	ghost.Light = ctx:Glow(ghost.Head, CALM, 14, 1.1)
	local label = ctx:Billboard(ghost.Head, "!", Vector2.new(2.4, 2.4), 3.4, { TextColor3 = ctx.Theme.Hazard })
	ghost.Alert = label.Parent :: BillboardGui
	ghost.Alert.Enabled = false
	return ghost
end

local function setHunting(ctx, ghost, hunting: boolean)
	local hazard = ctx.Theme.Hazard
	local body = if hunting then CALM:Lerp(hazard, 0.5) else CALM
	for _, part in ghost.Body do
		part.Color = body
	end
	for _, eye in ghost.Eyes do
		eye.Material = if hunting then Enum.Material.Neon else Enum.Material.SmoothPlastic
		eye.Color = if hunting then hazard else Color3.fromRGB(18, 16, 30)
	end
	ghost.Light.Color = if hunting then hazard else CALM
end

return {
	Id = "HauntedMaze",
	Name = "Haunted Maze",
	Hint = "Find the glowing exit before time runs out. Don't let the ghosts touch you!",
	MinFloor = 1,
	MinPlayers = 1,
	Weight = 1,
	BossOnly = false,
	Zone = 2, -- B10-B19
	-- A player who knows the way walks the solution at full speed in ~2/3 of the time; explorers get the rest.
	Duration = function(ctx)
		local maze = getMaze(ctx)
		local length = #maze.Path * CELL + PAD_D
		return math.clamp(math.max(26, length / 12 + 9), 26, 40)
	end,

	Build = function(ctx)
		local p = plan(ctx)
		local maze = getMaze(ctx)
		local N, half = maze.N, maze.Half
		local black = Color3.new(0, 0, 0)
		-- readable at a glance: a mid floor, lighter walls that stand out from it, slightly darker posts
		-- (the spooky mood comes from the mist, the ghosts' glow and the fence, not from black walls)
		local floorColor = ctx.Theme.Floor:Lerp(Color3.new(1, 1, 1), 0.12)
		local wallColor = ctx.Theme.Floor:Lerp(ctx.Theme.Primary, 0.3):Lerp(Color3.new(1, 1, 1), 0.32)
		local postColor = ctx.Theme.Floor:Lerp(ctx.Theme.Primary, 0.2):Lerp(Color3.new(1, 1, 1), 0.12)
		-- every wall top carries a trim and a wire: dozens of neon lines add up to glare at higher values
		local trim = soft(ctx.Theme.Primary, 0.5)
		local hazard = soft(ctx.Theme.Hazard, 0.55)

		-- Floor with faint cell lines, a start pad on the cab side and the exit pad beyond the far wall
		local floor = ctx:Part({ Name = "MazeFloor", Size = Vector3.new(N * CELL, 2, N * CELL), CFrame = ctx:At(0, -1, 0), Color = floorColor, Material = Enum.Material.Slate })
		for k = 1, N - 1 do
			local c = -half + k * CELL
			ctx:Decor({ Name = "CellLine", Size = Vector3.new(N * CELL, 0.02, 0.16), CFrame = ctx:At(0, 0.01, c), Color = floorColor:Lerp(trim, 0.12) })
			ctx:Decor({ Name = "CellLine", Size = Vector3.new(0.16, 0.02, N * CELL), CFrame = ctx:At(c, 0.05, 0), Color = floorColor:Lerp(trim, 0.12) })
		end
		ctx:Emitter(floor, { Texture = "Smoke", Rate = 4, Lifetime = NumberRange.new(5, 7), Speed = NumberRange.new(0.3, 0.8), SpreadAngle = Vector2.new(60, 60), Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 9) }), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 0.9), NumberSequenceKeypoint.new(1, 1) }), Color = ColorSequence.new(CALM:Lerp(trim, 0.3)), LightEmission = 0.2, Acceleration = Vector3.new(0, 0.2, 0) })

		local ex, _ = centreOf(maze, maze.Entrance, N)
		local padW = 3 * CELL
		local padX = math.clamp(ex, -half + padW / 2, half - padW / 2)
		local padZ = half + PAD_D / 2
		ctx:Part({ Name = "StartPad", Size = Vector3.new(padW, 2, PAD_D), CFrame = ctx:At(padX, -1, padZ), Color = floorColor:Lerp(trim, 0.1), Material = Enum.Material.SmoothPlastic })
		ctx:Decor({ Name = "StartLine", Size = Vector3.new(CELL - 1.4, 0.06, 0.25), CFrame = ctx:At(ex, 0.02, half + 0.5), Color = trim, Material = Enum.Material.Neon })
		-- railings around the start pad
		for _, s in { { padX, half + PAD_D - 0.3, padW - 1.2, 0.6 }, { padX - padW / 2 + 0.3, padZ, 0.6, PAD_D }, { padX + padW / 2 - 0.3, padZ, 0.6, PAD_D } } do
			ctx:Part({ Name = "Railing", Size = Vector3.new(s[3], 3, s[4]), CFrame = ctx:At(s[1], 1.5, s[2]), Color = wallColor })
			ctx:Decor({ Name = "RailingTrim", Size = if s[3] > s[4] then Vector3.new(s[3] - 0.1, 0.1, 0.2) else Vector3.new(0.2, 0.1, s[4] - 0.1), CFrame = ctx:At(s[1], 3.02, s[2]), Color = trim, Material = Enum.Material.Neon })
		end

		local xx, _ = centreOf(maze, maze.Exit, 1)
		local exitZ = -half - PAD_D / 2
		ctx:Part({ Name = "ExitPad", Size = Vector3.new(CELL, 2, PAD_D), CFrame = ctx:At(xx, -1, exitZ), Color = floorColor:Lerp(BEACON, 0.28), Material = Enum.Material.SmoothPlastic })
		for _, s in { { xx, -half - PAD_D + 0.5, CELL - 2 * WALL_T, WALL_T }, { xx - CELL / 2 + 0.5, exitZ, WALL_T, PAD_D }, { xx + CELL / 2 - 0.5, exitZ, WALL_T, PAD_D } } do
			ctx:Part({ Name = "ExitWall", Size = Vector3.new(s[3], WALL_H, s[4]), CFrame = ctx:At(s[1], WALL_H / 2, s[2]), Color = wallColor })
			ctx:Decor({ Name = "ExitTrim", Size = if s[3] > s[4] then Vector3.new(s[3] - 0.2, 0.1, 0.2) else Vector3.new(0.2, 0.1, s[4] - 0.2), CFrame = ctx:At(s[1], WALL_H + 0.01, s[2]), Color = soft(BEACON, 0.72), Material = Enum.Material.Neon })
			ctx:Part({ Name = "Barrier", Size = Vector3.new(s[3], BARRIER_H, s[4]), CFrame = ctx:At(s[1], WALL_H + BARRIER_H / 2, s[2]), Transparency = 1, CanQuery = false, CanTouch = false })
		end
		-- glowing exit ring and a beacon column of light that reads from anywhere in the maze
		ctx:Decor({ Name = "ExitRing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.06, 6.4, 6.4), CFrame = ctx:At(xx, 0.03, exitZ, 0, 0, 90), Color = BEACON, Material = Enum.Material.Neon, Transparency = 0.35 })
		ctx:Decor({ Name = "ExitDisc", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.06, 5.6, 5.6), CFrame = ctx:At(xx, 0.08, exitZ, 0, 0, 90), Color = floorColor:Lerp(BEACON, 0.45) })
		local column = ctx:Decor({ Name = "BeaconColumn", Shape = Enum.PartType.Cylinder, Size = Vector3.new(44, 3, 3), CFrame = ctx:At(xx, 22, exitZ, 0, 0, 90), Color = BEACON, Material = Enum.Material.ForceField, Transparency = 0.2 })
		ctx:Animate(column, "OMF_Pulse", { PulseMin = 0.1, PulseMax = 0.5, PulseSpeed = 0.6 })
		ctx:Decor({ Name = "BeaconCore", Shape = Enum.PartType.Cylinder, Size = Vector3.new(44, 0.45, 0.45), CFrame = ctx:At(xx, 22, exitZ, 0, 0, 90), Color = BEACON, Material = Enum.Material.Neon })
		ctx:Glow(column, BEACON, 26, 1.6)
		-- EXIT sign over the opening, facing into the maze
		local lintel = ctx:Part({ Name = "ExitLintel", Size = Vector3.new(CELL, 1.6, 0.6), CFrame = ctx:At(xx, 8.4, -half), Color = postColor })
		ctx:Sign(lintel, "EXIT", { Face = Enum.NormalId.Back, TextColor3 = BEACON })
		for _, sx in { -CELL / 2, CELL / 2 } do
			ctx:Part({ Name = "ExitPost", Size = Vector3.new(POST, 9.4 - POST_H, POST), CFrame = ctx:At(xx + sx, POST_H + (9.4 - POST_H) / 2, -half), Color = postColor })
		end
		ctx:Decor({ Name = "ExitLintelTrim", Size = Vector3.new(CELL - 0.2, 0.18, 0.3), CFrame = ctx:At(xx, 7.5, -half + 0.2), Color = soft(BEACON, 0.75), Material = Enum.Material.Neon })

		-- Walls: horizontal (along X) at row lines, vertical (along Z) at column lines; consecutive pieces merge
		local function hasH(i: number, j: number): boolean -- wall south of cell (i, j) for j = 1..N+1 (j is the line index)
			if j == 1 then
				return i ~= maze.Exit
			elseif j == N + 1 then
				return i ~= maze.Entrance
			end
			return not maze.Open[i][j - 1].PZ
		end
		local function hasV(i: number, j: number): boolean -- wall at column line i (1..N+1) beside row j
			if i == 1 or i == N + 1 then
				return true
			end
			return not maze.Open[i - 1][j].PX
		end
		local runs = {}
		for j = 1, N + 1 do
			local i = 1
			while i <= N do
				if hasH(i, j) then
					local i0 = i
					while i <= N and hasH(i, j) do
						i += 1
					end
					table.insert(runs, { Axis = "X", A = -half + (i0 - 1) * CELL, B = -half + (i - 1) * CELL, At = -half + (j - 1) * CELL })
				else
					i += 1
				end
			end
		end
		for i = 1, N + 1 do
			local j = 1
			while j <= N do
				if hasV(i, j) then
					local j0 = j
					while j <= N and hasV(i, j) do
						j += 1
					end
					table.insert(runs, { Axis = "Z", A = -half + (j0 - 1) * CELL, B = -half + (j - 1) * CELL, At = -half + (i - 1) * CELL })
				else
					j += 1
				end
			end
		end
		local posts = {}
		local function post(x: number, z: number)
			local key = string.format("%d,%d", math.floor(x + 0.5), math.floor(z + 0.5))
			if not posts[key] then
				posts[key] = true
				ctx:Part({ Name = "FencePost", Size = Vector3.new(POST, POST_H, POST), CFrame = ctx:At(x, POST_H / 2, z), Color = postColor, Material = Enum.Material.Metal })
			end
		end
		local wires = {}
		for _, run in runs do
			local length = run.B - run.A
			local mid = (run.A + run.B) / 2
			local function at(y: number): CFrame
				return if run.Axis == "X" then ctx:At(mid, y, run.At) else ctx:At(run.At, y, mid)
			end
			local function size(along: number, y: number, across: number): Vector3
				return if run.Axis == "X" then Vector3.new(along, y, across) else Vector3.new(across, y, along)
			end
			local h = if run.Axis == "X" then WALL_H else WALL_H - 0.06
			ctx:Part({ Name = "MazeWall", Size = size(length, h, WALL_T), CFrame = at(h / 2), Color = wallColor, Material = Enum.Material.Concrete })
			ctx:Decor({ Name = "WallTrim", Size = size(length, 0.1, 0.2), CFrame = at(h + 0.01), Color = trim, Material = Enum.Material.Neon })
			local wire = ctx:Decor({ Name = "ElectricWire", Size = size(length, 0.12, 0.12), CFrame = at(WIRE_Y), Color = hazard, Material = Enum.Material.Neon })
			ctx:Animate(wire, "OMF_Pulse", { PulseMin = 0, PulseMax = 0.55, PulseSpeed = 2.2, PulsePhase = ctx.Rng:NextNumber() })
			table.insert(wires, { Run = run, Wire = wire })
			ctx:Part({ Name = "Barrier", Size = size(length, BARRIER_H, WALL_T + 0.3), CFrame = at(WALL_H + BARRIER_H / 2), Transparency = 1, CanQuery = false, CanTouch = false })
			for k = 0, math.floor(length / CELL + 0.5) do
				local along = run.A + k * CELL
				if run.Axis == "X" then
					post(along, run.At)
				else
					post(run.At, along)
				end
			end
		end
		ctx.State.Wires = wires
		ctx.State.PartCount = #ctx.Folder:GetDescendants()

		-- Ghosts wait on the far third of the maze, spread out, away from the exit
		local candidates = {}
		for i = 1, N do
			for j = 1, math.ceil(N / 2) do
				if maze.FromExit[i][j] >= 2 and maze.FromEntrance[i][j] >= N then
					table.insert(candidates, { i, j })
				end
			end
		end
		local chosen = {}
		for _ = 1, p.Ghosts do
			local best, bestScore = nil, -math.huge
			for _, c in candidates do
				local score = ctx.Rng:NextNumber() * 2
				for _, other in chosen do
					local apart = math.abs(c[1] - other[1]) + math.abs(c[2] - other[2])
					score += math.min(apart, 5) * 2
				end
				if score > bestScore and not table.find(chosen, c) then
					best, bestScore = c, score
				end
			end
			if not best then
				best = { ctx.Rng:NextInteger(1, N), 1 }
			end
			table.insert(chosen, best)
		end
		local ghosts = {}
		for k, c in chosen do
			local gx, gz = centreOf(maze, c[1], c[2])
			table.insert(ghosts, buildGhost(ctx, gx, gz, k))
		end
		ctx.State.Ghosts = ghosts

		-- Line up on the start pad facing the entrance
		local spawns = {}
		for row = 0, 1 do
			for col = 0, 3 do
				local x = padX - 9 + col * 6
				local sz = half + 3 + row * 3.5
				table.insert(spawns, CFrame.lookAt(ctx:At(x, 3, sz).Position, ctx:At(ex, 3, half - CELL).Position))
			end
		end
		ctx:SetSpawns(spawns)
	end,

	Start = function(ctx)
		local p = plan(ctx)
		local maze = getMaze(ctx)
		local N, half = maze.N, maze.Half
		local ghosts = ctx.State.Ghosts
		local exitX = centreOf(maze, maze.Exit, 1)
		local arrived = {}
		ctx.State.Arrived = arrived

		-- Coins in the dead ends, the ones farthest off the solution first (risk / reward)
		local onPath = {}
		for _, c in maze.Path do
			onPath[c[1] * 100 + c[2]] = true
		end
		local ends = {}
		for i = 1, N do
			for j = 1, N do
				local cell = maze.Open[i][j]
				local exits = (if cell.PX then 1 else 0) + (if cell.NX then 1 else 0) + (if cell.PZ then 1 else 0) + (if cell.NZ then 1 else 0)
				if exits == 1 and not onPath[i * 100 + j] then
					table.insert(ends, { i, j, maze.FromEntrance[i][j] + ctx.Rng:NextNumber() * 3 })
				end
			end
		end
		table.sort(ends, function(a, b)
			return a[3] > b[3]
		end)
		for k = 1, math.min(p.Coins, #ends) do
			local cx, cz = centreOf(maze, ends[k][1], ends[k][2])
			ctx:SpawnCoin(ctx:At(cx, 2.6, cz).Position)
		end

		-- Sparks crackle along the electric fence now and then
		local wires = ctx.State.Wires
		ctx:Every(0.7, function()
			local w = wires[ctx.Rng:NextInteger(1, #wires)]
			local along = ctx.Rng:NextNumber(w.Run.A, w.Run.B)
			local pos = if w.Run.Axis == "X" then ctx:At(along, WIRE_Y, w.Run.At) else ctx:At(w.Run.At, WIRE_Y, along)
			ctx:Fx("Burst", { Position = pos.Position, Color = ctx.Theme.Hazard:Lerp(Color3.new(1, 1, 1), 0.3), Count = 6 })
		end)

		-- Distance fields toward each player inside the maze (refreshed a few times a second)
		local fields = {}
		local cells = {}
		local function refresh()
			table.clear(fields)
			table.clear(cells)
			for _, player in ctx:GetAlive() do
				local pos = ctx:LocalPosition(player)
				if pos and pos.Y > -4 then
					local i, j = cellOf(maze, pos.X, pos.Z)
					if i and j then
						cells[player] = { I = i, J = j, X = pos.X, Z = pos.Z }
						fields[player] = bfs(maze, i, j)
					end
				end
			end
		end

		local awake = false
		ctx:After(p.Wake, function()
			awake = true
			for _, ghost in ghosts do
				ctx:Fx("Burst", { Position = ghost.Root.Position, Color = CALM, Count = 20 })
			end
			ctx:Sound("Whoosh")
		end)

		local lastRefresh = 0
		ctx:Heartbeat(function(dt)
			local now = workspace:GetServerTimeNow()
			if os.clock() - lastRefresh > 0.12 then
				lastRefresh = os.clock()
				refresh()
			end
			for _, ghost in ghosts do
				if awake then
					local gi, gj = cellOf(maze, ghost.X, ghost.Z)
					gi, gj = gi or 1, gj or 1
					-- choose a target: the nearest player by path distance inside the hunting range
					local target, targetDist = nil, math.huge
					for player, field in fields do
						local dist = field[gi][gj]
						local range = if ghost.Target == player then p.Hunt + 2 else p.Hunt
						if dist and dist <= range and dist < targetDist then
							target, targetDist = player, dist
						end
					end
					if target ~= ghost.Target then
						if target and not ghost.Target then
							setHunting(ctx, ghost, true)
						elseif not target then
							setHunting(ctx, ghost, false)
						end
						if target and (os.clock() - (ghost.AlertAt or -10) > 2.5) then
							ghost.AlertAt = os.clock()
							ghost.Alert.Enabled = true
							ctx:Sound("Whoosh", ghost.Head)
							task.delay(1.2, function()
								ghost.Alert.Enabled = false
							end)
						end
						ghost.Target = target
						ghost.Next = nil
					end

					local tx, tz
					if target then
						local pc = cells[target]
						if pc.I == gi and pc.J == gj then
							local cx, cz = centreOf(maze, gi, gj)
							local lim = CELL / 2 - GHOST_MARGIN
							tx, tz = math.clamp(pc.X, cx - lim, cx + lim), math.clamp(pc.Z, cz - lim, cz + lim)
						else
							local field = fields[target]
							local here = field[gi][gj]
							local cell = maze.Open[gi][gj]
							for _, dir in DIRS do
								local ni, nj = gi + dir.DI, gj + dir.DJ
								if cell[dir.Key] and ni >= 1 and ni <= N and nj >= 1 and nj <= N and field[ni][nj] == here - 1 then
									tx, tz = centreOf(maze, ni, nj)
									break
								end
							end
						end
					end
					if not tx then
						-- wander: corridor to corridor, no U-turns unless it's a dead end
						if ghost.Next then
							local nx, nz = centreOf(maze, ghost.Next[1], ghost.Next[2])
							if math.abs(nx - ghost.X) < 0.05 and math.abs(nz - ghost.Z) < 0.05 then
								ghost.Prev = ghost.Here
								ghost.Here = ghost.Next
								ghost.Next = nil
							end
						end
						if not ghost.Next then
							local here = { gi, gj }
							local options, back = {}, nil
							for _, dir in DIRS do
								local ni, nj = gi + dir.DI, gj + dir.DJ
								if maze.Open[gi][gj][dir.Key] and ni >= 1 and ni <= N and nj >= 1 and nj <= N then
									if ghost.Prev and ghost.Prev[1] == ni and ghost.Prev[2] == nj then
										back = { ni, nj }
									else
										table.insert(options, { ni, nj })
									end
								end
							end
							ghost.Here = here
							ghost.Next = if #options > 0 then options[ctx.Rng:NextInteger(1, #options)] else back
						end
						if ghost.Next then
							tx, tz = centreOf(maze, ghost.Next[1], ghost.Next[2])
						end
					end
					if tx then
						local speed = if target then p.Speed else p.Speed * 0.75
						local dx, dz = tx - ghost.X, tz - ghost.Z
						local dist = math.sqrt(dx * dx + dz * dz)
						local step = math.min(dist, speed * dt)
						if dist > 1e-4 then
							ghost.X += dx / dist * step
							ghost.Z += dz / dist * step
							local yaw = math.atan2(-dx, -dz)
							local diff = (yaw - ghost.Yaw + math.pi) % (2 * math.pi) - math.pi
							ghost.Yaw += diff * math.min(1, dt * 10)
						end
					end
				end
				local bob = math.sin(os.clock() * 2.6 + ghost.Phase) * 0.3
				ghost.Root.CFrame = ctx:At(ghost.X, GHOST_Y + bob, ghost.Z) * CFrame.Angles(0, ghost.Yaw, 0)
				-- position history for lag-fair hit tests
				local history = ghost.History
				table.insert(history, { T = now, X = ghost.X, Z = ghost.Z })
				while #history > 2 and history[2].T < now - 0.5 do
					table.remove(history, 1)
				end
			end

			if not awake then
				return
			end
			for _, player in ctx:GetAlive() do
				local pos = ctx:LocalPosition(player)
				if not pos then
					continue
				end
				if pos.Z < -half - 0.5 and math.abs(pos.X - exitX) < CELL / 2 + 0.5 then
					if not arrived[player] then
						arrived[player] = true
						local root = ctx:GetRoot(player)
						if root then
							ctx:Fx("Burst", { Position = root.Position, Color = BEACON, Count = 24 })
						end
						ctx.Run:FireEffectTo(player, "Sound", { Name = "ElevatorDing" })
					end
					continue
				end
				local feet = ctx:FeetY(player) or pos.Y - 3
				if feet > GHOST_TOP then
					continue
				end
				local t = now - lagFor(player)
				for _, ghost in ghosts do
					local history = ghost.History
					local gx, gz = history[1].X, history[1].Z
					for k = #history, 1, -1 do
						local h = history[k]
						if h.T <= t then
							local nxt = history[k + 1]
							if nxt and nxt.T > h.T then
								local a = (t - h.T) / (nxt.T - h.T)
								gx, gz = h.X + (nxt.X - h.X) * a, h.Z + (nxt.Z - h.Z) * a
							else
								gx, gz = h.X, h.Z
							end
							break
						end
					end
					if math.abs(pos.X - gx) < GHOST_HIT and math.abs(pos.Z - gz) < GHOST_HIT then
						ctx:Eliminate(player, "Caught by a ghost")
						break
					end
				end
			end
		end)

		-- Everyone out: finish early
		ctx:Every(0.25, function()
			local alive = ctx:GetAlive()
			if #alive == 0 then
				return false
			end
			for _, player in alive do
				local pos = ctx:LocalPosition(player)
				if not pos or pos.Z > -half - 0.5 then
					return
				end
			end
			ctx:Finish()
			return false
		end)
	end,

	-- Time's up: anyone who hasn't escaped is lost in the maze.
	Judge = function(ctx)
		local maze = getMaze(ctx)
		local exitX = centreOf(maze, maze.Exit, 1)
		for _, player in ctx:GetAlive() do
			local pos = ctx:LocalPosition(player)
			if not pos or pos.Z > -maze.Half - 0.5 or math.abs(pos.X - exitX) > CELL / 2 + 0.5 or pos.Y < -4 then
				ctx:Eliminate(player, "Lost in the maze")
			end
		end
	end,
}
