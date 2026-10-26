-- Wrecking Balls: cross a long bridge while giant wrecking balls swing across it, then reach the far
-- platform. No rails on the bridge: falling off is out. Each pendulum follows
-- angle(t) = Amp * sin(Omega * t + Phase) about the bridge axis; clients replay it with OMF_Swing and the
-- server sweeps every ball against every player each frame (far too fast for hazard boxes).

local RunService = game:GetService("RunService")

local BRIDGE_W = 14
local DECK_W = 24
local START_Z, DECK_END = 38, 48 -- start deck spans z = 38..48 (the bridge starts at its front edge)
local FINISH_Z, FAR_Z = -40, -54 -- finish platform spans z = -40..-54
local PIVOT_Y = 30
local CHAIN = 26 -- pivot to ball centre
local BALL = 7
local BALL_R = BALL / 2
local AMP = 0.95
local HIT_PAD = 1 -- reach around the player's body segment
local PILLAR_X = 28.5 -- the swing reaches CHAIN * sin(AMP) + BALL_R ~ 24.6 to either side
local FIRST_Z, LAST_Z = 33, -35 -- pendulum planes; each ball's danger band is +-(BALL_R + HIT_PAD)
local GATE_Z = START_Z + 0.4

local function plan(ctx)
	local d = math.clamp(ctx.Difficulty, 0, 1.5)
	local m = math.min(d, 1)
	return {
		Count = 5 + (if d >= 0.45 then 1 else 0) + (if d >= 1 then 1 else 0),
		Omega = 1.6 + 0.8 * m,
		D = d,
	}
end

local function inFinish(pos: Vector3): boolean
	return pos.Z <= FINISH_Z + 0.5 and math.abs(pos.X) <= DECK_W / 2 + 1 and pos.Y > -2
end

-- Ball centre (arena-local) for a pendulum hanging at plane z, swung `angle` radians toward +X.
local function ballCentre(angle: number, z: number): Vector3
	return Vector3.new(CHAIN * math.sin(angle), PIVOT_Y - CHAIN * math.cos(angle), z)
end

-- Platform slab with a dark skirt and neon underglow. `drop` nudges the skirt layers so neighbouring
-- slabs' skirts never share a face where they overlap.
local function slab(ctx, name: string, width: number, z0: number, z1: number, drop: number, color: Color3, material: Enum.Material?)
	local length = math.abs(z1 - z0)
	local z = (z0 + z1) / 2
	ctx:Part({ Name = name, Size = Vector3.new(width, 2, length), CFrame = ctx:At(0, -1, z), Color = color, Material = material or Enum.Material.SmoothPlastic })
	ctx:Decor({ Name = "Skirt", Size = Vector3.new(width + 0.6, 0.9, length + 0.6), CFrame = ctx:At(0, -1.6 - drop, z), Color = ctx.Theme.Floor:Lerp(Color3.new(0, 0, 0), 0.5) })
	ctx:Decor({ Name = "Underglow", Size = Vector3.new(width + 1.2, 0.25, length + 1.2), CFrame = ctx:At(0, -2.175 - drop, z), Color = ctx.Theme.Secondary, Material = Enum.Material.Neon })
end

-- Low glowing safety rails around a platform's open edges (sides + the far end).
local function rails(ctx, z0: number, z1: number, endZ: number, color: Color3)
	local length = math.abs(z1 - z0)
	local z = (z0 + z1) / 2
	for _, side in { -1, 1 } do
		ctx:Decor({ Name = "Rail", Size = Vector3.new(0.8, 1, length), CFrame = ctx:At(side * (DECK_W / 2 - 0.4), 0.5, z), Color = color, Material = Enum.Material.Neon, CanCollide = true })
	end
	ctx:Decor({ Name = "Rail", Size = Vector3.new(DECK_W - 1.6, 1, 0.8), CFrame = ctx:At(0, 0.5, endZ), Color = color, Material = Enum.Material.Neon, CanCollide = true })
end

