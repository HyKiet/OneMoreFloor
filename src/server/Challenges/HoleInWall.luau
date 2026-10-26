-- Hole in the Wall: glowing energy walls sweep across the floor, each with a doorway. Stand in the gap!
-- Each wall is one welded assembly moved by a single linear server tween. Walls are fast, so the hit test is
-- swept maths on the server (no hazard boxes). Clients see the replicated wall a little late and the server
-- sees their character a little late, so a player seen in the doorway within one round trip of contact is fine.

local SIZE = 60
local HALF = SIZE / 2
local WALL_H = 12 -- far higher than any jump
local WALL_T = 0.8
local LINTEL_Y = 8.5
local EDGE = HALF + 1.6 -- launcher housings; each wall ends in a pylon riding over them
local TRAVEL = HALF + 3.5 -- walls appear / vanish this far from the centre (inside the launchers)
local CONTACT = 1.15 -- wall half thickness + body half depth
local SIDE_MARGIN = 0.7 -- body centre must be this far inside the doorway posts

local function plan(ctx)
	local d = math.clamp(ctx.Difficulty, 0, 1.5)
	local m = math.min(d, 1)
	local over = math.max(d - 1, 0)
	return {
		Gap = math.max(9 - 3.4 * m - 0.6 * over, 5.2),
		Speed = 11 + 7 * m + 4 * over,
		Interval = math.max(4.2 - 1.7 * m - 0.5 * over, 2.2),
		Telegraph = 1.7 - 0.6 * m,
		Alternate = d >= 0.5,
		Cross = d >= 0.9,
		D = d,
	}
end

-- World frame of a wall at travel position `s` (arena-local): local X runs along the wall, local Z is the
-- travel axis. "X" walls are turned so their local X points along arena +Z.
local function frame(ctx, axis: string, s: number): CFrame
	if axis == "Z" then
		return ctx:At(0, 0, s)
	end
	return ctx:At(s, 0, 0, 0, -90, 0)
end

-- Doorway centres along the wall. `near` forces one doorway to overlap an earlier wall's doorway.
local function pickGaps(ctx, width: number, count: number, near: number?): { number }
	local limit = HALF - width / 2 - 1.5
	local gaps = {}
	if near then
		table.insert(gaps, math.clamp(near + ctx.Rng:NextNumber(-0.3, 0.3) * width, -limit, limit))
	end
	local tries = 0
	while #gaps < count and tries < 100 do
		tries += 1
		local g = ctx.Rng:NextNumber(-limit, limit)
		local ok = true
		for _, other in gaps do
			if math.abs(g - other) < width + 8 then
				ok = false
				break
			end
		end
		if ok then
			table.insert(gaps, g)
		end
	end
	table.sort(gaps)
	return gaps
end

-- Builds a wall at travel position s0. Every piece is welded to the top rail, which is the only part the
-- server tweens (one replicated CFrame per wall).
local function buildWall(ctx, axis: string, s0: number, gaps: { number }, width: number): (BasePart, { BasePart })
	local f = frame(ctx, axis, s0)
	local dark = ctx.Theme.Floor:Lerp(Color3.new(0, 0, 0), 0.5)
	local energy = ctx.Theme.Hazard
	local white = Color3.new(1, 1, 1)
	local root = ctx:Decor({ Name = "WallRail", Size = Vector3.new(EDGE * 2, 0.6, 1.4), CFrame = f * CFrame.new(0, WALL_H + 0.9, 0), Color = dark })
	local parts = { root }
	local function add(props): BasePart
		local part = ctx:Decor(props)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = part
		weld.Parent = part
		part.Anchored = false
		table.insert(parts, part)
		return part
	end

	-- End pylons with emitter strips facing the floor
	for _, side in { -1, 1 } do
		add({ Name = "WallPylon", Size = Vector3.new(2.2, WALL_H + 1.6, 2.2), CFrame = f * CFrame.new(side * EDGE, (WALL_H + 1.6) / 2 - 0.2, 0), Color = dark })
		add({ Name = "WallEmitter", Size = Vector3.new(0.4, WALL_H - 0.4, 1.2), CFrame = f * CFrame.new(side * (EDGE - 1.15), WALL_H / 2, 0), Color = energy:Lerp(white, 0.35), Material = Enum.Material.Neon })
	end

	-- Energy panels: a translucent shell around a bright core sheet
	local function panel(a: number, b: number)
		local len = b - a
		if len <= 0.4 then
			return
		end
		local mid = (a + b) / 2
		add({ Name = "WallPanel", Size = Vector3.new(len, WALL_H - 0.15, WALL_T), CFrame = f * CFrame.new(mid, WALL_H / 2 + 0.075, 0), Color = energy, Material = Enum.Material.Neon, Transparency = 0.55 })
		add({ Name = "WallCore", Size = Vector3.new(len - 0.3, WALL_H - 0.8, 0.2), CFrame = f * CFrame.new(mid, WALL_H / 2, 0), Color = energy:Lerp(white, 0.2), Material = Enum.Material.Neon, Transparency = 0.2 })
	end

	local cursor = -(EDGE - 1)
	local lit = false
	for _, g in gaps do
		panel(cursor, g - width / 2 - 0.2)
		cursor = g + width / 2 + 0.2
		-- Doorway: neon posts (their inner faces are the true gap edges), a dark lintel overhead
		for _, side in { -1, 1 } do
			add({ Name = "DoorPost", Size = Vector3.new(0.6, WALL_H + 0.2, 1.0), CFrame = f * CFrame.new(g + side * (width / 2 + 0.3), (WALL_H + 0.2) / 2 + 0.2, 0), Color = ctx.Theme.Secondary, Material = Enum.Material.Neon })
		end
		add({ Name = "Lintel", Size = Vector3.new(width + 0.6, WALL_H + 0.2 - LINTEL_Y, 1.2), CFrame = f * CFrame.new(g, (LINTEL_Y + WALL_H + 0.2) / 2, 0), Color = dark })
		local strip = add({ Name = "LintelLight", Size = Vector3.new(width + 0.2, 0.3, 1.3), CFrame = f * CFrame.new(g, LINTEL_Y + 0.05, 0), Color = ctx.Theme.Secondary, Material = Enum.Material.Neon })
		if not lit then
			lit = true
			ctx:Glow(strip, ctx.Theme.Secondary, 16, 1.6)
		end
	end
	panel(cursor, EDGE - 1)
	return root, parts
