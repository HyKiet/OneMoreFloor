-- Layer Drop: three stacked layers of round tiles over the abyss. Every tile you touch fades and drops away,
-- so you fall through the layers one by one; never fall off the last one. The upper layers crumble on a
-- schedule (everyone plays all three) and deeper floors also decay tiles at random.
-- Detection is server maths: feet height picks the layer, a hex-grid lookup finds the tiles under the root.

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local TILE_R = 2.6 -- disc radius
local PITCH = 5.5 -- centre spacing (0.3 seams)
local THICK = 1.2
local LAYER_Y = { 0, -9, -18 } -- tile tops; KillDepth is 30 below the origin
local MARGIN = 0.45 -- the root this close past a disc edge still touches it
local SQ3 = math.sqrt(3)
local ROW_H = PITCH * SQ3 / 2
local FAST_FALL = -14 -- falling faster than this: passing through, not standing

local function soft(color: Color3, maxValue: number?): Color3
	local h, s, v = color:ToHSV()
	return Color3.fromHSV(h, s, math.min(v, maxValue or 0.85))
end

-- Players in this run (the Duration and the layer size are decided before anyone is on the arena).
local function lobbySize(ctx): number
	local ok, n = pcall(function()
		local count = 0
		for _, member in ctx.Run.Members do
			if member.Status == "Alive" and not member.Departed then
				count += 1
			end
		end
		return count
	end)
	return if ok and typeof(n) == "number" and n > 0 then math.min(n, 8) else 1
end

local function plan(ctx)
	local d = math.clamp(ctx.Difficulty, 0, 1.5)
	local z2 = math.clamp((d - 0.36) / 0.64, 0, 1)
	local over = math.max(d - 1, 0)
	local n = lobbySize(ctx)
	local radius = math.clamp(21.5 + 0.8 * (n - 1), 21.5, 27)
	return {
		Fade = if d < 0.36 then 0.8 - 0.2 * d / 0.36 else math.max(0.6 - 0.25 * z2 - 0.1 * over, 0.3),
		Radius = radius,
		BottomRadius = radius - 4 * math.clamp((d - 0.8) / 0.4, 0, 1), -- the last layer shrinks deep down
		Decay = if d >= 0.3 then 0.4 + 3.0 * (d - 0.3) else 0, -- random decay, tiles/s (solo; less with company)
		Duration = math.clamp(22 + 4 * z2 - 0.6 * (n - 1), 16, 26),
		Collapse = { 0.36, 0.68 }, -- the top and middle layers crumble at these fractions of the floor
		D = d,
	}
end

local function key(q: number, r: number): number
	return (r + 64) * 256 + (q + 64)
end

local function tileXZ(q: number, r: number): (number, number)
	return PITCH * (q + r / 2), ROW_H * r
end

-- Starts a tile fading to the hazard colour; it drops when the fade ends.
local function trigger(ctx, tile, fade: number)
	if tile.State ~= "Idle" then
		return
	end
	tile.State = "Fading"
	local part = tile.Part
	ctx:Tween(part, TweenInfo.new(fade, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Color = ctx.Theme.Hazard,
		CFrame = tile.Home * CFrame.new(-0.3, 0, 0), -- local X is world up: sag a little
	})
	tile.Ring.Color3 = soft(ctx.Theme.Hazard, 0.9)
	ctx:After(fade, function()
		tile.State = "Gone"
		part.CanCollide = false
		part.CanQuery = false
		tile.Ring:Destroy()
		table.insert(ctx.State.Rubble, part.Position)
		local tumble = ctx.Rng:NextNumber(-30, 30)
		ctx:Tween(part, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			CFrame = tile.Home * CFrame.new(-6, 0, 0) * CFrame.Angles(0, math.rad(tumble * 0.5), math.rad(tumble)),
			Transparency = 1,
		})
		ctx:After(0.55, function()
			part:Destroy()
		end)
	end)
end

