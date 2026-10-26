-- Lobby economy: permanent upgrades, relic collection & equipping, daily rewards, codes,
-- and the cash sinks (Relic Polish, Relic Capsule).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Relics = require(ReplicatedStorage.Shared.Relics)
local Rarity = require(ReplicatedStorage.Shared.Rarity)
local Upgrades = require(ReplicatedStorage.Shared.Upgrades)
local Format = require(ReplicatedStorage.Shared.Format)

local Analytics = require(script.Parent.Analytics)
local DataService = require(script.Parent.DataService)
local RateLimit = require(script.Parent.Parent.Util.RateLimit)

local EconomyService = {}

local toastRemote = Net.Event("Toast")
local relicFoundRemote = Net.Event("RelicFound")
local capsuleRng = Random.new()

function EconomyService.Toast(player: Player, text: string, style: string?)
	toastRemote:FireClient(player, text, style or "info")
end

function EconomyService.ToastAll(text: string, style: string?)
	toastRemote:FireAllClients(text, style or "info")
end

-- Stats from equipped relics plus permanent upgrades, used by runs.
function EconomyService.RunStats(player: Player): { [string]: number }
	local data = DataService.Get(player)
	if not data then
		return {}
	end
	local stats = Relics.SumStats(data.Equipped, data.Relics)
	local agility = Upgrades.Value("Agility", data.Upgrades.Agility or 0)
	stats.WalkSpeed = (stats.WalkSpeed or 0) + agility
	stats.Jump = (stats.Jump or 0) + agility
	stats.Insurance = (stats.Insurance or 0) + Upgrades.Value("Insurance", data.Upgrades.Insurance or 0)
	stats.BagMult = (stats.BagMult or 0) + Upgrades.Value("Greed", data.Upgrades.Greed or 0)
	stats.RelicChance = (stats.RelicChance or 0) + Upgrades.Value("Luck", data.Upgrades.Luck or 0)
	stats.Shields = (stats.Shields or 0) + Upgrades.Value("Shield", data.Upgrades.Shield or 0)
	if DataService.HasPass(player, "VIP") then
		stats.BagMult += Config.Monetization.VipBagBonus * (Config.Bag.Multiplier - 1)
	end
	if DataService.HasPass(player, "LuckyBellhop") then
		stats.RelicChance += Config.Monetization.LuckyRelicChance
	end
	return stats
end

