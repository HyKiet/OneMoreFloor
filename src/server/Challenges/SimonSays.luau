-- Simon Says: a giant host head barks orders (jump, go to a colour, stand in / leave the middle). Only obey
-- the ones that start with "SIMON SAYS". Follow a trick order and you're zapped; miss a real one and you're
-- zapped too, so standing still is not safe either.
-- Judging is position based and latency fair: each player's window starts one round trip after the order
-- (when their reaction can first reach the server) and real orders are checked at the end of that window.
-- Trick orders allow a short reaction grace (stopping a move already under way is fine).

local R = 26 -- floor radius
local MID_R = 6 -- neutral centre circle
local SIMON_Z = -40
local PANEL_Z = -30.5
local SLICES = 6 -- wedge triangles per quadrant

local QUADS = {
	{ Name = "RED", Color = Color3.fromRGB(200, 50, 60), Sx = -1, Sz = -1 },
	{ Name = "BLUE", Color = Color3.fromRGB(45, 95, 215), Sx = 1, Sz = -1 },
	{ Name = "GREEN", Color = Color3.fromRGB(40, 165, 80), Sx = -1, Sz = 1 },
	{ Name = "YELLOW", Color = Color3.fromRGB(220, 180, 40), Sx = 1, Sz = 1 },
}
local WHITE = Color3.fromRGB(245, 240, 230)

local JUMP_FEET = 1.5 -- feet this high = jumping
local GROUND_FEET = 0.6 -- feet this low = on the ground
local REACT = 0.35 -- trick orders: reaction grace after the order reaches you
local SLACK = 0.6 -- region tests: lenient (+) for "you did it", strict (-) for "you broke a trick"
local LAG_PAD = 0.38 -- the slowest connection's window ends this long after everyone else's
local INTRO = 1.6

local function plan(ctx)
	local d = math.clamp(ctx.Difficulty, 0, 1.5)
	local m = math.min(d, 1)
	local over = math.max(d - 1, 0)
	return {
		Count = 7 + math.floor(3 * m + 0.5) + (if over > 0.15 then 1 else 0),
		Window = math.max(2.4 - 0.9 * m - 0.15 * over, 1.35),
		Gap = 0.55 - 0.15 * m,
		Trick = math.min(0.2 + 0.2 * m + 0.05 * over, 0.45),
		Combo = d >= 0.55, -- "JUMP ON BLUE"
		Decoys = d >= 0.5, -- tricks get a fake first line ("QUICK!") instead of a blank one
		D = d,
	}
end

-- Theme colours for neon trims, capped below full brightness (bright theme colours glare under bloom).
local function palette(ctx)
	local function soft(c: Color3): Color3
		local h, sat, v = c:ToHSV()
		return Color3.fromHSV(h, sat, math.min(v, if sat < 0.25 then 0.7 else 0.8))
	end
	return { Primary = soft(ctx.Theme.Primary), Secondary = soft(ctx.Theme.Secondary), Hazard = soft(ctx.Theme.Hazard) }
end

local function lag(player: Player): number
	local ok, ping = pcall(player.GetNetworkPing, player)
	return math.clamp((if ok and typeof(ping) == "number" then ping else 0.1) + 0.04, 0.04, 0.35)
end

local function radius(pos: Vector3): number
	return math.sqrt(pos.X * pos.X + pos.Z * pos.Z)
end

local function inQuad(pos: Vector3, q, slack: number): boolean
	local r = radius(pos)
	if r < MID_R - slack or r > R + 1 then
		return false
	end
	return pos.X * q.Sx >= -slack and pos.Z * q.Sz >= -slack
end

local function inMiddle(pos: Vector3, slack: number): boolean
	return radius(pos) <= MID_R + slack
end

