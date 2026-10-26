-- Neon Snake: everyone drags a glowing tail that grows with every orb they eat. Touch any tail (your own too,
-- past the neck) and you're out. Eat your quota before time runs out.
--
-- Tails are breadcrumbs laid every SPACING studs along each player's server-side path. A tail is the window of
-- segments [TailStart, TailEnd] (segment j joins crumb j-1 to crumb j); TailEnd trails the newest crumb by NECK and
-- growing just pauses the tip. Each segment owns two pooled parts that are placed once when it joins the tail
-- and parked under the floor when it leaves, so an advancing tail only moves two segments (one BulkMoveTo).
-- Hits are maths on the server every Heartbeat: feet within HIT_R of a segment's centre line and below its top
-- (a well-timed jump clears a tail). Fresh segments arm after ARM seconds and spare anyone they were laid on top
-- of, so lag never drops a tail under someone's feet: you only die by walking into one.

local HALF = 40 -- arena half size (80 x 80)
local GRID_STEP = 8
local KERB_H = 2.4
local SPACING = 2.2 -- breadcrumb spacing = segment length
local SEG_W = 1.6
local SEG_H = 2.4 -- tail top
local SPINE_W = 0.5
local SPINE_H = 0.3
local NECK = 2 -- newest crumbs behind the head that are not tail yet
local SELF_SAFE = 3 -- your own newest tail segments can't hit you
local HIT_R = 1.3 -- feet within this of a segment's centre line ...
local FORGIVE = 0.3 -- ... and lower than its top minus this = hit
local ARM = 0.2 -- fresh segments turn lethal to other players after this long
local TELEPORT = 9 -- moving further than this between frames (a rescue) starts a new chain
local PICK_R = 3.2 -- orb pickup reach (root to orb, horizontal)
local ORB_Y = 2.1
local PARK_Y = -20 -- unused pooled parts wait under the floor
local DURATION = 23

-- Tail colours (neon, HSV value <= 0.85). Lime is kept for the orbs.
local PALETTE = {
	Color3.fromRGB(0, 185, 215), -- cyan
	Color3.fromRGB(215, 45, 175), -- magenta
	Color3.fromRGB(215, 120, 20), -- orange
	Color3.fromRGB(125, 75, 215), -- violet
	Color3.fromRGB(205, 170, 30), -- gold
	Color3.fromRGB(40, 95, 215), -- blue
	Color3.fromRGB(215, 55, 75), -- red
	Color3.fromRGB(30, 190, 150), -- teal
}
local ORB_COLOR = Color3.fromRGB(120, 215, 45)
local DONE_COLOR = Color3.fromRGB(140, 255, 150)

local function tone(c: Color3, cap: number?): Color3
	local h, s, v = c:ToHSV()
	return Color3.fromHSV(h, s, math.min(v, cap or 0.85))
end

-- Theme colour for a thin neon trim: value <= 0.65 and luminance <= 0.38, so yellow / white themes don't bloom out
-- (the rim and the kerb lights run side by side round the whole arena and add up).
local function glow(c: Color3): Color3
	local t = tone(c, 0.65)
	local lum = 0.2126 * t.R + 0.7152 * t.G + 0.0722 * t.B
	if lum > 0.38 then
		local h, s, v = t:ToHSV()
		t = Color3.fromHSV(h, s, v * 0.38 / lum)
	end
	return t
end

