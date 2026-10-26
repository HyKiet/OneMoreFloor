-- Spotlight: the floor is dark and something is watching. Three spotlights roam the floor on smooth
-- Lissajous paths, speeding up and shrinking. Stay inside one: linger in the dark and your exposure fills.
-- A light fails at 1/3 and 2/3 of the round (at least two stay on when 5+ players are left).

local RunService = game:GetService("RunService")

local SIZE = 72
local HALF = SIZE / 2
local AMP = 24 -- path amplitude: discs stay on the floor even at full radius
local LAMP_Y = 30
local LIGHT = Color3.fromRGB(255, 244, 214)
local DANGER = Color3.fromRGB(255, 40, 40)
local IN_MARGIN = 0.6 -- standing on the glowing edge still counts
local DRAIN = 0.45 -- seconds to empty a full exposure meter inside a light

-- Lissajous frequency pairs and start points (spread out so the circles start apart)
local PATHS = {
	{ A = 1, B = 2, X0 = -13, Z0 = 5 },
	{ A = 2, B = 1, X0 = 13, Z0 = 5 },
	{ A = 3, B = 2, X0 = 0, Z0 = -14 },
}

local function plan(ctx)
	local d = math.clamp(ctx.Difficulty, 0, 1.5)
	local m = math.min(d, 1)
	local over = math.max(d - 1, 0)
	return {
		R0 = 10 - 1.0 * m - 0.4 * over,
		R1 = math.max(6 - 0.8 * m - 0.6 * over, 4.4),
		V0 = 4 + 2.5 * m + 1.5 * over, -- top speed of a light (studs/s) at the start...
		V1 = 6.5 + 3.5 * m + 2 * over, -- ...and at the end
		Grace = math.max(1.6 - 0.6 * m - 0.2 * over, 0.85),
		D = d,
	}
end

-- Closed-form path parameter: speed ramps linearly from V0 to V1 over the round.
local function phase(p, duration: number, t: number): number
	return (p.V0 * t + 0.5 * (p.V1 - p.V0) / duration * t * t) / AMP
end

-- Arena-local centre of spot i at path parameter phi (normalised so every path has the same top speed).
local function spotXZ(path, phi: number): (number, number)
	local s = path.Sign / math.sqrt(path.A * path.A + path.B * path.B)
	return AMP * math.sin(path.A * s * phi + path.PX), AMP * math.sin(path.B * s * phi + path.PZ)
end

local function radiusAt(p, duration: number, t: number): number
	return p.R0 + (p.R1 - p.R0) * math.clamp(t / duration, 0, 1)
end

-- Moving pieces, sized for radius r. Layers per spot sit 0.1 apart so overlapping circles never z-fight.
local function layout(i: number, r: number)
	local base = 0.13 + (i - 1) * 0.1
	return {
		{ Key = "Ring", Y = base, Size = Vector3.new(0.02, r * 2 + 1, r * 2 + 1) },
		{ Key = "Disc", Y = base + 0.05, Size = Vector3.new(0.02, r * 2, r * 2) },
		{ Key = "Beam1", Y = 5.2, Size = Vector3.new(9.6, r * 1.92, r * 1.92) },
		{ Key = "Beam2", Y = 15.05, Size = Vector3.new(9.9, r * 1.44, r * 1.44) },
		{ Key = "Beam3", Y = 24.35, Size = Vector3.new(8.5, r * 0.96, r * 0.96) },
	}
end

local function coneAngle(r: number): number
	return math.clamp(math.deg(math.atan((r + 1) / (LAMP_Y - 1))) * 2, 5, 90)
end