-- Flat triangle O-A-B (arena-local, y = 0 top) from two wedges split along the altitude from O.
local function triangle(ctx, o: Vector3, a: Vector3, b: Vector3, color: Color3)
	local mid = (a + b) / 2
	for _, tip in { a, b } do
		local h = (tip - mid).Magnitude
		local l = (o - mid).Magnitude
		local yAxis = (tip - mid).Unit
		local zAxis = (mid - o).Unit
		local xAxis = yAxis:Cross(zAxis)
		local centre = mid + yAxis * (h / 2) - zAxis * (l / 2) + Vector3.new(0, -0.5, 0)
		ctx:Part({ ClassName = "WedgePart", Name = "Quadrant", Size = Vector3.new(1, h, l), CFrame = ctx.Origin * CFrame.fromMatrix(centre, xAxis, yAxis, zAxis), Color = color })
	end
end

-- The order card: a small panel under the HUD that shows the current order to each player wherever they look.
local function makeCard(player: Player, C)
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return nil
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "OMF_SimonSays"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 4
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.fromScale(0.5, 0.165)
	frame.Size = UDim2.fromScale(0.4, 0.14)
	frame.BackgroundColor3 = Color3.fromRGB(12, 12, 20)
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel = 0
	frame.Parent = gui
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = 4.4
	ratio.Parent = frame
	local limit = Instance.new("UISizeConstraint")
	limit.MinSize = Vector2.new(320, 72)
	limit.MaxSize = Vector2.new(720, 164)
	limit.Parent = frame
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.14, 0)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = C.Primary
	stroke.Thickness = 2
	stroke.Parent = frame
	local function label(y: number, h: number, color: Color3): TextLabel
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Position = UDim2.fromScale(0.04, y)
		l.Size = UDim2.fromScale(0.92, h)
		l.Font = Enum.Font.GothamBlack
		l.TextScaled = true
		l.TextColor3 = color
		l.Text = ""
		l.Parent = frame
		return l
	end
	local line1 = label(0.07, 0.28, C.Secondary)
	local line2 = label(0.36, 0.42, WHITE)
	local track = Instance.new("Frame")
	track.Position = UDim2.fromScale(0.06, 0.83)
	track.Size = UDim2.fromScale(0.88, 0.07)
	track.BackgroundColor3 = Color3.fromRGB(40, 40, 52)
	track.BorderSizePixel = 0
	track.Parent = frame
	local bar = Instance.new("Frame")
	bar.Size = UDim2.fromScale(1, 1)
	bar.BackgroundColor3 = C.Secondary
	bar.BorderSizePixel = 0
	bar.Parent = track
	gui.Parent = playerGui
	return { Gui = gui, Line1 = line1, Line2 = line2, Bar = bar, Stroke = stroke }
end

