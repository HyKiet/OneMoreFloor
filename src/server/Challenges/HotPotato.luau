-- Hot Potato: someone is holding a bomb. Touch another player to pass it before it blows.

local SIZE = 56
local HALF = SIZE / 2
local PASS_RANGE = 4.5
local PASS_COOLDOWN = 0.6

local function giveBomb(ctx, holders, player)
	local root = ctx:GetRoot(player)
	local character = ctx:GetCharacter(player)
	if not root or not character then
		return false
	end
	local bomb = ctx:Part({
		Name = "Bomb",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(2.4, 2.4, 2.4),
		CFrame = root.CFrame * CFrame.new(0, 4, 0),
		Color = Color3.fromRGB(30, 30, 35),
		Material = Enum.Material.SmoothPlastic,
		Anchored = false,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Massless = true,
	})
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = bomb
	weld.Parent = bomb

	local fuse = ctx:Part({ Name = "Fuse", Size = Vector3.new(0.5, 0.5, 0.5), CFrame = bomb.CFrame * CFrame.new(0, 1.4, 0), Color = ctx.Theme.Hazard, Material = Enum.Material.Neon, Anchored = false, CanCollide = false, CanQuery = false, CanTouch = false, Massless = true })
	local fuseWeld = Instance.new("WeldConstraint")
	fuseWeld.Part0 = bomb
	fuseWeld.Part1 = fuse
	fuseWeld.Parent = fuse
	-- a hissing spark fountain on the fuse and a red band so the bomb reads from anywhere
	ctx:Emitter(fuse, {
		Texture = "Sparks",
		Color = ColorSequence.new(Color3.fromRGB(255, 230, 140), ctx.Theme.Hazard),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) }),
		Speed = NumberRange.new(4, 9),
		SpreadAngle = Vector2.new(35, 35),
		Lifetime = NumberRange.new(0.2, 0.45),
		Acceleration = Vector3.new(0, -20, 0),
		Rate = 40,
	})
	local band = ctx:Part({ Name = "Band", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, 2.6, 2.6), CFrame = bomb.CFrame * CFrame.Angles(0, 0, math.rad(90)), Color = ctx.Theme.Hazard, Material = Enum.Material.Neon, Anchored = false, CanCollide = false, CanQuery = false, CanTouch = false, Massless = true, CastShadow = false })
	local bandWeld = Instance.new("WeldConstraint")
	bandWeld.Part0 = bomb
	bandWeld.Part1 = band
	bandWeld.Parent = band
	band.Parent = bomb
	ctx:Glow(fuse, Color3.fromRGB(255, 170, 80), 10, 1.5)

	local highlight = Instance.new("Highlight")
	highlight.Adornee = character
	highlight.FillColor = ctx.Theme.Hazard
	highlight.OutlineColor = Color3.new(1, 1, 1)
	highlight.FillTransparency = 0.55
	highlight.Parent = ctx.Folder

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(80, 40)
	gui.StudsOffset = Vector3.new(0, 2.6, 0)
	gui.AlwaysOnTop = true
	gui.Parent = bomb
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0
	label.Text = ""
	label.Parent = gui

	holders[player] = { Bomb = bomb, Fuse = fuse, Highlight = highlight, Label = label, Since = os.clock() }
	return true
end

local function takeBomb(holders, player)
	local h = holders[player]
	if h then
		h.Bomb:Destroy()
		h.Fuse:Destroy()
		h.Highlight:Destroy()
		holders[player] = nil
	end
end

