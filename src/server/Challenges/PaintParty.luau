-- Paint Party: walk to paint the tiles under you in your colour; own enough of them when time runs out.
-- Giant paint rollers drop onto a telegraphed row or column and roll down it, wiping it back to blank and
-- flattening anyone still in the lane. Paint bombs splash a 3x3 patch blank and shove people around.
--
-- Rollers move client-smooth: every roller part is tagged OMF_Orbit around a centre RBIG studs to the side of its
-- lane, so the tiny arc it follows is a straight roll to within ~0.2 studs (a uniform drum needs no visible spin).
-- The server keeps the same closed form for hits: a swept test along the lane with a one-round-trip grace, so a
-- player seen out of the lane within their ping of contact survives (near misses live).

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local N = 14 -- tiles per side
local TILE = 5
local HALF = N * TILE / 2 -- 35
local TILE_SIZE = TILE - 0.12
local KERB_H = 2
local R = 2.3 -- roller drum radius
local DRUM_W = 4.6
local LANE_HALF = DRUM_W / 2 + 0.15 -- body centre inside the lane (a hair inside its painted edge) = in the lane
local REACH = R + 0.4 -- along the lane: body centre this close to the axle = touching the drum
local TOP_CLEAR = 2 * R - 0.5 -- feet above this clear the drum (a very good jump)
local DROP = 0.35 -- the roller falls onto its lane during the last DROP seconds of the telegraph
local FADE = 0.35
local RBIG = 3000
local BOMB_FALL = 0.6
local DURATION = 23

-- Paint colours: mid / pastel tones on SmoothPlastic. No reds: red means roller.
local PAINTS = {
	Color3.fromRGB(55, 135, 245), -- blue
	Color3.fromRGB(45, 205, 120), -- mint
	Color3.fromRGB(240, 200, 40), -- lemon
	Color3.fromRGB(150, 95, 240), -- lilac
	Color3.fromRGB(250, 130, 30), -- orange
	Color3.fromRGB(240, 95, 190), -- pink
	Color3.fromRGB(25, 185, 200), -- teal
	Color3.fromRGB(150, 215, 45), -- lime
}
local BOMB_COLOR = Color3.fromRGB(232, 232, 238) -- "blank" paint
local DONE_COLOR = Color3.fromRGB(140, 255, 150)
local TEXT = Color3.fromRGB(245, 240, 230)

local function tone(c: Color3, cap: number?): Color3
	local h, s, v = c:ToHSV()
	return Color3.fromHSV(h, s, math.min(v, cap or 0.85))
end

-- Theme colour for a thin neon trim: value <= 0.85 and luminance <= 0.5, so yellow / white themes don't bloom out.
local function glow(c: Color3): Color3
	local t = tone(c)
	local lum = 0.2126 * t.R + 0.7152 * t.G + 0.0722 * t.B
	if lum > 0.5 then
		local h, s, v = t:ToHSV()
		t = Color3.fromHSV(h, s, v * 0.5 / lum)
	end
	return t
end

local function plan(ctx)
	local d = math.clamp(ctx.Difficulty, 0, 1.5)
	local m = math.min(d / 1.25, 1)
	local over = math.max(d - 1.25, 0)
	return {
		-- deep floors erase much more (two-roller waves, aimed lanes), so the danger is the rollers, not the
		-- quota: 20 at the top of zone 3 (d 0.76), 25 at d 1.25. A lane-following bot paints ~49 at d 0.8 and
		-- 22-44 at d 1.2-1.25 (passes ~60%), depending on how often rollers take its lane.
		SoloQuota = math.floor(12 + 10 * d + 0.5),
		Share = 0.5, -- multiplayer: everyone together must own about this much of the board
		RollerGap = math.max(4.6 - 1.6 * m - 0.8 * over, 2.6),
		RollerSpeed = 17 + 11 * m + 4 * over,
		WaveSize = 1 + (if d >= 0.9 then 1 else 0) + (if d >= 1.3 then 1 else 0),
		Aim = 0.45 + 0.15 * m, -- chance the first roller of a wave takes somebody's lane (and wipes their fresh paint)
		Telegraph = 1.4 - 0.2 * m,
		FirstRoller = 2.6, -- first roller lands this long after the start
		BombGap = math.max(6 - 1.6 * m - 0.6 * over, 3.6),
		BombTelegraph = 1.4,
		FirstBomb = 5,
		D = d,
	}
end

local function tileCentre(i: number, j: number): (number, number)
	return -HALF + (i - 0.5) * TILE, -HALF + (j - 0.5) * TILE
