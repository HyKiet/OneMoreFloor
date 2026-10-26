-- Pop Quiz: the arena floor IS the answer sheet. A big screen asks a quick, language-light question (maths,
-- counting cubes, ink colour, biggest number); stand on the platform with the right answer before the timer
-- bar runs out. The wrong platforms drop into the pit, then rise again for the next question.
-- Judged on position one round trip after the deadline (latency fair). The gaps between platforms are holes
-- and the glowing dividers in them have no collision, so there is nowhere to sit out a question.

local PLAT_W = 13
local GAP = 1.5
local PITCH = PLAT_W + GAP
local DEPTH = 16 -- platform depth along Z
local HALF_D = DEPTH / 2
local SCREEN_Z = -HALF_D - 7
local SCREEN_W, SCREEN_H = 46, 13
local SCREEN_Y = 9
local CUBE_Z = SCREEN_Z + 2.6

local INK = {
	{ Name = "RED", Color = Color3.fromRGB(220, 40, 50) },
	{ Name = "BLUE", Color = Color3.fromRGB(40, 100, 235) },
	{ Name = "GREEN", Color = Color3.fromRGB(35, 180, 70) },
	{ Name = "YELLOW", Color = Color3.fromRGB(235, 195, 25) },
	{ Name = "PURPLE", Color = Color3.fromRGB(145, 60, 225) },
}
local CUBE_COLOURS = {
	Color3.fromRGB(70, 190, 215),
	Color3.fromRGB(215, 95, 170),
	Color3.fromRGB(215, 175, 60),
	Color3.fromRGB(110, 205, 120),
}
local WHITE = Color3.fromRGB(245, 240, 230)

local function plan(ctx)
	local d = math.clamp(ctx.Difficulty, 0, 1.5)
	local m = math.min(d, 1)
	local over = math.max(d - 1, 0)
	return {
		Platforms = if d >= 0.6 then 4 else 3,
		Rounds = if d >= 0.6 then 4 else 3,
		Window = math.max(5.5 - 2.0 * m - 0.4 * over, 3.1), -- seconds to answer (cubes included)
		CubeShow = math.max(2.4 - 0.85 * m - 0.2 * over, 1.3),
		D = d,
	}
end

local INTRO = 0.8
local DROP_AT = 0.2 -- after the deadline
local OUT_AT = 0.65 -- doomed players are out by now (they are falling)
local RISE_AT = 1.5
local RISE_TIME = 0.5
local NEXT_AT = RISE_AT + RISE_TIME + 0.1

-- Theme colours for neon trims, capped below full brightness (bright theme colours glare under bloom).
local function palette(ctx)
	local function soft(c: Color3): Color3
		local h, sat, v = c:ToHSV()
		return Color3.fromHSV(h, sat, math.min(v, if sat < 0.25 then 0.7 else 0.8))
	end
	local h, sat, v = ctx.Theme.Primary:ToHSV()
	return {
		Primary = soft(ctx.Theme.Primary),
		Secondary = soft(ctx.Theme.Secondary),
		Hazard = soft(ctx.Theme.Hazard),
		-- platform edges fill the view when you stand on one: dimmer than the text colours
		Trim = Color3.fromHSV(h, sat, math.min(v, 0.6)),
	}
end

local function platX(p, i: number): number
	return (i - (p.Platforms + 1) / 2) * PITCH
end

local function lag(player: Player): number
	local ok, ping = pcall(player.GetNetworkPing, player)
	return math.clamp((if ok and typeof(ping) == "number" then ping else 0.1) + 0.04, 0.04, 0.35)
end

-- Platform under a player (gaps are split down the middle), or nil.
local function platformOf(ctx, p, player): number?
	local pos = ctx:LocalPosition(player)
	local feet = ctx:FeetY(player)
	if not pos or not feet or feet < -3 then
		return nil
	end
	if math.abs(pos.Z) > HALF_D + 0.75 then
		return nil
	end
	local i = math.floor((pos.X - platX(p, 1)) / PITCH + 0.5) + 1
	if i < 1 or i > p.Platforms then
		return nil
	end
	if math.abs(pos.X - platX(p, i)) > PLAT_W / 2 + GAP / 2 then
		return nil
	end
	return i
end

-- Question generators ----------------------------------------------------------------------------------
-- Each returns { Kind, Title, Main, MainColor?, Answers = { { Text, Color? } }, Correct } with the right
-- answer first; the caller shuffles the platforms.

