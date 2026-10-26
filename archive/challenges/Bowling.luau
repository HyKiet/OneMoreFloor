-- Bowling Night: giant balls barrel down the lane. You are the pins.

local WIDTH = 56
local LENGTH = 92

local function plan(ctx)
	local d = math.clamp(ctx.Difficulty, 0, 1.5)
	return {
		Interval = math.max(2.6 - 1.1 * d, 1),
		PerWave = 1 + math.floor(d * 1.5),
		Speed = 26 + 22 * d,
		Size = 10 + math.floor(3 * math.min(d, 1)),
		Telegraph = 1.25 - 0.55 * math.min(d, 1),
		Sides = d >= 0.5,
	}
end

-- Welds a decorative part onto a rolling ball.
local function attach(ball: BasePart, part: BasePart)
	part.Anchored = false
	part.Massless = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = ball
	weld.Part1 = part
	weld.Parent = part
	part.Parent = ball
end

-- Telegraphs a lane, then rolls a ball down it. `axis` is "Z" (along the lane) or "X" (across).
local function roll(ctx, p, axis, dir, offset)
	local size = p.Size
	local span = if axis == "Z" then LENGTH else WIDTH
	local startAlong = -dir * (span / 2 - size / 2)
	local function local3(along, y)
		return if axis == "Z" then Vector3.new(offset, y, along) else Vector3.new(along, y, offset)
	end
	local stripSize = if axis == "Z" then Vector3.new(size, 0.2, span) else Vector3.new(span, 0.2, size)
	ctx:Warn(ctx.Origin * CFrame.new(local3(0, 0.15)), stripSize, p.Telegraph, nil, { Sweep = local3(dir, 0) })
	ctx:Sound("Warning")

	ctx:After(p.Telegraph, function()
		local startPos = (ctx.Origin * CFrame.new(local3(startAlong, size / 2 + 0.2))).Position
		local direction = ctx.Origin:VectorToWorldSpace(local3(dir, 0) - local3(0, 0)).Unit
		local shell = ctx.Theme.Primary:Lerp(ctx.Theme.Secondary, ctx.Rng:NextNumber())
		local ball = ctx:Part({
			Name = "BowlingBall",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(size, size, size),
			CFrame = CFrame.lookAt(startPos, startPos + direction),
			Color = shell:Lerp(Color3.new(0, 0, 0), 0.55),
			Material = Enum.Material.SmoothPlastic,
			Reflectance = 0.15,
			Anchored = false,
			CastShadow = false,
			CustomPhysicalProperties = PhysicalProperties.new(8, 0.15, 0.1, 1, 1),
		})
		-- Neon equator band (rolls with the ball) and three finger holes
		attach(ball, ctx:Part({ Name = "Band", Shape = Enum.PartType.Cylinder, Size = Vector3.new(size * 0.12, size * 1.02, size * 1.02), CFrame = ball.CFrame * CFrame.Angles(0, math.rad(90), 0), Color = shell, Material = Enum.Material.Neon }))
		for k, o in { Vector2.new(-1, 1), Vector2.new(1, 1), Vector2.new(0, -0.6) } do
			local s = if k == 3 then 1.3 else 1
			local outward = Vector3.new(o.X, o.Y + 2.4, -size / 2).Unit
			local at = ball.CFrame * (outward * (size / 2 - 0.12))
			local hole = ctx:Part({ Name = "Hole", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, s, s), Color = Color3.new(0.02, 0.02, 0.03), CFrame = CFrame.lookAt(at, at + ball.CFrame:VectorToWorldSpace(outward)) * CFrame.Angles(0, math.rad(90), 0) })
			attach(ball, hole)
		end
		pcall(function()
			ball:SetNetworkOwner(nil)
		end)
		ball.AssemblyLinearVelocity = direction * p.Speed
		ball.AssemblyAngularVelocity = ctx.Origin.UpVector:Cross(direction) * (p.Speed / (size / 2))
		ctx:Glow(ball, shell, size * 1.6, 1.4)
		ctx:Impact((ctx.Origin * CFrame.new(local3(startAlong, 0.2))).Position, shell, size, 4)
		ctx:Sound("Whoosh", ball)
		task.delay(span / p.Speed + 3, function()
			ball:Destroy()
		end)
	end)
end