-- One pendulum: gantry (two pillars outside the swing + crossbeam) and the swinging chain and ball.
local function buildPendulum(ctx, z: number, phase: number, omega: number, startTime: number, swinging: { BasePart })
	local dark = ctx.Theme.Floor:Lerp(Color3.new(0, 0, 0), 0.45)
	local steel = ctx.Theme.Floor:Lerp(Color3.new(0, 0, 0), 0.6)
	for k, side in { -1, 1 } do
		ctx:Decor({ Name = "GantryPillar", Size = Vector3.new(3, 60, 3), CFrame = ctx:At(side * PILLAR_X, 3, z), Color = dark, Material = Enum.Material.Metal })
		ctx:Decor({ Name = "GantryLight", Size = Vector3.new(0.3, 48, 0.8), CFrame = ctx:At(side * (PILLAR_X - 1.6), 4, z), Color = ctx.Theme.Primary, Material = Enum.Material.Neon })
		local beacon = ctx:Decor({ Name = "Beacon", Shape = Enum.PartType.Ball, Size = Vector3.new(1.6, 1.6, 1.6), CFrame = ctx:At(side * PILLAR_X, 33.7, z), Color = ctx.Theme.Hazard, Material = Enum.Material.Neon })
		ctx:Animate(beacon, "OMF_Pulse", { PulseMin = 0, PulseMax = 0.9, PulseSpeed = omega / (2 * math.pi), PulsePhase = (phase / (2 * math.pi)) + k * 0.5 })
	end
	ctx:Decor({ Name = "Crossbeam", Size = Vector3.new(PILLAR_X * 2 + 2.6, 2, 2.6), CFrame = ctx:At(0, PIVOT_Y + 1.6, z), Color = dark, Material = Enum.Material.Metal })
	ctx:Decor({ Name = "BeamLight", Size = Vector3.new(PILLAR_X * 2 - 3.4, 0.2, 1), CFrame = ctx:At(0, PIVOT_Y + 0.55, z), Color = ctx.Theme.Hazard, Material = Enum.Material.Neon })
	ctx:Decor({ Name = "PivotHub", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3.4, 2.4, 2.4), CFrame = ctx:At(0, PIVOT_Y, z, 0, 90, 0), Color = steel, Material = Enum.Material.Metal })

	-- Swinging parts, posed for angle 0 (hanging straight down) relative to the pivot
	local pivot = ctx:At(0, PIVOT_Y, z)
	local angle0 = AMP * math.sin(omega * (workspace:GetServerTimeNow() - startTime) + phase)
	local function swing(offset: CFrame, props): BasePart
		props.CFrame = pivot * CFrame.fromAxisAngle(Vector3.zAxis, angle0) * offset
		local part = ctx:Decor(props)
		ctx:Animate(part, "OMF_Swing", {
			SwingPivot = pivot,
			SwingOffset = offset,
			SwingAmp = AMP,
			SwingOmega = omega,
			SwingPhase = phase,
			SwingAxis = Vector3.zAxis,
			StartTime = startTime,
		})
		table.insert(swinging, part)
		return part
	end
	local vertical = CFrame.Angles(0, 0, math.rad(90)) -- cylinder axis along the chain
	local rodLength = CHAIN - BALL_R - 0.4
	swing(CFrame.new(0, -rodLength / 2, 0) * vertical, { Name = "Chain", Shape = Enum.PartType.Cylinder, Size = Vector3.new(rodLength, 0.6, 0.6), Color = steel, Material = Enum.Material.Metal })
	for _, y in { -8, -16 } do
		swing(CFrame.new(0, y, 0) * vertical, { Name = "ChainCollar", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, 1.1, 1.1), Color = ctx.Theme.Primary, Material = Enum.Material.Neon })
	end
	swing(CFrame.new(0, -(CHAIN - BALL_R) - 0.1, 0) * vertical, { Name = "BallCap", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.2, 2.8, 2.8), Color = steel, Material = Enum.Material.Metal })
	local ball = swing(CFrame.new(0, -CHAIN, 0), { Name = "WreckingBall", Shape = Enum.PartType.Ball, Size = Vector3.new(BALL, BALL, BALL), Color = ctx.Theme.Floor:Lerp(Color3.new(0, 0, 0), 0.55), Material = Enum.Material.Metal })
	-- two crossing hazard belts (different diameters so they never share a surface)
	swing(CFrame.new(0, -CHAIN, 0), { Name = "BallBelt", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.9, BALL + 0.3, BALL + 0.3), Color = ctx.Theme.Hazard, Material = Enum.Material.Neon })
	swing(CFrame.new(0, -CHAIN, 0) * vertical, { Name = "BallBelt", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.9, BALL + 0.5, BALL + 0.5), Color = ctx.Theme.Hazard, Material = Enum.Material.Neon })
	-- motion blur ribbon so the swing reads at a glance
	ctx:Trail(ball, Vector3.new(0, 0, -2.4), Vector3.new(0, 0, 2.4), ctx.Theme.Hazard, 0.16)

	-- Danger band painted across the bridge under the swing
	local stripe = ctx:Decor({ Name = "DangerBand", Size = Vector3.new(BRIDGE_W - 1.4, 0.06, BALL), CFrame = ctx:At(0, 0.03, z), Color = ctx.Theme.Hazard, Material = Enum.Material.Neon, Transparency = 0.84 })
	ctx:Animate(stripe, "OMF_Pulse", { PulseMin = 0.74, PulseMax = 0.92, PulseSpeed = omega / math.pi, PulsePhase = phase / math.pi })
	for _, s in { -1, 1 } do
		ctx:Decor({ Name = "DangerEdge", Size = Vector3.new(BRIDGE_W - 1.8, 0.1, 0.25), CFrame = ctx:At(0, 0.09, z + s * BALL_R), Color = ctx.Theme.Hazard:Lerp(Color3.new(0, 0, 0), 0.2) })
	end