return {
	Id = "SimonSays",
	Name = "Simon Says",
	Hint = "Only obey orders that start with SIMON SAYS. Follow a trick order and you're out!",
	MinFloor = 1,
	MinPlayers = 1,
	Weight = 1,
	BossOnly = false,
	Zone = 2, -- B10-B19
	Duration = function(ctx)
		local p = plan(ctx)
		return INTRO + p.Count * (p.Window + LAG_PAD + p.Gap) + 0.3
	end,

	Build = function(ctx)
		local C = palette(ctx)
		local dark = ctx.Theme.Floor:Lerp(Color3.new(0, 0, 0), 0.45)

		-- Round floor: four coloured quadrants (wedge fans), dividers, a neutral middle and a glowing rim
		ctx:Decor({ Name = "FloorBase", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.9, (R - 0.5) * 2, (R - 0.5) * 2), CFrame = ctx:At(0, -1.45, 0, 0, 0, 90), Color = dark })
		for qi, q in QUADS do
			local a0 = math.atan2(q.Sz, q.Sx) - math.pi / 4
			for s = 0, SLICES - 1 do
				local a1 = a0 + s * (math.pi / 2) / SLICES
				local a2 = a1 + (math.pi / 2) / SLICES
				triangle(ctx, Vector3.zero, Vector3.new(R * math.cos(a1), 0, R * math.sin(a1)), Vector3.new(R * math.cos(a2), 0, R * math.sin(a2)), q.Color)
			end
			-- the colour's name painted in the quadrant (readable while facing Simon)
			local mid = math.atan2(q.Sz, q.Sx)
			local plate = ctx:Decor({ Name = "QuadLabel", Size = Vector3.new(4, 0.04, 11), CFrame = ctx:At(math.cos(mid) * 16.5, 0.06, math.sin(mid) * 16.5, 0, -90, 0), Transparency = 1 })
			ctx:Sign(plate, q.Name, { Face = Enum.NormalId.Top, TextColor3 = WHITE, TextTransparency = 0.1, TextStrokeTransparency = 0.4, TextStrokeColor3 = q.Color:Lerp(Color3.new(0, 0, 0), 0.6), PixelsPerStud = 16 })
			local _ = qi
		end
		ctx:RoundRim(R, C.Primary, C.Secondary)
		for _, dir in { Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) } do
			local len = R - MID_R - 0.5
			local centre = dir * (MID_R + 0.3 + len / 2)
			local size = if dir.X ~= 0 then Vector3.new(len, 0.05, 0.4) else Vector3.new(0.4, 0.05, len)
			ctx:Decor({ Name = "Divider", Size = size, CFrame = ctx:At(centre.X, 0.025, centre.Z), Color = WHITE:Lerp(dark, 0.1), Material = Enum.Material.SmoothPlastic })
		end
		ctx:Part({ Name = "Middle", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, MID_R * 2, MID_R * 2), CFrame = ctx:At(0, -0.14, 0, 0, 0, 90), Color = ctx.Theme.Floor:Lerp(WHITE, 0.35) })
		ctx:Decor({ Name = "MiddleRing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, MID_R * 2 + 0.5, MID_R * 2 + 0.5), CFrame = ctx:At(0, -0.1, 0, 0, 0, 90), Color = C.Primary, Material = Enum.Material.Neon, Transparency = 0.35 })
		local midPlate = ctx:Decor({ Name = "MiddleLabel", Size = Vector3.new(2, 0.04, 7), CFrame = ctx:At(0, 0.2, -3.4, 0, -90, 0), Transparency = 1 })
		ctx:Sign(midPlate, "MIDDLE", { Face = Enum.NormalId.Top, TextColor3 = dark, TextTransparency = 0.35, PixelsPerStud = 16 })

		-- Simon: a pillar, a big box head in a top hat, blinking eyes, angry brows, and a speech panel
		local head = ctx.Theme.Floor:Lerp(C.Primary, 0.28)
		ctx:Part({ Name = "SimonNeck", Size = Vector3.new(7, 13, 7), CFrame = ctx:At(0, 5.5, SIMON_Z), Color = ctx.Theme.Floor:Lerp(C.Primary, 0.15) })
		local skull = ctx:Part({ Name = "SimonHead", Size = Vector3.new(20, 14, 12), CFrame = ctx:At(0, 19, SIMON_Z), Color = head })
		local edges = Instance.new("SelectionBox")
		edges.Adornee = skull
		edges.Color3 = C.Primary
		edges.LineThickness = 0.2
		edges.SurfaceTransparency = 1
		edges.Parent = skull
		local face = SIMON_Z + 6
		local eyes = {}
		for _, side in { -1, 1 } do
			local white = ctx:Decor({ Name = "EyeWhite", Size = Vector3.new(4.6, 4.6, 0.3), CFrame = ctx:At(side * 4.8, 20.5, face + 0.15), Color = Color3.fromRGB(225, 225, 232) })
			local pupil = ctx:Decor({ Name = "Pupil", Size = Vector3.new(1.9, 1.9, 0.2), CFrame = ctx:At(side * 4.8, 20.3, face + 0.4), Color = C.Primary, Material = Enum.Material.Neon })
			local brow = ctx:Decor({ Name = "Brow", Size = Vector3.new(5, 0.8, 0.4), CFrame = ctx:At(side * 4.8, 23.9, face + 0.2), Color = dark })
			table.insert(eyes, { White = white, Pupil = pupil, Brow = brow, Side = side, BrowHome = brow.CFrame, WhiteHome = white.CFrame, PupilHome = pupil.CFrame })
		end
		local mouth = ctx:Decor({ Name = "Mouth", Size = Vector3.new(8, 0.8, 0.2), CFrame = ctx:At(0, 15.2, face + 0.1), Color = C.Secondary, Material = Enum.Material.Neon })
		ctx.State.Eyes = eyes
		ctx.State.Mouth = mouth
		ctx.State.EyeAt = ctx:At(0, 20.5, face + 1).Position
		-- top hat
		ctx:Decor({ Name = "HatBrim", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 15, 15), CFrame = ctx:At(0, 26.3, SIMON_Z, 0, 0, 90), Color = Color3.fromRGB(44, 44, 56) })
		ctx:Decor({ Name = "Hat", Shape = Enum.PartType.Cylinder, Size = Vector3.new(8, 10, 10), CFrame = ctx:At(0, 30.6, SIMON_Z, 0, 0, 90), Color = Color3.fromRGB(52, 52, 66) })
		ctx:Decor({ Name = "HatBand", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.8, 10.2, 10.2), CFrame = ctx:At(0, 27.2, SIMON_Z, 0, 0, 90), Color = C.Secondary, Material = Enum.Material.Neon })
		ctx:Glow(mouth, C.Primary, 28, 0.9)

		-- Speech panel (two lines) with a timer bar under it
		local panel = ctx:Part({ Name = "SpeechPanel", Size = Vector3.new(36, 8.4, 1), CFrame = ctx:At(0, 7.1, PANEL_Z, 0, 180, 0), Color = Color3.fromRGB(14, 14, 22) })
		ctx.State.Line1 = ctx:Sign(panel, "", { TextColor3 = C.Secondary, Size = UDim2.fromScale(0.9, 0.3), Position = UDim2.fromScale(0.05, 0.06), PixelsPerStud = 16 })
		ctx.State.Line2 = ctx:Sign(panel, "SIMON SAYS...", { TextColor3 = WHITE, Size = UDim2.fromScale(0.94, 0.52), Position = UDim2.fromScale(0.03, 0.4), PixelsPerStud = 16 })
		for _, s in { { 0, 4.35, 36.6, 0.3 }, { 0, -4.35, 36.6, 0.3 }, { -18.15, 0, 0.3, 8.4 }, { 18.15, 0, 0.3, 8.4 } } do
			ctx:Decor({ Name = "PanelTrim", Size = Vector3.new(s[3], s[4], 0.2), CFrame = ctx:At(s[1], 7.1 + s[2], PANEL_Z + 0.55), Color = C.Primary, Material = Enum.Material.Neon, Transparency = 0.3 })
		end
		ctx:Decor({ Name = "PanelLeg", Size = Vector3.new(1.4, 30, 1.4), CFrame = ctx:At(-14, -12.1, PANEL_Z - 0.8), Color = dark })
		ctx:Decor({ Name = "PanelLeg", Size = Vector3.new(1.4, 30, 1.4), CFrame = ctx:At(14, -12.1, PANEL_Z - 0.8), Color = dark })
		local barW = 34
		ctx.State.BarLeft = ctx:At(-barW / 2, 2.2, PANEL_Z + 0.6)
		ctx.State.BarW = barW
		ctx.State.Bar = ctx:Decor({ Name = "TimerBar", Size = Vector3.new(barW, 0.45, 0.3), CFrame = ctx:At(0, 2.2, PANEL_Z + 0.6), Color = C.Secondary, Material = Enum.Material.Neon })

		-- Everyone starts in the middle, facing Simon
		local spawns = {}
		for k = 0, 7 do
			local a = k / 8 * math.pi * 2
			local x, z = math.cos(a) * 3.4, math.sin(a) * 3.4
			table.insert(spawns, CFrame.lookAt(ctx:At(x, 3.2, z).Position, ctx:At(x, 3.2, SIMON_Z).Position))
		end
		ctx:SetSpawns(spawns)
	end,

	Start = function(ctx)
		local p = plan(ctx)
		local C = palette(ctx)
		local rng = ctx.Rng
		local S = ctx.State

		-- Order cards for everyone in the challenge (removed when they are out or the floor ends)
		local cards = {}
		for _, player in ctx:GetAlive() do
			cards[player] = makeCard(player, C)
		end
		local function dropCards()
			for player, card in cards do
				card.Gui:Destroy()
				cards[player] = nil
			end
		end
		ctx.Trove:Add(dropCards)
		task.spawn(function() -- the floor can end on the clock mid-order: take the cards down right away
			while not ctx.Ended do
				task.wait(0.2)
			end
			dropCards()
		end)

		local function say(line1: string, line2: string, color2: Color3?, color1: Color3?)
			S.Line1.Text = line1
			S.Line1.TextColor3 = color1 or C.Secondary
			S.Line2.Text = line2
			S.Line2.TextColor3 = color2 or WHITE
			for _, card in cards do
				card.Line1.Text = line1
				card.Line1.TextColor3 = color1 or C.Secondary
				card.Line2.Text = line2
				card.Line2.TextColor3 = color2 or WHITE
			end
		end

		local function runBars(seconds: number)
			S.Bar.Size = Vector3.new(S.BarW, 0.45, 0.3)
			S.Bar.CFrame = S.BarLeft * CFrame.new(S.BarW / 2, 0, 0)
			S.Bar.Color = C.Secondary
			ctx:Tween(S.Bar, TweenInfo.new(seconds, Enum.EasingStyle.Linear), { Size = Vector3.new(0.05, 0.45, 0.3), CFrame = S.BarLeft * CFrame.new(0.025, 0, 0), Color = C.Hazard })
			for _, card in cards do
				card.Bar.Size = UDim2.fromScale(1, 1)
				card.Bar.BackgroundColor3 = C.Secondary
				ctx:Tween(card.Bar, TweenInfo.new(seconds, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.Hazard })
			end
		end

		-- Simon's face: blinks now and then, glares red when someone fails
		local angryUntil = 0
		local function setEyes(color: Color3)
			for _, eye in S.Eyes do
				eye.Pupil.Color = color
			end
		end
		local function glare()
			angryUntil = os.clock() + 0.9
			setEyes(C.Hazard)
			S.Mouth.Color = C.Hazard
			for _, eye in S.Eyes do
				eye.Brow.CFrame = eye.BrowHome * CFrame.new(0, -0.5, 0) * CFrame.Angles(0, 0, math.rad(-18 * eye.Side))
			end
			ctx:After(0.9, function()
				if os.clock() >= angryUntil - 0.01 then
					setEyes(C.Primary)
					S.Mouth.Color = C.Secondary
					for _, eye in S.Eyes do
						eye.Brow.CFrame = eye.BrowHome
					end
				end
			end)
		end
		local function blink()
			for _, eye in S.Eyes do
				ctx:Tween(eye.White, TweenInfo.new(0.07), { Size = Vector3.new(4.6, 0.4, 0.3) })
				ctx:Tween(eye.Pupil, TweenInfo.new(0.07), { Size = Vector3.new(1.9, 0.2, 0.2) })
			end
			ctx:After(0.12, function()
				for _, eye in S.Eyes do
					ctx:Tween(eye.White, TweenInfo.new(0.08), { Size = Vector3.new(4.6, 4.6, 0.3) })
					ctx:Tween(eye.Pupil, TweenInfo.new(0.08), { Size = Vector3.new(1.9, 1.9, 0.2) })
				end
			end)
		end
		local nextBlink = os.clock() + 1.5
		ctx:Every(0.25, function()
			if os.clock() >= nextBlink then
				nextBlink = os.clock() + rng:NextNumber(1.8, 3.6)
				blink()
			end
			return true
		end)

		local function isAlive(player: Player): boolean
			return table.find(ctx:GetAlive(), player) ~= nil
		end

		local function zap(player: Player, reason: string)
			local root = ctx:GetRoot(player)
			if root then
				ctx:Fx("Shot", { From = S.EyeAt, To = root.Position, Color = C.Hazard })
				ctx:Impact(root.Position, C.Hazard, 7, 5)
			end
			ctx:Sound("Laser")
			glare()
			local card = cards[player]
			if card then
				card.Gui:Destroy()
				cards[player] = nil
			end
			ctx:Eliminate(player, reason)
		end

		-- Live judging of the current order
		local active = nil
		local function regionIn(o, pos: Vector3, slack: number): boolean
			if o.Kind == "Go" or o.Kind == "JumpOn" then
				return inQuad(pos, o.Quad, slack)
			elseif o.Kind == "Middle" or o.Kind == "Leave" then
				return inMiddle(pos, slack)
			end
			return false
		end
		local function passReal(o, st, pos: Vector3, feet: number): boolean
			if feet < -3 or radius(pos) > R + 1.5 then
				return false
			end
			if o.Kind == "Jump" then
				return st.Done == true
			elseif o.Kind == "Go" then
				return inQuad(pos, o.Quad, SLACK)
			elseif o.Kind == "Middle" then
				return inMiddle(pos, SLACK)
			elseif o.Kind == "Leave" then
				return radius(pos) >= MID_R - SLACK
			else -- JumpOn
				return st.Done == true and inQuad(pos, o.Quad, SLACK)
			end
		end
		ctx:Heartbeat(function()
			local o = active
			if not o then
				return
			end
			local now = os.clock()
			for player, st in o.States do
				if st.Judged then
					continue
				end
				if not isAlive(player) then
					st.Judged = true
					continue
				end
				local rel = now - o.T0 - st.Lag
				if rel < 0 then
					continue
				end
				local pos = ctx:LocalPosition(player)
				local feet = ctx:FeetY(player)
				if not pos or not feet then
					continue
				end
				local air = feet > JUMP_FEET
				if feet < GROUND_FEET then
					st.LastGround = rel
				end
				if o.Real then
					if air and (o.Kind == "Jump" or (o.Kind == "JumpOn" and inQuad(pos, o.Quad, SLACK))) then
						st.Done = true
					end
					if rel >= o.Window then
						st.Judged = true
						if not passReal(o, st, pos, feet) then
							st.Fail = true
							table.insert(o.Slow, player)
						end
					end
				else
					if rel >= REACT then
						if st.RefIn == nil then
							st.RefIn = if o.Kind == "Leave" then inMiddle(pos, 0) else regionIn(o, pos, SLACK)
						end
						local broke = false
						if (o.Kind == "Jump" or o.Kind == "JumpOn") and air and st.LastGround >= REACT then
							broke = true -- took off after the order reached them
						elseif o.Kind == "Leave" then
							broke = st.RefIn and radius(pos) > MID_R + 1
						elseif o.Kind ~= "Jump" then
							broke = not st.RefIn and regionIn(o, pos, -SLACK)
						end
						if broke then
							st.Judged = true
							st.Fail = true
							if not o.Called then
								o.Called = true
								say("SIMON DIDN'T SAY!", o.Text, WHITE, C.Hazard)
							end
							task.spawn(zap, player, "Simon didn't say!")
						end
					end
					if rel >= o.Window then
						st.Judged = true
					end
				end
			end
		end)

		-- Orders
		local function makeOrder(k: number, last, lastRealKind: string?, tricksInRow: number)
			local kinds
			if k == 1 then
				kinds = { "Jump", "Go" } -- the first order is real and makes idlers move
			else
				kinds = { "Jump", "Go", "Go" }
				if lastRealKind == "Middle" then
					table.insert(kinds, "Leave")
					table.insert(kinds, "Leave")
				else
					table.insert(kinds, "Middle")
				end
				if p.Combo then
					table.insert(kinds, "JumpOn")
					table.insert(kinds, "JumpOn")
				end
			end
			local kind
			for _ = 1, 6 do
				kind = kinds[rng:NextInteger(1, #kinds)]
				if not last or kind ~= last.Kind or kind == "Go" then
					break
				end
			end
			local real = k == 1 or tricksInRow >= 2 or rng:NextNumber() >= p.Trick
			local quad
			if kind == "Go" or kind == "JumpOn" then
				repeat
					quad = QUADS[rng:NextInteger(1, #QUADS)]
				until not last or last.Quad ~= quad
			end
			local text
			if kind == "Jump" then
				text = "JUMP!"
			elseif kind == "Go" then
				text = "GO TO " .. quad.Name .. "!"
			elseif kind == "Middle" then
				text = "GO TO THE MIDDLE!"
			elseif kind == "Leave" then
				text = "LEAVE THE MIDDLE!"
			else
				text = "JUMP ON " .. quad.Name .. "!"
			end
			return { Kind = kind, Quad = quad, Real = real, Text = text }
		end

		say("", "SIMON SAYS...", WHITE)
		ctx:Announce("LISTEN TO SIMON!", C.Secondary)
		if not ctx:Wait(INTRO) then
			return
		end

		local last, lastRealKind, tricksInRow = nil, nil, 0
		for k = 1, p.Count do
			local o = makeOrder(k, last, lastRealKind, tricksInRow)
			last = o
			if o.Real then
				lastRealKind = o.Kind
				tricksInRow = 0
			else
				tricksInRow += 1
			end
			for player, card in cards do
				if not isAlive(player) then
					card.Gui:Destroy()
					cards[player] = nil
				end
			end
			o.Window = p.Window
			o.States = {}
			o.Slow = {}
			for _, player in ctx:GetAlive() do
				o.States[player] = { Lag = lag(player), LastGround = -1 }
			end
			local prefix = if o.Real then "SIMON SAYS:" elseif p.Decoys and rng:NextNumber() < 0.5 then ({ "QUICK!", "NOW!", "EVERYBODY:", "READY?" })[rng:NextInteger(1, 4)] else ""
			say(prefix, o.Text, if o.Quad then o.Quad.Color:Lerp(WHITE, 0.25) else WHITE)
			ctx.State.Order = o -- (tests read this)
			o.T0 = os.clock()
			active = o
			runBars(p.Window)
			ctx:Sound("Click")
			-- a coin now and then, out in a quadrant (careful during tricks!)
			if rng:NextNumber() < 0.35 then
				local a = rng:NextNumber(0, math.pi * 2)
				local r = rng:NextNumber(10, R - 4)
				ctx:SpawnCoin(ctx:At(math.cos(a) * r, 3, math.sin(a) * r).Position)
			end
			if not ctx:Wait(p.Window + LAG_PAD) then
				return
			end
			active = nil

			-- Results
			local slow = {}
			for player, st in o.States do
				if o.Real and not st.Judged and isAlive(player) then
					local pos, feet = ctx:LocalPosition(player), ctx:FeetY(player)
					if not pos or not feet or not passReal(o, st, pos, feet) then
						table.insert(slow, player)
					end
				end
			end
			for _, player in o.Slow do
				if isAlive(player) then
					table.insert(slow, player)
				end
			end
			if #slow > 0 then
				say("TOO SLOW!", o.Text, WHITE, C.Hazard)
				for _, player in slow do
					zap(player, "Too slow!")
				end
			elseif not o.Called then
				say(if o.Real then "GOOD!" else "NICE, I DIDN'T SAY IT!", o.Text, WHITE, C.Primary)
				ctx:Sound("Coin")
			end
			if not ctx:Wait(p.Gap) then
				return
			end
		end
		active = nil
		say("", "SIMON IS PLEASED!", C.Secondary)
		dropCards()
		ctx:Finish()
	end,
}