local function explode(ctx, position)
	local blast = ctx:Part({ Name = "Blast", Shape = Enum.PartType.Ball, Size = Vector3.new(3, 3, 3), CFrame = CFrame.new(position), Color = ctx.Theme.Hazard, Material = Enum.Material.Neon, Transparency = 0.1, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
	ctx:Tween(blast, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(20, 20, 20), Transparency = 1 })
	task.delay(0.5, function()
		blast:Destroy()
	end)
	ctx:Impact(position - Vector3.new(0, 3, 0), ctx.Theme.Hazard, 24, 14)
	ctx:Fx("Burst", { Position = position, Color = Color3.fromRGB(255, 200, 90), Count = 50 })
	ctx:Sound("Explosion", position)
	ctx:Shake(1, 0.5)
end

local function contains(list, item)
	return table.find(list, item) ~= nil
end

-- Snapshot of current holders so we can hand bombs around while looping.
local function holderList(holders)
	local list = {}
	for player in holders do
		table.insert(list, player)
	end
	return list
end

return {
	Id = "HotPotato",
	Name = "Hot Potato",
	Hint = "Touch another player to pass the bomb before it explodes!",
	MinFloor = 2,
	MinPlayers = 2,
	Weight = 1.1,
	BossOnly = false,
	Zone = 2, -- B10-B19
	Duration = 25,

	Build = function(ctx)
		ctx:Part({ Name = "Floor", Size = Vector3.new(SIZE, 2, SIZE), CFrame = ctx:At(0, -1, 0), Color = ctx.Theme.Floor:Lerp(Color3.new(0, 0, 0), 0.1) })
		ctx:Rim(HALF, HALF, ctx.Theme.Primary, ctx.Theme.Hazard)
		-- Caution stripes around the edge of the floor
		local stripes = 10
		for side = 0, 3 do
			for k = 0, stripes - 1 do
				if k % 2 == 0 then
					local along = -HALF + (k + 0.5) * SIZE / stripes
					local x, z = along, HALF - 1.6
					if side == 1 then
						x, z = HALF - 1.6, -along
					elseif side == 2 then
						x, z = -along, -HALF + 1.6
					elseif side == 3 then
						x, z = -HALF + 1.6, along
					end
					local yaw = if side % 2 == 0 then 0 else 90
					ctx:Decor({ Name = "Caution", Size = Vector3.new(SIZE / stripes - 0.4, 0.06, 2), CFrame = ctx:At(x, 0.03, z, 0, yaw, 0), Color = Color3.fromRGB(255, 200, 40) })
				end
			end
		end
		-- Glass walls so the only way out is the bomb
		for _, s in { { 0, HALF + 0.5, SIZE + 2, 1 }, { 0, -HALF - 0.5, SIZE + 2, 1 }, { HALF + 0.5, 0, 1, SIZE }, { -HALF - 0.5, 0, 1, SIZE } } do
			ctx:Part({ Name = "Wall", Size = Vector3.new(s[3], 8, s[4]), CFrame = ctx:At(s[1], 4, s[2]), Color = ctx.Theme.Primary, Material = Enum.Material.Glass, Transparency = 0.7, CastShadow = false })
			ctx:Decor({ Name = "WallTop", Size = Vector3.new(s[3], 0.4, s[4]), CFrame = ctx:At(s[1], 8.2, s[2]), Color = ctx.Theme.Primary, Material = Enum.Material.Neon })
			ctx:Decor({ Name = "WallMid", Size = Vector3.new(math.max(s[3] - 0.6, 0.2), 0.15, math.max(s[4] - 0.6, 0.2)), CFrame = ctx:At(s[1], 4, s[2]), Color = ctx.Theme.Primary, Material = Enum.Material.Neon, Transparency = 0.5 })
		end
		-- Cover to juke around, with glowing caps
		local d = ctx.Difficulty
		local blocks = { { -12, -12, 4, 4 }, { 12, 12, 4, 4 }, { 12, -12, 4, 4 }, { -12, 12, 4, 4 }, { 0, 0, 10, 2 } }
		for k, b in blocks do
			if k <= 4 or d >= 0.4 then
				ctx:Part({ Name = "Cover", Size = Vector3.new(b[3], 5, b[4]), CFrame = ctx:At(b[1], 2.5, b[2]), Color = ctx.Theme.Floor:Lerp(ctx.Theme.Secondary, 0.25) })
				local cap = ctx:Decor({ Name = "CoverCap", Size = Vector3.new(b[3] + 0.2, 0.3, b[4] + 0.2), CFrame = ctx:At(b[1], 5.1, b[2]), Color = ctx.Theme.Secondary, Material = Enum.Material.Neon })
				ctx:Animate(cap, "OMF_Pulse", { PulseMin = 0, PulseMax = 0.5, PulseSpeed = 0.7, PulsePhase = k / 5 })
			end
		end
	end,

	Start = function(ctx)
		local d = math.clamp(ctx.Difficulty, 0, 1.5)
		local holders = {}
		local total = ctx.Duration or 25

		for _ = 1, 4 do
			ctx:SpawnCoin(ctx:At(ctx.Rng:NextNumber(-HALF + 4, HALF - 4), 3, ctx.Rng:NextNumber(-HALF + 4, HALF - 4)).Position)
		end

		while not ctx.Ended do
			local alive = ctx:GetAlive()
			if #alive < 2 then
				ctx:Finish()
				return
			end
			local remaining = total - ctx:Elapsed()
			local fuseTime = ctx.Rng:NextNumber(7, 10) - d * 1.5
			if remaining < 5 then
				return -- not enough time for a fair round; everyone left standing survives
			end
			fuseTime = math.min(fuseTime, remaining - 1)

			-- Hand out bombs
			local wanted = if #alive >= 5 then 2 else 1
			local pool = table.clone(alive)
			for _ = 1, wanted do
				if #pool == 0 then
					break
				end
				local pick = table.remove(pool, ctx.Rng:NextInteger(1, #pool))
				if giveBomb(ctx, holders, pick) then
					ctx:Announce(pick.DisplayName .. " has the bomb!", ctx.Theme.Hazard)
				end
			end
			ctx:Sound("Countdown")

			local blowAt = os.clock() + fuseTime
			while os.clock() < blowAt and not ctx.Ended do
				task.wait(0.1)
				alive = ctx:GetAlive()
				local left = blowAt - os.clock()

				for _, holder in holderList(holders) do
					local h = holders[holder]
					if not h then
						continue
					end
					-- Holder got eliminated another way: the bomb jumps to someone else
					if not contains(alive, holder) then
						takeBomb(holders, holder)
						local candidates = {}
						for _, p in alive do
							if not holders[p] then
								table.insert(candidates, p)
							end
						end
						if #candidates > 0 then
							giveBomb(ctx, holders, candidates[ctx.Rng:NextInteger(1, #candidates)])
						end
					else
						h.Label.Text = string.format("%.1f", math.max(left, 0))
						-- Blink faster as the fuse burns down
						local rate = if left < 2 then 0.1 elseif left < 4 then 0.25 else 0.5
						h.Fuse.Transparency = if (os.clock() % (rate * 2)) < rate then 0 else 0.8
					end
				end

				-- Passing
				for _, holder in holderList(holders) do
					local h = holders[holder]
					if h and os.clock() - h.Since >= PASS_COOLDOWN then
						local hr = ctx:GetRoot(holder)
						if hr then
							for _, other in alive do
								if other ~= holder and not holders[other] then
									local orr = ctx:GetRoot(other)
									if orr and (orr.Position - hr.Position).Magnitude < PASS_RANGE then
										takeBomb(holders, holder)
										if giveBomb(ctx, holders, other) then
											ctx:Announce(other.DisplayName .. " has the bomb!", ctx.Theme.Hazard)
											ctx:Sound("Whoosh", orr)
										end
										break
									end
								end
							end
						end
					end
				end
			end
			if ctx.Ended then
				return
			end

			-- BOOM
			for _, holder in holderList(holders) do
				local pos = holders[holder].Bomb.Position
				takeBomb(holders, holder)
				explode(ctx, pos)
				ctx:Eliminate(holder, "Blew up")
			end
			if not ctx:Wait(2) then
				return
			end
		end
	end,
}