end

return {
	Id = "WreckingBalls",
	Name = "Wrecking Balls",
	Hint = "Cross the bridge between the swinging wrecking balls. Reach the far platform!",
	MinFloor = 3,
	MinPlayers = 1,
	Weight = 1,
	BossOnly = false,
	Duration = function(ctx)
		return 24 - 3 * math.min(ctx.Difficulty, 1)
	end,

	Build = function(ctx)
		local p = plan(ctx)
		local deckColor = ctx.Theme.Floor:Lerp(Color3.new(0, 0, 0), 0.1)
		local dark = ctx.Theme.Floor:Lerp(Color3.new(0, 0, 0), 0.4)

		-- Start deck, bridge and finish platform (skirt layers offset so they never share a face)
		slab(ctx, "StartDeck", DECK_W, START_Z, DECK_END, 0, deckColor)
		slab(ctx, "Bridge", BRIDGE_W, START_Z, FINISH_Z, 0.05, ctx.Theme.Floor:Lerp(Color3.new(0, 0, 0), 0.2), Enum.Material.DiamondPlate)
		slab(ctx, "FinishDeck", DECK_W, FINISH_Z, FAR_Z, 0, deckColor)
		local bridgeLength = START_Z - FINISH_Z
		local bridgeZ = (START_Z + FINISH_Z) / 2
		for _, side in { -1, 1 } do
			ctx:Decor({ Name = "EdgeLine", Size = Vector3.new(0.5, 0.12, bridgeLength), CFrame = ctx:At(side * (BRIDGE_W / 2 - 0.25), 0.04, bridgeZ), Color = ctx.Theme.Primary, Material = Enum.Material.Neon })
		end
		-- A keel truss under the bridge
		ctx:Decor({ Name = "Keel", Size = Vector3.new(3, 3, bridgeLength - 2), CFrame = ctx:At(0, -4, bridgeZ), Color = dark, Material = Enum.Material.Metal })
		ctx:Decor({ Name = "KeelLight", Size = Vector3.new(3.2, 0.3, bridgeLength - 4), CFrame = ctx:At(0, -4.6, bridgeZ), Color = ctx.Theme.Primary, Material = Enum.Material.Neon })

		-- Start deck: rails, start line and a force-field gate that drops when the floor starts
		rails(ctx, START_Z + 0.4, DECK_END, DECK_END - 0.4, ctx.Theme.Primary)
		ctx:Decor({ Name = "StartLine", Size = Vector3.new(DECK_W - 2, 0.12, 0.8), CFrame = ctx:At(0, 0.06, START_Z + 1.2), Color = ctx.Theme.Primary, Material = Enum.Material.Neon })
		ctx.State.Gate = ctx:Part({ Name = "Gate", Size = Vector3.new(DECK_W + 12, 15.6, 0.6), CFrame = ctx:At(0, 6.2, GATE_Z), Color = ctx.Theme.Primary, Material = Enum.Material.ForceField, Transparency = 0.2, CanQuery = false, CastShadow = false })

		-- Finish: pulsing pad, checkered edge, rails and an arch
		rails(ctx, FINISH_Z - 1.2, FAR_Z, FAR_Z + 0.4, ctx.Theme.Secondary)
		for k = 0, 9 do
			local w = (DECK_W - 2) / 10
			ctx:Decor({ Name = "Checker", Size = Vector3.new(w, 0.16, 1.2), CFrame = ctx:At(-(DECK_W - 2) / 2 + (k + 0.5) * w, 0.08, FINISH_Z - 0.6), Color = if k % 2 == 0 then Color3.new(1, 1, 1) else Color3.new(0.05, 0.05, 0.05), Material = Enum.Material.Neon })
		end
		local padDepth = (FINISH_Z - 1.2) - (FAR_Z + 0.8)
		local pad = ctx:Decor({ Name = "Finish", Size = Vector3.new(DECK_W - 2, 0.12, padDepth), CFrame = ctx:At(0, 0.06, (FINISH_Z - 1.2 + FAR_Z + 0.8) / 2), Color = ctx.Theme.Secondary, Material = Enum.Material.Neon, Transparency = 0.45 })
		ctx:Animate(pad, "OMF_Pulse", { PulseMin = 0.35, PulseMax = 0.7, PulseSpeed = 0.6 })
		ctx:Glow(pad, ctx.Theme.Secondary, 26, 1.5)
		for _, side in { -1, 1 } do
			ctx:Decor({ Name = "ArchPost", Size = Vector3.new(2, 17, 2), CFrame = ctx:At(side * (DECK_W / 2 + 1.5), 5, FINISH_Z - 1), Color = dark })
			ctx:Decor({ Name = "ArchLight", Size = Vector3.new(0.4, 11, 0.4), CFrame = ctx:At(side * (DECK_W / 2 + 0.4), 6.5, FINISH_Z - 1), Color = ctx.Theme.Secondary, Material = Enum.Material.Neon })
		end
		local beam = ctx:Decor({ Name = "ArchBeam", Size = Vector3.new(DECK_W + 5, 2.4, 1.4), CFrame = ctx:At(0, 14.7, FINISH_Z - 1), Color = dark })
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

		-- Pendulums, evenly spaced, with staggered phases so there is always a rhythm to read
		local startTime = workspace:GetServerTimeNow()
		local balls = {}
		local swinging = {}
		local base = ctx.Rng:NextNumber(0, math.pi * 2)
		for k = 1, p.Count do
			local z = FIRST_Z + (LAST_Z - FIRST_Z) * (k - 1) / (p.Count - 1)
			local phase = base + k * math.pi * 0.55 + ctx.Rng:NextNumber(-0.35, 0.35)
			buildPendulum(ctx, z, phase, p.Omega, startTime, swinging)
			table.insert(balls, { Z = z, Phase = phase })
		end
		-- Forward chevrons on the safe strips between the balls
		local band = BALL_R + HIT_PAD
		for k = 1, #balls - 1 do
			local gap = (balls[k].Z - balls[k + 1].Z) - band * 2
			if gap >= 4 then
				local z = (balls[k].Z + balls[k + 1].Z) / 2
				-- a "V" whose tip points down the bridge (-Z); the two arms sit 0.04 apart
				for i, s in { -1, 1 } do
					ctx:Decor({ Name = "Chevron", Size = Vector3.new(0.45, 0.1, 2.6), CFrame = ctx:At(s * 0.8, 0.01 + i * 0.04, z + 0.6, 0, s * 40, 0), Color = ctx.Theme.Secondary, Material = Enum.Material.Neon, Transparency = 0.2 })
				end
			end
		end
		ctx.State.Plan = p
		ctx.State.Balls = balls
		ctx.State.Swinging = swinging
		ctx.State.StartTime = startTime

		-- Spawns on the start deck, facing down the bridge
		local spawns = {}
		for k = 0, 7 do
			local x = -DECK_W / 2 + 3 + k * (DECK_W - 6) / 7
			local z = if k % 2 == 0 then 43 else 45.5
			local pos = ctx:At(x, 3, z).Position
			table.insert(spawns, CFrame.lookAt(pos, ctx:At(x, 3, FAR_Z).Position))
		end
		ctx.State.Spawns = spawns
		ctx:SetSpawns(spawns)
	end,

	Start = function(ctx)
		local p = ctx.State.Plan
		local balls = ctx.State.Balls
		local startTime = ctx.State.StartTime

		-- Anyone who slipped past the gate during the briefing goes back to the deck, then the gate drops
		for i, player in ctx:GetAlive() do
			local pos = ctx:LocalPosition(player)
			if pos and pos.Z < GATE_Z + 1 then
				local spawns = ctx.State.Spawns
				ctx:Teleport(player, spawns[(i - 1) % #spawns + 1])
			end
		end
		local gate = ctx.State.Gate
		gate.CanCollide = false
		ctx:Tween(gate, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1, CFrame = ctx:At(0, -3, GATE_Z) })
		task.delay(0.45, function()
			gate:Destroy()
		end)
		ctx:Fx("Burst", { Position = ctx:At(0, 2, GATE_Z).Position, Color = ctx.Theme.Primary, Count = 30 })

		-- Coins along the bridge: some on the safe strips, some right in a ball's path
		for k = 1, 6 do
			local z
			if k % 2 == 0 then
				z = balls[ctx.Rng:NextInteger(1, #balls)].Z
			else
				z = ctx.Rng:NextNumber(LAST_Z, FIRST_Z)
			end
			ctx:SpawnCoin(ctx:At(ctx.Rng:NextNumber(-4.5, 4.5), 3, z).Position)
		end

		-- Precise swept test: each frame, step every ball from its last angle to its current one and
		-- eliminate anyone whose body segment (feet..head) comes within BALL_R + HIT_PAD of its centre.
		local reach = BALL_R + HIT_PAD
		local stopped = false
		ctx.Trove:Connect(RunService.Heartbeat, function()
			if ctx.Ended then
				if not stopped then
					stopped = true
					local now = workspace:GetServerTimeNow()
					for _, part in ctx.State.Swinging do
						if part.Parent then
							part:SetAttribute("StopTime", now)
						end
					end
				end
				return
			end
			local t = workspace:GetServerTimeNow() - startTime
			local bodies = {}
			for _, player in ctx:GetAlive() do
				local root = ctx:GetRoot(player)
				if root then
					local character = ctx:GetCharacter(player)
					table.insert(bodies, {
						Player = player,
						Pos = ctx.Origin:PointToObjectSpace(root.Position),
						Scale = if character then character:GetScale() else 1,
					})
				end
			end
			for _, ball in balls do
				local a1 = AMP * math.sin(p.Omega * t + ball.Phase)
				local a0 = ball.Last or a1
				ball.Last = a1
				local steps = math.clamp(math.ceil(math.abs(a1 - a0) * CHAIN / 0.5), 1, 24)
				for _, body in bodies do
					local pos, s = body.Pos, body.Scale
					if body.Hit or math.abs(pos.Z - ball.Z) > reach + 0.5 * s then
						continue
					end
					local lo, hi = pos.Y - 1.8 * s, pos.Y + 1.5 * s
					for i = 1, steps do
						local c = ballCentre(a0 + (a1 - a0) * i / steps, ball.Z)
						local nearest = Vector3.new(pos.X, math.clamp(c.Y, lo, hi), pos.Z)
						if (c - nearest).Magnitude < BALL_R + HIT_PAD * s then
							body.Hit = true
							local world = ctx.Origin:PointToWorldSpace(c)
							ctx:Impact(ctx.Origin:PointToWorldSpace(pos), ctx.Theme.Hazard, 9, 6)
							ctx:Sound("Impact", world)
							ctx:Shake(0.6, 0.3)
							ctx:Eliminate(body.Player, "Smashed")
							break
						end
					end
				end
			end
		end)

		-- Everyone across: no need to wait for the clock
		ctx:Every(0.25, function()
			local alive = ctx:GetAlive()
			if #alive == 0 then
				return nil
			end
			for _, player in alive do
				local pos = ctx:LocalPosition(player)
				if not pos or not inFinish(pos) then
					return nil
				end
			end
			ctx:Announce("ALL ACROSS!", ctx.Theme.Secondary)
			ctx:Finish()
			return false
		end)
	end,

	Judge = function(ctx)
		for _, player in ctx:GetAlive() do
			local pos = ctx:LocalPosition(player)
			if not pos or not inFinish(pos) then
				ctx:Eliminate(player, "Didn't make it across")
			end
		end
	end,
}
