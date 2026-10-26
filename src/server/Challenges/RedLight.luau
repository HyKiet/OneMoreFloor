-- Red Light, Green Light: run on green, freeze on red, reach the finish before time runs out.
-- A giant Watcher at the far end turns to face the track on red and zaps anyone who moves.

local WIDTH = 40
local START_Z = 46
local FINISH_Z = -40 -- finish zone runs from here to the far end
local FAR_Z = -52
local MOVE_LIMIT = 1.5
local HEAD_Y = 25

local GREEN = Color3.fromRGB(60, 255, 120)
local YELLOW = Color3.fromRGB(255, 215, 60)
local RED = Color3.fromRGB(255, 50, 60)

local function inFinish(pos)
	return pos.Z <= FINISH_Z and math.abs(pos.X) <= WIDTH / 2 + 1 and pos.Y > -2
end

-- facing = true turns the Watcher's face toward the players.
local function headCFrame(ctx, facing: boolean): CFrame
	return ctx:At(0, HEAD_Y, FAR_Z - 6, 0, if facing then 180 else 0, 0)
end

local function turnHead(ctx, facing: boolean, time: number)
	local head = ctx.State.Head
	local target = headCFrame(ctx, facing)
	local info = TweenInfo.new(time, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	for _, piece in head do
		ctx:Tween(piece.Part, info, { CFrame = target * piece.Offset })
	end
end

local function setLight(ctx, color)
	ctx.State.Glow.Color = color
	for _, part in ctx.State.Lit do
		part.Color = color
	end
end

return {
	Id = "RedLight",
	Name = "Red Light, Green Light",
	Hint = "Move on green. Freeze on red. Reach the finish line!",
	MinFloor = 1,
	MinPlayers = 1,
	Weight = 1,
	BossOnly = false,
	Zone = 1, -- B1-B9
	Duration = function(ctx)
		return 25 - 4 * math.min(ctx.Difficulty, 1)
	end,

	Build = function(ctx)
		local length = START_Z - FAR_Z + 4
		local centreZ = (START_Z + 2 + FAR_Z - 2) / 2
		local dark = ctx.Theme.Floor:Lerp(Color3.new(0, 0, 0), 0.4)
		ctx:Part({ Name = "Track", Size = Vector3.new(WIDTH, 2, length), CFrame = ctx:At(0, -1, centreZ), Color = ctx.Theme.Floor:Lerp(Color3.new(0, 0, 0), 0.1) })
		ctx:Decor({ Name = "Skirt", Size = Vector3.new(WIDTH + 0.6, 0.8, length + 0.6), CFrame = ctx:At(0, -1.6, centreZ), Color = dark })

		-- Lane stripes and distance ticks
		for k = -1, 1 do
			ctx:Decor({ Name = "Lane", Size = Vector3.new(0.3, 0.07, length - 4), CFrame = ctx:At(k * WIDTH / 4, 0.035, centreZ), Color = ctx.Theme.Floor:Lerp(ctx.Theme.Primary, 0.35) })
		end
		for z = START_Z - 15, FINISH_Z + 6, -12 do
			ctx:Decor({ Name = "Tick", Size = Vector3.new(WIDTH - 2, 0.03, 0.5), CFrame = ctx:At(0, 0.015, z), Color = ctx.Theme.Floor:Lerp(ctx.Theme.Primary, 0.2) })
		end

		-- Start line and finish zone (tops 0.04+ above the lane stripes so nothing z-fights)
		ctx:Decor({ Name = "StartLine", Size = Vector3.new(WIDTH, 0.12, 1), CFrame = ctx:At(0, 0.06, START_Z - 3), Color = ctx.Theme.Primary, Material = Enum.Material.Neon })
		local finishDepth = FINISH_Z - FAR_Z
		local finish = ctx:Decor({ Name = "Finish", Size = Vector3.new(WIDTH, 0.12, finishDepth), CFrame = ctx:At(0, 0.06, (FINISH_Z + FAR_Z) / 2), Color = ctx.Theme.Secondary, Material = Enum.Material.Neon, Transparency = 0.45 })
		ctx:Animate(finish, "OMF_Pulse", { PulseMin = 0.35, PulseMax = 0.7, PulseSpeed = 0.6 })
		-- Checkered finish edge
		for k = 0, 9 do
			ctx:Decor({ Name = "Checker", Size = Vector3.new(WIDTH / 10, 0.16, 1.2), CFrame = ctx:At(-WIDTH / 2 + (k + 0.5) * WIDTH / 10, 0.08, FINISH_Z + 0.6), Color = if k % 2 == 0 then Color3.new(1, 1, 1) else Color3.new(0.05, 0.05, 0.05), Material = Enum.Material.Neon })
		end
		-- Finish arch
		for _, side in { -1, 1 } do
			ctx:Decor({ Name = "ArchPost", Size = Vector3.new(2, 13, 2), CFrame = ctx:At(side * (WIDTH / 2 + 1.5), 6.5, FINISH_Z), Color = dark, CanCollide = true })
			ctx:Decor({ Name = "ArchLight", Size = Vector3.new(0.4, 11, 0.4), CFrame = ctx:At(side * (WIDTH / 2 + 0.4), 6.5, FINISH_Z), Color = ctx.Theme.Secondary, Material = Enum.Material.Neon })
		end
		local beam = ctx:Decor({ Name = "ArchBeam", Size = Vector3.new(WIDTH + 5, 2.4, 1.4), CFrame = ctx:At(0, 13.2, FINISH_Z), Color = dark })
		local sign = Instance.new("SurfaceGui")
		sign.Face = Enum.NormalId.Back
		sign.LightInfluence = 0
		sign.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sign.PixelsPerStud = 30
		sign.Parent = beam
		local text = Instance.new("TextLabel")
		text.Size = UDim2.fromScale(1, 1)
		text.BackgroundTransparency = 1
		text.Font = Enum.Font.Michroma
		text.Text = "FINISH"
		text.TextScaled = true
		text.TextColor3 = ctx.Theme.Secondary
		text.Parent = sign

		-- The Watcher: a pillar with a cube head that turns around on red
		ctx:Decor({ Name = "Pillar", Size = Vector3.new(5, HEAD_Y - 6, 5), CFrame = ctx:At(0, (HEAD_Y - 6) / 2, FAR_Z - 6), Color = dark, CanCollide = true })
		ctx:Decor({ Name = "Collar", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.2, 10, 10), CFrame = ctx:At(0, HEAD_Y - 7, FAR_Z - 6, 0, 0, 90), Color = ctx.Theme.Primary, Material = Enum.Material.Neon })
		local head = {}
		local lit = {}
		local function piece(offset: CFrame, props): BasePart
			props.CFrame = headCFrame(ctx, false) * offset
			local part = ctx:Decor(props)
			table.insert(head, { Part = part, Offset = offset })
			return part
		end
		local headPart = piece(CFrame.new(), { Name = "Head", Size = Vector3.new(17, 13, 13), Color = ctx.Theme.Floor:Lerp(Color3.new(0, 0, 0), 0.45), CanCollide = true })
		local edges = Instance.new("SelectionBox")
		edges.Adornee = headPart
		edges.Color3 = ctx.Theme.Primary
		edges.LineThickness = 0.25
		edges.SurfaceTransparency = 1
		edges.Parent = headPart
		-- Face (local -Z): a visor band with two big eyes
		local visor = piece(CFrame.new(0, 1.2, -6.55), { Name = "Visor", Size = Vector3.new(15, 4.6, 0.3), Color = GREEN, Material = Enum.Material.Neon, Transparency = 0.35 })
		table.insert(lit, visor)
		for _, x in { -3.8, 3.8 } do
			table.insert(lit, piece(CFrame.new(x, 1.2, -6.75), { Name = "Eye", Size = Vector3.new(3.4, 2.6, 0.25), Color = GREEN, Material = Enum.Material.Neon }))
		end
		piece(CFrame.new(0, -3.8, -6.6), { Name = "Grille", Size = Vector3.new(8, 0.7, 0.25), Color = ctx.Theme.Floor:Lerp(ctx.Theme.Primary, 0.4), Material = Enum.Material.Neon })
		-- Back of the head (what you see on green): calm stripes
		for k = -1, 1 do
			piece(CFrame.new(k * 4.5, 0, 6.55), { Name = "Stripe", Size = Vector3.new(0.9, 9.5, 0.25), Color = ctx.Theme.Primary, Material = Enum.Material.Neon })
		end
		ctx.State.Head = head
		ctx.State.Visor = visor
		ctx.State.Glow = ctx:Glow(visor, GREEN, 60, 2.5)

		-- Side rails that change colour with the light
		for _, side in { -1, 1 } do
			table.insert(lit, ctx:Decor({ Name = "Rail", Size = Vector3.new(0.8, 0.8, length), CFrame = ctx:At(side * (WIDTH / 2 + 0.4), 0.4, centreZ), Color = GREEN, Material = Enum.Material.Neon, CanCollide = true }))
			table.insert(lit, ctx:Decor({ Name = "Underglow", Size = Vector3.new(0.4, 0.3, length), CFrame = ctx:At(side * (WIDTH / 2 + 0.2), -2.1, centreZ), Color = GREEN, Material = Enum.Material.Neon }))
		end
		ctx.State.Lit = lit

		-- Obstacles to weave around on deeper floors
		if ctx.Difficulty >= 0.5 then
			for _ = 1, 4 + math.floor(ctx.Difficulty * 4) do
				local x = ctx.Rng:NextNumber(-WIDTH / 2 + 4, WIDTH / 2 - 4)
				local z = ctx.Rng:NextNumber(FINISH_Z + 8, START_Z - 12)
				ctx:Part({ Name = "Pillar", Size = Vector3.new(4, 6, 4), CFrame = ctx:At(x, 3, z), Color = ctx.Theme.Floor:Lerp(ctx.Theme.Primary, 0.2) })
				ctx:Decor({ Name = "PillarCap", Size = Vector3.new(4.2, 0.3, 4.2), CFrame = ctx:At(x, 6.1, z), Color = ctx.Theme.Primary, Material = Enum.Material.Neon })
			end
		end

		-- Spawns along the start line, facing the finish
		local spawns = {}
		for k = 0, 7 do
			local x = -WIDTH / 2 + 4 + k * (WIDTH - 8) / 7
			local pos = ctx:At(x, 3, START_Z).Position
			table.insert(spawns, CFrame.lookAt(pos, ctx:At(x, 3, FAR_Z).Position))
		end
		ctx:SetSpawns(spawns)
	end,

	Start = function(ctx)
		local d = math.clamp(ctx.Difficulty, 0, 1.5)
		local yellow = 0.7 - 0.3 * math.min(d, 1)

		for _ = 1, 5 do
			ctx:SpawnCoin(ctx:At(ctx.Rng:NextNumber(-16, 16), 3, ctx.Rng:NextNumber(FINISH_Z + 6, START_Z - 10)).Position)
		end

		ctx.State.Red = false
		task.spawn(function()
			while not ctx.Ended do
				setLight(ctx, GREEN)
				turnHead(ctx, false, 0.5)
				ctx:Announce("GREEN LIGHT", GREEN)
				if not ctx:Wait(ctx.Rng:NextNumber(1.6, 3.4) - d * 0.6) then
					return
				end
				setLight(ctx, YELLOW)
				turnHead(ctx, true, yellow + 0.35)
				if not ctx:Wait(yellow) then
					return
				end
				setLight(ctx, RED)
				ctx:Announce("RED LIGHT!", RED)
				ctx:Sound("Alarm")
				ctx.State.Red = true
				-- Grace period, then anyone who moves is out
				if not ctx:Wait(0.35) then
					return
				end
				local last = {}
				for _, player in ctx:GetAlive() do
					last[player] = ctx:LocalPosition(player)
				end
				local redTime = ctx.Rng:NextNumber(1.6, 2.8)
				-- A scanner plane sweeps down the track while the Watcher looks
				local scanner = ctx:Decor({ Name = "Scanner", Size = Vector3.new(WIDTH + 2, 7, 0.3), CFrame = ctx:At(0, 3.5, FINISH_Z), Color = RED, Material = Enum.Material.Neon, Transparency = 0.78 })
				ctx:Tween(scanner, TweenInfo.new(redTime, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { CFrame = ctx:At(0, 3.5, START_Z - 2) })
				local t = 0
				while t < redTime and not ctx.Ended do
					task.wait(0.25)
					t += 0.25
					for _, player in ctx:GetAlive() do
						local pos = ctx:LocalPosition(player)
						local prev = last[player]
						-- Horizontal distance only, so landing from a jump started on yellow is forgiven
						if pos and prev and not inFinish(prev) and Vector3.new(pos.X - prev.X, 0, pos.Z - prev.Z).Magnitude > MOVE_LIMIT then
							local root = ctx:GetRoot(player)
							if root then
								ctx:Fx("Shot", { From = ctx.State.Visor.Position, To = root.Position, Color = RED })
							end
							ctx:Eliminate(player, "Moved on red")
						end
						last[player] = pos
					end
				end
				scanner:Destroy()
				ctx.State.Red = false
			end
		end)
	end,

	Judge = function(ctx)
		for _, player in ctx:GetAlive() do
			local pos = ctx:LocalPosition(player)
			if not pos or not inFinish(pos) then
				ctx:Eliminate(player, "Didn't reach the finish")
			end
		end
	end,
}
