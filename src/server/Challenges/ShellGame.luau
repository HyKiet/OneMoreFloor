-- Shell Game: a glowing gem hides under one of several big domes on a stage. The domes shuffle by trading
-- places along arcs (one curves toward the players, the other away), then everyone must stand on the pad in
-- front of the right dome before the domes lift. Wrong pads drop into the void.
-- Each dome is one welded assembly with an anchored root; the server moves the roots along a closed-form arc
-- every frame (a handful of parts). The gem only exists while it is visible, so nothing leaks while covered.
-- Picks are judged on position one round trip after the countdown ends (latency fair).

local SPACING = 10 -- distance between dome slots along X
local DOME_Z = -12 -- dome row
local PAD_Z0, PAD_Z1 = 1.5, 8.5 -- answer pad depth (pads are piers off the back deck)
local PAD_W = 8.6
local PAD_Z = (PAD_Z0 + PAD_Z1) / 2
local DECK_Z1 = 23 -- back deck depth
local RAIL_Z = 0.9
local STAGE_Z0 = -27 -- far edge of the stage
local LIFT = 5.8 -- how high domes rise to show what is underneath
local FLARE_R = 3.6
local GEM = Color3.fromRGB(70, 225, 150)

-- Theme colours for neon trims, capped below full brightness (bright theme colours glare under bloom).
local function palette(ctx)
	local function soft(c: Color3): Color3
		local h, sat, v = c:ToHSV()
		return Color3.fromHSV(h, sat, math.min(v, if sat < 0.25 then 0.7 else 0.8))
	end
	return { Primary = soft(ctx.Theme.Primary), Secondary = soft(ctx.Theme.Secondary), Hazard = soft(ctx.Theme.Hazard) }
end

local function plan(ctx)
	local d = math.clamp(ctx.Difficulty, 0, 1.5)
	local m = math.min(d, 1)
	local over = math.max(d - 1, 0)
	local rounds = if d >= 0.5 then 3 else 2
	local most = math.floor(3 + 4.2 * m + 2 * over + 0.5) -- swaps in the last round
	local steps = {}
	for r = 1, rounds do
		steps[r] = math.max(2, most - (rounds - r))
	end
	return {
		Domes = if d < 0.4 then 3 elseif d < 0.8 then 4 else 5,
		Rounds = rounds,
		Steps = steps,
		SwapTime = math.max(0.75 - 0.4 * m - 0.07 * over, 0.3),
		Double = if d >= 0.55 then math.min(0.2 + 0.5 * (d - 0.55), 0.5) else 0, -- chance a step moves two pairs
		Fake = if d >= 0.45 then math.min(0.1 + 0.12 * m + 0.05 * over, 0.25) else 0, -- chance of a fake-out
		Show = 1.5 - 0.45 * m,
		Pick = math.max(3.2 - 1.1 * m - 0.2 * over, 1.9),
		Result = 1.45 - 0.25 * m,
		D = d,
	}
end

local LIFT_TIME = 0.45
local DROP_TIME = 0.35
local SETTLE = 0.3 -- pause after the domes drop, before the first swap
local STEP_GAP = 0.06
local JUDGE_PAD = 0.4 -- extra wait after the countdown for the slowest connection

local function stepTime(p, k: number, count: number): number
	-- each round starts a little slower and speeds up to the full swap speed
	local f = if count > 1 then (k - 1) / (count - 1) else 1
	return p.SwapTime * (1.25 - 0.25 * f)
end

local function roundSwapTime(p, r: number): number
	local total = 0
	for k = 1, p.Steps[r] do
		total += stepTime(p, k, p.Steps[r]) + STEP_GAP
	end
	return total
end

local function slotX(p, i: number): number
	return (i - (p.Domes + 1) / 2) * SPACING
end

-- Client -> server delay for a player's state to show up (round trip plus buffering): the countdown reaches
-- the client half a ping late and its position comes back half a ping late.
local function lag(player: Player): number
	local ok, ping = pcall(player.GetNetworkPing, player)
	return math.clamp((if ok and typeof(ping) == "number" then ping else 0.1) + 0.04, 0.04, 0.35)
end

