-- Glass Bridge: rows of identical glass panels hang over the abyss and only one panel per row holds.
-- The safe path flashes once while a gate holds everyone on the start tower; memorise it, then jump across.
-- A fake panel shatters the instant someone lands on it and stays broken, so followers learn from every fall.
-- Landing is judged on the server from feet height + root position over each panel (cheap box maths).

local PANEL = 6 -- glass panel size on X and Z
local GAP = 2.5 -- gap between rows: needs a jump, too wide to step over
local LANE_GAP = 2.5 -- gap between lanes
local PITCH = PANEL + GAP
local LANE_PITCH = PANEL + LANE_GAP
local GLASS_T = 0.5 -- panel thickness (top at y = 0)
local START_Y = 3 -- the start tower is raised so the whole bridge reads in perspective
local START_DEPTH = 9
local GOAL_DEPTH = 8
local MARGIN = 0.75 -- the root may hang this far past a panel edge while the feet still stand on it
local FEET_HIGH = 1.1 -- feet within this band of a panel top count as standing on it
local FEET_LOW = -1.4
local GATE_H = 14 -- higher than any (double) jump
local DOOM_TIME = 1.2 -- a player who touched fake glass but somehow did not fall is out after this long

-- Neon guard for theme colours (The Void / Gold Vault have near-white accents): cap the HSV value, lower for
-- whites, which bloom the most.
local function soft(color: Color3, maxValue: number?): Color3
	local h, s, v = color:ToHSV()
	return Color3.fromHSV(h, s, math.min(v, maxValue or (if s < 0.25 then 0.6 else 0.85)))
end

local function plan(ctx)
	local d = math.clamp(ctx.Difficulty, 0, 1.5)
	local z2 = math.clamp((d - 0.36) / 0.64, 0, 1) -- 0 at the top of zone 2 (B10), 1 at d = 1 (B26)
	local over = math.max(d - 1, 0)
	local rows = math.clamp(math.round(5.75 + 6.25 * d), 6, 12)
	local flash
	if d < 0.36 then
		flash = 0.4 - 0.05 * d / 0.36
	else
		flash = math.max(0.35 - 0.17 * z2 - 0.06 * over, 0.16)
	end
	-- The travelling flash leaves a trail of lit panels: the whole path stays lit at the easy end,
	-- deeper floors show only a short moving snake of it.
	local trail = if d < 0.55 then rows elseif d < 0.9 then 4 else 3
	local hold = if d < 0.55 then 1.1 elseif d < 0.9 then 0.35 else 0.2
	local lead = 0.8
	local memorise = lead + rows * flash + hold
	return {
		Rows = rows,
		Lanes = if d >= 0.8 then 3 else 2,
		Flash = flash,
		Trail = trail,
		Hold = hold,
		Lead = lead,
		Memorise = memorise,
		Duration = math.clamp(memorise + rows * 1.0 + 9, 22, 26),
		Coins = if d >= 0.6 then 5 else 4,
		D = d,
	}
end

-- Arena-local layout for a plan. Rows run from the cab side (+Z) toward -Z.
local function layout(p)
	local span = p.Rows * PANEL + (p.Rows + 1) * GAP
	local total = START_DEPTH + span + GOAL_DEPTH
	local zTop = total / 2
	local startFront = zTop - START_DEPTH -- front edge of the start tower
	local row1 = startFront - GAP - PANEL / 2
	local goalFront = row1 - (p.Rows - 1) * PITCH - PANEL / 2 - GAP
	local laneWidth = p.Lanes * PANEL + (p.Lanes - 1) * LANE_GAP
	return {
		ZTop = zTop,
		StartFront = startFront,
		Row1 = row1,
		GoalFront = goalFront,
		GoalBack = goalFront - GOAL_DEPTH,
		LaneWidth = laneWidth,
		Width = laneWidth + 8,
	}
end