-- Picks a relic id of a rolled rarity. `rng` decides rarity and relic.
function EconomyService.RollRelic(rng: Random, floor: number, forceRarity: string?): string
	local rarity = forceRarity or Rarity.Roll(rng, floor)
	local pool = Relics.ByRarity[rarity] or Relics.ByRarity.Common
	return pool[rng:NextInteger(1, #pool)].Id
end

-- Grants a relic (new or +1 level). Returns level, isNew; nil if data missing.
function EconomyService.GrantRelic(player: Player, relicId: string): (number?, boolean?)
	local data = DataService.Get(player)
	local relic = Relics.ById[relicId]
	if not data or not relic then
		return nil, nil
	end
	local current = data.Relics[relicId]
	local isNew = current == nil
	local level
	if isNew then
		level = 1
		data.Relics[relicId] = 1
		-- auto-equip into a free slot
		if #data.Equipped < DataService.RelicSlots(player) then
			table.insert(data.Equipped, relicId)
		end
	elseif current < Config.Relic.MaxLevel then
		level = current + 1
		data.Relics[relicId] = level
	else
		-- Maxed duplicate: melt into cash
		level = current
		local cash = 250 * Rarity.Info[relic.Rarity].Rank ^ 2
		DataService.AddCash(player, cash)
		EconomyService.Toast(player, `{relic.Name} is maxed — melted for {Format.Cash(cash)}`, "good")
	end
	data.FirstRelicGiven = true
	DataService.Push(player)
	return level, isNew
end

local function buyUpgrade(player: Player, upgradeId: unknown)
	if typeof(upgradeId) ~= "string" or not RateLimit.Check(player, "BuyUpgrade", 0.15) then
		return
	end
	local data = DataService.Get(player)
	local upgrade = Upgrades.ById[upgradeId]
	if not data or not upgrade then
		return
	end
	local level = data.Upgrades[upgradeId] or 0
	local cost = Upgrades.CostFor(upgradeId, level)
	if not cost then
		EconomyService.Toast(player, `{upgrade.Name} is already maxed!`, "info")
		return
	end
	if not DataService.SpendCash(player, cost) then
		EconomyService.Toast(player, `Need {Format.Cash(cost - data.Cash)} more`, "bad")
		return
	end
	data.Upgrades[upgradeId] = level + 1
	DataService.Push(player)
	Analytics.Step(player, 6)
	Analytics.Event(player, "UpgradeBought", level + 1, { [Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = upgradeId })
	EconomyService.Toast(player, `{upgrade.Name} upgraded to level {level + 1}!`, "good")
end

local function equip(player: Player, relicId: unknown, slot: unknown)
	if typeof(relicId) ~= "string" or typeof(slot) ~= "number" or not RateLimit.Check(player, "Equip", 0.1) then
		return
	end
	local data = DataService.Get(player)
	if not data or not data.Relics[relicId] then
		return
	end
	slot = math.floor(slot :: number)
	local slots = DataService.RelicSlots(player)
	if slot < 1 or slot > slots then
		return
	end
	if player:GetAttribute("InRun") then
		EconomyService.Toast(player, "You can't swap relics during a run.", "bad")
		return
	end
	-- remove from any other slot first
	local existing = table.find(data.Equipped, relicId)
	if existing then
		table.remove(data.Equipped, existing)
	end
	-- compact into a dense list capped at `slots`
	if slot > #data.Equipped then
		table.insert(data.Equipped, relicId)
	else
		data.Equipped[slot] = relicId
	end
	while #data.Equipped > slots do
		table.remove(data.Equipped)
	end
	DataService.Push(player)
end

local function unequip(player: Player, slot: unknown)
	if typeof(slot) ~= "number" or not RateLimit.Check(player, "Equip", 0.1) then
		return
	end
	local data = DataService.Get(player)
	if not data then
		return
	end
	if player:GetAttribute("InRun") then
		EconomyService.Toast(player, "You can't swap relics during a run.", "bad")
		return
	end
	slot = math.floor(slot :: number)
	if data.Equipped[slot] then
		table.remove(data.Equipped, slot)
		DataService.Push(player)
	end
end

-- Relic Polish: level a relic up with cash instead of waiting for duplicates.
local function polishRelic(player: Player, relicId: unknown)
	if typeof(relicId) ~= "string" or not RateLimit.Check(player, "PolishRelic", 0.25) then
		return
	end
	local data = DataService.Get(player)
	local relic = Relics.ById[relicId :: string]
	if not data or not relic or not data.Relics[relicId] then
		return
	end
	local level = data.Relics[relicId]
	local cost = Config.PolishCost(relic.Rarity, level)
	if not cost then
		EconomyService.Toast(player, `{relic.Name} is already max level!`, "info")
		return
	end
	if not DataService.SpendCash(player, cost) then
		EconomyService.Toast(player, `Need {Format.Cash(cost - data.Cash)} more`, "bad")
		return
	end
	data.Relics[relicId] = level + 1
	DataService.Push(player)
	Analytics.Event(player, "RelicPolished", level + 1, { [Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = relicId })
	EconomyService.Toast(player, `{relic.Name} polished to level {level + 1}!`, "good")
end

-- Relic Capsule: a random relic for cash. Odds are Rarity.Odds(Config.CapsuleFloor(deepest)), shown in the UI.
local function buyCapsule(player: Player)
	if not RateLimit.Check(player, "BuyCapsule", 1.2) then
		return
	end
	local data = DataService.Get(player)
	if not data then
		return
	end
	if not DataService.PaidRandomAllowed(player) then
		EconomyService.Toast(player, "Relic Capsules aren't available in your region.", "info")
		return
	end
	if player:GetAttribute("InRun") then
		return
	end
	local cost = Config.CapsuleCost(data.DeepestFloor, DataService.HasPass(player, "LuckyBellhop"))
	if not DataService.SpendCash(player, cost) then
		EconomyService.Toast(player, `Need {Format.Cash(cost - data.Cash)} more`, "bad")
		return
	end
	local relicId = EconomyService.RollRelic(capsuleRng, Config.CapsuleFloor(data.DeepestFloor))
	local level, isNew = EconomyService.GrantRelic(player, relicId)
	if not level then
		return
	end
	data.CapsulesOpened += 1
	Analytics.Event(player, "CapsuleOpened", cost, { [Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = relicId })
	relicFoundRemote:FireClient(player, { RelicId = relicId, Level = level, IsNew = isNew, Source = "Capsule" })
	local relic = Relics.ById[relicId]
	if Rarity.Info[relic.Rarity].Rank >= 5 then
		EconomyService.ToastAll(`{player.DisplayName} pulled a {string.upper(relic.Rarity)} {relic.Name} from a Relic Capsule!`, "rare")
	end
end

local function claimDaily(player: Player)
	if not RateLimit.Check(player, "ClaimDaily", 1) then
		return
	end
	local data = DataService.Get(player)
	if not data then
		return
	end
	local today = DataService.Today()
	if data.Daily.LastClaimDay >= today then
		EconomyService.Toast(player, "Come back tomorrow for your next reward!", "info")
		return
	end
	-- Missing a day only drops the streak by one (so the claim keeps it level) instead of resetting it.
	local missed = data.Daily.LastClaimDay > 0 and data.Daily.LastClaimDay < today - 1
	if missed then
		data.Daily.Streak = math.max(0, data.Daily.Streak - 1)
	end
	data.Daily.Streak += 1
	data.Daily.LastClaimDay = today
	local reward = DataService.DailyReward(data.Daily.Streak)
	DataService.AddCash(player, reward)
	EconomyService.Toast(player, `Day {data.Daily.Streak} reward: {Format.Cash(reward)}!`, "good")
end

local function redeemCode(player: Player, code: unknown): (boolean, string)
	if typeof(code) ~= "string" or #code > 40 or not RateLimit.Check(player, "RedeemCode", 1) then
		return false, "Slow down!"
	end
	local data = DataService.Get(player)
	if not data then
		return false, "Data not loaded yet."
	end
	local key = string.upper(((code :: string):gsub("%s", "")))
	local reward = Config.Codes[key]
	if not reward then
		return false, "Invalid code."
	end
	if data.Codes[key] then
		return false, "Already redeemed."
	end
	data.Codes[key] = true
	DataService.AddCash(player, reward)
	return true, `Redeemed {Format.Cash(reward)}!`
end

function EconomyService.Start()
	Net.Event("BuyUpgrade").OnServerEvent:Connect(buyUpgrade)
	Net.Event("Equip").OnServerEvent:Connect(equip)
	Net.Event("Unequip").OnServerEvent:Connect(unequip)
	Net.Event("ClaimDaily").OnServerEvent:Connect(claimDaily)
	Net.Function("RedeemCode").OnServerInvoke = redeemCode
	Net.Event("PolishRelic").OnServerEvent:Connect(polishRelic)
	Net.Event("BuyCapsule").OnServerEvent:Connect(buyCapsule)

	-- Remind returning players about their daily reward.
	DataService.Loaded:Connect(function(player, data)
		if data.Daily.LastClaimDay < DataService.Today() then
			task.delay(4, function()
				if player.Parent == Players then
					EconomyService.Toast(player, "Your daily reward is ready at the gift desk!", "good")
				end
			end)
		end
	end)
end

return EconomyService
