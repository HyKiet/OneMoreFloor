-- Player profiles (ProfileStore), leaderstats and the Data snapshot pushed to clients.

local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Upgrades = require(ReplicatedStorage.Shared.Upgrades)
local Signal = require(ReplicatedStorage.Packages.Signal)
local ProfileStore = require(ServerScriptService.ServerPackages.ProfileStore)

local DataService = {}

DataService.Loaded = Signal.new() -- (player, data)

local TEMPLATE = {
	Cash = 0,
	LifetimeCash = 0,
	DeepestFloor = 0,
	TotalRuns = 0,
	Upgrades = {},
	Relics = {},
	Equipped = {},
	Daily = { LastClaimDay = 0, Streak = 0 },
	DailyBest = { Day = 0, Floor = 0 },
	Codes = {},
	Stats = { FloorsCleared = 0, Deaths = 0, CashOuts = 0, BiggestCashOut = 0 },
	Purchases = {}, -- recent receipt ids, newest last
	FirstRelicGiven = false,
	ExtraLives = 0, -- banked Extra Life purchases, consumed like a shield in Normal runs
	CurseTokens = 0, -- banked Curse the Elevator purchases, used on the next run
	StarterGranted = false, -- Starter Pack pass contents handed out
	OwnedPasses = {}, -- pass keys Roblox confirmed owned: fallback when the ownership check fails at join
	CapsulesOpened = 0,
}

local store = ProfileStore.New("OneMoreFloor_PlayerData_v1", TEMPLATE)
local profiles: { [Player]: any } = {}
local passes: { [Player]: { [string]: boolean } } = {}
local paidRandomAllowed: { [Player]: boolean } = {}
local pushQueued: { [Player]: boolean } = {}

local dataRemote = Net.Event("Data")

function DataService.Today(): number
	return math.floor(os.time() / 86400)
end

function DataService.Get(player: Player): { [string]: any }?
	local profile = profiles[player]
	return profile and profile.Data
end

-- Yields until a DataStore save of the player's profile contains receipt `purchaseId` (ProfileStore's
-- developer-product pattern): a receipt is only confirmed to Roblox once the grant is durable, so a server
-- crash right after a purchase cannot lose it. False if the session ends first (Roblox retries the receipt).
function DataService.WaitForReceiptSaved(player: Player, purchaseId: string): boolean
	local profile = profiles[player]
	if not profile then
		return false
	end
	local function saved(): boolean
		local list = profile.LastSavedData and profile.LastSavedData.Purchases
		return list ~= nil and table.find(list, purchaseId) ~= nil
	end
	while profile:IsActive() do
		if saved() then
			return true
		end
		local lastSaved = profile.LastSavedData
		profile:Save()
		if profile.LastSavedData == lastSaved then
			profile.OnAfterSave:Wait()
		end
		if saved() then
			return true
		end
		if profile:IsActive() then
			task.wait(10)
		end
	end
	return false
end

-- Yields until the player's data is loaded (or they leave / 20 s pass).
function DataService.WaitFor(player: Player): { [string]: any }?
	local deadline = os.clock() + 20
	while player.Parent == Players and os.clock() < deadline do
		local data = DataService.Get(player)
		if data then
			return data
		end
		task.wait(0.1)
	end
	return nil
end

function DataService.SetPass(player: Player, key: string, owned: boolean)
	passes[player] = passes[player] or {}
	passes[player][key] = owned
	if key == "VIP" then
		player:SetAttribute("VIP", owned or nil)
	end
	DataService.Push(player)
end

function DataService.HasPass(player: Player, key: string): boolean
	return passes[player] ~= nil and passes[player][key] == true
end

function DataService.IsPremium(player: Player): boolean
	return player.MembershipType == Enum.MembershipType.Premium
end

-- Relic Capsules are paid random items (cash can be bought with Robux): blocked where policy requires.
function DataService.PaidRandomAllowed(player: Player): boolean
	return paidRandomAllowed[player] == true
end

function DataService.RelicSlots(player: Player): number
	local data = DataService.Get(player)
	if not data then
		return Config.BaseRelicSlots
	end
	local slots = Config.BaseRelicSlots + (data.Upgrades.Slots or 0)
	if DataService.HasPass(player, "VIP") then
		slots += 1
	end
	return slots
end

function DataService.UpgradeValue(player: Player, id: string): number
	local data = DataService.Get(player)
	return if data then Upgrades.Value(id, data.Upgrades[id] or 0) else 0
end

local function updateLeaderstats(player: Player, data)
	local stats = player:FindFirstChild("leaderstats")
	if not stats then
		return
	end
	stats.Cash.Value = data.Cash
	stats.Deepest.Value = data.DeepestFloor
end