return {
	Id = "LayerDrop",
	Name = "Layer Drop",
	Hint = "Tiles vanish after you touch them. Drop through three layers, but don't fall off the last one!",
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
		ctx.State.Plan = p
		local black = Color3.new(0, 0, 0)
		local accents = { ctx.Theme.Primary, ctx.Theme.Secondary, ctx.Theme.Primary:Lerp(ctx.Theme.Secondary, 0.5) }
		local layers = {}
		local K = math.ceil(p.Radius / PITCH) + 2
		for L = 1, 3 do
			local radius = if L == 3 then p.BottomRadius else p.Radius
			local top = LAYER_Y[L]
			local base = ctx.Theme.Floor:Lerp(accents[L], 0.5)
			local ringColor = soft(accents[L], 0.8)
			local layer = { Tiles = {}, Grid = {}, Top = top, Extent = 0 }
			for r = -K, K do
				for q = -K, K do
					local x, z = tileXZ(q, r)
					local dist = math.sqrt(x * x + z * z)
					if dist + TILE_R * 0.35 <= radius then
						local shade = ((q - r) % 3) * 0.06
						local home = ctx:At(x, top - THICK / 2, z, 0, 0, 90)
						local part = ctx:Part({
							Name = "Tile",
							Shape = Enum.PartType.Cylinder,
							Size = Vector3.new(THICK, TILE_R * 2, TILE_R * 2),
							CFrame = home,
							Color = base:Lerp(black, shade),
							CastShadow = false, -- keep the lower layers lit and readable
						})
						-- a thin glowing ring peeking out under the disc edge (adornment: no extra part)
						local ring = Instance.new("CylinderHandleAdornment")
						ring.Adornee = part
						ring.CFrame = CFrame.new(THICK / 2 - 0.27, 0, 0) * CFrame.Angles(0, math.rad(90), 0)
						ring.Radius = TILE_R + 0.12
						ring.InnerRadius = TILE_R - 0.25
						ring.Height = 0.16
						ring.Color3 = ringColor
						ring.Transparency = 0.15
						ring.Parent = part
						local tile = { Part = part, Ring = ring, Home = home, State = "Idle", X = x, Z = z, Layer = L }
						table.insert(layer.Tiles, tile)
						layer.Grid[key(q, r)] = tile
						layer.Extent = math.max(layer.Extent, dist + TILE_R)
					end
				end
			end
			-- edge ring so each layer's rim reads from anywhere
			local anchor = ctx:Decor({ Name = "LayerRing", Size = Vector3.new(1, 1, 1), CFrame = ctx:At(0, top - THICK + 0.2, 0), Transparency = 1 })
			local edge = Instance.new("CylinderHandleAdornment")
			edge.Adornee = anchor
			edge.CFrame = CFrame.Angles(math.rad(90), 0, 0)
			edge.Radius = layer.Extent + 1.1
			edge.InnerRadius = layer.Extent + 0.7
			edge.Height = 0.35
			edge.Color3 = soft(accents[L], 0.75)
			edge.Transparency = 0.1
			edge.Parent = anchor
			layers[L] = layer
		end
		ctx.State.Layers = layers

		-- Six pylons hold the stack (decor), with a lit band at every layer
		local dark = ctx.Theme.Floor:Lerp(ctx.Theme.Primary, 0.18)
		local pr = p.Radius + 4.5
		for k = 0, 5 do
			local a = math.rad(30 + k * 60)
			local x, z = math.sin(a) * pr, math.cos(a) * pr
			ctx:Decor({ Name = "Pylon", Size = Vector3.new(1.6, 25, 1.6), CFrame = ctx:At(x, -9.5, z, 0, math.deg(a), 0), Color = dark, Material = Enum.Material.Metal, CastShadow = false })
			for L = 1, 3 do
				ctx:Decor({ Name = "PylonBand", Size = Vector3.new(1.8, 0.3, 1.8), CFrame = ctx:At(x, LAYER_Y[L] - 0.4, z, 0, math.deg(a), 0), Color = soft(accents[L], 0.75), Material = Enum.Material.Neon })
			end
			local cap = ctx:Decor({ Name = "PylonCap", Size = Vector3.new(1.2, 0.6, 1.2), CFrame = ctx:At(x, 3.3, z, 0, math.deg(a), 0), Color = soft(ctx.Theme.Hazard, 0.8), Material = Enum.Material.Neon })
			ctx:Animate(cap, "OMF_Pulse", { PulseMin = 0, PulseMax = 0.6, PulseSpeed = 0.9, PulsePhase = k / 6 })
		end

		local spawns = {}
		for k = 0, 7 do
			local a = k / 8 * math.pi * 2
			local pos = ctx:At(math.sin(a) * 8, 3, math.cos(a) * 8).Position
			table.insert(spawns, CFrame.lookAt(pos, ctx:At(0, 3, 0).Position))
		end
		ctx:SetSpawns(spawns)
	end,

	Start = function(ctx)
		local p = ctx.State.Plan
		local layers = ctx.State.Layers
		ctx.State.Rubble = {}
		local rubble = ctx.State.Rubble
		local duration = ctx.Duration
		local company = math.max(#ctx:GetAlive(), 1)
		local reach = TILE_R + MARGIN

		-- Coins: a couple on the risky outer ring of the top layer, the rest waiting below
		local function coinsOn(L: number, count: number, minR: number)
			local tiles = layers[L].Tiles
			for _ = 1, count do
				for _ = 1, 12 do
					local tile = tiles[ctx.Rng:NextInteger(1, #tiles)]
					if tile.X * tile.X + tile.Z * tile.Z >= minR * minR then
						ctx:SpawnCoin(ctx:At(tile.X, LAYER_Y[L] + 2.6, tile.Z).Position, Config.CoinValue(ctx.Floor) + L - 1)
						break
					end
				end
			end
		end
		coinsOn(1, 2, p.Radius - 6)
		coinsOn(2, 3, 6)
		coinsOn(3, 3, 4)

		-- Touch detection: feet height picks the layer, then the few hex cells around the root
		local function touchAround(L: number, x: number, z: number)
			local grid = layers[L].Grid
			local rf = z / ROW_H
			local qf = x / PITCH - rf / 2
			local r0, q0 = math.floor(rf), math.floor(qf)
			for r = r0 - 1, r0 + 2 do
				for q = q0 - 2, q0 + 2 do
					local tile = grid[key(q, r)]
					if tile and tile.State == "Idle" then
						local dx, dz = tile.X - x, tile.Z - z
						if dx * dx + dz * dz <= reach * reach then
							trigger(ctx, tile, p.Fade)
						end
					end
				end
			end
		end

		local occupied = { 0, 0, 0 } -- players standing on each layer (last frame)
		ctx:Heartbeat(function()
			occupied[1], occupied[2], occupied[3] = 0, 0, 0
			for _, player in ctx:GetAlive() do
				local root = ctx:GetRoot(player)
				local pos = ctx:LocalPosition(player)
				local feet = ctx:FeetY(player)
				if not root or not pos or not feet then
					continue
				end
				for L = 1, 3 do
					local top = LAYER_Y[L]
					if feet >= top - 0.8 and feet <= top + 1.0 then
						occupied[L] += 1
						if root.AssemblyLinearVelocity.Y > FAST_FALL then
							touchAround(L, pos.X, pos.Z)
						end
						break
					elseif feet > top + 1.0 and feet < top + 8 then
						occupied[L] += 1 -- jumping above this layer
						break
					end
				end
			end
			if #rubble > 0 then
				ctx:Fx("Chunks", { Positions = table.clone(rubble), Color = ctx.Theme.Hazard, Size = 1.3 })
				table.clear(rubble)
			end
		end)

		-- Random decay (deeper floors; mostly a solo / small-group pressure, big lobbies eat tiles themselves)
		local rate = p.Decay * math.clamp(1 - (company - 1) / 4, 0, 1)
		if rate > 0.05 then
			ctx:Every(1 / rate, function()
				local highest = 3
				for L = 1, 3 do
					if occupied[L] > 0 then
						highest = L
						break
					end
				end
				local L = highest
				if highest < 3 and ctx.Rng:NextNumber() < 0.4 then
					L = ctx.Rng:NextInteger(highest + 1, 3)
				end
				local tiles = layers[L].Tiles
				for _ = 1, 10 do
					local tile = tiles[ctx.Rng:NextInteger(1, #tiles)]
					if tile.State == "Idle" then
						trigger(ctx, tile, p.Fade + 0.7)
						break
					end
				end
				return nil
			end)
		end

		-- Scheduled collapses: the top layer, then the middle one, crumble so the floor ends on the last layer
		local names = { "TOP LAYER", "MIDDLE LAYER" }
		for L, frac in p.Collapse do
			local at = duration * frac
			ctx:After(at - 1.6, function()
				local layer = layers[L]
				local remaining = 0
				for _, tile in layer.Tiles do
					if tile.State == "Idle" then
						remaining += 1
						ctx:Tween(tile.Part, TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Color = tile.Part.Color:Lerp(ctx.Theme.Hazard, 0.35) })
					end
				end
				if remaining > 0 then
					ctx:Announce(names[L] .. " CRUMBLING!", ctx.Theme.Hazard)
					ctx:Sound("Alarm")
					ctx:Warn(ctx:At(0, layer.Top + 0.25, 0), Vector3.new(layer.Extent * 2, 0.2, layer.Extent * 2), 1.6, ctx.Theme.Hazard, { Shape = "Disc" })
				end
			end)
			ctx:After(at, function()
				local layer = layers[L]
				for _, tile in layer.Tiles do
					if tile.State == "Idle" then
						ctx:After(ctx.Rng:NextNumber(0, 1.2), function()
							trigger(ctx, tile, p.Fade + 0.3)
						end)
					end
				end
				ctx:Shake(0.5, 0.5)
				ctx:Sound("Explosion")
			end)
		end
		ctx:After(duration * p.Collapse[2] + 1.8, function()
			ctx:Announce("LAST LAYER!", soft(ctx.Theme.Secondary))
		end)
	end,

	-- Anyone already falling past the last layer when time runs out is still out.
	Judge = function(ctx)
		for _, player in ctx:GetAlive() do
			local feet = ctx:FeetY(player)
			if not feet or feet < LAYER_Y[3] - 3 then
				ctx:Eliminate(player, "Fell")
			end
		end
	end,
}