return {
	Id = "Spotlight",
	Name = "Spotlight",
	Hint = "Stay inside a spotlight. Linger in the dark and you're gone!",
	MinFloor = 1,
	MinPlayers = 1,
	Weight = 1,
	BossOnly = false,
	Zone = 3, -- B20+
	Duration = 22,

	Build = function(ctx)
		local p = plan(ctx)
		local black = Color3.new(0, 0, 0)
		-- dark, but never below value 0.2: The Void's floor is dark already and went pitch black
		local h, s, v = ctx.Theme.Floor:ToHSV()
		ctx:Part({ Name = "Floor", Size = Vector3.new(SIZE, 2, SIZE), CFrame = ctx:At(0, -1, 0), Color = Color3.fromHSV(h, s, math.max(v * 0.45, 0.2)) })
		-- Faint tiles: the floor reads in the dark, the lit circles stand out from it
		for k = -2, 2 do
			ctx:Decor({ Name = "Seam", Size = Vector3.new(0.2, 0.02, SIZE - 1), CFrame = ctx:At(k * 12, 0.03, 0), Color = Color3.fromHSV(h, s, math.max(v * 0.7, 0.3)) })
			ctx:Decor({ Name = "Seam", Size = Vector3.new(SIZE - 1, 0.02, 0.2), CFrame = ctx:At(0, 0.07, k * 12), Color = Color3.fromHSV(h, s, math.max(v * 0.7, 0.3)) })
		end
		ctx:Rim(HALF, HALF, ctx.Theme.Primary:Lerp(black, 0.35), ctx.Theme.Secondary:Lerp(black, 0.55))

		-- Eyes in the dark around the edges, blinking slowly out of step
		local eyeColors = { ctx.Theme.Hazard, ctx.Theme.Secondary, Color3.fromRGB(255, 225, 90) }
		for k = 1, 12 do
			local edge = (k - 1) % 4
			local lateral = ctx.Rng:NextNumber(-HALF + 6, HALF - 6)
			local out = HALF + ctx.Rng:NextNumber(4, 9)
			local x, z
			if edge == 0 then
				x, z = lateral, -out
			elseif edge == 1 then
				x, z = out, lateral
			elseif edge == 2 then
				x, z = lateral, out
			else
				x, z = -out, lateral
			end
			local y = ctx.Rng:NextNumber(1.5, 7)
			local look = CFrame.lookAt(ctx:At(x, y, z).Position, ctx:At(0, y, 0).Position)
			local scale = ctx.Rng:NextNumber(1.4, 2.2)
			local color = eyeColors[(k % #eyeColors) + 1]
			local blink = { PulseMin = 0, PulseMax = 1, PulseSpeed = ctx.Rng:NextNumber(0.12, 0.3), PulsePhase = ctx.Rng:NextNumber() }
			for _, side in { -1, 1 } do
				local eye = ctx:Decor({ Name = "Eye", Size = Vector3.new(0.8, 0.32, 0.12) * scale, CFrame = look * CFrame.new(side * 0.6 * scale, 0, 0) * CFrame.Angles(0, 0, math.rad(side * -8)), Color = color, Material = Enum.Material.Neon })
				ctx:Animate(eye, "OMF_Pulse", blink)
			end
		end

		-- The three lights: floor disc with a glowing edge, a stepped beam and a lamp with one SpotLight.
		-- The disc is the anchored root; everything else is welded to it (one replicated CFrame per light).
		local spots = {}
		for i, def in PATHS do
			local path = {
				A = def.A,
				B = def.B,
				Sign = if ctx.Rng:NextNumber() < 0.5 then -1 else 1,
				PX = math.asin(def.X0 / AMP),
				PZ = math.asin(def.Z0 / AMP),
			}
			-- flip the starting direction on either axis for variety (same start point)
			if ctx.Rng:NextNumber() < 0.5 then
				path.PX = math.pi - path.PX
			end
			if ctx.Rng:NextNumber() < 0.5 then
				path.PZ = math.pi - path.PZ
			end
			local x, z = spotXZ(path, 0)
			local spot = { Path = path, Active = true, Parts = {}, X = x, Z = z, Index = i }
			local rim = ctx.Theme.Primary:Lerp(LIGHT, 0.35)
			local props = {
				Ring = { Color = rim, Material = Enum.Material.Neon, Transparency = 0.05 },
				Disc = { Color = LIGHT:Lerp(ctx.Theme.Primary, 0.15), Material = Enum.Material.Neon, Transparency = 0.66 },
				Beam1 = { Color = LIGHT, Material = Enum.Material.Neon, Transparency = 0.955 },
				Beam2 = { Color = LIGHT, Material = Enum.Material.Neon, Transparency = 0.945 },
				Beam3 = { Color = LIGHT, Material = Enum.Material.Neon, Transparency = 0.93 },
			}
			local root
			for _, piece in layout(i, p.R0) do
				local def2 = props[piece.Key]
				local part = ctx:Decor({ Name = "Spot" .. piece.Key, Shape = Enum.PartType.Cylinder, Size = piece.Size, CFrame = ctx:At(x, piece.Y, z, 0, 0, 90), Color = def2.Color, Material = def2.Material, Transparency = def2.Transparency })
				spot.Parts[piece.Key] = part
				if piece.Key == "Disc" then
					root = part
				end
			end
			spot.Root = root
			local housing = ctx:Decor({ Name = "LampHousing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.2, 3.4, 3.4), CFrame = ctx:At(x, LAMP_Y + 0.2, z, 0, 0, 90), Color = ctx.Theme.Floor:Lerp(black, 0.5) })
			local lens = ctx:Decor({ Name = "LampLens", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 2.8, 2.8), CFrame = ctx:At(x, LAMP_Y - 1.05, z, 0, 0, 90), Color = LIGHT, Material = Enum.Material.Neon })
			spot.Parts.Housing = housing
			spot.Parts.Lens = lens
			local light = Instance.new("SpotLight")
			-- the lens cylinder is rolled 90° about Z, so its local +X points up: shine out of the Left face
			light.Face = Enum.NormalId.Left
			light.Color = LIGHT
			light.Brightness = 2.6
			light.Range = LAMP_Y + 8
			light.Angle = coneAngle(p.R0)
			light.Shadows = false
			light.Parent = lens
			spot.Light = light
			for key, part in spot.Parts do
				if part ~= root then
					local weld = Instance.new("WeldConstraint")
					weld.Part0 = root
					weld.Part1 = part
					weld.Parent = part
					part.Anchored = false
				end
			end
			table.insert(spots, spot)
		end
		ctx.State.Spots = spots

		-- Spawn inside the starting circles (3 + 3 + 2), facing the middle
		local spawns = {}
		for k = 0, 7 do
			local spot = spots[(k % 3) + 1]
			local a = k * 2.4
			local px, pz = spot.X + math.cos(a) * 3.5, spot.Z + math.sin(a) * 3.5
			table.insert(spawns, CFrame.lookAt(ctx:At(px, 3, pz).Position, ctx:At(0, 3, 0).Position))
		end
		ctx:SetSpawns(spawns)
	end,

	Start = function(ctx)
		local p = plan(ctx)
		local spots = ctx.State.Spots
		local duration = ctx.Duration

		-- Coins glinting out in the dark: worth a quick dash
		local function darkCoin()
			for _ = 1, 20 do
				local x, z = ctx.Rng:NextNumber(-HALF + 4, HALF - 4), ctx.Rng:NextNumber(-HALF + 4, HALF - 4)
				local clear = true
				for _, spot in spots do
					if spot.Active and (Vector2.new(x, z) - Vector2.new(spot.X, spot.Z)).Magnitude < p.R0 + 3 then
						clear = false
						break
					end
				end
				if clear then
					ctx:SpawnCoin(ctx:At(x, 3, z).Position)
					return
				end
			end
		end
		for _ = 1, 5 do
			darkCoin()
		end
		local extra = 0
		ctx:Every(3.5, function()
			darkCoin()
			extra += 1
			return extra < 4
		end)

		-- Lights fail at 1/3 and 2/3 of the round: ~2 s of flicker, then darkness
		local function fail(which: number)
			local alive = #ctx:GetAlive()
			local active = {}
			for _, spot in spots do
				if spot.Active then
					table.insert(active, spot)
				end
			end
			if #active <= 1 or (#active <= 2 and alive >= 5) then
				return
			end
			local spot = active[ctx.Rng:NextInteger(1, #active)]
			ctx:Announce(if which == 1 then "A LIGHT IS FAILING!" else "ANOTHER LIGHT IS FAILING!", ctx.Theme.Hazard)
			ctx:Sound("Warning")
			for _, key in { "Disc", "Ring", "Beam1", "Beam2", "Beam3", "Lens" } do
				local part = spot.Parts[key]
				ctx:Animate(part, "OMF_Pulse", { PulseMin = part.Transparency, PulseMax = 1, PulseSpeed = 4.5 + which, PulsePhase = 0 })
			end
			local flickers = 0
			ctx:Every(0.09, function()
				flickers += 1
				spot.Light.Brightness = if math.random() < 0.45 then 0.3 else 2.6 -- cosmetic: keep ctx.Rng deterministic
				return flickers < 22
			end)
			ctx:After(2, function()
				spot.Active = false
				spot.Light.Brightness = 0
				for key, part in spot.Parts do
					part:RemoveTag("OMF_Pulse")
					if key ~= "Housing" then
						ctx:Tween(part, TweenInfo.new(0.4), { Transparency = 1 })
					end
				end
				ctx:Fx("Burst", { Position = spot.Parts.Lens.Position, Color = LIGHT, Count = 24 })
				ctx:Sound("Impact", spot.Parts.Housing)
			end)
		end
		ctx:After(duration / 3 - 2, function()
			fail(1)
		end)
		ctx:After(duration * 2 / 3 - 2, function()
			fail(2)
		end)

		local exposure = {}
		local highlights = {}
		local shown = {}
		local lastSize = 0
		local startTime = os.clock()

		local function setGlow(player: Player, e: number)
			local q = math.floor(e * 20 + 0.5) / 20
			if shown[player] == q then
				return
			end
			shown[player] = q
			local h = highlights[player]
			if not h or not h.Parent then
				local character = ctx:GetCharacter(player)
				if not character then
					return
				end
				h = Instance.new("Highlight")
				h.Name = "SpotlightExposure"
				h.FillTransparency = 1
				h.OutlineTransparency = 1
				h.Parent = character
				ctx.Trove:Add(h)
				highlights[player] = h
			end
			local color = LIGHT:Lerp(DANGER, math.min(q * 1.4, 1))
			h.FillColor = color
			h.OutlineColor = color
			h.FillTransparency = 1 - 0.65 * q
			h.OutlineTransparency = 1 - q
		end

		local cleaned = false
		ctx.Trove:Connect(RunService.Heartbeat, function(dt)
			if ctx.Ended then
				if not cleaned then
					cleaned = true
					for _, h in highlights do
						h:Destroy()
					end
				end
				return
			end
			local t = os.clock() - startTime
			local phi = phase(p, duration, t)
			local r = radiusAt(p, duration, t)
			for _, spot in spots do
				spot.X, spot.Z = spotXZ(spot.Path, phi)
				spot.Root.CFrame = ctx:At(spot.X, 0.18 + (spot.Index - 1) * 0.1, spot.Z, 0, 0, 90)
			end
			-- Shrink in small steps (fewer property updates)
			if math.abs(r - lastSize) > 0.04 then
				lastSize = r
				for _, spot in spots do
					if spot.Active then
						for _, piece in layout(spot.Index, r) do
							spot.Parts[piece.Key].Size = piece.Size
						end
						spot.Light.Angle = coneAngle(r)
					end
				end
			end

			local alive = ctx:GetAlive()
			for _, player in alive do
				local pos = ctx:LocalPosition(player)
				if not pos then
					continue
				end
				local lit = false
				for _, spot in spots do
					if spot.Active and (pos.X - spot.X) ^ 2 + (pos.Z - spot.Z) ^ 2 <= (r + IN_MARGIN) ^ 2 then
						lit = true
						break
					end
				end
				local e = exposure[player] or 0
				e = if lit then math.max(e - dt / DRAIN, 0) else e + dt / p.Grace
				if e >= 1 then
					e = 0 -- a shield/extra life drops you next to a survivor with a fresh meter
					ctx:Eliminate(player, "Lost in the dark")
				end
				exposure[player] = e
				setGlow(player, e)
			end
			-- Drop the glow from anyone who is out
			for player, h in highlights do
				if not table.find(alive, player) then
					h:Destroy()
					highlights[player] = nil
					shown[player] = nil
				end
			end
		end)
	end,
}