end

local function tileAt(x: number, z: number): (number?, number?)
	if math.abs(x) >= HALF or math.abs(z) >= HALF then
		return nil, nil
	end
	return math.clamp(math.floor((x + HALF) / TILE) + 1, 1, N), math.clamp(math.floor((z + HALF) / TILE) + 1, 1, N)
end

-- Arena-local frame of a lane: origin on its centre line in the middle of the board, LookVector = travel.
local function laneFrame(axis: string, index: number, dir: number): CFrame
	local c = -HALF + (index - 0.5) * TILE
	if axis == "Row" then
		return CFrame.lookAt(Vector3.new(0, 0, c), Vector3.new(dir, 0, c))
	end
	return CFrame.lookAt(Vector3.new(c, 0, 0), Vector3.new(c, 0, dir))
end

-- Network grace after first contact: one round trip (+ a little buffering) for this player.
local function graceFor(player: Player): number
	local ok, ping = pcall(player.GetNetworkPing, player)
	return math.clamp((if ok and typeof(ping) == "number" then ping else 0.1) + 0.06, 0.1, 0.35)
end

-- Roller pieces relative to the drum pose (X = across the lane = drum axis, -Z = travel, handle trails behind).
local function boxBetween(a: Vector3, b: Vector3): CFrame
	return CFrame.lookAt((a + b) / 2, b)
end
local ARM_X = DRUM_W / 2 + 0.55
local BAR_Y, BAR_Z = R + 1.6, 2.2
local POLE_END = Vector3.new(0, R + 6, 6.6)
local POLE_DIR = (POLE_END - Vector3.new(0, BAR_Y, BAR_Z)).Unit
local PIECES = {
	{ Name = "RollerDrum", Shape = "Cylinder", Size = Vector3.new(DRUM_W, R * 2, R * 2), Offset = CFrame.identity, Look = "Drum" },
	{ Name = "RollerNap", Shape = "Cylinder", Size = Vector3.new(0.5, R * 2 + 0.16, R * 2 + 0.16), Offset = CFrame.new(-1.15, 0, 0), Look = "Nap" },
	{ Name = "RollerNap", Shape = "Cylinder", Size = Vector3.new(0.5, R * 2 + 0.16, R * 2 + 0.16), Offset = CFrame.new(1.15, 0, 0), Look = "Nap" },
	{ Name = "RollerCap", Shape = "Cylinder", Size = Vector3.new(0.22, R * 2 + 0.3, R * 2 + 0.3), Offset = CFrame.new(DRUM_W / 2 + 0.13, 0, 0), Look = "Cap" },
	{ Name = "RollerCap", Shape = "Cylinder", Size = Vector3.new(0.22, R * 2 + 0.3, R * 2 + 0.3), Offset = CFrame.new(-DRUM_W / 2 - 0.13, 0, 0), Look = "Cap" },
	{ Name = "RollerYoke", Size = Vector3.new(0.35, 0.35, (Vector3.new(0, BAR_Y, BAR_Z)).Magnitude + 0.2), Offset = boxBetween(Vector3.new(ARM_X, 0, 0), Vector3.new(ARM_X, BAR_Y, BAR_Z)), Look = "Metal" },
	{ Name = "RollerYoke", Size = Vector3.new(0.35, 0.35, (Vector3.new(0, BAR_Y, BAR_Z)).Magnitude + 0.2), Offset = boxBetween(Vector3.new(-ARM_X, 0, 0), Vector3.new(-ARM_X, BAR_Y, BAR_Z)), Look = "Metal" },
	{ Name = "RollerBar", Size = Vector3.new(ARM_X * 2 + 0.35, 0.4, 0.4), Offset = CFrame.new(0, BAR_Y, BAR_Z), Look = "Metal" },
	{ Name = "RollerHandle", Size = Vector3.new(0.45, 0.45, (POLE_END - Vector3.new(0, BAR_Y, BAR_Z)).Magnitude), Offset = boxBetween(Vector3.new(0, BAR_Y, BAR_Z), POLE_END), Look = "Metal" },
	{ Name = "RollerGrip", Size = Vector3.new(0.8, 0.8, 1.8), Offset = CFrame.lookAt(POLE_END + POLE_DIR * 0.7, POLE_END + POLE_DIR * 2), Look = "Grip" },
}