end

-- Network grace after first contact: one round trip (+ a little buffering) for this player.
local function graceFor(player: Player): number
	local ok, ping = pcall(player.GetNetworkPing, player)
	return math.clamp((if ok and typeof(ping) == "number" then ping else 0.1) + 0.06, 0.1, 0.35)
end

local function inGap(wall, u: number): boolean
	for _, g in wall.Gaps do
		if math.abs(u - g) <= wall.Width / 2 - SIDE_MARGIN then
			return true
		end
	end
	return false
end

-- Telegraphs then sends one wall across. spec = { Axis, Dir, Gaps, Telegraph, Speed, Layer }
local function launch(ctx, p, spec)
	local axis, dir, gaps = spec.Axis, spec.Dir, spec.Gaps
	local width = p.Gap
	local travelVec = if axis == "Z" then Vector3.new(0, 0, dir) else Vector3.new(dir, 0, 0)
	local function floorAt(s: number, u: number, y: number): CFrame
		return frame(ctx, axis, s) * CFrame.new(u, y, 0)
	end

	-- Telegraph: the entry strip charges toward the travel direction while each doorway's lane lights up
	ctx:Warn(floorAt(-dir * (HALF - 3), 0, 0.3), Vector3.new(SIZE, 0.2, 6), spec.Telegraph, nil, { Sweep = travelVec })
	for _, g in gaps do
		ctx:Warn(floorAt(0, g, 0.42), Vector3.new(width, 0.2, SIZE), spec.Telegraph, ctx.Theme.Secondary, { Sweep = travelVec })
	end
	ctx:Sound("Warning")

	ctx:After(spec.Telegraph, function()
		local s0, s1 = -dir * TRAVEL, dir * TRAVEL
		local root, parts = buildWall(ctx, axis, s0, gaps, width)
		local travel = (s1 - s0) * dir / spec.Speed
		local railOffset = CFrame.new(0, WALL_H + 0.9, 0)
		local tween = ctx:Tween(root, TweenInfo.new(travel, Enum.EasingStyle.Linear), { CFrame = frame(ctx, axis, s1) * railOffset })
		ctx:Sound("Whoosh", root)

		-- The lit lane stays on the floor ahead of the doorway and shrinks with the wall
		local laneY = 0.12 + (spec.Layer % 3) * 0.05
		local lanes = {}
		for _, g in gaps do
			table.insert(lanes, ctx:Decor({ Name = "SafeLane", Size = Vector3.new(width - 0.4, 0.02, SIZE), CFrame = floorAt(0, g, laneY), Color = ctx.Theme.Secondary, Material = Enum.Material.Neon, Transparency = 0.6 }))
		end
		local tIn = (TRAVEL - HALF) / spec.Speed
		local tOut = (TRAVEL + HALF) / spec.Speed
		task.delay(tIn, function()
			for k, lane in lanes do
				if lane.Parent then
					ctx:Tween(lane, TweenInfo.new(tOut - tIn, Enum.EasingStyle.Linear), { Size = Vector3.new(width - 0.4, 0.02, 0.05), CFrame = floorAt(dir * HALF, gaps[k], laneY) })
				end
			end
		end)
		task.delay(tOut, function()
			for _, lane in lanes do
				lane:Destroy()
			end
		end)

		table.insert(ctx.State.Walls, { Axis = axis, Gaps = gaps, Width = width, Root = root, Contact = {}, Cleared = {}, Prev = {} })
		tween.Completed:Once(function()
			for _, part in parts do
				part:Destroy()
			end
		end)
	end)
