-- Falling Floor: every tile you step on flashes and drops a moment later. Keep moving.

local GRID = 10
local TILE = 7
local GAP = 0.4
local PITCH = TILE + GAP
local HALF = GRID * PITCH / 2

local function tileCentre(i: number, j: number): (number, number)
	return -HALF + (i - 0.5) * PITCH, -HALF + (j - 0.5) * PITCH
end

-- Drops a tile: sag and flash, then fall away tumbling.
local function dropTile(ctx, tile, delay: number, rubble: { Vector3 })
	if tile.State ~= "Idle" then
		return
	end
	tile.State = "Triggered"
	local part = tile.Part
	part.Material = Enum.Material.Neon
	ctx:Tween(part, TweenInfo.new(delay * 0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 1, true), {
		Color = ctx.Theme.Hazard,
	})
	-- a small sag sells the "it's giving way" moment
	ctx:Tween(part, TweenInfo.new(delay, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		CFrame = tile.Home * CFrame.new(0, -0.35, 0),
	})
	ctx:After(delay, function()
		tile.State = "Gone"
		part.CanCollide = false
		part.Color = ctx.Theme.Hazard
		table.insert(rubble, part.Position)
		local tumble = ctx.Rng:NextNumber(-35, 35)
		ctx:Tween(part, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			CFrame = tile.Home * CFrame.new(0, -28, 0) * CFrame.Angles(math.rad(tumble), 0, math.rad(-tumble * 0.6)),
			Transparency = 1,
		})
	end)
end

return {
	Id = "FallingTiles",
	Name = "Falling Floor",
	Hint = "Tiles drop shortly after you step on them. Keep moving!",
	MinFloor = 1,
	MinPlayers = 1,
	Weight = 1.2,
	BossOnly = false,
	Duration = 20,

	Build = function(ctx)
		local tiles = {}
		for i = 1, GRID do
			tiles[i] = {}
			for j = 1, GRID do
				local x, z = tileCentre(i, j)
				local shade = if (i + j) % 2 == 0 then 0.16 else 0.3
				local part = ctx:Part({
					Name = "Tile",
					Size = Vector3.new(TILE, 1.5, TILE),
					CFrame = ctx:At(x, -0.75, z),
					Color = ctx.Theme.Floor:Lerp(ctx.Theme.Primary, shade),
				})
				tiles[i][j] = { Part = part, Home = part.CFrame, State = "Idle" }
			end
		end
		ctx.State.Tiles = tiles

		-- Light leaking up through the seams; the lines stay hanging over the void as tiles drop
		local seam = ctx.Theme.Primary:Lerp(ctx.Theme.Floor, 0.25)
		for k = 1, GRID - 1 do
			local p = -HALF + k * PITCH - GAP / 2
			ctx:Decor({ Name = "Seam", Size = Vector3.new(GRID * PITCH, 0.12, 0.18), CFrame = ctx:At(0, -0.9, p), Color = seam, Material = Enum.Material.Neon })
			ctx:Decor({ Name = "Seam", Size = Vector3.new(0.18, 0.12, GRID * PITCH), CFrame = ctx:At(p, -0.9, 0), Color = seam, Material = Enum.Material.Neon })
		end

		-- Frame: bright edge, dark skirt, underglow, and four breathing corner posts
		local edge = HALF + 0.6
		for _, side in { { 0, edge, 2 * edge + 1.2, 1.2 }, { 0, -edge, 2 * edge + 1.2, 1.2 }, { edge, 0, 1.2, 2 * edge }, { -edge, 0, 1.2, 2 * edge } } do
			ctx:Decor({ Name = "Frame", Size = Vector3.new(side[3], 1.6, side[4]), CFrame = ctx:At(side[1], -0.8, side[2]), Color = ctx.Theme.Floor:Lerp(Color3.new(0, 0, 0), 0.45) })
			ctx:Decor({ Name = "FrameLine", Size = Vector3.new(math.max(side[3] - 0.6, 0.3), 0.15, math.max(side[4] - 0.6, 0.3)), CFrame = ctx:At(side[1], 0.06, side[2]), Color = ctx.Theme.Primary, Material = Enum.Material.Neon })
			ctx:Decor({ Name = "Underglow", Size = Vector3.new(side[3], 0.3, side[4]), CFrame = ctx:At(side[1], -1.75, side[2]), Color = ctx.Theme.Secondary, Material = Enum.Material.Neon })
		end
		for k, c in { { 1, 1 }, { 1, -1 }, { -1, -1 }, { -1, 1 } } do
			ctx:Decor({ Name = "Post", Size = Vector3.new(1.6, 5, 1.6), CFrame = ctx:At(c[1] * edge, 2.5, c[2] * edge), Color = ctx.Theme.Floor:Lerp(Color3.new(0, 0, 0), 0.3) })
			local cap = ctx:Decor({ Name = "PostCap", Size = Vector3.new(1.9, 0.6, 1.9), CFrame = ctx:At(c[1] * edge, 5.3, c[2] * edge), Color = ctx.Theme.Secondary, Material = Enum.Material.Neon })
			ctx:Animate(cap, "OMF_Pulse", { PulseMin = 0, PulseMax = 0.6, PulseSpeed = 0.8, PulsePhase = k / 4 })
		end
	end,

	Start = function(ctx)
		local tiles = ctx.State.Tiles
		local d = math.clamp(ctx.Difficulty, 0, 1.5)
		local delay = 0.9 - 0.55 * math.min(d / 1.2, 1)
		local rubble: { Vector3 } = {}

		-- Coins sit on random tiles
		for _ = 1, 4 do
			local i, j = ctx.Rng:NextInteger(1, GRID), ctx.Rng:NextInteger(1, GRID)
			local x, z = tileCentre(i, j)
			ctx:SpawnCoin(ctx:At(x, 3, z).Position)
		end

		-- Tiles under players
		ctx:Every(0.1, function()
			for _, player in ctx:GetAlive() do
				local pos = ctx:LocalPosition(player)
				if pos and pos.Y > -1 and pos.Y < 7 then
					local i = math.floor((pos.X + HALF) / PITCH) + 1
					local j = math.floor((pos.Z + HALF) / PITCH) + 1
					local row = tiles[i]
					local tile = row and row[j]
					if tile then
						dropTile(ctx, tile, delay, rubble)
					end
				end
			end
			-- one batched rubble effect per tick for every tile that just fell
			if #rubble > 0 then
				ctx:Fx("Chunks", { Positions = table.clone(rubble), Color = ctx.Theme.Hazard, Size = 1.6 })
				table.clear(rubble)
			end
			return nil
		end)

		-- Deeper floors also crumble random tiles on their own
		if d >= 0.3 then
			local interval = math.max(1.6 - d * 0.8, 0.5)
			ctx:Every(interval, function()
				local i, j = ctx.Rng:NextInteger(1, GRID), ctx.Rng:NextInteger(1, GRID)
				dropTile(ctx, tiles[i][j], delay + 0.4, rubble)
				return nil
			end)
		end
	end,
}