local function laneX(p, lane: number): number
	return (lane - (p.Lanes + 1) / 2) * LANE_PITCH
end

local function rowZ(l, row: number): number
	return l.Row1 - (row - 1) * PITCH
end

-- Safe lane per row: random with 2 lanes; with 3 lanes the path only ever shifts by one lane so every
-- step is a jump you can actually make.
local function makePath(ctx, p): { number }
	local path = {}
	local lane = ctx.Rng:NextInteger(1, p.Lanes)
	for row = 1, p.Rows do
		if row > 1 then
			if p.Lanes == 2 then
				lane = ctx.Rng:NextInteger(1, 2)
			else
				local roll = ctx.Rng:NextNumber()
				if lane == 2 then
					lane = if roll < 0.3 then 2 elseif roll < 0.65 then 1 else 3
				else
					lane = if roll < 0.4 then lane else 2
				end
			end
		end
		path[row] = lane
	end
	return path
end

local function setLit(ctx, panel, on: boolean)
	if panel.Broken then
		return
	end
	if on then
		panel.Part.Color = panel.LitColor
		panel.Part.Transparency = 0.25
		panel.Lamp.Transparency = 0.35
	else
		panel.Part.Color = panel.Color
		panel.Part.Transparency = panel.Transparency
		panel.Lamp.Transparency = 1
	end
end

-- Shatter: the panel vanishes into falling shards, a few jagged pieces stay stuck in the frame.
local function shatter(ctx, panel)
	panel.Broken = true
	local part = panel.Part
	part.CanCollide = false
	part.CanQuery = false
	part.Transparency = 1
	panel.Lamp.Transparency = 1
	local centre = part.Position
	local glass = panel.Color:Lerp(Color3.new(1, 1, 1), 0.35)
	local points = { centre }
	for k = 1, 6 do
		local a = k / 6 * math.pi * 2
		table.insert(points, centre + Vector3.new(math.cos(a) * 1.9, 0.2, math.sin(a) * 1.9))
	end
	ctx:Fx("Chunks", { Positions = points, Color = glass, Size = 0.85 })
	ctx:Fx("Burst", { Position = centre + Vector3.new(0, 0.5, 0), Color = glass, Count = 26 })
	ctx:Sound("Impact", centre)
	-- jagged leftovers stuck in three corners of the frame (flat glass triangles)
	for k, c in { { 1, 1 }, { 1, -1 }, { -1, -1 }, { -1, 1 } } do
		if k ~= panel.Seed then
			local s = 1.3 + ((k + panel.Seed) % 3) * 0.45
			ctx:Decor({
				ClassName = "WedgePart",
				Name = "Shard",
				Size = Vector3.new(0.2, s, s),
				CFrame = ctx:At(panel.X + c[1] * (PANEL / 2 - s / 2), -0.2, panel.Z + c[2] * (PANEL / 2 - s / 2), 0, (k - 1) * 90, 90),
				Color = glass,
				Material = Enum.Material.Glass,
				Transparency = 0.3,
				Reflectance = 0.15,
			})
		end
	end
end