local function hex(c: Color3): string
	return string.format("#%02X%02X%02X", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

local function plan(ctx)
	local d = math.clamp(ctx.Difficulty, 0, 1.5)
	-- a bot that beelines eats ~12 in 23 s; a person ~8. Solo: 3 orbs on B1, 6 on B20, 8 on B32
	return {
		Quota = math.floor(3 + 3.6 * d + 0.5),
		StartLength = 4,
		Grow = if d >= 1 then 4 else 3,
		ExtraOrbs = 3, -- orbs on the field = alive players + this
		D = d,
	}
end

-- Horizontal distance from (px, pz) to the segment a-b.
local function distToSeg(px: number, pz: number, a: Vector3, b: Vector3): number
	local abx, abz = b.X - a.X, b.Z - a.Z
	local apx, apz = px - a.X, pz - a.Z
	local len2 = abx * abx + abz * abz
	local t = if len2 > 1e-6 then math.clamp((apx * abx + apz * abz) / len2, 0, 1) else 0
	local dx, dz = apx - abx * t, apz - abz * t
	return math.sqrt(dx * dx + dz * dz)
end

-- World CFrames of a segment's body and spine between two arena-local crumbs (y = 0).
local function segFrames(ctx, a: Vector3, b: Vector3): (CFrame, CFrame)
	local mid = (a + b) / 2
	local dir = b - a
	local base = if dir.Magnitude > 1e-3 then CFrame.lookAt(mid, mid + dir) else CFrame.new(mid)
	local bodyH = SEG_H - SPINE_H + 0.1
	return ctx.Origin * base * CFrame.new(0, bodyH / 2 - 0.05, 0), ctx.Origin * base * CFrame.new(0, SEG_H - SPINE_H / 2, 0)
end

local function newPair(ctx, snake)
	local park = ctx:At(0, PARK_Y, 0)
	local body = ctx:Decor({
		Name = "TailBody",
		Size = Vector3.new(SEG_W, SEG_H - SPINE_H + 0.1, SPACING + 0.2),
		CFrame = park,
		Color = snake.Body,
		Material = Enum.Material.SmoothPlastic,
		Transparency = 0.25,
	})
	local spine = ctx:Decor({
		Name = "TailSpine",
		Size = Vector3.new(SPINE_W, SPINE_H, SPACING + 0.1),
		CFrame = park,
		Color = snake.Color,
		Material = Enum.Material.Neon,
	})
	return { body, spine }
end

-- Moves new crumbs into the tail and the tip out of it. `others` = arena-local positions of the other players.
local function advance(ctx, snake, now: number, others: { [Player]: Vector3 })
	local parts, frames = {}, {}
	local target = snake.Count - NECK
	while snake.TailEnd < target do
		local j = snake.TailEnd + 1
		snake.TailEnd = j
		local a, b = snake.Crumbs[j - 1], snake.Crumbs[j]
		if a and b and not snake.Breaks[j] then
			local seg = { A = a, B = b, Mid = (a + b) / 2, TailAt = now, Immune = {} }
			-- whoever this lands on may walk off it
			for other, pos in others do
				if other ~= snake.Player and distToSeg(pos.X, pos.Z, a, b) <= HIT_R + 0.4 then
					seg.Immune[other] = true
				end
			end
			local pair = table.remove(snake.Pool) or newPair(ctx, snake)
			seg.Pair = pair
			local bodyCF, spineCF = segFrames(ctx, a, b)
			table.insert(parts, pair[1])
			table.insert(frames, bodyCF)
			table.insert(parts, pair[2])
			table.insert(frames, spineCF)
			snake.Segs[j] = seg
		end
	end
	local park = ctx:At(0, PARK_Y, 0)
	while snake.TailEnd - snake.TailStart + 1 > snake.Length do
		local seg = snake.Segs[snake.TailStart]
		if seg then
			table.insert(parts, seg.Pair[1])
			table.insert(frames, park)
			table.insert(parts, seg.Pair[2])
			table.insert(frames, park)
			table.insert(snake.Pool, seg.Pair)
			snake.Segs[snake.TailStart] = nil
		end
		snake.Crumbs[snake.TailStart - 2] = nil
		snake.TailStart += 1
	end
	if #parts > 0 then
		workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

-- A dead player's tail fades out from the tip to the neck. It is harmless from the moment they die.
local function dissolve(ctx, snake)
	snake.Dead = true
	if snake.Gui then
		snake.Gui:Destroy()
		snake.Gui = nil
	end
	local list = {}
	for j = snake.TailStart, snake.TailEnd do
		local seg = snake.Segs[j]
		if seg then
			table.insert(list, seg)
		end
	end
	snake.Segs = {}
	local count = #list
	for k, seg in list do
		local delay = (k - 1) / math.max(count, 1) * 0.9
		task.delay(delay, function()
			if ctx.Ended and not seg.Pair[1].Parent then
				return
			end
			for _, part in seg.Pair do
				if part.Parent then
					ctx:Tween(part, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1, Size = part.Size * Vector3.new(1.4, 0.15, 1) })
				end
			end
			if k % 4 == 1 then
				ctx:Fx("Burst", { Position = ctx.Origin * (seg.Mid + Vector3.new(0, 1.2, 0)), Color = snake.Color, Count = 6 })
			end
		end)
	end
	task.delay(2.2, function()
		for _, seg in list do
			for _, part in seg.Pair do
				part:Destroy()
			end
		end
	end)