local function shuffle(rng: Random, list)
	for k = #list, 2, -1 do
		local r = rng:NextInteger(1, k)
		list[k], list[r] = list[r], list[k]
	end
	return list
end

-- answer + (count - 1) distinct distractors taken from `pool` in order of preference groups
local function withDistractors(rng: Random, answer: number, groups: { { number } }, count: number, minValue: number)
	local values = { answer }
	local used = { [answer] = true }
	for _, group in groups do
		shuffle(rng, group)
		for _, v in group do
			if #values >= count then
				break
			end
			if v >= minValue and not used[v] then
				used[v] = true
				table.insert(values, v)
			end
		end
	end
	local spread = 3
	while #values < count do -- fallback, never needed in practice
		local v = answer + spread
		if not used[v] then
			used[v] = true
			table.insert(values, v)
		end
		spread += 1
	end
	return values
end

local function textAnswers(values)
	local list = {}
	for _, v in values do
		table.insert(list, { Text = tostring(v) })
	end
	return list
end

local function maths(rng: Random, p, count: number)
	local d = p.D
	local roll = rng:NextNumber()
	local a, b, op, ans
	if d < 0.3 then
		if roll < 0.55 then
			a, b, op = rng:NextInteger(2, 9), rng:NextInteger(2, 9), "+"
		else
			a, b, op = rng:NextInteger(9, 18), rng:NextInteger(2, 8), "-"
		end
	elseif d < 0.65 then
		if roll < 0.4 then
			a, b, op = rng:NextInteger(12, 39), rng:NextInteger(4, 19), "+"
		elseif roll < 0.75 then
			a, b, op = rng:NextInteger(21, 50), rng:NextInteger(4, 19), "-"
		else
			a, b, op = rng:NextInteger(2, 6), rng:NextInteger(3, 9), "×"
		end
	else
		if roll < 0.5 then
			a, b, op = rng:NextInteger(3, 9), rng:NextInteger(4, 9), "×"
		elseif roll < 0.75 then
			a, b, op = rng:NextInteger(25, 79), rng:NextInteger(15, 49), "+"
		else
			a, b, op = rng:NextInteger(40, 95), rng:NextInteger(15, 39), "-"
		end
	end
	local groups
	if op == "+" then
		ans = a + b
		groups = { { ans - 1, ans + 1, ans + 2, ans - 2 }, { ans + 10, ans - 10 } }
	elseif op == "-" then
		ans = a - b
		groups = { { ans - 1, ans + 1, ans + 2, ans - 2 }, { ans + 10, ans - 10 } }
	else
		ans = a * b
		groups = { { (a - 1) * b, (a + 1) * b, a * (b - 1), a * (b + 1) }, { ans + 1, ans - 1, ans + 10 } }
	end
	return {
		Kind = "Maths",
		Title = "QUICK MATHS!",
		Main = string.format("%d %s %d = ?", a, op, b),
		Answers = textAnswers(withDistractors(rng, ans, groups, count, 0)),
	}
end

local function cubes(rng: Random, p, count: number)
	local d = p.D
	local n = if d < 0.35 then rng:NextInteger(3, 7) elseif d < 0.75 then rng:NextInteger(5, 9) else rng:NextInteger(7, 12)
	local values = withDistractors(rng, n, { { n - 1, n + 1 }, { n - 2, n + 2 } }, count, 1)
	return {
		Kind = "Cubes",
		Title = "HOW MANY CUBES?",
		Main = "",
		Count = n,
		Answers = textAnswers(values),
	}
end

local function stroop(rng: Random, _p, count: number)
	local order = shuffle(rng, { 1, 2, 3, 4, 5 })
	local word, ink = INK[order[1]], INK[order[2]]
	-- the right answer is the ink; the written word is always one of the traps
	local answers = { { Text = ink.Name, Color = ink.Color }, { Text = word.Name, Color = word.Color } }
	for k = 3, count do
		local c = INK[order[k]]
		table.insert(answers, { Text = c.Name, Color = c.Color })
	end
	return {
		Kind = "Stroop",
		Title = "WHAT COLOUR IS THE INK?",
		Main = word.Name,
		MainColor = ink.Color,
		Answers = answers,
	}
end

-- All arrangements of `len` digits taken from `digits` (no leading zero).
local function arrangements(digits: { number }, len: number): { number }
	local out = {}
	local function go(prefix: number, used: { boolean }, depth: number)
		if depth == len then
			table.insert(out, prefix)
			return
		end
		for k, digit in digits do
			if not used[k] and not (depth == 0 and digit == 0) then
				used[k] = true
				go(prefix * 10 + digit, used, depth + 1)
				used[k] = false
			end
		end
	end
	go(0, {}, 0)
	return out