return {
	Id = "GlassBridge",
	Name = "Glass Bridge",
	Hint = "Half the glass shatters. Memorise the path when it flashes, then jump across!",
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
		local l = layout(p)
		local black = Color3.new(0, 0, 0)
		local dark = ctx.Theme.Floor:Lerp(black, 0.25)
		local frameColor = ctx.Theme.Floor:Lerp(ctx.Theme.Primary, 0.22)
		local steel = ctx.Theme.Floor:Lerp(Color3.fromRGB(170, 176, 196), 0.55)
		local trim = soft(ctx.Theme.Primary)
		local safeTrim = soft(ctx.Theme.Secondary)
		local halfW = l.Width / 2

		-- Start tower (raised) and goal deck ---------------------------------------------------------
		local startMid = (l.ZTop + l.StartFront) / 2
		ctx:Part({ Name = "StartTower", Size = Vector3.new(l.Width, 4, START_DEPTH), CFrame = ctx:At(0, START_Y - 2, startMid), Color = ctx.Theme.Floor:Lerp(Color3.new(1, 1, 1), 0.2) })
		ctx:Decor({ Name = "StartSkirt", Size = Vector3.new(l.Width + 0.6, 1, START_DEPTH + 0.6), CFrame = ctx:At(0, START_Y - 4.2, startMid), Color = dark })
		ctx:Decor({ Name = "StartUnderglow", Size = Vector3.new(l.Width + 1.2, 0.3, START_DEPTH + 1.2), CFrame = ctx:At(0, START_Y - 4.9, startMid), Color = soft(ctx.Theme.Secondary, 0.7), Material = Enum.Material.Neon })
		for _, s in { -1, 1 } do
			ctx:Decor({ Name = "StartTrim", Size = Vector3.new(0.3, 0.06, START_DEPTH - 1.2), CFrame = ctx:At(s * (halfW - 0.3), START_Y + 0.03, startMid + 0.3), Color = trim, Material = Enum.Material.Neon })
		end
		ctx:Decor({ Name = "StartTrim", Size = Vector3.new(l.Width - 0.6, 0.06, 0.3), CFrame = ctx:At(0, START_Y + 0.03, l.StartFront + 0.3), Color = trim, Material = Enum.Material.Neon })

		local goalMid = (l.GoalFront + l.GoalBack) / 2
		ctx:Part({ Name = "GoalDeck", Size = Vector3.new(l.Width, 2, GOAL_DEPTH), CFrame = ctx:At(0, -1, goalMid), Color = ctx.Theme.Floor:Lerp(ctx.Theme.Secondary, 0.22) })
		ctx:Decor({ Name = "GoalSkirt", Size = Vector3.new(l.Width + 0.6, 0.85, GOAL_DEPTH + 0.6), CFrame = ctx:At(0, -1.6, goalMid), Color = dark })
		ctx:Decor({ Name = "GoalUnderglow", Size = Vector3.new(l.Width + 1.2, 0.3, GOAL_DEPTH + 1.2), CFrame = ctx:At(0, -2.1, goalMid), Color = soft(ctx.Theme.Secondary, 0.7), Material = Enum.Material.Neon })
		ctx:Decor({ Name = "GoalLine", Size = Vector3.new(l.Width - 0.6, 0.06, 0.4), CFrame = ctx:At(0, 0.03, l.GoalFront - 0.4), Color = safeTrim, Material = Enum.Material.Neon })
		for k = 1, 3 do
			ctx:Decor({ Name = "GoalStripe", Size = Vector3.new(l.Width - 3, 0.02, 0.6), CFrame = ctx:At(0, 0.03, l.GoalFront - 1.6 - k * 1.6), Color = ctx.Theme.Floor:Lerp(ctx.Theme.Secondary, 0.38) })
		end
		-- Goal arch at the back of the deck
		for _, s in { -1, 1 } do
			ctx:Part({ Name = "ArchPost", Size = Vector3.new(1.2, 11, 1.2), CFrame = ctx:At(s * (halfW - 0.6), 5.5, l.GoalBack + 0.6), Color = frameColor })
			ctx:Decor({ Name = "ArchStrip", Size = Vector3.new(0.3, 9, 0.12), CFrame = ctx:At(s * (halfW - 0.6), 5.5, l.GoalBack + 1.26), Color = safeTrim, Material = Enum.Material.Neon })
		end
		local lintel = ctx:Part({ Name = "ArchLintel", Size = Vector3.new(l.Width, 2.4, 1.2), CFrame = ctx:At(0, 12.2, l.GoalBack + 0.6), Color = frameColor })
		ctx:Sign(lintel, "SAFE", { Face = Enum.NormalId.Back, TextColor3 = safeTrim })
		local beacon = ctx:Decor({ Name = "ArchLight", Size = Vector3.new(l.Width - 2, 0.3, 0.3), CFrame = ctx:At(0, 10.85, l.GoalBack + 1.3), Color = safeTrim, Material = Enum.Material.Neon })
		ctx:Glow(beacon, safeTrim, 22, 1.4)

		-- Gate on the start tower: holds everyone back while the path flashes -------------------------
		-- no shadow: the moon sits behind the gate, and its shadow blacked out the whole tower top
		local gate = ctx:Part({ Name = "Gate", Size = Vector3.new(l.Width, GATE_H, 0.4), CFrame = ctx:At(0, START_Y + GATE_H / 2, l.StartFront + 0.25), Color = trim, Material = Enum.Material.ForceField, Transparency = 0.15, CastShadow = false })
		local gateTop = ctx:Decor({ Name = "GateTop", Size = Vector3.new(l.Width, 0.3, 0.5), CFrame = ctx:At(0, START_Y + GATE_H + 0.15, l.StartFront + 0.25), Color = trim, Material = Enum.Material.Neon })
		local gatePosts = {}
		for _, s in { -1, 1 } do
			table.insert(gatePosts, ctx:Part({ Name = "GatePost", Size = Vector3.new(0.8, GATE_H + 0.6, 0.8), CFrame = ctx:At(s * (halfW + 0.4), START_Y + (GATE_H + 0.6) / 2, l.StartFront + 0.25), Color = frameColor }))
		end
		ctx.State.Gate = { gate, gateTop }

		-- Glass rows -----------------------------------------------------------------------------------
		local path = makePath(ctx, p)
		-- Pale, fairly opaque plastic: clear panes (and the Glass material, which mirrors the night sky) show the
		-- black void below and read as holes
		local glassColor = ctx.Theme.Floor:Lerp(ctx.Theme.Primary, 0.45):Lerp(Color3.new(1, 1, 1), 0.45)
		local litColor = ctx.Theme.Secondary:Lerp(Color3.new(1, 1, 1), 0.2)
		local rows = {}
		for row = 1, p.Rows do
			local z = rowZ(l, row)
			local entry = { Z = z, Safe = path[row], Panels = {} }
			for lane = 1, p.Lanes do
				local x = laneX(p, lane)
				local part = ctx:Part({
					Name = "Glass",
					Size = Vector3.new(PANEL, GLASS_T, PANEL),
					CFrame = ctx:At(x, -GLASS_T / 2, z),
					Color = glassColor,
					Material = Enum.Material.SmoothPlastic,
					Transparency = 0.3,
					Reflectance = 0,
					CastShadow = false,
				})
				-- the flash lamp sits just under the glass and shows through it
				local lamp = ctx:Decor({ Name = "Lamp", Size = Vector3.new(PANEL - 0.8, 0.1, PANEL - 0.8), CFrame = ctx:At(x, -GLASS_T - 0.1, z), Color = soft(ctx.Theme.Secondary, 0.8), Material = Enum.Material.Neon, Transparency = 1, NeonGuard = false })
				-- thin steel frame just outside the panel, top face below the glass top (no z-fighting)
				for _, s in { -1, 1 } do
					ctx:Decor({ Name = "Frame", Size = Vector3.new(PANEL + 0.6, 0.35, 0.3), CFrame = ctx:At(x, -0.24, z + s * (PANEL / 2 + 0.15)), Color = steel, Material = Enum.Material.Metal })
					ctx:Decor({ Name = "Frame", Size = Vector3.new(0.3, 0.35, PANEL), CFrame = ctx:At(x + s * (PANEL / 2 + 0.15), -0.24, z), Color = steel, Material = Enum.Material.Metal })
				end
				entry.Panels[lane] = {
					Part = part,
					Lamp = lamp,
					X = x,
					Z = z,
					Fake = lane ~= path[row],
					Broken = false,
					Color = glassColor,
					LitColor = litColor,
					Transparency = 0.3,
					Seed = ctx.Rng:NextInteger(1, 4),
				}
			end
			table.insert(rows, entry)
		end
		ctx.State.Rows = rows
		ctx.State.Plan = p
		ctx.State.Layout = l

		-- Structure: cross ties under every gap and two side girders (decor: nothing to stand on) -------
		local z0, z1 = l.StartFront, l.GoalFront
		local spanLen = z0 - z1
		local mid = (z0 + z1) / 2
		local outer = l.LaneWidth / 2 + 0.9
		for _, s in { -1, 1 } do
			ctx:Decor({ Name = "Girder", Size = Vector3.new(0.8, 1.4, spanLen), CFrame = ctx:At(s * outer, -1.9, mid), Color = steel, Material = Enum.Material.Metal })
			ctx:Decor({ Name = "GirderLight", Size = Vector3.new(0.12, 0.25, spanLen - 1), CFrame = ctx:At(s * (outer + 0.46), -1.7, mid), Color = trim, Material = Enum.Material.Neon })
		end
		for k = 0, p.Rows do
			local z = l.StartFront - GAP / 2 - k * PITCH
			ctx:Decor({ Name = "CrossTie", Size = Vector3.new(l.LaneWidth + 1.8, 0.6, 0.5), CFrame = ctx:At(0, -1.7, z), Color = dark, Material = Enum.Material.Metal })
		end
		-- Everyone lines up on the start tower, facing the bridge
		local spawns = {}
		for k = 0, 7 do
			local col = k % 4
			local rowIndex = math.floor(k / 4)
			local x = -6 + col * 4
			local z = l.StartFront + 2.4 + rowIndex * 3.6
			table.insert(spawns, CFrame.lookAt(ctx:At(x, START_Y + 3, z).Position, ctx:At(x, START_Y + 3, z - 20).Position))
		end
		ctx:SetSpawns(spawns)
		ctx.State.GatePosts = gatePosts
	end,

	Start = function(ctx)
		local p = ctx.State.Plan
		local l = ctx.State.Layout
		local rows = ctx.State.Rows
		ctx.State.Open = false
		ctx.State.OnGoal = {}

		-- Coins over random panels, fake ones included (greed lure)
		local picked = {}
		local candidates = {}
		for row = 2, p.Rows - 1 do
			table.insert(candidates, row)
		end
		for _ = 1, math.min(p.Coins, #candidates) do
			local index = ctx.Rng:NextInteger(1, #candidates)
			local row = table.remove(candidates, index)
			local lane = ctx.Rng:NextInteger(1, p.Lanes)
			local panel = rows[row].Panels[lane]
			table.insert(picked, row)
			ctx:SpawnCoin(ctx:At(panel.X, 2.6, panel.Z).Position)
		end

		-- MEMORISE: the safe panels light up one row after another ----------------------------------
		ctx:Announce("MEMORISE!", soft(ctx.Theme.Secondary))
		ctx:Sound("Countdown")
		for row = 1, p.Rows do
			local panel = rows[row].Panels[rows[row].Safe]
			ctx:After(p.Lead + (row - 1) * p.Flash, function()
				setLit(ctx, panel, true)
				ctx:Sound("Click", panel.Part)
			end)
			if p.Trail < p.Rows then
				ctx:After(p.Lead + (row - 1 + p.Trail) * p.Flash, function()
					setLit(ctx, panel, false)
				end)
			end
		end
		ctx:After(p.Memorise, function()
			for _, entry in rows do
				for _, panel in entry.Panels do
					setLit(ctx, panel, false)
				end
			end
			-- Gate drops: GO!
			ctx.State.Open = true
			for _, part in ctx.State.Gate do
				part.CanCollide = false
				ctx:Tween(part, TweenInfo.new(0.35), { Transparency = 1 })
			end
			ctx:Fx("Burst", { Position = ctx:At(0, START_Y + 2, l.StartFront).Position, Color = soft(ctx.Theme.Primary), Count = 30 })
			ctx:Announce("GO!", soft(ctx.Theme.Secondary))
			ctx:Sound("Whoosh")
		end)

		-- Landing test: feet near a panel top while the root is over it ------------------------------
		local doomed: { [Player]: number } = {}
		local flash: { [any]: boolean } = {}
		ctx:Heartbeat(function()
			local now = os.clock()
			for _, player in ctx:GetAlive() do
				local pos = ctx:LocalPosition(player)
				local feet = ctx:FeetY(player)
				if not pos or not feet then
					continue
				end
				-- goal check
				if pos.Z < l.GoalFront + 0.4 and pos.Z > l.GoalBack - 1 and math.abs(pos.X) < l.Width / 2 + 1 and feet > -2 then
					if not ctx.State.OnGoal[player] then
						ctx.State.OnGoal[player] = true
						ctx:Fx("Burst", { Position = ctx:At(pos.X, 1, pos.Z).Position, Color = soft(ctx.Theme.Secondary), Count = 20 })
						ctx:Sound("Coin")
					end
				end
				if feet < FEET_LOW or feet > FEET_HIGH then
					continue
				end
				-- which row band are we in?
				local rowF = (l.Row1 - pos.Z) / PITCH + 1
				local row = math.round(rowF)
				local entry = rows[row]
				if not entry or math.abs(pos.Z - entry.Z) > PANEL / 2 + MARGIN then
					continue
				end
				for _, panel in entry.Panels do
					if math.abs(pos.X - panel.X) <= PANEL / 2 + MARGIN then
						if panel.Fake and not panel.Broken then
							shatter(ctx, panel)
						end
						if panel.Fake and doomed[player] == nil then
							doomed[player] = now + DOOM_TIME
						elseif not panel.Fake and not flash[panel] then
							-- first landing on a safe panel: a soft pulse (everyone sees it hold)
							flash[panel] = true
							panel.Lamp.Transparency = 0.6
							ctx:Tween(panel.Lamp, TweenInfo.new(0.5), { Transparency = 1 })
						end
					end
				end
			end
			-- Fake-glass touch that did not end in a fall (e.g. a hop the server saw late): still out
			for player, at in doomed do
				if now >= at then
					doomed[player] = nil
					local feet = ctx:FeetY(player)
					if feet and feet > -4 and table.find(ctx:GetAlive(), player) then
						ctx:Eliminate(player, "Stepped on fake glass")
					end
				end
			end
		end)

		-- Everyone across: finish early
		ctx:Every(0.25, function()
			if not ctx.State.Open then
				return nil
			end
			local alive = ctx:GetAlive()
			if #alive == 0 then
				return false
			end
			for _, player in alive do
				if not ctx.State.OnGoal[player] then
					return nil
				end
				local pos = ctx:LocalPosition(player)
				if not pos or pos.Z > l.GoalFront + 0.4 then
					return nil
				end
			end
			ctx:Announce("ALL ACROSS!", soft(ctx.Theme.Secondary))
			ctx:Finish()
			return false
		end)

		-- Last seconds: a warning so stragglers hurry
		ctx:After(math.max(ctx.Duration - 5, p.Memorise + 1), function()
			for _, player in ctx:GetAlive() do
				if not ctx.State.OnGoal[player] then
					ctx:Announce("5 SECONDS!", ctx.Theme.Hazard)
					ctx:Sound("Warning")
					break
				end
			end
		end)
	end,

	-- Time's up: anyone not on the goal deck is left behind.
	Judge = function(ctx)
		local l = ctx.State.Layout
		if not l then
			return
		end
		for _, player in ctx:GetAlive() do
			local pos = ctx:LocalPosition(player)
			local feet = ctx:FeetY(player)
			if not pos or not feet or pos.Z > l.GoalFront + 0.4 or feet < -3 then
				ctx:Eliminate(player, "Stranded on the bridge")
			end
		end
	end,
}
