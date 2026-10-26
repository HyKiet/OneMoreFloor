-- Block Rain: blocks crash down onto marked squares. Watch the floor and dodge.

local CELLS = 8
local CELL = 8
local HALF = CELLS * CELL / 2
local DROP_HEIGHT = 48

local function cellCentre(i, j)
	return -HALF + (i - 0.5) * CELL, -HALF + (j - 0.5) * CELL
end

-- Telegraphs then drops a block covering `span` x `span` cells starting at (i, j).
local function dropBlock(ctx, i, j, span, telegraph)
	local x0, z0 = cellCentre(i, j)
	local offset = (span - 1) * CELL / 2
	local x, z = x0 + offset, z0 + offset
	local size = span * CELL - 0.6

	ctx:Warn(ctx:At(x, 0.12, z), Vector3.new(size, 0.2, size), telegraph)
	ctx:After(telegraph, function()
		local height = size * 0.6
		local colour = ctx.Theme.Hazard:Lerp(ctx.Theme.Secondary, ctx.Rng:NextNumber(0, 0.3))
		local block = ctx:Hazard({
			Name = "FallingBlock",
			Size = Vector3.new(size, height, size),
			CFrame = ctx:At(x, DROP_HEIGHT, z),
			Color = colour:Lerp(Color3.new(0, 0, 0), 0.25),
			Material = Enum.Material.SmoothPlastic,
			CastShadow = false,
		})
		-- glowing edges + a hot core read clearly against the dark floor
		local outline = Instance.new("SelectionBox")
		outline.Adornee = block
		outline.Color3 = colour
		outline.LineThickness = 0.18
		outline.SurfaceColor3 = colour
		outline.SurfaceTransparency = 0.55
		outline.Parent = block
		local fall = 0.38
		ctx:Tween(block, TweenInfo.new(fall, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			CFrame = ctx:At(x, height / 2, z),
		})
		ctx:After(fall, function()
			ctx:Sound("Impact", block)
			ctx:Impact(ctx:At(x, 0.1, z).Position, colour, size * 0.9 + 3, if span > 1 then 8 else 3)
			if span > 1 then
				ctx:Shake(0.6, 0.25)
			end
		end)
		-- Still deadly for a beat after landing, then sinks into the floor
		task.delay(fall + 0.2, function()
			if block.Parent then
				block.Parent = ctx.Folder
				block.CanCollide = false
				ctx:Tween(block, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					CFrame = ctx:At(x, -height / 2, z),
					Transparency = 1,
				})
				task.delay(0.35, function()
					block:Destroy()
				end)
			end
		end)
	end)
end

return {
	Id = "RainingBlocks",
	Name = "Block Rain",
	Hint = "Blocks fall on the glowing squares. Get out of the way!",
	MinFloor = 1,
	MinPlayers = 1,
	Weight = 1.1,
	BossOnly = false,
	Duration = 20,

	Build = function(ctx)
		ctx:Part({ Name = "Floor", Size = Vector3.new(CELLS * CELL, 2, CELLS * CELL), CFrame = ctx:At(0, -1, 0), Color = ctx.Theme.Floor:Lerp(Color3.new(0, 0, 0), 0.1) })
		-- Neon grid lines between the cells, with small studs at the crossings
		local lineColor = ctx.Theme.Floor:Lerp(ctx.Theme.Primary, 0.5)
		for k = 1, CELLS - 1 do
			local p = -HALF + k * CELL
			ctx:Decor({ Name = "Grid", Size = Vector3.new(CELLS * CELL, 0.06, 0.25), CFrame = ctx:At(0, 0.03, p), Color = lineColor, Material = Enum.Material.Neon })
			ctx:Decor({ Name = "Grid", Size = Vector3.new(0.25, 0.06, CELLS * CELL), CFrame = ctx:At(p, 0.03, 0), Color = lineColor, Material = Enum.Material.Neon })
		end
		ctx:Rim(HALF, HALF)

		-- Four "chute" gantries overhead where the blocks come from
		for k, c in { { 1, 1 }, { 1, -1 }, { -1, -1 }, { -1, 1 } } do
			local x, z = c[1] * (HALF + 2), c[2] * (HALF + 2)
			ctx:Decor({ Name = "Pillar", Size = Vector3.new(2, 40, 2), CFrame = ctx:At(x, 18, z), Color = ctx.Theme.Floor:Lerp(Color3.new(0, 0, 0), 0.3) })
			local lamp = ctx:Decor({ Name = "PillarLight", Size = Vector3.new(0.5, 34, 0.5), CFrame = ctx:At(x - c[1] * 1.1, 18, z - c[2] * 1.1), Color = ctx.Theme.Primary, Material = Enum.Material.Neon })
			ctx:Animate(lamp, "OMF_Pulse", { PulseMin = 0, PulseMax = 0.7, PulseSpeed = 0.6, PulsePhase = k / 4 })
		end
		for _, s in { { 0, HALF + 2, CELLS * CELL + 6, 1.2 }, { 0, -HALF - 2, CELLS * CELL + 6, 1.2 }, { HALF + 2, 0, 1.2, CELLS * CELL + 4 }, { -HALF - 2, 0, 1.2, CELLS * CELL + 4 } } do
			ctx:Decor({ Name = "Gantry", Size = Vector3.new(s[3], 1.2, s[4]), CFrame = ctx:At(s[1], 38, s[2]), Color = ctx.Theme.Floor:Lerp(Color3.new(0, 0, 0), 0.3) })
			ctx:Decor({ Name = "GantryLight", Size = Vector3.new(math.max(s[3] - 1, 0.4), 0.2, math.max(s[4] - 1, 0.4)), CFrame = ctx:At(s[1], 37.3, s[2]), Color = ctx.Theme.Hazard, Material = Enum.Material.Neon })
		end
	end,

	Start = function(ctx)
		local d = math.clamp(ctx.Difficulty, 0, 1.5)
		local telegraph = 1.2 - 0.55 * math.min(d / 1.2, 1)
		local interval = math.max(1.5 - 0.6 * d, 0.75)
		local maxCells = math.floor(CELLS * CELLS * 0.4)

		for _ = 1, 4 do
			local x, z = cellCentre(ctx.Rng:NextInteger(1, CELLS), ctx.Rng:NextInteger(1, CELLS))
			ctx:SpawnCoin(ctx:At(x, 3, z).Position)
		end

		ctx:Every(interval, function(elapsed)
			local count = math.min(2 + math.floor(elapsed / 4) + math.floor(d * 4), maxCells)
			local used = {}
			for _ = 1, count do
				local i, j = ctx.Rng:NextInteger(1, CELLS), ctx.Rng:NextInteger(1, CELLS)
				local key = i * 100 + j
				if not used[key] then
					used[key] = true
					-- Big 2x2 slabs on deeper floors
					if d >= 0.6 and i < CELLS and j < CELLS and ctx.Rng:NextNumber() < 0.15 then
						dropBlock(ctx, i, j, 2, telegraph + 0.2)
					else
						dropBlock(ctx, i, j, 1, telegraph)
					end
				end
			end
			-- Occasionally target where players are standing
			if d >= 0.3 then
				for _, player in ctx:GetAlive() do
					local pos = ctx:LocalPosition(player)
					if pos and ctx.Rng:NextNumber() < 0.35 then
						local i = math.clamp(math.floor((pos.X + HALF) / CELL) + 1, 1, CELLS)
						local j = math.clamp(math.floor((pos.Z + HALF) / CELL) + 1, 1, CELLS)
						dropBlock(ctx, i, j, 1, telegraph)
					end
				end
			end
			return nil
		end)
	end,
}