end

local function biggest(rng: Random, p, count: number)
	local d = p.D
	local pool = shuffle(rng, { 1, 2, 3, 4, 5, 6, 7, 8, 9 })
	local digits, len
	if d < 0.35 then
		digits, len = { pool[1], pool[2], pool[3] }, 2
	elseif d < 0.75 then
		digits, len = { pool[1], pool[2], if rng:NextNumber() < 0.5 then 0 else pool[3] }, 3
	else
		digits, len = { pool[1], pool[2], pool[3], if rng:NextNumber() < 0.5 then 0 else pool[4] }, 4
	end
	local candidates = shuffle(rng, arrangements(digits, len))
	local smallest = d >= 0.5 and rng:NextNumber() < 0.4
	local values = {}
	for k = 1, count do
		values[k] = candidates[k]
	end
	local best = 1
	for k, v in values do
		if (smallest and v < values[best]) or (not smallest and v > values[best]) then
			best = k
		end
	end
	values[1], values[best] = values[best], values[1]
	return {
		Kind = "Biggest",
		Title = if smallest then "FIND THE SMALLEST NUMBER" else "FIND THE BIGGEST NUMBER",
		Main = if smallest then "SMALLEST?" else "BIGGEST?",
		Answers = textAnswers(values),
	}
end

local GENERATORS = { Maths = maths, Cubes = cubes, Stroop = stroop, Biggest = biggest }

