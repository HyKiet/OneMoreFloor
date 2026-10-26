-- One elevator run: a group of players descending floor after floor until everyone has left or died.
-- Phases: Descending -> Briefing -> Challenge -> Results -> Decision -> (Descending...) -> Ended

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Curses = require(ReplicatedStorage.Shared.Curses)
local Format = require(ReplicatedStorage.Shared.Format)
local Net = require(ReplicatedStorage.Shared.Net)
local Rarity = require(ReplicatedStorage.Shared.Rarity)
local Relics = require(ReplicatedStorage.Shared.Relics)
local Trove = require(ReplicatedStorage.Packages.Trove)

local Services = script.Parent.Parent.Services
local DataService = require(Services.DataService)
local EconomyService = require(Services.EconomyService)
local LobbyService = require(Services.LobbyService)
local LeaderboardService = require(Services.LeaderboardService)
local Analytics = require(Services.Analytics)
local Badges = require(Services.Badges)

local Cab = require(script.Parent.Cab)
local ChallengeRegistry = require(script.Parent.ChallengeRegistry)
local Context = require(script.Parent.Context)
local Modifiers = require(script.Parent.Modifiers)

local remotes = {
	RunUpdate = Net.Event("RunUpdate"),
	Eliminated = Net.Event("Eliminated"),
	CashedOut = Net.Event("CashedOut"),
	RelicFound = Net.Event("RelicFound"),
	VoteOptions = Net.Event("VoteOptions"),
	Effect = Net.Event("Effect"),
	Toast = Net.Event("Toast"),
}

local MONITOR_INTERVAL = 0.1
local PICKUP_RADIUS = 4.5
local HIT_BOX = Vector3.new(2.6, 5, 1.6)

-- Built-in floor used only when no challenge templates loaded.
local BREATHER = {
	Id = "Breather",
	Name = "Catch Your Breath",
	Hint = "Grab the coins!",
	Duration = 10,
	Build = function(ctx)
		ctx:Part({ Size = Vector3.new(60, 2, 60), CFrame = ctx:At(0, -1, 0), Color = ctx.Theme.Floor })
		for i = 1, 8 do
			ctx:SpawnCoin(ctx:At(ctx.Rng:NextNumber(-25, 25), 3, ctx.Rng:NextNumber(-25, 25)).Position)
		end
	end,
	Start = function() end,
}

local Run = {}
Run.__index = Run

local function runsFolder(): Folder
	local folder = workspace:FindFirstChild("Runs")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Runs"
		folder.Parent = workspace
	end
	return folder
end

local function pivotCharacter(player: Player, cframe: CFrame)
	local character = player.Character
	if character and character.Parent and character:FindFirstChild("HumanoidRootPart") then
		character:PivotTo(cframe)
		local root = character.HumanoidRootPart :: BasePart
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end
end

function Run.new(params)
	local slot = params.Slot
	local pivot = CFrame.new(Config.SlotOrigin + Vector3.new((slot - 1) * Config.SlotSpacing, 0, 0))
	local arenaOrigin = pivot * Config.ArenaOffset

	local folder = Instance.new("Folder")
	folder.Name = "Run_" .. slot
	folder.Parent = runsFolder()

	local self = setmetatable({
		Id = HttpService:GenerateGUID(false),
		Slot = slot,
		Mode = params.Mode,
		Seed = params.Seed,
		Rng = Random.new(params.Seed),
		LootRng = Random.new(),
		OnEnded = params.OnEnded,
		Folder = folder,
		Pivot = pivot,
		ArenaOrigin = arenaOrigin,
		Cab = nil,
		Members = {} :: { [Player]: any },
		Order = {} :: { Player },
		Floor = 0,
		IsBoss = false,
		Phase = "Descending",
		PhaseEndsAt = 0,
		Template = nil,
		Ctx = nil,
		CursesActive = {} :: { string },
		CursesNext = {} :: { string },
		VoteOptions = nil,
		ShopOpen = false,
		Recent = {} :: { string },
		Seen = {} :: { [string]: boolean }, -- every template played this run (no repeats until all are seen)
		Ended = false,
		Trove = Trove.new(),
		_finishEarly = false,
		_pushQueued = false,
		_pickups = {},
	}, Run)

	self.Trove:Add(folder)
	self.Cab = Cab.new(folder, pivot, arenaOrigin)
	self:_buildArenaLights()

	for _, player in params.Players do
		self:_addMember(player)
	end
	return self
end

-- Members --------------------------------------------------------------------

