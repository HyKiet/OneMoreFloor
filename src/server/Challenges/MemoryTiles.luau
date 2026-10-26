-- Colour Memory: a colour is called, then every other tile vanishes. Deeper floors hide the colours first.

local GRID = 8
local TILE = 7
local GAP = 0.5
local PITCH = TILE + GAP
local HALF = GRID * PITCH / 2
local BEACON_Y = 24

-- Revealed tiles glow at a much lower value than the called colour: 64 neon tiles make one big lit floor,
-- which blows out to a glare at full value. Yellow and orange keep more value and shift hue apart so they read
-- as yellow / orange instead of orange / red.
local function tileGlow(color: Color3, value: number): Color3
	local h, s = color:ToHSV()
	return Color3.fromHSV(h, s, value)
end

-- Deep, saturated values: neon + bloom brightens them, and lighter tones blow out to white.
local PALETTE = {
	{ Name = "RED", Color = Color3.fromRGB(225, 25, 45), Tile = tileGlow(Color3.fromRGB(225, 25, 45), 0.45) },
	{ Name = "BLUE", Color = Color3.fromRGB(25, 70, 235), Tile = tileGlow(Color3.fromRGB(25, 70, 235), 0.5) },
	{ Name = "GREEN", Color = Color3.fromRGB(20, 185, 60), Tile = tileGlow(Color3.fromRGB(20, 185, 60), 0.45) },
	{ Name = "YELLOW", Color = Color3.fromRGB(235, 190, 15), Tile = Color3.fromHSV(0.15, 0.94, 0.56) },
	{ Name = "PURPLE", Color = Color3.fromRGB(135, 40, 230), Tile = tileGlow(Color3.fromRGB(135, 40, 230), 0.5) },
	{ Name = "ORANGE", Color = Color3.fromRGB(240, 100, 15), Tile = Color3.fromHSV(0.085, 0.95, 0.55) },
}
local HIDDEN = Color3.fromRGB(70, 72, 82)
local IDLE_BEACON = Color3.fromRGB(235, 235, 245)