-- Scoreboard row: a bar that fills in the player's colour, their name and count.
local function newRow(list: Frame, order: number): { [string]: any }
	local row = Instance.new("Frame")
	row.Name = "Row"
	row.BackgroundColor3 = Color3.fromRGB(12, 12, 18)
	row.BackgroundTransparency = 0.25
	row.BorderSizePixel = 0
	row.LayoutOrder = order
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.2, 0)
	corner.Parent = row
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BorderSizePixel = 0
	fill.BackgroundTransparency = 0.2
	fill.Size = UDim2.fromScale(0, 1)
	fill.Parent = row
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0.2, 0)
	fillCorner.Parent = fill
	local name = Instance.new("TextLabel")
	name.Name = "Name"
	name.BackgroundTransparency = 1
	name.Position = UDim2.fromScale(0.03, 0.1)
	name.Size = UDim2.fromScale(0.6, 0.8)
	name.Font = Enum.Font.GothamBlack
	name.TextScaled = true
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextColor3 = TEXT
	name.TextStrokeTransparency = 0.4
	name.Parent = row
	local count = Instance.new("TextLabel")
	count.Name = "Count"
	count.BackgroundTransparency = 1
	count.Position = UDim2.fromScale(0.62, 0.1)
	count.Size = UDim2.fromScale(0.35, 0.8)
	count.Font = Enum.Font.GothamBlack
	count.TextScaled = true
	count.TextXAlignment = Enum.TextXAlignment.Right
	count.TextColor3 = TEXT
	count.TextStrokeTransparency = 0.4
	count.Parent = row
	row.Parent = list
	return { Row = row, Fill = fill, Name = name, Count = count }
end