-- Which pad (slot index) a player stands on, or nil. The gaps between pads are split down the middle.
local function padOf(ctx, p, player): number?
	local pos = ctx:LocalPosition(player)
	local feet = ctx:FeetY(player)
	if not pos or not feet or feet < -2.5 then
		return nil
	end
	if pos.Z < PAD_Z0 - 0.7 or pos.Z > PAD_Z1 + 0.8 then
		return nil
	end
	local i = math.floor((pos.X - slotX(p, 1)) / SPACING + 0.5) + 1
	if i < 1 or i > p.Domes then
		return nil
	end
	if math.abs(pos.X - slotX(p, i)) > PAD_W / 2 + 0.75 then
		return nil
	end
	return i
end

-- One dome: an invisible anchored root at the base centre with the visible pieces welded to it.
local function buildDome(ctx, x: number)
	local C = palette(ctx)
	local dark = ctx.Theme.Floor:Lerp(Color3.new(0, 0, 0), 0.4)
	local body = C.Primary:Lerp(ctx.Theme.Floor, 0.45)
	local base = ctx:At(x, 0.02, DOME_Z)
	local root = ctx:Decor({ Name = "DomeRoot", Size = Vector3.new(1, 1, 1), CFrame = base, Transparency = 1 })
	local function add(props, offset: CFrame)
		props.CFrame = base * offset
		local part = ctx:Decor(props)
		part.Anchored = false
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = part
		weld.Parent = part
		return part
	end
	local up = CFrame.Angles(0, 0, math.rad(90)) -- cylinders stand upright
	add({ Name = "DomeFlare", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.72, FLARE_R * 2, FLARE_R * 2), Color = dark }, CFrame.new(0, 0.36, 0) * up)
	add({ Name = "DomeRing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.22, FLARE_R * 2 + 0.24, FLARE_R * 2 + 0.24), Color = C.Secondary, Material = Enum.Material.Neon }, CFrame.new(0, 0.42, 0) * up)
	-- Optional art: a silver cloche (pivot at its bottom centre) standing on the flare
	local prop = ctx:Prop("Dome")
	if prop and prop:IsA("Model") then
		local _, size = prop:GetBoundingBox()
		prop:ScaleTo(prop:GetScale() * (FLARE_R * 2 - 0.6) / math.max(size.X, size.Z, 0.1))
		prop:PivotTo(base * CFrame.new(0, 0.7, 0))
		for _, d in prop:GetDescendants() do
			if d:IsA("BasePart") then
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
				d.Anchored = false
				if d.Name == "Body" then
					d.Material = Enum.Material.SmoothPlastic
					d.Color = body:Lerp(Color3.new(1, 1, 1), 0.3)
					d.Reflectance = 0.08
				end
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = root
				weld.Part1 = d
				weld.Parent = d
			end
		end
		return { Root = root }
	end
	add({ Name = "DomeBody", Shape = Enum.PartType.Cylinder, Size = Vector3.new(4, 6.4, 6.4), Color = body, Reflectance = 0.06 }, CFrame.new(0, 2.72, 0) * up)
	add({ Name = "DomeBand", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, 6.56, 6.56), Color = C.Secondary:Lerp(dark, 0.35) }, CFrame.new(0, 3.9, 0) * up)
	add({ Name = "DomeCap", Shape = Enum.PartType.Ball, Size = Vector3.new(6.4, 6.4, 6.4), Color = body, Reflectance = 0.06 }, CFrame.new(0, 4.72, 0))
	add({ Name = "DomeKnob", Shape = Enum.PartType.Ball, Size = Vector3.new(1.4, 1.4, 1.4), Color = C.Secondary, Material = Enum.Material.Neon }, CFrame.new(0, 8.05, 0))
	return { Root = root }
end

-- The gem only exists while it can be seen (spinning crystal, sparkles, a light).
local function showGem(ctx, x: number)
	local gem = ctx:Decor({ Name = "Gem", Size = Vector3.new(1.5, 1.5, 1.5), CFrame = ctx:At(x, 1.6, DOME_Z) * CFrame.Angles(math.rad(45), 0, math.rad(35)), Color = GEM, Material = Enum.Material.Neon })
	ctx:Animate(gem, "OMF_Spin", { SpinSpeed = 2.2 })
	local stand = ctx:Decor({ Name = "GemStand", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, 2.4, 2.4), CFrame = ctx:At(x, 0.27, DOME_Z, 0, 0, 90), Color = ctx.Theme.Floor:Lerp(GEM, 0.25) })
	ctx:Emitter(gem, {
		Texture = "Sparkle",
		Rate = 14,
		Lifetime = NumberRange.new(0.5, 0.9),
		Speed = NumberRange.new(1.5, 3.5),
		SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0) }),
		Color = ColorSequence.new(GEM:Lerp(Color3.new(1, 1, 1), 0.4)),
	})
	ctx:Glow(gem, GEM, 14, 2)
	return { gem, stand }