-- Round timings, shared by Duration and Start so they always agree.
local function plan(ctx)
	local d = math.clamp(ctx.Difficulty, 0, 1.5)
	local rounds = 3 + (if d >= 0.5 then 1 else 0) + (if d >= 1 then 1 else 0)
	local colours = math.min(4 + math.floor(d * 2), #PALETTE)
	return {
		Rounds = rounds,
		Colours = colours,
		Show = 2.2,
		Countdown = 3.6 - 1.4 * math.min(d, 1),
		Hide = d >= 0.6, -- colours turn grey before the call
		Gone = 1.8,
		Break = 0.8,
	}
end

local function tileCentre(i, j)
	return -HALF + (i - 0.5) * PITCH, -HALF + (j - 0.5) * PITCH
end

-- The beacon cube and frame lines show the called colour from anywhere in the arena.
local function setBeacon(ctx, color: Color3)
	for _, part in ctx.State.Beacon do
		part.Color = color
	end
	ctx.State.BeaconLight.Color = color
end

return {
	Id = "MemoryTiles",
	Name = "Colour Memory",
	Hint = "Stand on the colour that gets called before the other tiles vanish!",
	MinFloor = 1,
	MinPlayers = 1,
	Weight = 1,
	BossOnly = false,
	Zone = 1, -- B1-B9
	Duration = function(ctx)
		local p = plan(ctx)
		return p.Rounds * (p.Show + p.Countdown + p.Gone + p.Break) + 1.5
	end,

	Build = function(ctx)
		local tiles = {}
		for i = 1, GRID do
			for j = 1, GRID do
				local x, z = tileCentre(i, j)
				local part = ctx:Part({
					Name = "Tile",
					Size = Vector3.new(TILE, 1.5, TILE),
					CFrame = ctx:At(x, -0.75, z),
					Color = HIDDEN,
					Material = Enum.Material.SmoothPlastic,
				})
				table.insert(tiles, { Part = part, Home = part.CFrame, Colour = 1 })
			end
		end
		ctx.State.Tiles = tiles
		-- A glowing grid far below makes the pit read as a pit
		ctx:Decor({ Name = "PitGlow", Size = Vector3.new(GRID * PITCH + 4, 0.5, GRID * PITCH + 4), CFrame = ctx:At(0, -26, 0), Color = ctx.Theme.Hazard, Material = Enum.Material.Neon, Transparency = 0.55 })
		for k = -2, 2 do
			ctx:Decor({ Name = "PitLine", Size = Vector3.new(GRID * PITCH + 4, 0.4, 0.4), CFrame = ctx:At(0, -25.6, k * 13), Color = ctx.Theme.Hazard:Lerp(Color3.new(1, 1, 1), 0.3), Material = Enum.Material.Neon })
			ctx:Decor({ Name = "PitLine", Size = Vector3.new(0.4, 0.4, GRID * PITCH + 4), CFrame = ctx:At(k * 13, -25.6, 0), Color = ctx.Theme.Hazard:Lerp(Color3.new(1, 1, 1), 0.3), Material = Enum.Material.Neon })
		end

		local beacon = {}
		for _, s in { { 0, HALF + 1, GRID * PITCH + 3, 1 }, { 0, -HALF - 1, GRID * PITCH + 3, 1 }, { HALF + 1, 0, 1, GRID * PITCH + 1 }, { -HALF - 1, 0, 1, GRID * PITCH + 1 } } do
			table.insert(beacon, ctx:Decor({ Name = "Frame", Size = Vector3.new(s[3], 0.6, s[4]), CFrame = ctx:At(s[1], -0.3, s[2]), Color = IDLE_BEACON, Material = Enum.Material.Neon }))
		end

		-- Beacon: a big turning cube high above the middle, framed by an outer cage
		local beaconCF = ctx:At(0, BEACON_Y, 0)
		local cube = ctx:Decor({ Name = "Beacon", Size = Vector3.new(6, 6, 6), CFrame = beaconCF * CFrame.Angles(math.rad(35), 0, math.rad(45)), Color = IDLE_BEACON, Material = Enum.Material.Neon })
		ctx:Animate(cube, "OMF_Spin", { SpinSpeed = 0.9 })
		table.insert(beacon, cube)
		local cage = ctx:Decor({ Name = "Cage", Size = Vector3.new(9, 9, 9), CFrame = beaconCF, Color = ctx.Theme.Floor, Transparency = 1 })
		local cageLines = Instance.new("SelectionBox")
		cageLines.Adornee = cage
		cageLines.Color3 = ctx.Theme.Primary
		cageLines.LineThickness = 0.15
		cageLines.SurfaceTransparency = 1
		cageLines.Parent = cage
		ctx:Animate(cage, "OMF_Spin", { SpinSpeed = -0.4 })
		ctx.State.Beacon = beacon
		ctx.State.BeaconLight = ctx:Glow(cube, IDLE_BEACON, 40, 1.2)

		-- Four palette totems at the corners showing which colours are in play
		local p = plan(ctx)
		for _, c in { { 1, 1 }, { 1, -1 }, { -1, -1 }, { -1, 1 } } do
			local x, z = c[1] * (HALF + 4), c[2] * (HALF + 4)
			ctx:Decor({ Name = "Totem", Size = Vector3.new(2.2, p.Colours * 1.6 + 1, 2.2), CFrame = ctx:At(x, (p.Colours * 1.6 + 1) / 2 - 1, z), Color = ctx.Theme.Floor:Lerp(Color3.new(0, 0, 0), 0.4) })
			for n = 1, p.Colours do
				ctx:Decor({ Name = "Swatch", Size = Vector3.new(2.4, 1, 2.4), CFrame = ctx:At(x, n * 1.6 - 0.6, z), Color = PALETTE[n].Color, Material = Enum.Material.Neon })
			end
		end
	end,

	Start = function(ctx)
		local p = plan(ctx)
		local tiles = ctx.State.Tiles
		local centre = ctx:At(0, 0.2, 0).Position

		for round = 1, p.Rounds do
			-- Shuffle colours, making sure every colour in play gets a fair share
			local bag = {}
			for k = 1, #tiles do
				bag[k] = (k - 1) % p.Colours + 1
			end
			for k = #bag, 2, -1 do
				local r = ctx.Rng:NextInteger(1, k)
				bag[k], bag[r] = bag[r], bag[k]
			end
			for k, tile in tiles do
				tile.Colour = bag[k]
				tile.Part.CFrame = tile.Home
				tile.Part.Transparency = 0
				tile.Part.CanCollide = true
				tile.Part.Material = Enum.Material.Neon
				tile.Part.Color = PALETTE[bag[k]].Tile
			end
			setBeacon(ctx, IDLE_BEACON)
			-- the reveal ripples out from the middle
			ctx:Fx("Impact", { Position = centre, Color = Color3.new(1, 1, 1), Radius = HALF + 6, Debris = 0 })
			-- A coin on a random tile each round
			local coinTile = tiles[ctx.Rng:NextInteger(1, #tiles)]
			ctx:SpawnCoin(coinTile.Home.Position + Vector3.new(0, 3.5, 0))

			if not ctx:Wait(p.Show) then
				return
			end

			if p.Hide then
				for _, tile in tiles do
					tile.Part.Material = Enum.Material.SmoothPlastic
					tile.Part.Color = HIDDEN
				end
			end

			local target = PALETTE[ctx.Rng:NextInteger(1, p.Colours)]
			local targetIndex = table.find(PALETTE, target)
			setBeacon(ctx, target.Color)
			ctx:Fx("Burst", { Position = ctx:At(0, BEACON_Y, 0).Position, Color = target.Color, Count = 40 })
			ctx:Announce(target.Name .. "!", target.Color)
			ctx:Sound("Countdown")
			if not ctx:Wait(p.Countdown) then
				return
			end

			-- Everything that is not the called colour drops away
			local rubble = {}
			for _, tile in tiles do
				if tile.Colour == targetIndex then
					tile.Part.Material = Enum.Material.Neon
					tile.Part.Color = target.Tile
				else
					tile.Part.CanCollide = false
					local spin = ctx.Rng:NextNumber(-25, 25)
					ctx:Tween(tile.Part, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
						CFrame = tile.Home * CFrame.new(0, -16, 0) * CFrame.Angles(math.rad(spin), 0, math.rad(-spin)),
						Transparency = 1,
					})
					if #rubble < 16 and ctx.Rng:NextNumber() < 0.3 then
						table.insert(rubble, tile.Home.Position)
					end
				end
			end
			ctx:Fx("Chunks", { Positions = rubble, Color = HIDDEN, Size = 1.6 })
			ctx:Shake(0.4, 0.3)
			ctx:Sound("Impact")
			if not ctx:Wait(p.Gone) then
				return
			end

			if round < p.Rounds then
				-- Bring the floor back grey before the next shuffle
				for _, tile in tiles do
					tile.Part.CFrame = tile.Home
					tile.Part.Transparency = 0
					tile.Part.CanCollide = true
					tile.Part.Material = Enum.Material.SmoothPlastic
					tile.Part.Color = HIDDEN
				end
				setBeacon(ctx, IDLE_BEACON)
				if not ctx:Wait(p.Break) then
					return
				end
			end
		end
		ctx:Finish()
	end,
}