function Run:_addMember(player: Player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	local stats = EconomyService.RunStats(player)
	local member = {
		Player = player,
		Status = "Alive",
		Departed = false,
		Finalized = false,
		InChallenge = false,
		Bag = 0,
		BagAtDeath = 0,
		LastGain = 0,
		Shields = math.floor(stats.Shields or 0),
		Insured = false,
		CharmFloors = 0,
		Bought = {},
		Choice = nil,
		Vote = nil,
		Stats = stats,
		InvulnerableUntil = 0,
		ExtraLifeUsed = false,
		KeptAtDeath = 0, -- insurance share already banked when they died (not restored by a revive)
		ReviveUntil = 0, -- server time the Extra Life offer for this elimination closes
		ReviveHoldUntil = 0, -- an Extra Life purchase prompt is open: keep the run alive until then
		Trove = Trove.new(),
	}
	self.Members[player] = member
	table.insert(self.Order, player)
	if data.TotalRuns == 0 then
		Analytics.Step(player, 2)
	end

	player:SetAttribute("InRun", true)
	player:SetAttribute("RunStatus", "Alive")
	player:SetAttribute("DoubleJump", (stats.DoubleJump or 0) >= 1)

	member.Trove:Connect(player.CharacterAdded, function(character)
		self:_onCharacterAdded(member, character)
	end)
	if player.Character then
		self:_watchHumanoid(member, player.Character)
	end
end

function Run:_watchHumanoid(member, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 5) :: Humanoid?
	if not humanoid then
		return
	end
	member.Trove:Connect(humanoid.Died, function()
		if self.Phase == "Challenge" and member.InChallenge and member.Status == "Alive" then
			self:EliminateFromChallenge(member.Player, "Knocked out")
		end
	end)
end

function Run:_onCharacterAdded(member, character: Model)
	if member.Departed or self.Ended then
		return
	end
	self:_watchHumanoid(member, character)
	character:WaitForChild("HumanoidRootPart", 5)
	task.wait(0.1)
	if member.Departed or self.Ended then
		return
	end
	if member.Status == "Dead" then
		pivotCharacter(member.Player, self:_boothSpawn())
	elseif member.Status == "Alive" then
		if self.Phase == "Challenge" and member.InChallenge then
			self:EliminateFromChallenge(member.Player, "Knocked out")
			return
		end
		pivotCharacter(member.Player, self:_cabSpawn(member.Player))
		Modifiers.Apply(character, member.Stats, {})
	end
end

function Run:_present(): { any }
	local list = {}
	for _, player in self.Order do
		local member = self.Members[player]
		if member and not member.Departed then
			table.insert(list, member)
		end
	end
	return list
end

function Run:_alive(): { any }
	local list = {}
	for _, member in self:_present() do
		if member.Status == "Alive" then
			table.insert(list, member)
		end
	end
	return list
end

function Run:GetAliveInChallenge(): { Player }
	local list = {}
	for _, member in self:_present() do
		if member.Status == "Alive" and member.InChallenge then
			table.insert(list, member.Player)
		end
	end
	return list
end

function Run:HasPlayer(player: Player): boolean
	local member = self.Members[player]
	return member ~= nil and not member.Departed
end

function Run:_cabSpawn(player: Player): CFrame
	local spawns = self.Cab:GetSpawns()
	local index = table.find(self.Order, player) or 1
	return spawns[((index - 1) % #spawns) + 1]
end

function Run:_boothSpawn(): CFrame
	local spawns = self.Cab.BoothSpawns
	return spawns[math.random(1, #spawns)]
end

-- Ends a member's participation exactly once (stats + lobby state).
function Run:_finalize(member)
	if member.Finalized then
		return
	end
	member.Finalized = true
	member.Departed = true
	member.InChallenge = false
	member.Trove:Destroy()
	local player = member.Player
	local data = DataService.Get(player)
	if data then
		data.TotalRuns += 1
		DataService.Push(player)
	end
	LeaderboardService.MarkDirty(player)
	if player.Parent == Players then
		player:SetAttribute("InRun", nil)
		player:SetAttribute("RunStatus", nil)
		player:SetAttribute("DoubleJump", nil)
		remotes.RunUpdate:FireClient(player, nil)
		remotes.VoteOptions:FireClient(player, nil)
		remotes.Effect:FireClient(player, "Curses", { List = {} })
		Modifiers.Clear(player.Character)
	end
end

-- Pushes -------------------------------------------------------------------------

function Run:_queuePush()
	if self._pushQueued then
		return
	end
	self._pushQueued = true
	task.defer(function()
		self._pushQueued = false
		self:_push()
	end)
end

function Run:_multiplierFor(member, isBoss: boolean): number
	local base = if isBoss then Config.Bag.BossMultiplier else Config.Bag.Multiplier
	return base + (member.Stats.BagMult or 0)
end

function Run:_push()
	if self.Ended and self.Phase ~= "Ended" then
		return
	end
	local present = self:_present()
	local players = {}
	local aliveCount = 0
	for _, player in self.Order do
		local member = self.Members[player]
		if member.Status == "Alive" and not member.Departed then
			aliveCount += 1
		end
		table.insert(players, {
			UserId = player.UserId,
			Name = player.DisplayName,
			Status = member.Status,
			Bag = member.Bag,
			Choice = member.Choice,
		})
	end
	local curses = if self.Phase == "Decision" then self.CursesNext else self.CursesActive
	local challenge = self.Template and {
		Id = self.Template.Id,
		Name = self.Template.Name,
		Hint = self.Template.Hint or "",
	} or nil
	local nextIsBoss = if self.Phase == "Decision" or self.Phase == "Results"
		then (self.Floor + 1) % Config.BossEvery == 0
		else self.IsBoss

	for _, member in present do
		local snapshot = {
			RunId = self.Id,
			Mode = self.Mode,
			Phase = self.Phase,
			Floor = self.Floor,
			IsBoss = self.IsBoss,
			EndsAt = self.PhaseEndsAt,
			Challenge = challenge,
			Curses = table.clone(curses),
			Multiplier = self:_multiplierFor(member, nextIsBoss),
			ShopOpen = self.ShopOpen,
			Alive = aliveCount,
			Total = #self.Order,
			You = {
				Status = member.Status,
				Bag = member.Bag,
				Shields = member.Shields,
				Choice = member.Choice,
				Insured = member.Insured,
				CharmFloors = member.CharmFloors,
				Bought = member.Bought,
				LastGain = member.LastGain,
				ReviveUntil = member.ReviveUntil,
				ReviveBag = math.max(member.BagAtDeath - member.KeptAtDeath, 0),
				ExtraLifeUsed = member.ExtraLifeUsed,
			},
			Players = players,
		}
		remotes.RunUpdate:FireClient(member.Player, snapshot)
	end
end

function Run:FireEffect(name: string, args: any, onlyAlive: boolean?)
	for _, member in self:_present() do
		if not onlyAlive or member.Status == "Alive" then
			remotes.Effect:FireClient(member.Player, name, args)
		end
	end
end

-- One run member only (e.g. a Knockback for the player who got hit).
function Run:FireEffectTo(player: Player, name: string, args: any)
	if self.Members[player] then
		remotes.Effect:FireClient(player, name, args)
	end
end

function Run:Announce(text: string, color: Color3?)
	self:FireEffect("Banner", { Text = text, Color = color })
end

function Run:ToastRun(text: string, style: string?)
	for _, member in self:_present() do
		remotes.Toast:FireClient(member.Player, text, style or "info")
	end
end

-- Phases ---------------------------------------------------------------------

function Run:_setPhase(phase: string, duration: number)
	self.Phase = phase
	self.PhaseEndsAt = workspace:GetServerTimeNow() + duration
	self:_queuePush()
end

-- Waits up to `duration`, returning early when `done()` is true or the run is aborted.
function Run:_wait(duration: number, done: (() -> boolean)?)
	local deadline = os.clock() + duration
	while os.clock() < deadline and not self.Ended do
		if done and done() then
			return
		end
		task.wait(0.1)
	end
end

function Run:Start()
	task.spawn(function()
		local ok, err = xpcall(function()
			self:_main()
		end, debug.traceback)
		if not ok then
			warn("[Run] crashed:", err)
		end
		self:_end()
	end)
end

function Run:_main()
	for _, member in self:_alive() do
		pivotCharacter(member.Player, self:_cabSpawn(member.Player))
		Modifiers.Apply(member.Player.Character, member.Stats, {})
	end
	self.Cab:SetDisplay("G")
	-- Studio only: start deeper to test zones (workspace attribute OMF_StartFloor = 12 plays B12 first)
	local startFloor = workspace:GetAttribute("OMF_StartFloor")
	if RunService:IsStudio() and typeof(startFloor) == "number" and startFloor > 1 then
		self.Floor = math.floor(startFloor) - 1
	end

	while not self.Ended do
		if #self:_alive() == 0 and not self:_awaitRevives() then
			break
		end
		self.Floor += 1
		self.IsBoss = self.Floor % Config.BossEvery == 0
		self:_resolveCurses()

		-- Descending: doors shut, previous arena cleared, next one built
		self.Cab:SetDoors(false)
		self:_destroyArena()
		self.Template = self:_pickTemplate()
		self:_setPhase("Descending", Config.DescendTime)
		self:FireEffect("Descend", { Duration = Config.DescendTime, Floor = self.Floor }, true)
		self:FireEffect("Curses", { List = {} })
		self:_buildArena()
		self.Cab:SetDisplay("B" .. self.Floor, if self.IsBoss then Color3.fromRGB(255, 70, 70) else nil)
		self:_wait(Config.DescendTime)
		if self.Ended or #self:_alive() == 0 then
			break
		end

		-- Briefing: doors open, players placed on the arena
		self.Cab:SetDoors(true)
		self:FireEffect("Sound", { Name = "ElevatorDing" })
		self:_placeOnArena()
		self:_applyCurses()
		self:_setPhase("Briefing", Config.BriefingTime)
		self:_wait(Config.BriefingTime, function()
			self:_guardBriefing()
			return false
		end)
		if self.Ended then
			break
		end

		-- Challenge
		self:_runChallenge()
		if self.Ended then
			break
		end

		-- Results
		self:_results()
		self:_setPhase("Results", Config.ResultsTime)
		self:_wait(Config.ResultsTime)
		if #self:_alive() == 0 and not self:_awaitRevives() then
			break
		end

		-- Decision
		self:_decision()
	end
end

function Run:_pickTemplate()
	local rng = if self.Mode == "Daily" then Random.new(self.Seed * 7919 + self.Floor) else self.Rng
	local template = ChallengeRegistry.Pick(rng, self.Floor, self.IsBoss, #self:_alive(), self.Seen, self.Recent)
	template = template or BREATHER
	self.Seen[template.Id] = true
	table.insert(self.Recent, 1, template.Id)
	if #self.Recent > 6 then
		table.remove(self.Recent)
	end
	return template
end

-- Overhead "stadium" lights so arenas read well under the night lighting; tinted per depth theme.
function Run:_buildArenaLights()
	self._lights = {}
	local rig = Instance.new("Folder")
	rig.Name = "ArenaLights"
	rig.Parent = self.Folder
	for _, offset in { Vector3.new(-30, 42, -30), Vector3.new(30, 42, -30), Vector3.new(-30, 42, 30), Vector3.new(30, 42, 30), Vector3.new(0, 46, 0) } do
		local emitter = Instance.new("Part")
		emitter.Name = "Light"
		emitter.Anchored = true
		emitter.CanCollide = false
		emitter.CanQuery = false
		emitter.CanTouch = false
		emitter.CastShadow = false
		emitter.Transparency = 1
		emitter.Size = Vector3.new(2, 1, 2)
		emitter.CFrame = self.ArenaOrigin * CFrame.new(offset)
		local light = Instance.new("SurfaceLight")
		light.Face = Enum.NormalId.Bottom
		light.Range = 60
		light.Angle = 110
		light.Brightness = 1.4
		light.Shadows = true
		light.Parent = emitter
		emitter.Parent = rig
		table.insert(self._lights, light)
	end
	self:_buildShaft(rig)
end

-- The elevator shaft around the arena: dark walls with neon rails, depth bands, a glowing abyss and a
-- giant floor number. Built once per run (~40 parts) and recoloured per depth theme in _tintLights.
local SHAFT_X, SHAFT_NEAR, SHAFT_FAR = 112, 122, -132
local SHAFT_BOTTOM, SHAFT_TOP = -140, 150

function Run:_buildShaft(parent: Instance)
	local env = { Walls = {}, Rails = {}, Bands = {}, Fog = {} }
	local origin = self.ArenaOrigin
	local function piece(list, props): Part
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Material = Enum.Material.SmoothPlastic
		for key, value in props do
			(p :: any)[key] = value
		end
		p.Parent = parent
		if list then
			table.insert(list, p)
		end
		return p
	end
	local height = SHAFT_TOP - SHAFT_BOTTOM
	local midY = (SHAFT_TOP + SHAFT_BOTTOM) / 2
	local depth = SHAFT_NEAR - SHAFT_FAR
	local midZ = (SHAFT_NEAR + SHAFT_FAR) / 2

	-- Walls
	piece(env.Walls, { Name = "WallL", Size = Vector3.new(4, height, depth), CFrame = origin * CFrame.new(-SHAFT_X - 2, midY, midZ) })
	piece(env.Walls, { Name = "WallR", Size = Vector3.new(4, height, depth), CFrame = origin * CFrame.new(SHAFT_X + 2, midY, midZ) })
	local far = piece(env.Walls, { Name = "WallFar", Size = Vector3.new(SHAFT_X * 2 + 8, height, 4), CFrame = origin * CFrame.new(0, midY, SHAFT_FAR - 2) })
	piece(env.Walls, { Name = "WallNear", Size = Vector3.new(SHAFT_X * 2 + 8, height, 4), CFrame = origin * CFrame.new(0, midY, SHAFT_NEAR + 2) })

	-- Vertical guide rails (the shaft's "lines of speed")
	for k = -3, 3 do
		piece(env.Rails, { Name = "Rail", Material = Enum.Material.Neon, Size = Vector3.new(0.6, height, 0.4), CFrame = origin * CFrame.new(k * 30, midY, SHAFT_FAR + 0.2) })
		local z = midZ + k * 34
		piece(env.Rails, { Name = "Rail", Material = Enum.Material.Neon, Size = Vector3.new(0.4, height, 0.6), CFrame = origin * CFrame.new(-SHAFT_X + 0.2, midY, z) })
		piece(env.Rails, { Name = "Rail", Material = Enum.Material.Neon, Size = Vector3.new(0.4, height, 0.6), CFrame = origin * CFrame.new(SHAFT_X - 0.2, midY, z) })
	end

	-- Depth bands: one just under the arena, one high above
	for _, y in { -14, 40 } do
		piece(env.Bands, { Name = "Band", Material = Enum.Material.Neon, Size = Vector3.new(SHAFT_X * 2, 1.4, 0.5), CFrame = origin * CFrame.new(0, y, SHAFT_FAR + 0.3) })
		piece(env.Bands, { Name = "Band", Material = Enum.Material.Neon, Size = Vector3.new(0.5, 1.4, depth), CFrame = origin * CFrame.new(-SHAFT_X + 0.3, y, midZ) })
		piece(env.Bands, { Name = "Band", Material = Enum.Material.Neon, Size = Vector3.new(0.5, 1.4, depth), CFrame = origin * CFrame.new(SHAFT_X - 0.3, y, midZ) })
	end

	-- Glowing abyss far below and two thin haze layers that sell the depth
	env.Abyss = piece(nil, { Name = "Abyss", Material = Enum.Material.Neon, Size = Vector3.new(SHAFT_X * 2, 1, depth), CFrame = origin * CFrame.new(0, SHAFT_BOTTOM + 20, midZ), Transparency = 0.86 })
	for k, y in { -45, -85 } do
		piece(env.Fog, { Name = "Haze", Material = Enum.Material.Neon, Size = Vector3.new(SHAFT_X * 2, 0.2, depth), CFrame = origin * CFrame.new(0, y, midZ), Transparency = 0.95 + k * 0.01 })
	end

	-- Giant floor number on the far wall
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back -- the far wall's face pointing at the arena (+Z)
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 8
	gui.LightInfluence = 0
	gui.Brightness = 1.6
	gui.Parent = far
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.new(0.5, 0, 0.5, -(62 - midY) * 8) -- centred ~62 studs above the arena
	label.Size = UDim2.fromOffset(110 * 8, 46 * 8)
	label.Font = Enum.Font.Michroma
	label.TextScaled = true
	label.TextTransparency = 0.15
	label.Text = ""
	label.Parent = gui
	env.FloorLabel = label

	self._env = env
end

function Run:_tintLights(theme)
	for _, light in self._lights do
		light.Color = theme.Primary:Lerp(Color3.new(1, 1, 1), 0.65)
	end
	local env = self._env
	if not env then
		return
	end
	local wall = theme.Floor:Lerp(Color3.new(0, 0, 0), 0.62)
	for _, p in env.Walls do
		p.Color = wall
	end
	for i, p in env.Rails do
		p.Color = theme.Primary:Lerp(wall, 0.35)
		p.Transparency = if i % 3 == 1 then 0.45 else 0.72
	end
	-- the bands run right round the shaft behind every arena: capped so yellow / white themes don't glare
	local h, s, v = theme.Secondary:ToHSV()
	for _, p in env.Bands do
		p.Color = Color3.fromHSV(h, s, math.min(v, 0.6))
		p.Transparency = 0.35
	end
	env.Abyss.Color = theme.Primary:Lerp(theme.Floor, 0.35)
	for _, p in env.Fog do
		p.Color = theme.Primary
	end
	env.FloorLabel.TextColor3 = if self.IsBoss then theme.Hazard else theme.Primary
	env.FloorLabel.Text = "B" .. self.Floor
end

function Run:_destroyArena()
	if self.Ctx then
		self.Ctx:_destroy()
		self.Ctx = nil
	end
	table.clear(self._pickups)
end

function Run:_buildArena()
	local curseSet = {}
	for _, id in self.CursesActive do
		curseSet[id] = true
	end
	local difficulty = Config.Difficulty(self.Floor, self.IsBoss)
	if curseSet.Hyper then
		difficulty += 0.3
	end
	local seed = if self.Mode == "Daily" then self.Seed * 104729 + self.Floor else self.Rng:NextInteger(1, 2 ^ 30)
	local ctx = Context.new(self, {
		Parent = self.Folder,
		Floor = self.Floor,
		IsBoss = self.IsBoss,
		Difficulty = difficulty,
		Mode = self.Mode,
		Origin = self.ArenaOrigin,
		Rng = Random.new(seed),
		Curses = curseSet,
	})
	self.Ctx = ctx
	self:_tintLights(ctx.Theme)
	local template = self.Template
	local duration = template.Duration
	if typeof(duration) == "function" then
		local ok, value = pcall(duration, ctx)
		duration = if ok and typeof(value) == "number" then value else 20
	end
	ctx.Duration = duration or 20

	local ok, err = pcall(template.Build, ctx)
	if not ok then
		warn(`[Run] {template.Id}.Build failed: {err}`)
		-- fall back to the breather so the run never soft-locks
		ctx:_destroy()
		self.Template = BREATHER
		self.Ctx = Context.new(self, {
			Parent = self.Folder,
			Floor = self.Floor,
			IsBoss = self.IsBoss,
			Difficulty = difficulty,
			Mode = self.Mode,
			Origin = self.ArenaOrigin,
			Rng = Random.new(seed),
			Curses = curseSet,
		})
		self.Ctx.Duration = BREATHER.Duration
		BREATHER.Build(self.Ctx)
	end
end

function Run:_defaultSpawns(): { CFrame }
	local spawns = {}
	for i = 0, 7 do
		local angle = i / 8 * math.pi * 2
		local position = self.ArenaOrigin * Vector3.new(math.cos(angle) * 12, 3, math.sin(angle) * 12)
		table.insert(spawns, CFrame.lookAt(position, self.ArenaOrigin.Position + Vector3.new(0, 3, 0)))
	end
	return spawns
end

function Run:_arenaSpawns(): { CFrame }
	local spawns = self.Ctx and self.Ctx.Spawns
	if not spawns or #spawns == 0 then
		spawns = self:_defaultSpawns()
	end
	return spawns
end

function Run:_placeOnArena()
	local spawns = self:_arenaSpawns()
	for i, member in self:_alive() do
		member.InChallenge = true
		member.Choice = nil
		member._briefingSpawn = spawns[((i - 1) % #spawns) + 1]
		pivotCharacter(member.Player, member._briefingSpawn)
	end
end

-- During briefing nobody can die: put fallers back on their spawn.
function Run:_guardBriefing()
	for _, member in self:_alive() do
		local root = member.InChallenge and self.Ctx and self.Ctx:GetRoot(member.Player)
		if root and root.Position.Y < self.ArenaOrigin.Y - 6 and member._briefingSpawn then
			pivotCharacter(member.Player, member._briefingSpawn)
		end
	end
end

function Run:_applyCurses()
	local set = {}
	for _, id in self.CursesActive do
		set[id] = true
	end
	for _, member in self:_alive() do
		Modifiers.Apply(member.Player.Character, member.Stats, set)
	end
	self:FireEffect("Curses", { List = table.clone(self.CursesActive) })
	if #self.CursesActive > 0 then
		local names = {}
		for _, id in self.CursesActive do
			table.insert(names, Curses.ById[id].Name)
		end
		self:FireEffect("Sound", { Name = "CurseApplied" })
		self:Announce("CURSED: " .. table.concat(names, " + "), Color3.fromRGB(255, 70, 120))
	end
end

function Run:_runChallenge()
	local ctx = self.Ctx
	local template = self.Template
	self._finishEarly = false
	self:_setPhase("Challenge", ctx.Duration)
	self:FireEffect("Sound", { Name = "Go" })
	ctx.Started = true
	ctx.StartedAt = os.clock()

	task.spawn(function()
		local ok, err = pcall(template.Start, ctx)
		if not ok then
			warn(`[Run] {template.Id}.Start failed: {err}`)
		end
	end)

	local monitorThread = task.spawn(function()
		while self.Phase == "Challenge" and not self.Ended and not ctx.Ended do
			self:_monitor(ctx)
			task.wait(MONITOR_INTERVAL)
		end
	end)

	self:_wait(ctx.Duration, function()
		return self._finishEarly or #self:GetAliveInChallenge() == 0
	end)
	task.cancel(monitorThread)

	if template.Judge and #self:GetAliveInChallenge() > 0 and not self.Ended then
		local ok, err = pcall(template.Judge, ctx)
		if not ok then
			warn(`[Run] {template.Id}.Judge failed: {err}`)
		end
	end
	ctx.Ended = true -- stops template loops; geometry stays until the next descent
end

function Run:FinishChallengeEarly(ctx)
	if ctx == self.Ctx then
		self._finishEarly = true
	end
end

-- Hazard overlap, fall depth and pickups for everyone still in the challenge.
function Run:_monitor(ctx)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { ctx.HazardFolder }
	local killY = self.ArenaOrigin.Y - Config.KillDepth
	local now = os.clock()

	for _, player in self:GetAliveInChallenge() do
		local member = self.Members[player]
		local root = ctx:GetRoot(player)
		if not root then
			continue
		end
		if root.Position.Y < killY then
			self:EliminateFromChallenge(player, "Fell")
			continue
		end
		if now >= member.InvulnerableUntil then
			local character = player.Character
			local scale = if character then character:GetScale() else 1
			local hits = workspace:GetPartBoundsInBox(root.CFrame, HIT_BOX * scale, params)
			if #hits > 0 then
				self:EliminateFromChallenge(player, "Hit by " .. hits[1].Name)
				continue
			end
		end
		-- pickups
		local radius = PICKUP_RADIUS * (1 + (member.Stats.PickupRadius or 0))
		for i = #self._pickups, 1, -1 do
			local pickup = self._pickups[i]
			if not pickup.Part.Parent then
				table.remove(self._pickups, i)
			elseif (pickup.Part.Position - root.Position).Magnitude <= radius then
				table.remove(self._pickups, i)
				self:_collect(member, pickup)
			end
		end
	end
end

function Run:SpawnPickup(ctx, position: Vector3, kind: string, value: number)
	if ctx ~= self.Ctx then
		return nil
	end
	local isBag = kind == "Bag"
	local part = Instance.new("Part")
	part.Name = kind
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	if isBag then
		part.Shape = Enum.PartType.Ball
		part.Size = Vector3.new(3.2, 3.2, 3.2)
		part.Color = Color3.fromRGB(255, 190, 60)
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromOffset(160, 40)
		gui.StudsOffset = Vector3.new(0, 3, 0)
		gui.AlwaysOnTop = true
		gui.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBlack
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(255, 220, 90)
		label.TextStrokeTransparency = 0.3
		label.Text = "BAG " .. Format.Cash(value)
		label.Parent = gui
		gui.Parent = part
	else
		part.Shape = Enum.PartType.Cylinder
		part.Size = Vector3.new(0.5, 2.4, 2.4)
		part.Color = Color3.fromRGB(190, 140, 25) -- well below full value: brighter coins bloom into a blob up close
	end
	part.CFrame = CFrame.new(position)
	local light = Instance.new("PointLight")
	light.Range = if isBag then 12 else 6
	light.Brightness = 1
	light.Color = part.Color
	light.Parent = part
	-- a few twinkles so pickups catch the eye from across the arena
	local twinkle = Instance.new("ParticleEmitter")
	twinkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	twinkle.Color = ColorSequence.new(Color3.fromRGB(255, 240, 170))
	twinkle.LightEmission = 1
	twinkle.LightInfluence = 0
	twinkle.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, if isBag then 1 else 0.6), NumberSequenceKeypoint.new(1, 0) })
	twinkle.Lifetime = NumberRange.new(0.5, 0.9)
	twinkle.Speed = NumberRange.new(0.5, 1.5)
	twinkle.SpreadAngle = Vector2.new(180, 180)
	twinkle.Rate = if isBag then 6 else 2.5
	twinkle.Parent = part
	CollectionService:AddTag(part, "Spin")
	part.Parent = ctx.Folder
	table.insert(self._pickups, { Part = part, Kind = kind, Value = value })
	return part
end

function Run:_collect(member, pickup)
	local value = pickup.Value
	if pickup.Kind == "Coin" then
		value = math.floor(value * (1 + (member.Stats.CoinValue or 0)) + 0.5)
	end
	member.Bag += value
	local position = pickup.Part.Position
	pickup.Part:Destroy()
	remotes.Effect:FireClient(member.Player, "CoinPop", { Position = position, Amount = value })
	remotes.Effect:FireClient(member.Player, "Sound", { Name = "Coin" })
	if pickup.Kind == "Bag" then
		self:ToastRun(`{member.Player.DisplayName} grabbed a dropped bag worth {Format.Cash(value)}!`, "good")
	end
	self:_queuePush()
end

-- Eliminations -------------------------------------------------------------------

-- Elimination / save burst, drawn on clients (ring, chunks, sparks, flash) by ArenaFx.
function Run:_burst(position: Vector3, color: Color3)
	self:FireEffect("Fx", { Kind = "Impact", Position = position, Color = color, Radius = 10, Debris = 8 })
end

-- Saves a member from an elimination (shield, phoenix, banked extra life). Returns the save type.
function Run:_trySave(member): string?
	-- Studio only: player attribute OMF_God = true survives everything (visual sweeps across many floors);
	-- OMF_GodSaves counts what would have killed them.
	if RunService:IsStudio() and member.Player:GetAttribute("OMF_God") then
		member.Player:SetAttribute("OMF_GodSaves", (member.Player:GetAttribute("OMF_GodSaves") or 0) + 1)
		return "God mode"
	end
	if member.Shields > 0 then
		member.Shields -= 1
		return "Shield"
	end
	local revive = member.Stats.Revive or 0
	if revive > 0 and self.LootRng:NextNumber() < revive then
		return "Phoenix"
	end
	if self.Mode == "Normal" then
		local data = DataService.Get(member.Player)
		if data and data.ExtraLives > 0 then
			data.ExtraLives -= 1
			DataService.Push(member.Player)
			return "Extra Life"
		end
	end
	return nil
end

function Run:_rescue(member)
	-- drop them next to a random surviving player (they're standing on something), else a spawn
	local target
	local others = {}
	for _, player in self:GetAliveInChallenge() do
		if player ~= member.Player then
			local root = self.Ctx and self.Ctx:GetRoot(player)
			if root and root.Position.Y > self.ArenaOrigin.Y - 5 then
				table.insert(others, root)
			end
		end
	end
	if #others > 0 then
		target = others[math.random(1, #others)].CFrame + Vector3.new(0, 4, 0)
	else
		local spawns = self:_arenaSpawns()
		target = spawns[math.random(1, #spawns)]
	end
	pivotCharacter(member.Player, target)
	member.InvulnerableUntil = os.clock() + 2.5
	local character = member.Player.Character
	if character then
		local field = Instance.new("ForceField")
		field.Parent = character
		task.delay(2.5, function()
			field:Destroy()
		end)
	end
end

function Run:EliminateFromChallenge(player: Player, reason: string)
	local member = self.Members[player]
	if not member or member.Departed or member.Status ~= "Alive" or not member.InChallenge then
		return
	end
	if self.Phase ~= "Challenge" or os.clock() < member.InvulnerableUntil then
		return
	end
	local root = self.Ctx and self.Ctx:GetRoot(player)
	local deathPosition = if root then root.Position else self.ArenaOrigin.Position

	local saved = self:_trySave(member)
	if saved then
		self:_burst(deathPosition, Color3.fromRGB(140, 220, 255))
		self:_rescue(member)
		remotes.Effect:FireClient(player, "Flash", { Color = Color3.fromRGB(140, 220, 255), Duration = 0.4 })
		self:ToastRun(`{player.DisplayName}'s {saved} saved them!`, "good")
		self:_queuePush()
		return
	end

	member.Status = "Dead"
	member.InChallenge = false
	player:SetAttribute("RunStatus", "Dead")
	local data = DataService.Get(player)
	if data then
		data.Stats.Deaths += 1
	end
	Analytics.Event(player, "Eliminated", self.Floor, { [Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = self.Template and self.Template.Id or "?" })

	-- Insurance: keep a share of the bag, banked immediately. Part of the rest drops for survivors.
	local bag = member.Bag
	member.BagAtDeath = bag
	local keepShare = math.clamp(member.Stats.Insurance or 0, 0, 0.9)
	if member.Insured then
		keepShare = math.max(keepShare, 0.75)
	end
	local kept = math.floor(bag * keepShare)
	local lost = bag - kept
	local dropped = math.floor(lost * Config.Bag.DropShare)
	member.Bag = 0
	member.KeptAtDeath = kept
	-- Extra Life offer: a revive restores what the player just lost, so only offer it when there is a bag at stake
	local canRevive = self.Mode == "Normal" and not member.ExtraLifeUsed
	member.ReviveUntil = if canRevive and lost > 0 then workspace:GetServerTimeNow() + Config.Monetization.ReviveWindow else 0
	if kept > 0 then
		DataService.AddCash(player, kept)
	end

	self:_burst(deathPosition, self.Ctx and self.Ctx.Theme.Hazard or Color3.new(1, 0.2, 0.2))
	if dropped > 0 and self.Ctx and #self:GetAliveInChallenge() > 0 then
		-- keep the dropped bag reachable: clamp into the arena, float above the floor
		local localPos = self.ArenaOrigin:PointToObjectSpace(deathPosition)
		local limit = Config.ArenaHalfExtent - 8
		local x = math.clamp(localPos.X, -limit, limit)
		local z = math.clamp(localPos.Z, -limit, limit)
		local y = math.clamp(localPos.Y, 3, 40)
		self:SpawnPickup(self.Ctx, self.ArenaOrigin * Vector3.new(x, y, z), "Bag", dropped)
	end

	pivotCharacter(player, self:_boothSpawn())
	Modifiers.Apply(player.Character, member.Stats, {})
	remotes.Effect:FireClient(player, "Curses", { List = {} })
	remotes.Effect:FireClient(player, "Sound", { Name = "Eliminated" })
	remotes.Effect:FireClient(player, "Shake", { Intensity = 1.5, Duration = 0.5 })
	remotes.Eliminated:FireClient(player, {
		Reason = reason,
		Lost = lost,
		Kept = kept,
		Dropped = dropped,
		Floor = self.Floor,
		CanRevive = canRevive,
		ReviveUntil = member.ReviveUntil,
		ReviveBag = lost,
		ExtraLifeKey = Config.ExtraLifeKey(self.Floor),
	})
	self:ToastRun(`{player.DisplayName} was eliminated!`, "bad")
	self:_queuePush()
end

-- Extra Life purchase while spectating: back into the cab with the bag restored (Normal mode, once per run).
function Run:TryRevive(player: Player): boolean
	local member = self.Members[player]
	if not member or member.Departed or member.Status ~= "Dead" or self.Mode ~= "Normal" or member.ExtraLifeUsed then
		return false
	end
	if self.Phase == "Ended" or self.Ended then
		return false
	end
	member.ExtraLifeUsed = true
	member.Status = "Alive"
	member.InChallenge = false
	member.Bag = math.max(member.BagAtDeath - member.KeptAtDeath, 0)
	member.ReviveUntil = 0
	member.ReviveHoldUntil = 0
	player:SetAttribute("RunStatus", "Alive")
	pivotCharacter(player, self:_cabSpawn(player))
	Modifiers.Apply(player.Character, member.Stats, {})
	remotes.VoteOptions:FireClient(player, nil)
	self:ToastRun(`{player.DisplayName} used an EXTRA LIFE and is back in the elevator!`, "rare")
	self:_queuePush()
	return true
end

-- An Extra Life purchase prompt opened (`open`) or closed for this spectator: keeps the run alive meanwhile.
function Run:HoldRevive(player: Player, open: boolean, purchased: boolean?)
	local member = self.Members[player]
	if not member or member.Status ~= "Dead" then
		return
	end
	local now = workspace:GetServerTimeNow()
	if open then
		if now < member.ReviveUntil then
			member.ReviveHoldUntil = now + 30
		end
	else
		-- the receipt can land just after the prompt closes
		member.ReviveHoldUntil = if purchased then now + 6 else 0
	end
end

function Run:_reviveDeadline(): number
	local latest = 0
	for _, member in self:_present() do
		if member.Status == "Dead" and not member.ExtraLifeUsed then
			latest = math.max(latest, member.ReviveUntil, member.ReviveHoldUntil)
		end
	end
	return latest
end

-- Everyone is out: hold the run open while a fresh elimination still has its Extra Life offer up.
-- Returns true if someone came back.
function Run:_awaitRevives(): boolean
	while not self.Ended and #self:_alive() == 0 do
		local deadline = self:_reviveDeadline()
		local now = workspace:GetServerTimeNow()
		if deadline <= now then
			break
		end
		if self.Phase ~= "Results" or math.abs(self.PhaseEndsAt - deadline) > 0.5 then
			self:_setPhase("Results", deadline - now)
		end
		task.wait(0.1)
	end
	return #self:_alive() > 0
end

-- Bless the Elevator (bought by a spectator): every survivor gets a Bubble Shield.
function Run:Bless(byName: string): boolean
	if self.Ended or self.Phase == "Ended" or self.Mode ~= "Normal" then
		return false
	end
	local blessed = 0
	for _, member in self:_alive() do
		member.Shields += 1
		blessed += 1
		remotes.Effect:FireClient(member.Player, "Flash", { Color = Color3.fromRGB(140, 220, 255), Duration = 0.4 })
	end
	if blessed == 0 then
		return false
	end
	self:Announce(`{string.upper(byName)} BLESSED THE ELEVATOR`, Color3.fromRGB(140, 220, 255))
	self:ToastRun(`{byName} gave every survivor a Bubble Shield!`, "rare")
	self:_queuePush()
	return true
end

-- Results ---------------------------------------------------------------------------

function Run:_results(): { any }
	local survivors = {}
	for _, member in self:_alive() do
		if member.InChallenge then
			table.insert(survivors, member)
		end
	end

	for _, member in survivors do
		local player = member.Player
		local before = member.Bag
		local mult = self:_multiplierFor(member, self.IsBoss)
		member.Bag = math.floor((member.Bag + Config.FloorReward(self.Floor)) * mult)
		member.LastGain = member.Bag - before
		if member.CharmFloors > 0 then
			member.CharmFloors -= 1
		end

		Analytics.Event(player, "FloorCleared", self.Floor, { [Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = self.Mode })
		Badges.OnFloor(player, self.Floor)
		if self.Floor == 1 then
			Analytics.Step(player, 3)
		elseif self.Floor == 3 then
			Analytics.Step(player, 4)
		end
		if DataService.RecordFloor(player, self.Floor, self.Mode) and self.Floor >= 5 then
			remotes.Toast:FireClient(player, `New personal record: Floor {self.Floor}!`, "rare")
		end
		LeaderboardService.MarkDirty(player)
		remotes.Effect:FireClient(player, "Sound", { Name = "Survived" })
		self:_rollRelic(member)
	end

	if #survivors > 0 and self.Floor >= 15 and self.Floor % 5 == 0 then
		local names = {}
		for _, member in survivors do
			table.insert(names, member.Player.DisplayName)
		end
		EconomyService.ToastAll(`{table.concat(names, ", ")} reached FLOOR {self.Floor}!`, "rare")
	end

	-- Everyone still alive returns to the cab; curses wear off.
	for _, member in self:_alive() do
		member.InChallenge = false
		pivotCharacter(member.Player, self:_cabSpawn(member.Player))
		Modifiers.Apply(member.Player.Character, member.Stats, {})
	end
	self:FireEffect("Curses", { List = {} })
	self.Cab:SetDoors(false)
	self:_queuePush()
	return survivors
end

function Run:_rollRelic(member)
	local player = member.Player
	local data = DataService.Get(player)
	if not data then
		return
	end
	local forced = not data.FirstRelicGiven and self.Floor >= Config.Relic.GuaranteedFirstFloor
	local chance = (Config.Relic.BaseChance + Config.Relic.PerFloor * self.Floor) * (1 + (member.Stats.RelicChance or 0))
	if member.CharmFloors > 0 then
		chance *= 2
	end
	chance = math.min(chance, Config.Relic.MaxChance)
	if not forced and self.LootRng:NextNumber() > chance then
		return
	end
	local relicId = EconomyService.RollRelic(self.LootRng, self.Floor, if forced then "Common" else nil)
	local level, isNew = EconomyService.GrantRelic(player, relicId)
	if not level then
		return
	end
	local relic = Relics.ById[relicId]
	remotes.RelicFound:FireClient(player, { RelicId = relicId, Level = level, IsNew = isNew })
	local rank = Rarity.Info[relic.Rarity].Rank
	if rank >= 5 then
		Badges.Award(player, "LegendaryRelic")
		EconomyService.ToastAll(`{player.DisplayName} found a {string.upper(relic.Rarity)} {relic.Name} on floor {self.Floor}!`, "rare")
		self:FireEffect("Confetti", {})
	elseif rank >= 4 then
		self:ToastRun(`{player.DisplayName} found an EPIC {relic.Name}!`, "rare")
	end
end

-- Decision ----------------------------------------------------------------------------

function Run:_decision()
	for _, member in self:_alive() do
		member.Choice = nil
	end
	self.ShopOpen = Config.ShopAfterBoss and self.IsBoss
	local duration = Config.DecisionTime + (if self.ShopOpen then Config.ShopTime - Config.DecisionTime + 4 else 0)

	self:_useCurseTokens()
	self:_startVote(duration)
	self:_setPhase("Decision", duration)

	local start = os.clock()
	self:_wait(duration, function()
		if os.clock() - start < 1.5 then
			return false
		end
		for _, member in self:_alive() do
			if member.Choice == nil then
				return false
			end
		end
		return true
	end)

	self:_endVote()
	self.ShopOpen = false

	for _, member in self:_alive() do
		if member.Choice == "Leave" then
			self:_cashOut(member)
		else
			member.Choice = "Deeper"
		end
	end
	self:_queuePush()
end

function Run:Choose(player: Player, choice: string)
	local member = self.Members[player]
	if not member or member.Departed or member.Status ~= "Alive" or self.Phase ~= "Decision" then
		return
	end
	if member.Choice ~= nil or (choice ~= "Deeper" and choice ~= "Leave") then
		return
	end
	member.Choice = choice
	self:_queuePush()
end

function Run:BuyRunItem(player: Player, itemId: string)
	local member = self.Members[player]
	if not member or member.Departed or member.Status ~= "Alive" or self.Phase ~= "Decision" or not self.ShopOpen then
		return
	end
	if member.Bought[itemId] then
		return
	end
	local item
	for _, candidate in Config.RunItems do
		if candidate.Id == itemId then
			item = candidate
		end
	end
	if not item then
		return
	end
	local cost = math.ceil(member.Bag * item.Cost)
	if member.Bag < 20 or cost <= 0 then
		remotes.Toast:FireClient(player, "Your bag is too light to afford that.", "bad")
		return
	end
	member.Bag -= cost
	member.Bought[itemId] = true
	if itemId == "Shield" then
		member.Shields += 1
	elseif itemId == "Insurance" then
		member.Insured = true
	elseif itemId == "Charm" then
		member.CharmFloors = 5
	end
	remotes.Effect:FireClient(player, "Sound", { Name = "Purchase" })
	remotes.Toast:FireClient(player, `Bought {item.Name} for {Format.Cash(cost)}`, "good")
	self:_queuePush()
end

function Run:_cashOut(member)
	local player = member.Player
	local bonus = 1 + (member.Stats.CashOut or 0)
	local double = DataService.HasPass(player, "DoubleCash")
	local golden = (workspace:GetAttribute("OMF_GoldenUntil") or 0) > workspace:GetServerTimeNow()
	local premium = DataService.IsPremium(player)
	local amount = member.Bag * bonus * (if double then 2 else 1)
	if golden then
		amount *= Config.Monetization.GoldenCashMult
	end
	if premium then
		amount *= Config.Monetization.PremiumCashMult
	end
	amount = math.floor(amount)
	member.Status = "Left"
	DataService.AddCash(player, amount)
	local data = DataService.Get(player)
	if data then
		data.Stats.CashOuts += 1
		data.Stats.BiggestCashOut = math.max(data.Stats.BiggestCashOut, amount)
	end
	Analytics.Step(player, 5)
	Badges.Award(player, "FirstCashOut")
	Analytics.Event(player, "CashOut", amount, { [Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = tostring(self.Floor) })
	remotes.CashedOut:FireClient(player, { Amount = amount, Floor = self.Floor, Bonus = bonus, Double = double, Golden = golden, Premium = premium })
	remotes.Effect:FireClient(player, "Confetti", {})
	remotes.Effect:FireClient(player, "Sound", { Name = "CashOut" })
	if amount >= 1000 then
		self:ToastRun(`{player.DisplayName} walked out with {Format.Cash(amount)}!`, "good")
	end
	LobbyService.SendToLobby(player)
	self:_finalize(member)
end

-- Curses & voting -------------------------------------------------------------------

local function conflicts(list: { string }, id: string): boolean
	if table.find(list, id) then
		return true
	end
	local opposite = Curses.Conflicts[id]
	return opposite ~= nil and table.find(list, opposite) ~= nil
end

function Run:_randomCurse(rng: Random, exclude: { string }): string?
	local pool = {}
	for _, curse in Curses.List do
		if not conflicts(exclude, curse.Id) then
			table.insert(pool, curse.Id)
		end
	end
	if #pool == 0 then
		return nil
	end
	return pool[rng:NextInteger(1, #pool)]
end

function Run:_resolveCurses()
	self.CursesActive = self.CursesNext
	self.CursesNext = {}
	if #self.CursesActive == 0 and self.Floor >= Config.CurseMinFloor then
		local rng = if self.Mode == "Daily" then Random.new(self.Seed * 31 + self.Floor) else self.Rng
		if rng:NextNumber() < Config.CurseChance then
			local id = self:_randomCurse(rng, {})
			if id then
				table.insert(self.CursesActive, id)
			end
		end
	end
	while #self.CursesActive > 2 do
		table.remove(self.CursesActive)
	end
	-- Studio only: workspace attribute OMF_NoCurses = true keeps test floors curse-free
	if RunService:IsStudio() and workspace:GetAttribute("OMF_NoCurses") then
		table.clear(self.CursesActive)
	end
end

function Run:AddCurse(id: string?, byName: string?): boolean
	id = id or self:_randomCurse(self.LootRng, self.CursesNext)
	if not id or conflicts(self.CursesNext, id) or #self.CursesNext >= 2 then
		return false
	end
	table.insert(self.CursesNext, id)
	if byName then
		local curse = Curses.ById[id]
		self:Announce(`{byName} CURSED THE ELEVATOR: {curse.Name}!`, curse.Color)
		EconomyService.ToastAll(`{byName} cursed their elevator with {curse.Name}!`, "rare")
	end
	self:_queuePush()
	return true
end

function Run:_useCurseTokens()
	if self.Mode ~= "Normal" then
		return
	end
	for _, member in self:_present() do
		local data = DataService.Get(member.Player)
		if data and data.CurseTokens > 0 and #self.CursesNext < 2 then
			if self:AddCurse(nil, member.Player.DisplayName) then
				data.CurseTokens -= 1
				DataService.Push(member.Player)
			end
		end
	end
end

function Run:_startVote(duration: number)
	self.VoteOptions = nil
	if self.Mode ~= "Normal" then
		return
	end
	local spectators = {}
	for _, member in self:_present() do
		member.Vote = nil
		if member.Status == "Dead" then
			table.insert(spectators, member)
		end
	end
	if #spectators == 0 or #self:_alive() == 0 then
		return
	end
	local options = {}
	for _ = 1, Config.VoteOptionCount do
		local exclude = table.clone(options)
		for _, id in self.CursesNext do
			table.insert(exclude, id)
		end
		local id = self:_randomCurse(self.LootRng, exclude)
		if id then
			table.insert(options, id)
		end
	end
	if #options == 0 then
		return
	end
	self.VoteOptions = options
	local endsAt = workspace:GetServerTimeNow() + duration
	for _, member in spectators do
		remotes.VoteOptions:FireClient(member.Player, { Options = options, EndsAt = endsAt })
	end
end

function Run:Vote(player: Player, curseId: string)
	local member = self.Members[player]
	if not member or member.Departed or member.Status ~= "Dead" or not self.VoteOptions then
		return
	end
	if table.find(self.VoteOptions, curseId) then
		member.Vote = curseId
	end
end

function Run:_endVote()
	local options = self.VoteOptions
	self.VoteOptions = nil
	if not options then
		return
	end
	local tally = {}
	local best, bestCount = nil, 0
	for _, member in self:_present() do
		if member.Status == "Dead" then
			remotes.VoteOptions:FireClient(member.Player, nil)
			if member.Vote then
				tally[member.Vote] = (tally[member.Vote] or 0) + 1
				if tally[member.Vote] > bestCount or (tally[member.Vote] == bestCount and math.random() < 0.5) then
					best, bestCount = member.Vote, tally[member.Vote]
				end
			end
		end
		member.Vote = nil
	end
	if best and self:AddCurse(best) then
		local curse = Curses.ById[best]
		self:Announce(`SPECTATORS CHOSE: {curse.Name}`, curse.Color)
	end
end

-- Leaving ------------------------------------------------------------------------------

-- Spectator chooses to go back to the lobby early.
function Run:ReturnToLobby(player: Player)
	local member = self.Members[player]
	if not member or member.Departed or member.Status ~= "Dead" then
		return
	end
	LobbyService.SendToLobby(player)
	self:_finalize(member)
	self:_queuePush()
end

-- Server shutting down: every alive player banks their bag so nobody loses progress to a restart.
function Run:BankEveryone()
	for _, member in self:_present() do
		if member.Status == "Alive" and member.Bag > 0 then
			DataService.AddCash(member.Player, math.floor(member.Bag * (1 + (member.Stats.CashOut or 0))))
			member.Bag = 0
		end
	end
end

-- Player left the game. Outside of a live challenge an alive player banks their bag.
function Run:RemovePlayer(player: Player)
	local member = self.Members[player]
	if not member or member.Departed then
		return
	end
	if member.Status == "Alive" and not (self.Phase == "Challenge" and member.InChallenge) then
		local amount = math.floor(member.Bag * (1 + (member.Stats.CashOut or 0)))
		DataService.AddCash(player, amount)
	end
	member.Status = if member.Status == "Alive" then "Left" else member.Status
	self:_finalize(member)
	self:_queuePush()
end

function Run:_end()
	if self.Phase == "Ended" then
		return
	end
	self.Ended = true
	self.Phase = "Ended"
	self.PhaseEndsAt = workspace:GetServerTimeNow() + Config.EndedLinger
	self:_push()
	self:_endVote()
	task.wait(Config.EndedLinger)
	for _, member in self:_present() do
		if member.Status == "Alive" then
			self:_cashOut(member)
		else
			LobbyService.SendToLobby(member.Player)
			self:_finalize(member)
		end
	end
	if self.Ctx then
		self.Ctx:_destroy()
		self.Ctx = nil
	end
	self.Trove:Destroy()
	if self.OnEnded then
		self.OnEnded(self)
	end
end

return Run