end

local function hideGem(gem)
	if gem then
		for _, part in gem do
			part:Destroy()
		end
	end
end

local function setBoard(ctx, text: string, color: Color3?)
	local label = ctx.State.Board
	if label then
		label.Text = text
		label.TextColor3 = color or Color3.fromRGB(245, 240, 230)
	end
end

return {
	Id = "ShellGame",
	Name = "Shell Game",
	Hint = "Watch the glowing gem. When the domes stop, stand on the pad in front of the right one!",
	MinFloor = 1,
	MinPlayers = 1,
	Weight = 1,
	BossOnly = false,
	Zone = 1, -- B1-B9
	Duration = function(ctx)
		local p = plan(ctx)
		local total = 0.6 + LIFT_TIME + 0.3
		for r = 1, p.Rounds do
			total += p.Show + DROP_TIME + SETTLE + roundSwapTime(p, r) + 0.25 + p.Pick + JUDGE_PAD + LIFT_TIME + p.Result
		end
		return total
	end,

	Build = function(ctx)
		local C = palette(ctx)
		local p = plan(ctx)
		local n = p.Domes
		local half = n * SPACING / 2 + 3
		local dark = ctx.Theme.Floor:Lerp(Color3.new(0, 0, 0), 0.45)
		local deckColor = ctx.Theme.Floor:Lerp(Color3.new(0, 0, 0), 0.1)
		local wall = ctx.Theme.Floor:Lerp(C.Primary, 0.2) -- big walls contrast with the floors

		-- Back deck where everyone starts, with the answer pads sticking out of it toward the stage
		local deckDepth = DECK_Z1 - PAD_Z1
		ctx:Part({ Name = "Deck", Size = Vector3.new(half * 2, 2, deckDepth), CFrame = ctx:At(0, -1, PAD_Z1 + deckDepth / 2), Color = deckColor })
		ctx:Decor({ Name = "DeckSkirt", Size = Vector3.new(half * 2 + 0.6, 0.8, deckDepth + 0.6), CFrame = ctx:At(0, -1.7, PAD_Z1 + deckDepth / 2), Color = dark })
		ctx:Decor({ Name = "DeckEdge", Size = Vector3.new(half * 2, 0.06, 0.4), CFrame = ctx:At(0, 0.03, DECK_Z1 - 0.3), Color = C.Primary, Material = Enum.Material.Neon })
		for _, side in { -1, 1 } do
			ctx:Decor({ Name = "DeckEdge", Size = Vector3.new(0.4, 0.06, deckDepth - 0.6), CFrame = ctx:At(side * (half - 0.3), 0.03, PAD_Z1 + deckDepth / 2 - 0.3), Color = C.Primary, Material = Enum.Material.Neon })
		end
		-- the edge facing the pads: a soft line so the pier boundary reads
		ctx:Decor({ Name = "PadLine", Size = Vector3.new(half * 2, 0.04, 0.25), CFrame = ctx:At(0, 0.02, PAD_Z1 + 0.35), Color = ctx.Theme.Floor:Lerp(C.Primary, 0.45) })

		-- Answer pads: each is a welded assembly so a wrong pad can drop away in one piece
		local pads = {}
		for i = 1, n do
			local x = slotX(p, i)
			local home = ctx:At(x, -0.9, PAD_Z)
			local pad = ctx:Part({ Name = "Pad", Size = Vector3.new(PAD_W, 1.8, PAD_Z1 - PAD_Z0), CFrame = home, Color = ctx.Theme.Floor:Lerp(C.Primary, 0.16) })
			local trims = {}
			local function weld(part: BasePart)
				part.Anchored = false
				local w = Instance.new("WeldConstraint")
				w.Part0 = pad
				w.Part1 = part
				w.Parent = part
				return part
			end
			local depth = PAD_Z1 - PAD_Z0
			for _, s in { { 0, -depth / 2 + 0.15, PAD_W, 0.3 }, { 0, depth / 2 - 0.15, PAD_W, 0.3 }, { -PAD_W / 2 + 0.15, 0, 0.3, depth - 0.6 }, { PAD_W / 2 - 0.15, 0, 0.3, depth - 0.6 } } do
				table.insert(trims, weld(ctx:Decor({ Name = "PadTrim", Size = Vector3.new(s[3], 0.06, s[4]), CFrame = ctx:At(x + s[1], 0.03, PAD_Z + s[2]), Color = C.Primary, Material = Enum.Material.Neon, Transparency = 0.25 })))
			end
			local plate = weld(ctx:Decor({ Name = "PadNumber", Size = Vector3.new(5, 0.04, 5), CFrame = ctx:At(x, 0.09, PAD_Z, 0, -90, 0), Transparency = 1 })) -- top-face text reads upright facing -Z
			local label = ctx:Sign(plate, tostring(i), { Face = Enum.NormalId.Top, TextColor3 = C.Primary:Lerp(Color3.new(1, 1, 1), 0.55), TextTransparency = 0.25 })
			-- under-glow line so the gap between pads reads as a drop
			weld(ctx:Decor({ Name = "PadUnder", Size = Vector3.new(PAD_W - 0.6, 0.25, depth - 0.6), CFrame = ctx:At(x, -1.95, PAD_Z), Color = C.Secondary, Material = Enum.Material.Neon, Transparency = 0.3 }))
			table.insert(pads, { Part = pad, Home = home, Trims = trims, Label = label, X = x })
		end
		ctx.State.Pads = pads

		-- Rail between the pads and the stage, with a number plate in front of each pad. An invisible wall
		-- keeps everyone off the stage (nobody peeks under a dome).
		ctx:Part({ Name = "Rail", Size = Vector3.new(half * 2, 1.2, 0.8), CFrame = ctx:At(0, 0.6, RAIL_Z), Color = wall })
		ctx:Decor({ Name = "RailLight", Size = Vector3.new(half * 2, 0.08, 0.3), CFrame = ctx:At(0, 1.24, RAIL_Z), Color = C.Secondary, Material = Enum.Material.Neon, Transparency = 0.3 })
		ctx:Part({ Name = "StageGuard", Size = Vector3.new(half * 2 + 6, 16, 0.6), CFrame = ctx:At(0, 8, RAIL_Z - 0.7), Transparency = 1 })
		for i = 1, n do
			local plate = ctx:Decor({ Name = "RailPlate", Size = Vector3.new(2.6, 1.8, 0.3), CFrame = ctx:At(slotX(p, i), 2.1, RAIL_Z + 0.1, 0, 180, 0), Color = dark })
			ctx:Sign(plate, tostring(i), { TextColor3 = C.Secondary })
		end

		-- The stage: a dark table the domes slide on, a backdrop and a carnival header board
		local stageDepth = RAIL_Z - 0.4 - STAGE_Z0
		ctx:Part({ Name = "Stage", Size = Vector3.new(half * 2, 2, stageDepth), CFrame = ctx:At(0, -1, STAGE_Z0 + stageDepth / 2), Color = ctx.Theme.Floor:Lerp(Color3.new(0, 0, 0), 0.15) })
		for k = 1, n do
			-- faint slot marks where the domes come to rest
			ctx:Decor({ Name = "SlotMark", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.04, FLARE_R * 2 + 1.2, FLARE_R * 2 + 1.2), CFrame = ctx:At(slotX(p, k), 0.0, DOME_Z, 0, 0, 90), Color = ctx.Theme.Floor:Lerp(C.Primary, 0.22) })
		end
		ctx:Part({ Name = "Backdrop", Size = Vector3.new(half * 2, 14, 1.6), CFrame = ctx:At(0, 7, STAGE_Z0 - 0.8), Color = wall })
		for k = -2, 2 do
			ctx:Decor({ Name = "BackdropStripe", Size = Vector3.new(0.4, 12, 0.1), CFrame = ctx:At(k * (half * 2 / 5), 7, STAGE_Z0 + 0.05), Color = ctx.Theme.Floor:Lerp(C.Primary, 0.3) })
		end
		local header = ctx:Part({ Name = "Header", Size = Vector3.new(34, 5, 1), CFrame = ctx:At(0, 15.5, STAGE_Z0 - 0.4, 0, 180, 0), Color = ctx.Theme.Floor:Lerp(Color3.new(0, 0, 0), 0.55) })
		ctx.State.Board = ctx:Sign(header, "SHELL GAME", { TextColor3 = C.Secondary, Size = UDim2.fromScale(0.9, 0.8), Position = UDim2.fromScale(0.05, 0.1) })
		for k = 0, 11 do
			for row, y in { 18.35, 12.65 } do
				local bulb = ctx:Decor({ Name = "Bulb", Shape = Enum.PartType.Ball, Size = Vector3.new(0.6, 0.6, 0.6), CFrame = ctx:At(-16.5 + k * 3, y, STAGE_Z0 + 0.2), Color = C.Primary:Lerp(C.Secondary, (k % 2) * 0.7), Material = Enum.Material.Neon })
				ctx:Animate(bulb, "OMF_Pulse", { PulseMin = 0, PulseMax = 0.75, PulseSpeed = 1.6, PulsePhase = ((k + row) % 2) * 0.5 })
			end
		end
		for _, side in { -1, 1 } do
			local x = side * (half + 1.2)
			ctx:Part({ Name = "Tower", Size = Vector3.new(2.4, 16, 2.4), CFrame = ctx:At(x, 7, STAGE_Z0 + 1), Color = wall })
			local cap = ctx:Decor({ Name = "TowerCap", Shape = Enum.PartType.Ball, Size = Vector3.new(1.8, 1.8, 1.8), CFrame = ctx:At(x, 15.6, STAGE_Z0 + 1), Color = C.Secondary, Material = Enum.Material.Neon })
			ctx:Glow(cap, C.Primary, 26, 0.8)
			ctx:Decor({ Name = "TowerStrip", Size = Vector3.new(0.3, 13, 0.1), CFrame = ctx:At(x, 7, STAGE_Z0 + 2.25), Color = C.Primary, Material = Enum.Material.Neon })
		end

		-- Domes start in their slots, resting on the stage
		local domes = {}
		for i = 1, n do
			local dome = buildDome(ctx, slotX(p, i))
			dome.Slot = i
			domes[i] = dome
		end
		ctx.State.Domes = domes

		-- Everyone starts on the back deck facing the stage
		local spawns = {}
		for row = 0, 1 do
			for col = 0, 3 do
				local x = -10.5 + col * 7
				local z = 13.5 + row * 4.5
				table.insert(spawns, CFrame.lookAt(ctx:At(x, 3, z).Position, ctx:At(x, 3, DOME_Z).Position))
			end
		end
		ctx:SetSpawns(spawns)
	end,

	Start = function(ctx)
		local C = palette(ctx)
		local p = plan(ctx)
		local n = p.Domes
		local domes = ctx.State.Domes
		local pads = ctx.State.Pads
		local rng = ctx.Rng
		local white = Color3.fromRGB(245, 240, 230)

		-- Dome motion: closed-form arcs driven every frame for the few domes that move
		local moving = {}
		ctx:Heartbeat(function()
			local now = os.clock()
			for dome, mv in moving do
				local u = math.clamp((now - mv.Start) / mv.Dur, 0, 1)
				local theta = if mv.Fake then mv.Fake * math.sin(math.pi * u) else math.pi * (1 - math.cos(math.pi * u)) / 2
				local cx, s = (mv.X0 + mv.X1) / 2, (mv.X1 - mv.X0) / 2
				local x = cx - s * math.cos(theta)
				local z = DOME_Z + mv.Bulge * math.sin(theta)
				dome.Root.CFrame = ctx:At(x, 0.02 + mv.Hop * math.sin(theta), z)
				if u >= 1 then
					moving[dome] = nil
					dome.Root.CFrame = ctx:At(if mv.Fake then mv.X0 else mv.X1, 0.02, DOME_Z)
				end
			end
		end)

		local function domeAt(slot: number)
			for _, dome in domes do
				if dome.Slot == slot then
					return dome
				end
			end
			return domes[1]
		end

		local function liftAll(up: boolean, time: number)
			local info = TweenInfo.new(time, if up then Enum.EasingStyle.Back else Enum.EasingStyle.Quad, if up then Enum.EasingDirection.Out else Enum.EasingDirection.In)
			for _, dome in domes do
				ctx:Tween(dome.Root, info, { CFrame = ctx:At(slotX(p, dome.Slot), if up then LIFT else 0.02, DOME_Z) })
			end
		end

		-- One shuffle step: swap slots i and j (or fake it), with the arcs on opposite sides
		local function swap(i: number, j: number, dur: number, fake: number?)
			local a, b = domeAt(i), domeAt(j)
			local gap = math.abs(i - j)
			local bulge = if gap == 1 then 4.3 else 7.6 + 0.35 * (gap - 2)
			local sign = if rng:NextNumber() < 0.5 then 1 else -1
			local start = os.clock()
			moving[a] = { X0 = slotX(p, i), X1 = slotX(p, j), Bulge = bulge * sign, Start = start, Dur = dur, Fake = fake, Hop = 0 }
			moving[b] = { X0 = slotX(p, j), X1 = slotX(p, i), Bulge = -bulge * sign, Start = start, Dur = dur, Fake = fake, Hop = 0 }
			if not fake then
				a.Slot, b.Slot = j, i
			end
		end

		local function randomPair(lo: number, hi: number, prefer: number?): (number, number)
			local i = if prefer and prefer >= lo and prefer <= hi and rng:NextNumber() < 0.6 then prefer else rng:NextInteger(lo, hi)
			local j = rng:NextInteger(lo, hi - 1)
			if j >= i then
				j += 1
			end
			return i, j
		end

		local function setPads(color: Color3)
			for _, pad in pads do
				for _, trim in pad.Trims do
					trim.Color = color
				end
			end
		end

		local gemDome = domes[rng:NextInteger(1, n)]
		local gem
		ctx.State.GemDome = gemDome -- (tests read ctx.State.GemDome.Slot)
		ctx.State.Log = {}

		setBoard(ctx, "WATCH THE GEM!", C.Secondary)
		ctx:Announce("WATCH THE GEM!", GEM)
		if not ctx:Wait(0.6) then
			return
		end
		-- First reveal
		gem = showGem(ctx, slotX(p, gemDome.Slot))
		liftAll(true, LIFT_TIME)
		ctx:Sound("Whoosh")
		ctx:Fx("Burst", { Position = ctx:At(slotX(p, gemDome.Slot), 2, DOME_Z).Position, Color = GEM, Count = 30 })
		if not ctx:Wait(LIFT_TIME) then
			return
		end

		for round = 1, p.Rounds do
			-- A couple of coins on the pads while everyone looks at the gem
			for _ = 1, 2 do
				local pad = pads[rng:NextInteger(1, n)]
				ctx:SpawnCoin(ctx:At(pad.X + rng:NextNumber(-2.5, 2.5), 3, PAD_Z0 + 1.2).Position)
			end
			setBoard(ctx, "WATCH THE GEM!", C.Secondary)
			if not ctx:Wait(p.Show) then
				return
			end

			-- Cover it up
			liftAll(false, DROP_TIME)
			ctx:Sound("Impact")
			if not ctx:Wait(DROP_TIME) then
				return
			end
			hideGem(gem)
			gem = nil
			setBoard(ctx, "KEEP WATCHING...", white)
			if not ctx:Wait(SETTLE) then
				return
			end

			-- Shuffle
			local count = p.Steps[round]
			local lastFake = false
			for k = 1, count do
				local dur = stepTime(p, k, count)
				local roll = rng:NextNumber()
				if k > 1 and k < count and not lastFake and roll < p.Fake then
					-- fake-out: a pair starts to trade places, then both go back
					local i, j = randomPair(1, n, gemDome.Slot)
					swap(i, j, dur, math.pi * 0.36)
					lastFake = true
				elseif n >= 4 and roll < p.Fake + p.Double then
					-- two pairs at once, on separate halves so their paths never cross
					local split = if n == 4 then 2 else rng:NextInteger(2, 3)
					local i, j = randomPair(1, split, gemDome.Slot)
					local i2, j2 = randomPair(split + 1, n, gemDome.Slot)
					swap(i, j, dur)
					swap(i2, j2, dur)
					lastFake = false
				else
					local i, j = randomPair(1, n, gemDome.Slot)
					swap(i, j, dur)
					lastFake = false
				end
				ctx:Sound("Whoosh")
				if not ctx:Wait(dur + STEP_GAP) then
					return
				end
			end
			if not ctx:Wait(0.25) then
				return
			end

			-- Pick a pad
			local answer = gemDome.Slot
			setPads(C.Secondary)
			ctx:Announce("PICK A DOME!", C.Secondary)
			ctx:Sound("Countdown")
			local pickEnds = os.clock() + p.Pick
			while os.clock() < pickEnds - 0.02 do
				setBoard(ctx, string.format("PICK A DOME!  %d", math.ceil(pickEnds - os.clock() - 0.02)), C.Secondary)
				if not ctx:Wait(math.min(0.1, pickEnds - os.clock())) then
					return
				end
			end

			-- Time! Judge everyone one round trip later, while the domes lift
			setBoard(ctx, "DOME " .. answer .. "!", GEM)
			gem = showGem(ctx, slotX(p, answer))
			liftAll(true, LIFT_TIME)
			ctx:Sound("Whoosh")
			local doomed = {}
			for _, player in ctx:GetAlive() do
				task.delay(lag(player), function()
					if ctx.Ended then
						return
					end
					local on = padOf(ctx, p, player)
					table.insert(ctx.State.Log, string.format("r%d %s pad=%s answer=%d pos=%s", round, player.Name, tostring(on), answer, tostring(ctx:LocalPosition(player))))
					if on ~= answer then
						doomed[player] = on or 0
					end
				end)
			end
			if not ctx:Wait(JUDGE_PAD) then
				return
			end
			ctx:Fx("Burst", { Position = ctx:At(slotX(p, answer), 2, DOME_Z).Position, Color = GEM, Count = 40 })

			-- Wrong pads drop away, the right one lights up
			setPads(C.Primary)
			for i, pad in pads do
				if i == answer then
					for _, trim in pad.Trims do
						trim.Color = GEM
					end
					ctx:Fx("Burst", { Position = ctx:At(pad.X, 1, PAD_Z).Position, Color = GEM, Count = 24 })
				else
					for _, trim in pad.Trims do
						trim.Color = C.Hazard
					end
					pad.Part.CanCollide = false
					ctx:Tween(pad.Part, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
						CFrame = pad.Home * CFrame.new(0, -24, 0) * CFrame.Angles(math.rad(rng:NextNumber(-20, 20)), 0, math.rad(rng:NextNumber(-20, 20))),
					})
				end
			end
			ctx:Sound("Impact")
			ctx:Shake(0.35, 0.3)
			local zapFrom = ctx:At(slotX(p, answer), 9.5 + LIFT, DOME_Z).Position
			local anyDoomed = false
			for player, on in doomed do
				anyDoomed = true
				local root = ctx:GetRoot(player)
				if root and on == 0 then
					-- not on any pad: zapped from the dome
					ctx:Fx("Shot", { From = zapFrom, To = root.Position, Color = C.Hazard })
					ctx:Eliminate(player, "Not on a pad!")
				end
			end
			if anyDoomed then
				ctx:Sound("Laser")
			end
			-- players on wrong pads fall with them, then they're out
			ctx:After(0.3, function()
				for player, on in doomed do
					if on ~= 0 then
						ctx:Eliminate(player, "Wrong dome!")
					end
				end
			end)
			if not ctx:Wait(LIFT_TIME + p.Result - JUDGE_PAD) then
				return
			end

			-- Pads come back for the next round
			for i, pad in pads do
				if i ~= answer then
					ctx:Tween(pad.Part, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = pad.Home })
					ctx:After(0.42, function()
						pad.Part.CanCollide = true
					end)
				end
			end
			setPads(C.Primary)
		end
		hideGem(gem)
		setBoard(ctx, "WELL WATCHED!", GEM)
		ctx:Finish()
	end,
}