return {
	Id = "PopQuiz",
	Name = "Pop Quiz",
	Hint = "Read the question on the big screen, then stand on the right answer before the floor drops!",
	MinFloor = 1,
	MinPlayers = 1,
	Weight = 1,
	BossOnly = false,
	Zone = 1, -- B1-B9
	Duration = function(ctx)
		local p = plan(ctx)
		return INTRO + p.Rounds * (p.Window + NEXT_AT) + 0.2
	end,

	Build = function(ctx)
		local p = plan(ctx)
		local C = palette(ctx)
		local dark = ctx.Theme.Floor:Lerp(Color3.new(0, 0, 0), 0.45)
		local plainTop = ctx.Theme.Floor:Lerp(C.Primary, 0.14)

		-- Answer platforms: each a welded assembly (trims, number plate, back sign) that can drop as one
		local platforms = {}
		for i = 1, p.Platforms do
			local x = platX(p, i)
			local home = ctx:At(x, -1, 0)
			local plat = ctx:Part({ Name = "Answer", Size = Vector3.new(PLAT_W, 2, DEPTH), CFrame = home, Color = plainTop })
			local function weld(part: BasePart): BasePart
				part.Anchored = false
				local w = Instance.new("WeldConstraint")
				w.Part0 = plat
				w.Part1 = part
				w.Parent = part
				return part
			end
			local trims = {}
			for _, s in { { 0, -HALF_D + 0.15, PLAT_W, 0.3 }, { 0, HALF_D - 0.15, PLAT_W, 0.3 }, { -PLAT_W / 2 + 0.15, 0, 0.3, DEPTH - 0.6 }, { PLAT_W / 2 - 0.15, 0, 0.3, DEPTH - 0.6 } } do
				table.insert(trims, weld(ctx:Decor({ Name = "Trim", Size = Vector3.new(s[3], 0.06, s[4]), CFrame = ctx:At(x + s[1], 0.03, s[2]), Color = C.Trim, Material = Enum.Material.Neon, Transparency = 0.25 })))
			end
			weld(ctx:Decor({ Name = "Underglow", Size = Vector3.new(PLAT_W - 0.8, 0.25, DEPTH - 0.8), CFrame = ctx:At(x, -2.15, 0), Color = C.Secondary, Material = Enum.Material.Neon, Transparency = 0.35 }))
			-- big answer text on the top face (turned so it reads upright for players facing the screen)
			local plate = weld(ctx:Decor({ Name = "AnswerPlate", Size = Vector3.new(DEPTH - 6, 0.04, PLAT_W - 2), CFrame = ctx:At(x, 0.09, 0.6, 0, -90, 0), Transparency = 1 }))
			local top = ctx:Sign(plate, "", { Face = Enum.NormalId.Top, TextStrokeTransparency = 0.35, TextStrokeColor3 = Color3.fromRGB(10, 10, 16), PixelsPerStud = 16 })
			-- small upright sign at the back edge, facing the players
			local board = weld(ctx:Decor({ Name = "AnswerSign", Size = Vector3.new(7, 2.2, 0.3), CFrame = ctx:At(x, 1.8, -HALF_D + 0.5, 0, 180, 0), Color = Color3.fromRGB(16, 16, 24) }))
			local signText = ctx:Sign(board, "", { TextColor3 = WHITE })
			weld(ctx:Decor({ Name = "SignPost", Size = Vector3.new(0.3, 0.7, 0.3), CFrame = ctx:At(x, 0.35, -HALF_D + 0.5), Color = dark }))
			table.insert(platforms, { Part = plat, Home = home, Trims = trims, Top = top, Sign = signText, Board = board, X = x, PlainTop = plainTop })
		end
		ctx.State.Platforms = platforms

		-- Glowing dividers in the gaps (no collision: the gaps are holes)
		for i = 1, p.Platforms - 1 do
			local x = (platX(p, i) + platX(p, i + 1)) / 2
			ctx:Decor({ Name = "Divider", Size = Vector3.new(0.2, 0.8, DEPTH), CFrame = ctx:At(x, -1.6, 0), Color = C.Secondary, Material = Enum.Material.Neon, Transparency = 0.35 })
		end
		-- The pit far below
		local span = p.Platforms * PITCH + 8
		ctx:Decor({ Name = "PitGlow", Size = Vector3.new(span, 0.5, DEPTH + 16), CFrame = ctx:At(0, -26, 0), Color = C.Hazard, Material = Enum.Material.Neon, Transparency = 0.6 })
		for k = -2, 2 do
			ctx:Decor({ Name = "PitLine", Size = Vector3.new(0.4, 0.4, DEPTH + 16), CFrame = ctx:At(k * span / 5, -25.6, 0), Color = C.Hazard:Lerp(Color3.new(0, 0, 0), 0.2), Material = Enum.Material.Neon })
		end

		-- The big screen on the far side: title line, main line, seconds left, and a timer bar under it
		local screen = ctx:Part({ Name = "Screen", Size = Vector3.new(SCREEN_W, SCREEN_H, 1), CFrame = ctx:At(0, SCREEN_Y, SCREEN_Z, 0, 180, 0), Color = Color3.fromRGB(14, 14, 22) })
		ctx.State.Title = ctx:Sign(screen, "POP QUIZ", { TextColor3 = C.Secondary, Size = UDim2.fromScale(0.8, 0.22), Position = UDim2.fromScale(0.1, 0.72), PixelsPerStud = 16 })
		ctx.State.Main = ctx:Sign(screen, "GET READY!", { TextColor3 = WHITE, Size = UDim2.fromScale(0.86, 0.6), Position = UDim2.fromScale(0.05, 0.07), PixelsPerStud = 16 })
		ctx.State.Clock = ctx:Sign(screen, "", { TextColor3 = C.Hazard, Size = UDim2.fromScale(0.08, 0.2), Position = UDim2.fromScale(0.9, 0.05), PixelsPerStud = 16 })
		local frontZ = SCREEN_Z + 0.55
		for _, s in { { 0, SCREEN_H / 2, SCREEN_W + 0.6, 0.3 }, { 0, -SCREEN_H / 2, SCREEN_W + 0.6, 0.3 }, { -SCREEN_W / 2, 0, 0.3, SCREEN_H }, { SCREEN_W / 2, 0, 0.3, SCREEN_H } } do
			ctx:Decor({ Name = "ScreenTrim", Size = Vector3.new(s[3], s[4], 0.2), CFrame = ctx:At(s[1], SCREEN_Y + s[2], frontZ), Color = C.Primary, Material = Enum.Material.Neon, Transparency = 0.3 })
		end
		ctx:Part({ Name = "ScreenBack", Size = Vector3.new(SCREEN_W + 2, SCREEN_H + 2, 1), CFrame = ctx:At(0, SCREEN_Y, SCREEN_Z - 0.9), Color = ctx.Theme.Floor:Lerp(C.Primary, 0.2) })
		for _, side in { -1, 1 } do
			ctx:Part({ Name = "ScreenLeg", Size = Vector3.new(2, SCREEN_Y + 26, 2), CFrame = ctx:At(side * (SCREEN_W / 2 - 4), (SCREEN_Y - 26) / 2, SCREEN_Z - 1.6), Color = ctx.Theme.Floor:Lerp(C.Primary, 0.12) })
		end
		local barY = SCREEN_Y - SCREEN_H / 2 - 1.1
		local barW = SCREEN_W - 2
		ctx.State.BarLeft = ctx:At(-barW / 2, barY, frontZ)
		ctx.State.BarW = barW
		ctx:Decor({ Name = "BarTrack", Size = Vector3.new(barW + 0.4, 0.9, 0.3), CFrame = ctx:At(0, barY, frontZ - 0.25), Color = dark })
		ctx.State.Bar = ctx:Decor({ Name = "TimerBar", Size = Vector3.new(barW, 0.5, 0.3), CFrame = ctx:At(0, barY, frontZ), Color = C.Secondary, Material = Enum.Material.Neon })
		ctx:Glow(ctx:Decor({ Name = "ScreenLamp", Size = Vector3.new(1, 1, 1), CFrame = ctx:At(0, SCREEN_Y, SCREEN_Z + 6), Transparency = 1 }), C.Primary, 30, 0.6)

		-- Start on the middle platform(s), facing the screen
		local spawns = {}
		local starts = if p.Platforms == 3 then { 2 } else { 2, 3 }
		for k = 0, 7 do
			local i = starts[(k % #starts) + 1]
			local slot = math.floor(k / #starts)
			local per = 8 / #starts
			local col = slot % (per / 2)
			local row = math.floor(slot / (per / 2))
			local ox = if per == 8 then -4.5 + col * 3 else -3 + col * 6
			local x, z = platX(p, i) + ox, 2.5 + row * 3
			table.insert(spawns, CFrame.lookAt(ctx:At(x, 3, z).Position, ctx:At(x, 3, SCREEN_Z).Position))
		end
		ctx:SetSpawns(spawns)
	end,

	Start = function(ctx)
		local p = plan(ctx)
		local C = palette(ctx)
		local rng = ctx.Rng
		local platforms = ctx.State.Platforms
		local bar = ctx.State.Bar

		-- Question order: no repeats until every kind has been asked
		local kinds = shuffle(rng, { "Maths", "Cubes", "Stroop", "Biggest" })
		if p.Rounds > #kinds then
			table.insert(kinds, kinds[rng:NextInteger(1, 3)])
		end

		ctx.State.Title.Text = "POP QUIZ"
		ctx.State.Main.Text = "GET READY!"
		ctx:Announce("POP QUIZ!", C.Secondary)
		if not ctx:Wait(INTRO) then
			return
		end

		for round = 1, p.Rounds do
			local q = GENERATORS[kinds[round]](rng, p, p.Platforms)
			-- shuffle the answers onto the platforms; remember where the right one went
			local order = {}
			for k = 1, #q.Answers do
				order[k] = k
			end
			shuffle(rng, order)
			local correct = table.find(order, 1)
			ctx.State.Correct = correct -- (tests read this)
			for i, plat in platforms do
				local a = q.Answers[order[i]]
				plat.Top.Text = a.Text
				plat.Sign.Text = a.Text
				if a.Color then
					plat.Part.Color = a.Color
					plat.Board.Color = a.Color:Lerp(Color3.new(0, 0, 0), 0.35)
				else
					plat.Part.Color = plat.PlainTop
					plat.Board.Color = Color3.fromRGB(16, 16, 24)
				end
				for _, trim in plat.Trims do
					trim.Color = C.Trim
				end
			end
			ctx.State.Title.Text = q.Title
			ctx.State.Main.Text = q.Main
			ctx.State.Main.TextColor3 = q.MainColor or WHITE
			ctx:Sound("Click")
			ctx:Fx("Burst", { Position = ctx:At(0, SCREEN_Y, SCREEN_Z + 1).Position, Color = C.Secondary, Count = 20 })

			-- A coin on a random platform's far end: grab it if you dare, then get back to your answer
			local coinPlat = platforms[rng:NextInteger(1, #platforms)]
			ctx:SpawnCoin(ctx:At(coinPlat.X + rng:NextNumber(-4, 4), 3, -HALF_D + 2.5).Position)

			-- Cubes pop up in front of the screen for a moment
			if q.Kind == "Cubes" then
				local cells = {}
				for col = 1, 6 do
					for row = 1, 3 do
						table.insert(cells, { -17.5 + (col - 1) * 7, SCREEN_Y - 1.2 + (row - 1) * 2.9 })
					end
				end
				shuffle(rng, cells)
				local parts, positions = {}, {}
				for k = 1, q.Count do
					local cell = cells[k]
					local pos = ctx:At(cell[1] + rng:NextNumber(-0.8, 0.8), cell[2] + rng:NextNumber(-0.3, 0.3), CUBE_Z)
					local cube = ctx:Decor({ Name = "QuizCube", Size = Vector3.new(2, 2, 2), CFrame = pos * CFrame.Angles(rng:NextNumber(-0.5, 0.5), rng:NextNumber(0, 1.5), rng:NextNumber(-0.5, 0.5)), Color = CUBE_COLOURS[rng:NextInteger(1, #CUBE_COLOURS)], Material = Enum.Material.SmoothPlastic })
					table.insert(parts, cube)
					table.insert(positions, pos.Position)
				end
				ctx:Sound("Whoosh")
				ctx:After(p.CubeShow, function()
					for _, cube in parts do
						cube:Destroy()
					end
					ctx:Fx("Chunks", { Positions = positions, Color = C.Secondary, Size = 0.8 })
					ctx:Sound("Click")
				end)
				ctx.Trove:Add(function()
					for _, cube in parts do
						cube:Destroy()
					end
				end)
			end

			-- Timer bar drains left to right over the answer window
			bar.Size = Vector3.new(ctx.State.BarW, 0.5, 0.3)
			bar.CFrame = ctx.State.BarLeft * CFrame.new(ctx.State.BarW / 2, 0, 0)
			bar.Color = C.Secondary
			ctx:Tween(bar, TweenInfo.new(p.Window, Enum.EasingStyle.Linear), {
				Size = Vector3.new(0.05, 0.5, 0.3),
				CFrame = ctx.State.BarLeft * CFrame.new(0.025, 0, 0),
				Color = C.Hazard,
			})
			local deadline = os.clock() + p.Window
			local beeped = false
			while os.clock() < deadline - 0.02 do
				local left = deadline - os.clock()
				ctx.State.Clock.Text = tostring(math.ceil(left - 0.02))
				if left <= 2 and not beeped then
					beeped = true
					ctx:Sound("Countdown")
				end
				if not ctx:Wait(math.min(0.1, left)) then
					return
				end
			end
			ctx.State.Clock.Text = ""

			-- Time! Judge one round trip later; wrong platforms drop
			local doomed = {}
			for _, player in ctx:GetAlive() do
				task.delay(lag(player), function()
					if ctx.Ended then
						return
					end
					local on = platformOf(ctx, p, player)
					if on ~= correct then
						doomed[player] = true
					end
				end)
			end
			local right = q.Answers[1]
			ctx.State.Title.Text = "ANSWER"
			ctx.State.Main.Text = right.Text
			ctx.State.Main.TextColor3 = right.Color or C.Secondary
			if not ctx:Wait(DROP_AT) then
				return
			end
			for i, plat in platforms do
				if i == correct then
					for _, trim in plat.Trims do
						trim.Color = C.Secondary
					end
					ctx:Fx("Burst", { Position = ctx:At(plat.X, 1.5, 0).Position, Color = C.Secondary, Count = 30 })
				else
					for _, trim in plat.Trims do
						trim.Color = C.Hazard
					end
					plat.Part.CanCollide = false
					ctx:Tween(plat.Part, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = plat.Home * CFrame.new(0, -22, 0) })
				end
			end
			ctx:Sound("Impact")
			ctx:Shake(0.4, 0.35)
			if not ctx:Wait(OUT_AT - DROP_AT) then
				return
			end
			local anyOut = false
			for player in doomed do
				anyOut = true
				ctx:Eliminate(player, "Wrong answer!")
			end
			if not anyOut then
				ctx:Sound("Coin")
			end
			if not ctx:Wait(RISE_AT - OUT_AT) then
				return
			end

			-- Platforms come back up for the next question
			for i, plat in platforms do
				if i ~= correct then
					ctx:Tween(plat.Part, TweenInfo.new(RISE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = plat.Home })
					ctx:After(RISE_TIME + 0.02, function()
						plat.Part.CanCollide = true
					end)
				end
			end
			if round < p.Rounds then
				ctx.State.Title.Text = "NEXT QUESTION..."
				ctx.State.Main.Text = ""
			end
			if not ctx:Wait(NEXT_AT - RISE_AT) then
				return
			end
		end
		ctx.State.Title.Text = "CLASS DISMISSED!"
		ctx.State.Main.Text = "A+"
		ctx.State.Main.TextColor3 = C.Secondary
		ctx:Finish()
	end,
}