end

-- Scoreboard ---------------------------------------------------------------------

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
	fill.BackgroundTransparency = 0.35
	fill.Size = UDim2.fromScale(0, 1)
	fill.Parent = row
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0.2, 0)
	fillCorner.Parent = fill
	local name = Instance.new("TextLabel")
	name.Name = "Name"
	name.BackgroundTransparency = 1
	name.Position = UDim2.fromScale(0.03, 0.1)
	name.Size = UDim2.fromScale(0.64, 0.8)
	name.Font = Enum.Font.GothamBlack
	name.TextScaled = true
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextColor3 = Color3.fromRGB(245, 240, 230)
	name.TextStrokeTransparency = 0.5
	name.Parent = row
	local count = Instance.new("TextLabel")
	count.Name = "Count"
	count.BackgroundTransparency = 1
	count.Position = UDim2.fromScale(0.66, 0.1)
	count.Size = UDim2.fromScale(0.31, 0.8)
	count.Font = Enum.Font.GothamBlack
	count.TextScaled = true
	count.TextXAlignment = Enum.TextXAlignment.Right
	count.TextColor3 = Color3.fromRGB(245, 240, 230)
	count.TextStrokeTransparency = 0.5
	count.Parent = row
	row.Parent = list
	return { Row = row, Fill = fill, Name = name, Count = count }
end