function DataService.Snapshot(player: Player)
	local data = DataService.Get(player)
	if not data then
		return nil
	end
	local today = DataService.Today()
	local streakDay = (data.Daily.Streak % #Config.DailyRewards) + 1
	return {
		Cash = data.Cash,
		LifetimeCash = data.LifetimeCash,
		DeepestFloor = data.DeepestFloor,
		TotalRuns = data.TotalRuns,
		Upgrades = data.Upgrades,
		Relics = data.Relics,
		Equipped = data.Equipped,
		Slots = DataService.RelicSlots(player),
		Daily = {
			Streak = data.Daily.Streak,
			CanClaim = data.Daily.LastClaimDay < today,
			NextReward = DataService.DailyReward(data.Daily.Streak + 1),
			Day = streakDay,
		},
		DailyBest = if data.DailyBest.Day == today then data.DailyBest.Floor else 0,
		Passes = {
			DoubleCash = DataService.HasPass(player, "DoubleCash"),
			VIP = DataService.HasPass(player, "VIP"),
			LuckyBellhop = DataService.HasPass(player, "LuckyBellhop"),
			StarterPack = DataService.HasPass(player, "StarterPack"),
		},
		Stats = data.Stats,
		FirstTime = data.TotalRuns == 0,
		ExtraLives = data.ExtraLives,
		Premium = DataService.IsPremium(player),
		PaidRandomAllowed = DataService.PaidRandomAllowed(player),
		CapsuleCost = Config.CapsuleCost(data.DeepestFloor, DataService.HasPass(player, "LuckyBellhop")),
		CapsuleFloor = Config.CapsuleFloor(data.DeepestFloor),
		CashPacks = {
			CashSmall = Config.CashPackAmount("CashSmall", data.DeepestFloor),
			CashMedium = Config.CashPackAmount("CashMedium", data.DeepestFloor),
			CashLarge = Config.CashPackAmount("CashLarge", data.DeepestFloor),
		},
	}
end

-- Reward for claiming on streak day `streak` (1-based). Later weeks pay 50% more per completed week.
function DataService.DailyReward(streak: number): number
	local index = ((streak - 1) % #Config.DailyRewards) + 1
	local week = math.floor((streak - 1) / #Config.DailyRewards)
	return math.floor(Config.DailyRewards[index] * (1 + week * 0.5))
end

-- Queues a Data push (coalesced to one per frame).
function DataService.Push(player: Player)
	if pushQueued[player] then
		return
	end
	pushQueued[player] = true
	task.defer(function()
		pushQueued[player] = nil
		local snapshot = DataService.Snapshot(player)
		if snapshot and player.Parent == Players then
			dataRemote:FireClient(player, snapshot)
			updateLeaderstats(player, DataService.Get(player))
		end
	end)
end

function DataService.AddCash(player: Player, amount: number): boolean
	local data = DataService.Get(player)
	if not data then
		return false
	end
	amount = math.floor(amount)
	data.Cash += amount
	if amount > 0 then
		data.LifetimeCash += amount
	end
	DataService.Push(player)
	return true
end

function DataService.SpendCash(player: Player, amount: number): boolean
	local data = DataService.Get(player)
	if not data or data.Cash < amount then
		return false
	end
	data.Cash -= math.floor(amount)
	DataService.Push(player)
	return true
end

-- Records a cleared floor for depth records. Returns true if it is a new personal best.
function DataService.RecordFloor(player: Player, floor: number, mode: string): boolean
	local data = DataService.Get(player)
	if not data then
		return false
	end
	data.Stats.FloorsCleared += 1
	local best = false
	if floor > data.DeepestFloor then
		data.DeepestFloor = floor
		best = true
	end
	if mode == "Daily" then
		local today = DataService.Today()
		if data.DailyBest.Day ~= today then
			data.DailyBest = { Day = today, Floor = 0 }
		end
		data.DailyBest.Floor = math.max(data.DailyBest.Floor, floor)
	end
	DataService.Push(player)
	return best
end

local function onPlayerAdded(player: Player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local cash = Instance.new("IntValue")
	cash.Name = "Cash"
	cash.Parent = leaderstats
	local deepest = Instance.new("IntValue")
	deepest.Name = "Deepest"
	deepest.Parent = leaderstats
	leaderstats.Parent = player

	task.spawn(function()
		local ok, policy = pcall(PolicyService.GetPolicyInfoForPlayerAsync, PolicyService, player)
		paidRandomAllowed[player] = ok and policy ~= nil and not policy.ArePaidRandomItemsRestricted
		DataService.Push(player)
	end)

	-- Studio only: workspace attribute OMF_MockData = true (set in edit mode) gives every tester a throwaway
	-- profile, so test runs at deep floors never touch the real save.
	local source = store
	if RunService:IsStudio() and workspace:GetAttribute("OMF_MockData") then
		source = store.Mock
		warn(`[DataService] OMF_MockData is on: {player.Name} plays on a throwaway profile (nothing is saved)`)
	end
	local profile = source:StartSessionAsync(`Player_{player.UserId}`, {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})
	if profile == nil then
		player:Kick("Your data could not be loaded. Please rejoin!")
		return
	end

	profile:AddUserId(player.UserId)
	profile:Reconcile()
	profile.OnSessionEnd:Connect(function()
		profiles[player] = nil
		player:Kick("Your data was loaded on another server. Please rejoin!")
	end)

	if player.Parent ~= Players then
		profile:EndSession()
		return
	end

	profiles[player] = profile
	if profile.Data.TotalRuns == 0 then
		require(script.Parent.Analytics).Step(player, 1)
	end
	require(script.Parent.Badges).Award(player, "Welcome")
	DataService.Push(player)
	DataService.Loaded:Fire(player, profile.Data)
end

function DataService.Start()
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		local profile = profiles[player]
		if profile then
			profiles[player] = nil
			profile:EndSession()
		end
		passes[player] = nil
		paidRandomAllowed[player] = nil
	end)
	-- Premium perks (+cash) show up as soon as someone upgrades mid-session
	Players.PlayerMembershipChanged:Connect(function(player)
		DataService.Push(player)
	end)
end

return DataService