return {
	Id = "PaintParty",
	Name = "Paint Party",
	Hint = "Walk to paint tiles your colour. Own enough tiles when time runs out, and dodge the rollers!",
	MinFloor = 1,
	MinPlayers = 1,
	Weight = 1,
	BossOnly = false,
	Zone = 3, -- B20+
	Duration = DURATION,

	Build = function(ctx)
		local dark = ctx.Theme.Floor:Lerp(Color3.new(0, 0, 0), 0.15)
		local trim = glow(ctx.Theme.Primary)
		local blank = ctx.Theme.Floor:Lerp(Color3.fromRGB(150, 150, 160), 0.3)
		ctx.State.Blank = blank

		-- Dark slab under the tiles shows through the gaps as grout lines
		ctx:Part({ Name = "Slab", Size = Vector3.new(HALF * 2 + 0.6, 1, HALF * 2 + 0.6), CFrame = ctx:At(0, -1.05, 0), Color = ctx.Theme.Floor:Lerp(Color3.new(0, 0, 0), 0.35) })
		local tiles = {}
		for i = 1, N do
			tiles[i] = {}
			for j = 1, N do
				local x, z = tileCentre(i, j)
				local part = ctx:Part({ Name = "Tile", Size = Vector3.new(TILE_SIZE, 1, TILE_SIZE), CFrame = ctx:At(x, -0.5, z), Color = blank, Material = Enum.Material.SmoothPlastic })
				tiles[i][j] = { Part = part, Owner = nil, I = i, J = j }
			end
		end
		ctx.State.Tiles = tiles

		-- Kerbs all round with a thin light on top
		local kx = HALF + 0.6
		for _, side in { -1, 1 } do
			ctx:Part({ Name = "Kerb", Size = Vector3.new(kx * 2 + 1, KERB_H + 1.5, 1), CFrame = ctx:At(0, (KERB_H - 1.5) / 2, side * kx), Color = dark })
			ctx:Decor({ Name = "KerbLight", Size = Vector3.new(kx * 2 + 0.6, 0.1, 0.3), CFrame = ctx:At(0, KERB_H + 0.04, side * kx), Color = trim, Material = Enum.Material.Neon })
			ctx:Part({ Name = "Kerb", Size = Vector3.new(1, KERB_H + 1.5, kx * 2 - 1), CFrame = ctx:At(side * kx, (KERB_H - 1.5) / 2, 0), Color = dark })
			ctx:Decor({ Name = "KerbLight", Size = Vector3.new(0.3, 0.1, kx * 2 - 1.4), CFrame = ctx:At(side * kx, KERB_H + 0.04, 0), Color = trim, Material = Enum.Material.Neon })
		end
		-- Paint buckets on the corners
		for k, c in { { 1, 1 }, { 1, -1 }, { -1, -1 }, { -1, 1 } } do
			local x, z = c[1] * (kx + 1.6), c[2] * (kx + 1.6)
			ctx:Part({ Name = "Bucket", Shape = Enum.PartType.Cylinder, Size = Vector3.new(4.5, 3.6, 3.6), CFrame = ctx:At(x, 0.75, z, 0, 0, 90), Color = Color3.fromRGB(150, 155, 165), Material = Enum.Material.Metal })
			-- the paint surface sits 0.08 above a slightly wider neon disc, which shows as a thin rim
			ctx:Decor({ Name = "BucketRim", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 3.7, 3.7), CFrame = ctx:At(x, 2.95, z, 0, 0, 90), Color = trim, Material = Enum.Material.Neon })
			ctx:Decor({ Name = "BucketPaint", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 3.3, 3.3), CFrame = ctx:At(x, 3.05, z, 0, 0, 90), Color = PAINTS[k * 2 - 1], Material = Enum.Material.SmoothPlastic })
		end

		-- Scoreboard on the far side, facing the players
		local boardZ = -(kx + 6)
		local panel = ctx:Part({ Name = "Scoreboard", Size = Vector3.new(38, 13, 0.8), CFrame = ctx:At(0, 10.5, boardZ), Color = ctx.Theme.Floor:Lerp(Color3.new(0, 0, 0), 0.35) })
		for _, s in { { 0, 6.35, 38, 0.3 }, { 0, -6.35, 38, 0.3 }, { 18.85, 0, 0.3, 12.4 }, { -18.85, 0, 0.3, 12.4 } } do
			ctx:Decor({ Name = "BoardTrim", Size = Vector3.new(s[3], s[4], 0.1), CFrame = ctx:At(s[1], 10.5 + s[2], boardZ + 0.46), Color = trim, Material = Enum.Material.Neon })
		end
		for _, x in { -13, 13 } do
			ctx:Part({ Name = "BoardLeg", Size = Vector3.new(1.2, 10, 1.2), CFrame = ctx:At(x, -0.5, boardZ), Color = dark })
		end
		local title = ctx:Sign(panel, "PAINT PARTY", { Face = Enum.NormalId.Back, Size = UDim2.fromScale(1, 0.22), Position = UDim2.fromScale(0, 0.03) })
		local list = Instance.new("Frame")
		list.Name = "List"
		list.BackgroundTransparency = 1
		list.Position = UDim2.fromScale(0.04, 0.28)
		list.Size = UDim2.fromScale(0.92, 0.68)
		list.Parent = title.Parent
		local layout = Instance.new("UIListLayout")
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0.02, 0)
		layout.Parent = list
		ctx.State.BoardTitle = title
		ctx.State.BoardList = list

		-- Spawn ring facing the middle (each player starts in their own patch)
		local spawns = {}
		for k = 0, 7 do
			local angle = math.pi / 2 + k * math.pi / 4
			local pos = ctx:At(math.cos(angle) * 17.5, 3, math.sin(angle) * 17.5).Position
			table.insert(spawns, CFrame.lookAt(pos, ctx:At(0, 3, 0).Position))
		end
		ctx:SetSpawns(spawns)
	end,

	Start = function(ctx)
		local p = plan(ctx)
		local tiles = ctx.State.Tiles
		local blank = ctx.State.Blank
		local alive = ctx:GetAlive()
		local solo = #alive <= 1
		-- rivals steal tiles, so even a 2-player floor asks a bit less than solo; crowds split the board
		local quota = if solo then p.SoloQuota else math.min(math.floor(p.SoloQuota * 0.85 + 0.5), math.clamp(math.floor(N * N * p.Share / #alive + 0.5), 10, 50))
		ctx.State.Quota = quota
		local counts: { [Player]: number } = {}
		ctx.State.Counts = counts
		local colours: { [Player]: Color3 } = {}
		local labels: { [Player]: TextLabel } = {}
		local rows = {}
		ctx.State.BoardTitle.Text = if solo then `PAINT {quota} TILES` else `OWN {quota} TILES EACH`

		for k, player in alive do
			local color = PAINTS[(k - 1) % #PAINTS + 1]
			colours[player] = color
			counts[player] = 0
			local character = ctx:GetCharacter(player)
			local head = character and (character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart"))
			if head and head:IsA("BasePart") then
				local label = ctx:Billboard(head, `0/{quota}`, Vector2.new(2.8, 1), 1.9, { TextColor3 = color })
				label.Parent.Parent = ctx.Folder -- adorned to the head, cleaned up with the arena
				labels[player] = label
			end
			local row = newRow(ctx.State.BoardList, k)
			row.Fill.BackgroundColor3 = color
			row.Name.Text = if solo then "TILES" else player.DisplayName
			row.Count.Text = `0/{quota}`
			row.Row.Size = UDim2.new(1, 0, 1 / math.max(#alive, 2) - 0.02, 0)
			rows[player] = row
		end

		-- Painting ----------------------------------------------------------------------
		local function setColour(tile, color: Color3, fresh: boolean)
			if tile.Tween then
				tile.Tween:Cancel()
				tile.Tween = nil
			end
			if fresh then
				-- wet paint: lands bright, settles in a moment
				tile.Part.Color = color:Lerp(Color3.new(1, 1, 1), 0.45)
				tile.Tween = TweenService:Create(tile.Part, TweenInfo.new(0.3, Enum.EasingStyle.Quad), { Color = color })
				tile.Tween:Play()
			else
				tile.Part.Color = color
			end
		end
		local function paint(tile, player: Player)
			local old = tile.Owner
			if old == player then
				return
			end
			if old and counts[old] then
				counts[old] -= 1
			end
			tile.Owner = player
			counts[player] += 1
			setColour(tile, colours[player], true)
		end
		local function erase(tile)
			local old = tile.Owner
			if not old then
				return
			end
			if counts[old] then
				counts[old] -= 1
			end
			tile.Owner = nil
			setColour(tile, blank, false)
		end

		-- Board + billboards, 4x a second
		local function refresh()
			for player, row in rows do
				local n = counts[player] or 0
				local done = n >= quota
				local out = row.Out
				local text = if out then "OUT" else `{n}/{quota}`
				row.Count.Text = if done and not out then `{text} SAFE` else text
				row.Count.TextColor3 = if done and not out then DONE_COLOR else TEXT
				row.Fill.Size = UDim2.fromScale(math.clamp(n / quota, 0, 1), 1)
				row.Row.LayoutOrder = if out then 1000 + table.find(alive, player) else -n * 10 + table.find(alive, player)
				row.Row.BackgroundTransparency = if out then 0.7 else 0.25
				local label = labels[player]
				if label then
					label.Text = `{n}/{quota}`
					label.TextColor3 = if done then DONE_COLOR else colours[player]
				end
			end
		end
		ctx:Every(0.25, function()
			local aliveSet = {}
			for _, player in ctx:GetAlive() do
				aliveSet[player] = true
			end
			for player, row in rows do
				if not aliveSet[player] and not row.Out then
					row.Out = true
					local label = labels[player]
					if label then
						label.Parent:Destroy()
						labels[player] = nil
					end
				end
			end
			refresh()
			return true
		end)

		-- Rollers --------------------------------------------------------------------------
		local rollers = {}
		ctx.State.Rollers = rollers
		local hazardBody = ctx.Theme.Hazard:Lerp(Color3.new(0, 0, 0), 0.15)
		local looks = {
			Drum = { Color = hazardBody, Material = Enum.Material.SmoothPlastic },
			Nap = { Color = ctx.Theme.Hazard:Lerp(Color3.new(1, 1, 1), 0.25), Material = Enum.Material.SmoothPlastic },
			Cap = { Color = glow(ctx.Theme.Hazard), Material = Enum.Material.Neon },
			Metal = { Color = Color3.fromRGB(60, 62, 72), Material = Enum.Material.Metal },
			Grip = { Color = Color3.fromRGB(38, 38, 44), Material = Enum.Material.SmoothPlastic },
		}
		local A0, A1 = -(HALF - TILE / 2), HALF - TILE / 2

		local function launchRoller(axis: string, index: number, dir: number)
			local lane = laneFrame(axis, index, dir)
			local T = ctx.Origin * lane
			local speed = p.RollerSpeed
			local tel = p.Telegraph
			-- lane tiles in travel order
			local laneTiles = {}
			for k = 1, N do
				local idx = if dir > 0 then k else N + 1 - k
				laneTiles[k] = if axis == "Row" then tiles[idx][index] else tiles[index][idx]
			end
			local roller = { Axis = axis, Index = index, T = T, Speed = speed, Tiles = laneTiles, Next = 1, Prev = A0, Pending = {}, Parts = {}, Live = false, Ends = os.clock() + tel + (A1 - A0) / speed }
			table.insert(rollers, roller)

			ctx:Warn(T * CFrame.new(0, 0.3, 0), Vector3.new(TILE, 0.2, HALF * 2), tel, ctx.Theme.Hazard, { Sweep = lane.LookVector })
			ctx:Sound("Warning", (T * CFrame.new(0, 2, -A0)).Position)
			if ctx.Rng:NextNumber() < 0.3 then
				-- greed: a coin waits in the lane
				ctx:SpawnCoin((T * CFrame.new(0, 3, -ctx.Rng:NextNumber(-HALF + 8, HALF - 8))).Position)
			end

			local function pose(a: number, lift: number): CFrame
				return T * CFrame.new(0, R + lift, -a)
			end
			ctx:After(tel - DROP, function()
				for _, piece in PIECES do
					local look = looks[piece.Look]
					local part = ctx:Decor({
						Name = piece.Name,
						Shape = if piece.Shape == "Cylinder" then Enum.PartType.Cylinder else Enum.PartType.Block,
						Size = piece.Size,
						CFrame = pose(A0, 14) * piece.Offset,
						Color = look.Color,
						Material = look.Material,
					})
					table.insert(roller.Parts, { Part = part, Offset = piece.Offset })
					ctx:Tween(part, TweenInfo.new(DROP, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = pose(A0, 0) * piece.Offset })
				end
			end)
			ctx:After(tel, function()
				-- Landed: hand the motion to the clients (OMF_Orbit about a far-away centre = a straight roll)
				local landed = pose(A0, 0)
				local centre = T * CFrame.new(RBIG, R, 0)
				local startTime = workspace:GetServerTimeNow()
				local parts, frames = {}, {}
				for _, piece in roller.Parts do
					table.insert(parts, piece.Part)
					table.insert(frames, landed * piece.Offset)
				end
				workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
				for _, piece in roller.Parts do
					ctx:Animate(piece.Part, "OMF_Orbit", {
						OrbitCenter = centre,
						OrbitOffset = centre:ToObjectSpace(pose(0, 0) * piece.Offset),
						OrbitAxis = Vector3.yAxis,
						Angle0 = -A0 / RBIG,
						Omega0 = speed / RBIG,
						Ramp = 0,
						Dir = -1,
						StartTime = startTime,
					})
				end
				roller.LandClock = os.clock()
				roller.Live = true
				ctx:Impact(landed.Position - Vector3.new(0, R - 0.2, 0), ctx.Theme.Hazard, 6, 4)
				ctx:Sound("Impact", landed.Position)
				ctx:Shake(0.25, 0.2)
			end)
		end

		-- Freezes a roller where it is (clients stop replaying the roll) and fades it out.
		local function retire(roller)
			if roller.Retired then
				return
			end
			roller.Retired = true
			roller.Live = false
			local now = workspace:GetServerTimeNow()
			local a = math.min(A0 + roller.Speed * (os.clock() - (roller.LandClock or os.clock())), A1)
			local parts, frames = {}, {}
			for _, piece in roller.Parts do
				piece.Part:SetAttribute("StopTime", now)
				table.insert(parts, piece.Part)
				table.insert(frames, roller.T * CFrame.new(0, R, -a) * piece.Offset)
			end
			if #parts > 0 then
				workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
			end
			if ctx.Ended then
				return
			end
			for _, piece in roller.Parts do
				ctx:Tween(piece.Part, TweenInfo.new(FADE), { Transparency = 1 })
			end
			ctx:Fx("Burst", { Position = (roller.T * CFrame.new(0, R, -a)).Position, Color = ctx.Theme.Hazard, Count = 14 })
			task.delay(FADE + 0.05, function()
				for _, piece in roller.Parts do
					piece.Part:Destroy()
				end
			end)
		end

		local function pickWave()
			local now = os.clock()
			local busyAxis, busyLanes = nil, {}
			for _, r in rollers do
				if not r.Retired then
					busyLanes[r.Axis .. r.Index] = true
					-- rollers still on the board when the new ones land fix the axis (no crossing drums)
					if r.Ends > now + p.Telegraph - 0.2 then
						busyAxis = r.Axis
					end
				end
			end
			local axis = busyAxis or (if ctx.Rng:NextNumber() < 0.5 then "Row" else "Col")
			local picked = {}
			local aliveNow = ctx:GetAlive()
			for n = 1, p.WaveSize do
				for _ = 1, 24 do
					local candidate
					if #aliveNow > 0 and n == 1 and ctx.Rng:NextNumber() < p.Aim then
						-- aim at somebody's lane
						local pos = ctx:LocalPosition(aliveNow[ctx.Rng:NextInteger(1, #aliveNow)])
						if pos then
							local i, j = tileAt(math.clamp(pos.X, -HALF + 0.1, HALF - 0.1), math.clamp(pos.Z, -HALF + 0.1, HALF - 0.1))
							candidate = if axis == "Row" then j else i
						end
					end
					candidate = candidate or ctx.Rng:NextInteger(1, N)
					local ok = not busyLanes[axis .. candidate]
					for _, other in picked do
						if math.abs(other - candidate) < 2 then
							ok = false
						end
					end
					if ok then
						table.insert(picked, candidate)
						break
					end
				end
			end
			for _, index in picked do
				launchRoller(axis, index, if ctx.Rng:NextNumber() < 0.5 then 1 else -1)
			end
		end

		-- Paint bombs ------------------------------------------------------------------------
		local function dropBomb()
			-- with rivals, aim at the leader's paint (catch-up); solo, anywhere
			local leader, most = nil, 0
			if not solo then
				for _, player in ctx:GetAlive() do
					if (counts[player] or 0) > most then
						leader, most = player, counts[player]
					end
				end
			end
			local bi, bj, best = 2, 2, -1
			for _ = 1, if leader then 6 else 1 do
				local ci, cj = ctx.Rng:NextInteger(2, N - 1), ctx.Rng:NextInteger(2, N - 1)
				local score = ctx.Rng:NextNumber() * 0.5
				for di = -1, 1 do
					for dj = -1, 1 do
						if leader and tiles[ci + di][cj + dj].Owner == leader then
							score += 1
						end
					end
				end
				if score > best then
					bi, bj, best = ci, cj, score
				end
			end
			local cx, cz = tileCentre(bi, bj)
			ctx:Warn(ctx:At(cx, 0.35, cz), Vector3.new(TILE * 3, 0.2, TILE * 3), p.BombTelegraph, BOMB_COLOR)
			ctx:After(p.BombTelegraph - BOMB_FALL, function()
				local ball = ctx:Decor({ Name = "PaintBomb", Shape = Enum.PartType.Ball, Size = Vector3.new(3, 3, 3), CFrame = ctx:At(cx, 40, cz), Color = BOMB_COLOR, Material = Enum.Material.SmoothPlastic })
				local band = ctx:Decor({ Name = "BombBand", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 3.1, 3.1), CFrame = ball.CFrame * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(60, 62, 72), Anchored = false })
				local fuse = ctx:Decor({ Name = "BombFuse", Shape = Enum.PartType.Ball, Size = Vector3.new(0.6, 0.6, 0.6), CFrame = ball.CFrame * CFrame.new(0, 1.6, 0), Color = Color3.fromRGB(215, 120, 30), Material = Enum.Material.Neon, Anchored = false })
				for _, part in { band, fuse } do
					local weld = Instance.new("WeldConstraint")
					weld.Part0 = ball
					weld.Part1 = part
					weld.Parent = part
				end
				ctx:Emitter(fuse, {
					Texture = "Sparks",
					Color = ColorSequence.new(Color3.fromRGB(255, 220, 140), Color3.fromRGB(255, 120, 40)),
					Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0) }),
					Speed = NumberRange.new(3, 7),
					SpreadAngle = Vector2.new(40, 40),
					Lifetime = NumberRange.new(0.2, 0.4),
					Rate = 30,
				})
				ctx:Tween(ball, TweenInfo.new(BOMB_FALL, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = ctx:At(cx, 1.5, cz) })
				ctx:Sound("Whoosh", ball)
				task.delay(BOMB_FALL + 0.05, function()
					ball:Destroy()
				end)
			end)
			ctx:After(p.BombTelegraph, function()
				for di = -1, 1 do
					for dj = -1, 1 do
						erase(tiles[bi + di][bj + dj])
					end
				end
				ctx:Impact(ctx:At(cx, 0.2, cz).Position, BOMB_COLOR, TILE * 1.8, 8)
				ctx:Sound("Explosion", ctx:At(cx, 2, cz).Position)
				ctx:Shake(0.35, 0.25)
				-- splash shoves everyone in the patch outward (never lethal)
				for _, player in ctx:GetAlive() do
					local pos = ctx:LocalPosition(player)
					local feet = ctx:FeetY(player)
					if pos and feet and feet < 4 and math.abs(pos.X - cx) <= TILE * 1.5 + 0.6 and math.abs(pos.Z - cz) <= TILE * 1.5 + 0.6 then
						local away = Vector3.new(pos.X - cx, 0, pos.Z - cz)
						away = if away.Magnitude > 0.5 then away.Unit else Vector3.new(ctx.Rng:NextNumber(-1, 1), 0, ctx.Rng:NextNumber(-1, 1)).Unit
						ctx:Knockback(player, ctx.Origin:VectorToWorldSpace(away * 30 + Vector3.new(0, 22, 0)))
					end
				end
			end)
		end

		-- Main loop (own connection so the rollers can be frozen the moment the floor ends) ------
		local stopped = false
		ctx.Trove:Connect(RunService.Heartbeat, function()
			if ctx.Ended then
				if not stopped then
					stopped = true
					for _, roller in rollers do
						retire(roller)
					end
				end
				return
			end
			local now = os.clock()
			local aliveNow = ctx:GetAlive()

			-- paint under grounded feet
			for _, player in aliveNow do
				local pos = ctx:LocalPosition(player)
				local feet = ctx:FeetY(player)
				if pos and feet and feet < 0.9 and feet > -1.5 and colours[player] then
					local i, j = tileAt(pos.X, pos.Z)
					if i and j then
						paint(tiles[i][j], player)
					end
				end
			end

			-- rollers: wipe the lane behind the drum, swept hits ahead of it
			for k = #rollers, 1, -1 do
				local roller = rollers[k]
				if roller.Live then
					local a = math.min(A0 + roller.Speed * (now - roller.LandClock), A1)
					while roller.Next <= N and A0 + (roller.Next - 1) * TILE <= a + 0.01 do
						erase(roller.Tiles[roller.Next])
						roller.Next += 1
					end
					for _, player in aliveNow do
						if roller.Pending[player] then
							continue
						end
						local root = ctx:GetRoot(player)
						if not root then
							continue
						end
						local lp = roller.T:PointToObjectSpace(root.Position)
						local along = -lp.Z
						if math.abs(lp.X) < LANE_HALF and along >= roller.Prev - REACH and along <= a + REACH then
							local feet = ctx:FeetY(player)
							if feet and feet < TOP_CLEAR and feet > -4 then
								roller.Pending[player] = now + graceFor(player)
							end
						end
					end
					roller.Prev = a
					if a >= A1 then
						retire(roller)
					end
				end
				-- resolve contacts: seen out of the lane (or above the drum) within the grace survives
				for player, deadline in roller.Pending do
					local root = ctx:GetRoot(player)
					local feet = ctx:FeetY(player)
					if not root or not feet or not table.find(aliveNow, player) then
						roller.Pending[player] = nil
						continue
					end
					local lp = roller.T:PointToObjectSpace(root.Position)
					if math.abs(lp.X) >= LANE_HALF or feet >= TOP_CLEAR then
						roller.Pending[player] = nil
					elseif now >= deadline then
						roller.Pending[player] = nil
						ctx:Eliminate(player, "Flattened by a roller")
					end
				end
				if roller.Retired and next(roller.Pending) == nil then
					table.remove(rollers, k)
				end
			end
		end)

		-- Coins on a few random tiles
		for _ = 1, 4 do
			local x, z = tileCentre(ctx.Rng:NextInteger(1, N), ctx.Rng:NextInteger(1, N))
			ctx:SpawnCoin(ctx:At(x, 3, z).Position)
		end

		ctx:Announce(if solo then `PAINT {quota} TILES!` else `OWN {quota} TILES!`, colours[alive[1]] or TEXT)

		-- Bombs on their own clock
		task.spawn(function()
			if not ctx:Wait(p.FirstBomb - p.BombTelegraph) then
				return
			end
			while ctx:Remaining() > p.BombTelegraph + 0.5 do
				dropBomb()
				if not ctx:Wait(p.BombGap * ctx.Rng:NextNumber(0.85, 1.15)) then
					return
				end
			end
		end)

		-- Last call
		ctx:After(DURATION - 5, function()
			ctx:Announce("5 SECONDS!", ctx.Theme.Hazard)
			ctx:Sound("Countdown")
		end)

		-- Roller waves until there is no time left for another roll
		if not ctx:Wait(p.FirstRoller - p.Telegraph) then
			return
		end
		while ctx:Remaining() > p.Telegraph + 1.5 do
			pickWave()
			if not ctx:Wait(p.RollerGap * ctx.Rng:NextNumber(0.85, 1.15)) then
				return
			end
		end
	end,

	Judge = function(ctx)
		local counts = ctx.State.Counts or {}
		local quota = ctx.State.Quota or 0
		for _, player in ctx:GetAlive() do
			if (counts[player] or 0) < quota then
				ctx:Eliminate(player, "Not enough tiles")
			end
		end
	end,
}