return {
	Id = "NeonSnake",
	Name = "Neon Snake",
	Hint = "Eat orbs to grow your tail. Touch any tail and you're out! Eat enough before time runs out.",
	MinFloor = 1,
	MinPlayers = 1,
	Weight = 1,
	BossOnly = false,
	Zone = 3, -- B20+
	Duration = DURATION,

	Build = function(ctx)
		-- darker than most floors so the trails pop, but never black; kerbs are lighter than the floor
		local floorColor = ctx.Theme.Floor:Lerp(Color3.new(0, 0, 0), 0.3)
		local dark = ctx.Theme.Floor:Lerp(Color3.new(1, 1, 1), 0.06)
		local trim = glow(ctx.Theme.Primary)
		ctx:Part({ Name = "Floor", Size = Vector3.new(HALF * 2, 2, HALF * 2), CFrame = ctx:At(0, -1, 0), Color = floorColor })
		-- Faint grid; the cross lines sit 0.05 higher so crossings never z-fight
		local gridColor = floorColor:Lerp(ctx.Theme.Primary, 0.26)
		for k = -4, 4 do
			local o = k * GRID_STEP
			ctx:Decor({ Name = "GridX", Size = Vector3.new(HALF * 2 - 2, 0.02, 0.14), CFrame = ctx:At(0, 0.03, o), Color = gridColor })
			ctx:Decor({ Name = "GridZ", Size = Vector3.new(0.14, 0.02, HALF * 2 - 2), CFrame = ctx:At(o, 0.08, 0), Color = gridColor })
		end
		ctx:Rim(HALF, HALF, trim, glow(ctx.Theme.Primary):Lerp(Color3.new(0, 0, 0), 0.3))

		-- Low kerbs all round (as tall as a tail) with a thin light on top
		for _, side in { -1, 1 } do
			ctx:Part({ Name = "Kerb", Size = Vector3.new(HALF * 2 + 2, KERB_H + 1, 1), CFrame = ctx:At(0, (KERB_H - 1) / 2, side * (HALF + 0.5)), Color = dark })
			ctx:Decor({ Name = "KerbLight", Size = Vector3.new(HALF * 2 + 1.6, 0.1, 0.3), CFrame = ctx:At(0, KERB_H + 0.04, side * (HALF + 0.5)), Color = trim, Material = Enum.Material.Neon })
			ctx:Part({ Name = "Kerb", Size = Vector3.new(1, KERB_H + 1, HALF * 2), CFrame = ctx:At(side * (HALF + 0.5), (KERB_H - 1) / 2, 0), Color = dark })
			ctx:Decor({ Name = "KerbLight", Size = Vector3.new(0.3, 0.1, HALF * 2 - 0.4), CFrame = ctx:At(side * (HALF + 0.5), KERB_H + 0.04, 0), Color = trim, Material = Enum.Material.Neon })
		end
		for k, c in { { 1, 1 }, { 1, -1 }, { -1, -1 }, { -1, 1 } } do
			local x, z = c[1] * (HALF + 0.5), c[2] * (HALF + 0.5)
			ctx:Part({ Name = "Pylon", Size = Vector3.new(2.4, 7, 2.4), CFrame = ctx:At(x, 2.5, z), Color = dark })
			local cap = ctx:Decor({ Name = "PylonCap", Size = Vector3.new(1.8, 0.7, 1.8), CFrame = ctx:At(x, 6.3, z), Color = PALETTE[k * 2 - 1], Material = Enum.Material.Neon })
			ctx:Animate(cap, "OMF_Pulse", { PulseMin = 0, PulseMax = 0.5, PulseSpeed = 1.2, PulsePhase = k / 4 })
		end

		-- Scoreboard on the far side, facing the players
		local boardZ = -(HALF + 5)
		local panel = ctx:Part({ Name = "Scoreboard", Size = Vector3.new(34, 12, 0.8), CFrame = ctx:At(0, 10, boardZ), Color = ctx.Theme.Floor:Lerp(Color3.new(0, 0, 0), 0.35) })
		for _, s in { { 0, 5.85, 34, 0.3 }, { 0, -5.85, 34, 0.3 }, { 16.85, 0, 0.3, 11.4 }, { -16.85, 0, 0.3, 11.4 } } do
			ctx:Decor({ Name = "BoardTrim", Size = Vector3.new(s[3], s[4], 0.1), CFrame = ctx:At(s[1], 10 + s[2], boardZ + 0.46), Color = trim, Material = Enum.Material.Neon })
		end
		for _, x in { -12, 12 } do
			ctx:Part({ Name = "BoardLeg", Size = Vector3.new(1.2, 10, 1.2), CFrame = ctx:At(x, -0.5, boardZ), Color = dark })
		end
		local title = ctx:Sign(panel, "NEON SNAKE", { Face = Enum.NormalId.Back, Size = UDim2.fromScale(1, 0.24), Position = UDim2.fromScale(0, 0.03), TextColor3 = ORB_COLOR:Lerp(Color3.new(1, 1, 1), 0.35) })
		local list = Instance.new("Frame")
		list.Name = "List"
		list.BackgroundTransparency = 1
		list.Position = UDim2.fromScale(0.04, 0.3)
		list.Size = UDim2.fromScale(0.92, 0.66)
		list.Parent = title.Parent
		local layout = Instance.new("UIListLayout")
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0.02, 0)
		layout.Parent = list
		ctx.State.BoardList = list
		ctx.State.BoardTitle = title

		-- Spawn ring facing the middle
		local spawns = {}
		for k = 0, 7 do
			local angle = math.pi / 2 + k * math.pi / 4
			local pos = ctx:At(math.cos(angle) * 24, 3, math.sin(angle) * 24).Position
			table.insert(spawns, CFrame.lookAt(pos, ctx:At(0, 3, 0).Position))
		end
		ctx:SetSpawns(spawns)
	end,

	Start = function(ctx)
		local p = plan(ctx)
		local alive = ctx:GetAlive()
		local solo = #alive == 1
		-- with rivals the orbs are shared and their tails block the way: one fewer
		local quota = if solo then p.Quota else math.max(p.Quota - 1, 2)
		ctx.State.Quota = quota
		local snakes: { [Player]: any } = {}
		ctx.State.Snakes = snakes
		local orbs = {}
		ctx.State.Orbs = orbs
		local list = ctx.State.BoardList
		ctx.State.BoardTitle.Text = `EAT {quota} ORBS`

		for k, player in alive do
			local color = PALETTE[(k - 1) % #PALETTE + 1]
			local snake = {
				Player = player,
				Color = color,
				Body = color:Lerp(Color3.new(0, 0, 0), 0.25),
				Crumbs = {},
				Breaks = {},
				Count = 0,
				Last = nil,
				Segs = {},
				TailStart = 1,
				TailEnd = 0,
				Length = p.StartLength,
				Eaten = 0,
				Pool = {},
				Dead = false,
			}
			snakes[player] = snake
			local character = ctx:GetCharacter(player)
			local head = character and (character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart"))
			if head and head:IsA("BasePart") then
				local label = ctx:Billboard(head, `0/{quota}`, Vector2.new(2.8, 1), 1.9, { TextColor3 = color:Lerp(Color3.new(1, 1, 1), 0.3) })
				local gui = label.Parent :: BillboardGui
				gui.Parent = ctx.Folder -- adorned to the head, cleaned up with the arena
				snake.Label = label
				snake.Gui = gui
			end
			local row = newRow(list, k)
			row.Fill.BackgroundColor3 = color
			row.Name.Text = if solo then "ORBS" else player.DisplayName
			row.Count.Text = `0/{quota}`
			snake.Row = row
		end
		-- One row per player; a solo board is one big bar
		local rows = math.max(#alive, 2)
		for _, snake in snakes do
			snake.Row.Row.Size = UDim2.new(1, 0, 1 / rows - 0.02, 0)
		end

		local function refresh(snake)
			local done = snake.Eaten >= quota
			local text = `{snake.Eaten}/{quota}`
			if snake.Label then
				snake.Label.Text = text
				snake.Label.TextColor3 = if done then DONE_COLOR else snake.Color:Lerp(Color3.new(1, 1, 1), 0.3)
			end
			local row = snake.Row
			row.Count.Text = if done then `{text} SAFE` else text
			row.Count.TextColor3 = if done then DONE_COLOR else Color3.fromRGB(245, 240, 230)
			row.Fill.Size = UDim2.fromScale(math.clamp(snake.Eaten / quota, 0, 1), 1)
			row.Row.LayoutOrder = -snake.Eaten * 10 + table.find(alive, snake.Player)
		end

		-- Orbs ------------------------------------------------------------------------
		local function clearance(x: number, z: number, positions: { [Player]: Vector3 }): number
			local score = math.huge
			for _, s in snakes do
				if not s.Dead then
					for _, seg in s.Segs do
						score = math.min(score, distToSeg(x, z, seg.A, seg.B) / 4)
					end
				end
			end
			for _, pos in positions do
				local dx, dz = pos.X - x, pos.Z - z
				score = math.min(score, math.sqrt(dx * dx + dz * dz) / 12)
			end
			for _, orb in orbs do
				local dx, dz = orb.Pos.X - x, orb.Pos.Z - z
				score = math.min(score, math.sqrt(dx * dx + dz * dz) / 10)
			end
			return score
		end

		local function spawnOrb(positions: { [Player]: Vector3 })
			local bestX, bestZ, bestScore = 0, 0, -1
			for _ = 1, 40 do
				local x = ctx.Rng:NextNumber(-HALF + 5, HALF - 5)
				local z = ctx.Rng:NextNumber(-HALF + 5, HALF - 5)
				local score = clearance(x, z, positions)
				if score > bestScore then
					bestX, bestZ, bestScore = x, z, score
				end
				if score >= 1 then
					break
				end
			end
			local pos = Vector3.new(bestX, ORB_Y, bestZ)
			local core = ctx:Decor({ Name = "Orb", Shape = Enum.PartType.Ball, Size = Vector3.new(1.4, 1.4, 1.4), CFrame = ctx:At(bestX, ORB_Y, bestZ), Color = ORB_COLOR, Material = Enum.Material.Neon })
			local shell = ctx:Decor({ Name = "OrbShell", Shape = Enum.PartType.Ball, Size = Vector3.new(2.6, 2.6, 2.6), CFrame = core.CFrame, Color = ORB_COLOR, Material = Enum.Material.ForceField })
			local ring = ctx:Decor({ Name = "OrbRing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.04, 3.4, 3.4), CFrame = ctx:At(bestX, 0.13, bestZ, 0, 0, 90), Color = ORB_COLOR, Material = Enum.Material.Neon, Transparency = 0.55 })
			ctx:Animate(ring, "OMF_Pulse", { PulseMin = 0.45, PulseMax = 0.85, PulseSpeed = 1.4, PulsePhase = ctx.Rng:NextNumber() })
			local beam = ctx:Decor({ Name = "OrbBeam", Size = Vector3.new(0.16, 7, 0.16), CFrame = ctx:At(bestX, ORB_Y + 4.5, bestZ), Color = ORB_COLOR, Material = Enum.Material.Neon, Transparency = 0.5 })
			ctx:Animate(beam, "OMF_Pulse", { PulseMin = 0.45, PulseMax = 0.8, PulseSpeed = 0.9, PulsePhase = ctx.Rng:NextNumber() })
			ctx:Fx("Burst", { Position = core.Position, Color = ORB_COLOR, Count = 10 })
			table.insert(orbs, { Pos = pos, Parts = { core, shell, ring, beam } })
		end

		local function eat(snake, orb)
			for _, part in orb.Parts do
				part:Destroy()
			end
			local world = ctx.Origin * orb.Pos
			ctx:Fx("Burst", { Position = world, Color = ORB_COLOR, Count = 16 })
			snake.Eaten += 1
			snake.Length += p.Grow
			refresh(snake)
			ctx.Run:FireEffectTo(snake.Player, "Sound", { Name = "BagGrow" })
			if snake.Eaten == quota then
				ctx.Run:FireEffectTo(snake.Player, "Sound", { Name = "ElevatorDing" })
				ctx.Run:FireEffectTo(snake.Player, "Banner", { Text = "QUOTA MET! STAY ALIVE", Color = DONE_COLOR })
				ctx:Fx("Burst", { Position = world + Vector3.new(0, 2, 0), Color = DONE_COLOR, Count = 30 })
			end
		end

		local function positionsNow(): { [Player]: Vector3 }
			local out = {}
			for _, player in ctx:GetAlive() do
				local pos = ctx:LocalPosition(player)
				if pos then
					out[player] = pos
				end
			end
			return out
		end

		do
			local positions = positionsNow()
			for _ = 1, #alive + p.ExtraOrbs do
				spawnOrb(positions)
			end
		end

		-- Coins: corners first, then now and then right beside someone's tail
		for _, c in { { 1, 1 }, { -1, -1 }, { 1, -1 }, { -1, 1 } } do
			if ctx.Rng:NextNumber() < 0.75 then
				ctx:SpawnCoin(ctx:At(c[1] * (HALF - 4), 3, c[2] * (HALF - 4)).Position)
			end
		end
		local coinsLeft = 3
		ctx:Every(5, function()
			local segs = {}
			for _, s in snakes do
				if not s.Dead then
					for _, seg in s.Segs do
						table.insert(segs, seg)
					end
				end
			end
			if #segs >= 6 then
				-- floating over a tail: reachable, but only from right beside it
				local seg = segs[ctx.Rng:NextInteger(1, #segs)]
				ctx:SpawnCoin(ctx.Origin * Vector3.new(seg.Mid.X, 5.2, seg.Mid.Z))
				coinsLeft -= 1
			end
			return coinsLeft > 0
		end)

		ctx:Announce(`EAT {quota} ORBS!`, ORB_COLOR)

		-- Main loop -----------------------------------------------------------------------
		local hurried = false
		ctx:Heartbeat(function()
			local now = os.clock()
			local aliveNow = ctx:GetAlive()
			local aliveSet = {}
			for _, player in aliveNow do
				aliveSet[player] = true
			end
			for player, snake in snakes do
				if not snake.Dead and not aliveSet[player] then
					dissolve(ctx, snake)
				end
			end

			local positions = {}
			for _, player in aliveNow do
				local pos = ctx:LocalPosition(player)
				if pos and snakes[player] then
					positions[player] = pos
				end
			end

			-- Lay crumbs along each path and slide the tails
			for player, pos in positions do
				local snake = snakes[player]
				if math.abs(pos.X) > HALF + 1 or math.abs(pos.Z) > HALF + 1 or pos.Y < -6 then
					continue
				end
				local flat = Vector3.new(pos.X, 0, pos.Z)
				local last = snake.Last
				local added = false
				if not last or (flat - last).Magnitude > TELEPORT then
					snake.Count += 1
					snake.Crumbs[snake.Count] = flat
					snake.Breaks[snake.Count] = true
					snake.Last = flat
					added = true
				else
					local delta = flat - last
					local dist = delta.Magnitude
					if dist >= SPACING then
						local dir = delta / dist
						while dist >= SPACING do
							last += dir * SPACING
							snake.Count += 1
							snake.Crumbs[snake.Count] = last
							dist -= SPACING
						end
						snake.Last = last
						added = true
					end
				end
				if added then
					advance(ctx, snake, now, positions)
				end
			end

			-- Tail hits: feet within HIT_R of a lethal segment and below its top
			for player, pos in positions do
				local feet = ctx:FeetY(player)
				if not feet or feet >= SEG_H - FORGIVE or feet < -4 then
					continue
				end
				local hitBy: Player? = nil
				for owner, s in snakes do
					if s.Dead then
						continue
					end
					local own = owner == player
					local last = if own then s.TailEnd - SELF_SAFE else s.TailEnd
					for j = s.TailStart, last do
						local seg = s.Segs[j]
						if not seg or (not own and now < seg.TailAt + ARM) then
							continue
						end
						local immune = seg.Immune[player]
						if not immune and (math.abs(pos.X - seg.Mid.X) > SPACING / 2 + HIT_R + 0.1 or math.abs(pos.Z - seg.Mid.Z) > SPACING / 2 + HIT_R + 0.1) then
							continue
						end
						local dist = distToSeg(pos.X, pos.Z, seg.A, seg.B)
						if immune then
							if dist > HIT_R + 0.6 then
								seg.Immune[player] = nil
							end
						elseif dist <= HIT_R then
							hitBy = owner
							break
						end
					end
					if hitBy then
						break
					end
				end
				if hitBy then
					ctx:Eliminate(player, if hitBy == player then "Bit your own tail" else `Hit {hitBy.DisplayName}'s tail`)
				end
			end

			-- Orb pickups
			for player, pos in positions do
				if not aliveSet[player] or pos.Y > ORB_Y + 7 or pos.Y < -3 then
					continue
				end
				for k = #orbs, 1, -1 do
					local orb = orbs[k]
					local dx, dz = pos.X - orb.Pos.X, pos.Z - orb.Pos.Z
					if dx * dx + dz * dz <= PICK_R * PICK_R then
						table.remove(orbs, k)
						eat(snakes[player], orb)
					end
				end
			end

			if not hurried and ctx:Remaining() <= 6 then
				hurried = true
				for player in positions do
					if snakes[player].Eaten < quota then
						ctx:Announce("6 SECONDS LEFT!", ctx.Theme.Hazard)
						ctx:Sound("Countdown")
						break
					end
				end
			end
		end)

		-- Keep the field stocked (alive + ExtraOrbs)
		ctx:Every(0.3, function()
			local target = #ctx:GetAlive() + p.ExtraOrbs
			if #orbs < target then
				spawnOrb(positionsNow())
			end
			return true
		end)
	end,

	Judge = function(ctx)
		local snakes = ctx.State.Snakes or {}
		local quota = ctx.State.Quota or 0
		for _, player in ctx:GetAlive() do
			local snake = snakes[player]
			if not snake or snake.Eaten < quota then
				ctx:Eliminate(player, "Not enough orbs")
			end
		end
	end,
}