end

return {
	Id = "HoleInWall",
	Name = "Hole in the Wall",
	Hint = "Walls are coming! Stand in the gap before they reach you.",
	MinFloor = 1,
	MinPlayers = 1,
	Weight = 1,
	BossOnly = false,
	Zone = 1, -- B1-B9
	Duration = 22,

	Build = function(ctx)
		local dark = ctx.Theme.Floor:Lerp(Color3.new(0, 0, 0), 0.45)
		ctx:Part({ Name = "Floor", Size = Vector3.new(SIZE, 2, SIZE), CFrame = ctx:At(0, -1, 0), Color = ctx.Theme.Floor:Lerp(Color3.new(0, 0, 0), 0.12) })
		-- Lane markings along the main travel axis, faint cross lines 0.05 higher (crossings don't z-fight)
		for k = -3, 3 do
			local centre = k == 0
			ctx:Decor({ Name = "Lane", Size = Vector3.new(if centre then 0.5 else 0.25, 0.02, SIZE - 1), CFrame = ctx:At(k * 7.5, 0.03, 0), Color = ctx.Theme.Floor:Lerp(ctx.Theme.Primary, if centre then 0.55 else 0.3), Material = if centre then Enum.Material.Neon else Enum.Material.SmoothPlastic })
			ctx:Decor({ Name = "CrossLine", Size = Vector3.new(SIZE - 1, 0.02, 0.2), CFrame = ctx:At(0, 0.08, k * 7.5), Color = ctx.Theme.Floor:Lerp(ctx.Theme.Primary, 0.16) })
		end
		ctx:Rim(HALF, HALF)

		-- Wall launchers along every edge: a low housing with a hot slot and pulsing nozzles
		for _, e in { { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } } do
			local alongX = e[1] == 0
			local cx, cz = e[1] * EDGE, e[2] * EDGE
			local len = SIZE - 2
			ctx:Part({ Name = "Launcher", Size = if alongX then Vector3.new(len, 1, 2.4) else Vector3.new(2.4, 1, len), CFrame = ctx:At(cx, 0.1, cz), Color = dark })
			ctx:Decor({ Name = "LauncherSlot", Size = if alongX then Vector3.new(len - 1, 0.16, 0.5) else Vector3.new(0.5, 0.16, len - 1), CFrame = ctx:At(cx, 0.58, cz), Color = ctx.Theme.Hazard:Lerp(ctx.Theme.Floor, 0.35), Material = Enum.Material.Neon })
			for j = -1, 1 do
				local o = j * 18
				local nozzle = ctx:Decor({ Name = "Nozzle", Size = Vector3.new(1.6, 0.5, 1.6), CFrame = ctx:At(cx + (if alongX then o else 0), 0.8, cz + (if alongX then 0 else o)), Color = ctx.Theme.Secondary, Material = Enum.Material.Neon })
				ctx:Animate(nozzle, "OMF_Pulse", { PulseMin = 0.1, PulseMax = 0.75, PulseSpeed = 0.8, PulsePhase = (j + 1) / 6 + (e[1] + e[2] * 2) / 8 })
			end
		end

		-- Corner pylons with breathing caps
		for k, c in { { 1, 1 }, { 1, -1 }, { -1, -1 }, { -1, 1 } } do
			local x, z = c[1] * EDGE, c[2] * EDGE
			ctx:Part({ Name = "Pylon", Size = Vector3.new(2.6, 10, 2.6), CFrame = ctx:At(x, 4.6, z), Color = dark })
			ctx:Decor({ Name = "PylonStrip", Size = Vector3.new(0.3, 8, 0.3), CFrame = ctx:At(x - c[1] * 1.3, 4.6, z - c[2] * 1.3), Color = ctx.Theme.Primary, Material = Enum.Material.Neon })
			local cap = ctx:Decor({ Name = "PylonCap", Size = Vector3.new(2, 1.2, 2), CFrame = ctx:At(x, 10.2, z), Color = ctx.Theme.Hazard, Material = Enum.Material.Neon })
			ctx:Animate(cap, "OMF_Pulse", { PulseMin = 0, PulseMax = 0.55, PulseSpeed = 1.1, PulsePhase = k / 4 })
		end

		-- Spawn on the cab side, facing where the first wall comes from
		local spawns = {}
		for row = 0, 1 do
			for col = 0, 3 do
				local x = -10.5 + col * 7
				local z = 8 + row * 6
				table.insert(spawns, CFrame.lookAt(ctx:At(x, 3, z).Position, ctx:At(x, 3, -HALF).Position))
			end
		end
		ctx:SetSpawns(spawns)
	end,

	Start = function(ctx)
		local p = plan(ctx)
		ctx.State.Walls = {}
		local walls = ctx.State.Walls

		for _ = 1, 4 do
			ctx:SpawnCoin(ctx:At(ctx.Rng:NextNumber(-HALF + 5, HALF - 5), 3, ctx.Rng:NextNumber(-HALF + 5, HALF - 5)).Position)
		end

		-- Swept hit test: a player touches a wall when their offset from it crossed the contact band this frame
		ctx:Heartbeat(function()
			local now = os.clock()
			for i = #walls, 1, -1 do
				local wall = walls[i]
				if not wall.Root.Parent then
					table.remove(walls, i)
					continue
				end
				local wp = ctx.Origin:PointToObjectSpace(wall.Root.Position)
				local s = if wall.Axis == "Z" then wp.Z else wp.X
				for _, player in ctx:GetAlive() do
					if wall.Cleared[player] then
						continue
					end
					local pos = ctx:LocalPosition(player)
					if not pos or pos.Y < -6 then
						continue
					end
					local u = if wall.Axis == "Z" then pos.X else pos.Z
					local rel = (if wall.Axis == "Z" then pos.Z else pos.X) - s
					local prev = wall.Prev[player] or rel
					wall.Prev[player] = rel
					local touching = math.min(prev, rel) <= CONTACT and math.max(prev, rel) >= -CONTACT and math.abs(u) <= EDGE + 1.2
					local contact = wall.Contact[player]
					if contact == nil then
						if touching then
							if inGap(wall, u) then
								wall.Cleared[player] = true
							else
								wall.Contact[player] = now
							end
						end
					elseif inGap(wall, u) then
						wall.Cleared[player] = true
					elseif now - contact >= graceFor(player) then
						wall.Cleared[player] = true
						ctx:Eliminate(player, "Hit the wall")
					end
				end
			end
		end)

		task.spawn(function()
			if not ctx:Wait(0.4) then
				return
			end
			local active = {}
			local k = 0
			while not ctx.Ended do
				k += 1
				local telegraph = p.Telegraph + (if k == 1 then 0.6 else 0)
				local speed = p.Speed + (k - 1) * 0.3
				local travel = 2 * TRAVEL / speed
				-- only launch walls that are gone before the timer runs out
				if ctx:Elapsed() + telegraph + travel > ctx.Duration - 0.2 then
					break
				end
				local axis, dir = "Z", 1
				if p.Alternate and k % 2 == 0 then
					dir = -1
				end
				if p.Cross and k >= 2 and ctx.Rng:NextNumber() < 0.35 then
					axis = "X"
					dir = if ctx.Rng:NextNumber() < 0.5 then 1 else -1
				end
				-- Fairness: a wall crossing an oncoming one on the same axis shares part of its doorway,
				-- so there is always a column that survives both
				local now = os.clock()
				local near
				for i = #active, 1, -1 do
					local other = active[i]
					if other.EndsAt < now + telegraph then
						table.remove(active, i)
					elseif other.Axis == axis and other.Dir ~= dir then
						near = other.Gaps[ctx.Rng:NextInteger(1, #other.Gaps)]
					end
				end
				local count = if #ctx:GetAlive() >= 5 then 2 else 1
				local gaps = pickGaps(ctx, p.Gap, count, near)
				launch(ctx, p, { Axis = axis, Dir = dir, Gaps = gaps, Telegraph = telegraph, Speed = speed, Layer = k })
				table.insert(active, { Axis = axis, Dir = dir, Gaps = gaps, EndsAt = now + telegraph + travel })

				-- A coin waiting in one of the doorway lanes
				if ctx.Rng:NextNumber() < 0.5 then
					local s = ctx.Rng:NextNumber(-HALF + 6, HALF - 6)
					ctx:SpawnCoin((frame(ctx, axis, s) * CFrame.new(gaps[1], 3, 0)).Position)
				end

				if not ctx:Wait(p.Interval * 0.97 ^ (k - 1)) then
					return
				end
			end
		end)
	end,
}