return {
	Id = "Bowling",
	Name = "Bowling Night",
	Hint = "Giant balls roll down the lane. Don't get knocked off!",
	MinFloor = 3,
	MinPlayers = 1,
	Weight = 0.9,
	BossOnly = false,
	Duration = 20,

	Build = function(ctx)
		local wood = ctx.Theme.Floor:Lerp(Color3.fromRGB(150, 100, 60), 0.35)
		ctx:Part({ Name = "Lane", Size = Vector3.new(WIDTH, 2, LENGTH), CFrame = ctx:At(0, -1, 0), Color = wood, Material = Enum.Material.WoodPlanks })
		-- Lane boards and the five target dots / arrows
		for k = -6, 6 do
			ctx:Decor({ Name = "Board", Size = Vector3.new(0.12, 0.04, LENGTH), CFrame = ctx:At(k * 4, 0.02, 0), Color = wood:Lerp(Color3.new(0, 0, 0), 0.3) })
		end
		for k = -2, 2 do
			ctx:Decor({ Name = "Arrow", ClassName = "WedgePart", Size = Vector3.new(2, 0.1, 4), CFrame = ctx:At(k * 9, 0.05, 12 - math.abs(k) * 3, 0, 180, 0), Color = ctx.Theme.Secondary, Material = Enum.Material.Neon })
			ctx:Decor({ Name = "Dot", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.08, 1.2, 1.2), CFrame = ctx:At(k * 9, 0.04, 30, 0, 0, 90), Color = ctx.Theme.Primary, Material = Enum.Material.Neon })
		end
		-- Foul line near the elevator, glowing gutters down both sides
		ctx:Decor({ Name = "FoulLine", Size = Vector3.new(WIDTH, 0.08, 0.6), CFrame = ctx:At(0, 0.04, LENGTH / 2 - 4), Color = ctx.Theme.Hazard, Material = Enum.Material.Neon })
		for _, side in { -1, 1 } do
			ctx:Decor({ Name = "Gutter", Size = Vector3.new(1.4, 0.6, LENGTH + 2), CFrame = ctx:At(side * (WIDTH / 2 + 0.7), -0.7, 0), Color = ctx.Theme.Floor:Lerp(Color3.new(0, 0, 0), 0.5) })
			ctx:Decor({ Name = "GutterGlow", Size = Vector3.new(0.6, 0.1, LENGTH + 2), CFrame = ctx:At(side * (WIDTH / 2 + 0.7), -0.38, 0), Color = ctx.Theme.Primary, Material = Enum.Material.Neon })
			ctx:Decor({ Name = "Edge", Size = Vector3.new(0.4, 0.4, LENGTH), CFrame = ctx:At(side * (WIDTH / 2 - 0.2), 0.2, 0), Color = ctx.Theme.Primary, Material = Enum.Material.Neon })
		end
		ctx:Decor({ Name = "Underglow", Size = Vector3.new(WIDTH + 3, 0.3, LENGTH + 2), CFrame = ctx:At(0, -2.2, 0), Color = ctx.Theme.Secondary, Material = Enum.Material.Neon })

		-- Giant pins at the far end, just for show
		for k, x in { -9, 0, 9, -4.5, 4.5 } do
			local z = -LENGTH / 2 - (if k <= 3 then 7 else 3)
			ctx:Decor({ Name = "Pin", Shape = Enum.PartType.Cylinder, Size = Vector3.new(9, 3.4, 3.4), CFrame = ctx:At(x, 4.5, z, 0, 0, 90), Color = Color3.fromRGB(245, 245, 250) })
			ctx:Decor({ Name = "PinHead", Shape = Enum.PartType.Ball, Size = Vector3.new(3, 3, 3), CFrame = ctx:At(x, 10, z), Color = Color3.fromRGB(245, 245, 250) })
			ctx:Decor({ Name = "PinStripe", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 3.6, 3.6), CFrame = ctx:At(x, 7.6, z, 0, 0, 90), Color = ctx.Theme.Hazard, Material = Enum.Material.Neon })
		end
		-- Pin deck backdrop with a breathing neon strike sign
		ctx:Decor({ Name = "Deck", Size = Vector3.new(WIDTH + 4, 18, 1.5), CFrame = ctx:At(0, 9, -LENGTH / 2 - 11), Color = ctx.Theme.Floor:Lerp(Color3.new(0, 0, 0), 0.5) })
		for k = 1, 3 do
			local stripe = ctx:Decor({ Name = "Strike", Size = Vector3.new(WIDTH - 6 - k * 8, 0.6, 0.3), CFrame = ctx:At(0, 13 + k * 1.4, -LENGTH / 2 - 10.1), Color = if k == 2 then ctx.Theme.Secondary else ctx.Theme.Primary, Material = Enum.Material.Neon })
			ctx:Animate(stripe, "OMF_Pulse", { PulseMin = 0, PulseMax = 0.7, PulseSpeed = 1, PulsePhase = k / 3 })
		end
	end,

	Start = function(ctx)
		local p = plan(ctx)

		for _ = 1, 5 do
			ctx:SpawnCoin(ctx:At(ctx.Rng:NextNumber(-WIDTH / 2 + 4, WIDTH / 2 - 4), 3, ctx.Rng:NextNumber(-LENGTH / 2 + 6, LENGTH / 2 - 6)).Position)
		end

		ctx:Every(p.Interval, function()
			local used = {}
			for _ = 1, p.PerWave do
				local lane = ctx.Rng:NextInteger(-2, 2)
				if not used[lane] then
					used[lane] = true
					local dir = if ctx.Rng:NextNumber() < 0.75 then 1 else -1
					roll(ctx, p, "Z", dir, lane * 10)
				end
			end
			if p.Sides and ctx.Rng:NextNumber() < 0.4 then
				local dir = if ctx.Rng:NextNumber() < 0.5 then 1 else -1
				roll(ctx, p, "X", dir, ctx.Rng:NextInteger(-3, 3) * 12)
			end
			return nil
		end)
	end,
}
