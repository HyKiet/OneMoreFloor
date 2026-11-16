-- Developer products, game passes, Premium perks and ProcessReceipt. Ids live in Config.Products / Config.Passes;
-- design notes in docs/MONETIZATION.md.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Net = require(ReplicatedStorage.Shared.Net)

local Analytics = require(script.Parent.Analytics)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local ElevatorService = require(script.Parent.ElevatorService)
local RateLimit = require(script.Parent.Parent.Util.RateLimit)

local MonetizationService = {}

local MAX_RECEIPTS = 100
local PASS_RETRY_DELAYS = { 2, 5, 10, 20, 40, 60 } -- seconds between ownership checks that errored
local M = Config.Monetization

local productKeyById: { [number]: string } = {}
local passKeyById: { [number]: string } = {}

local function grantExtraLife(player: Player)
	local data = DataService.Get(player)
	local run = ElevatorService.GetRun(player)
	if run and run:TryRevive(player) then
		return true
	end
	-- not spectating right now: bank it (saves your next elimination in a Normal run)
	data.ExtraLives += 1
	EconomyService.Toast(player, "Extra Life banked: it will save you in your next run!", "good")
	return true
end

-- Golden Elevator: x2 cash-outs for everyone in the server; buying again stacks the time.
local function startGoldenHour(player: Player)
	local now = workspace:GetServerTimeNow()
	local current = workspace:GetAttribute("OMF_GoldenUntil") or 0
	workspace:SetAttribute("OMF_GoldenUntil", math.max(current, now) + M.GoldenMinutes * 60)
	workspace:SetAttribute("OMF_GoldenBy", player.DisplayName)
	EconomyService.ToastAll(`{player.DisplayName} started a GOLDEN HOUR: x{M.GoldenCashMult} cash for everyone!`, "rare")
	return true
end

local GRANTS = {
	ExtraLife = grantExtraLife,
	ExtraLife2 = grantExtraLife,
	ExtraLife3 = grantExtraLife,
	CurseElevator = function(player: Player)
		local data = DataService.Get(player)
		local run = ElevatorService.GetRun(player)
		if run and run.Mode == "Normal" and run:AddCurse(nil, player.DisplayName) then
			return true
		end
		data.CurseTokens += 1
		EconomyService.Toast(player, "Curse saved: it will hit your next elevator!", "good")
		return true
	end,
	BlessElevator = function(player: Player)
		local run = ElevatorService.GetRun(player)
		if run and run:Bless(player.DisplayName) then
			return true
		end
		-- nobody left to bless: the shield is not wasted, it becomes a banked Extra Life for the buyer
		DataService.Get(player).ExtraLives += 1
		EconomyService.Toast(player, "The run had ended, so your blessing became a banked Extra Life.", "good")
		return true
	end,
	GoldenElevator = startGoldenHour,
}

local function grantCash(key: string)
	return function(player: Player)
		local data = DataService.Get(player)
		local amount = Config.CashPackAmount(key, data.DeepestFloor)
		DataService.AddCash(player, amount)
		EconomyService.Toast(player, `+{Format.Cash(amount)} banked. Thanks for the support!`, "good")
		return true
	end
end

for key in Config.Monetization.CashPackShare do
	GRANTS[key] = grantCash(key)
end

local function processReceipt(receipt)
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local data = DataService.WaitFor(player)
	if not data then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Grant once per receipt: the id goes into the profile in the same step as the reward.
	if not table.find(data.Purchases, receipt.PurchaseId) then
		local key = productKeyById[receipt.ProductId]
		local grant = key and GRANTS[key]
		if not grant then
			warn("[Monetization] unknown product", receipt.ProductId)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		local ok, result = pcall(grant, player)
		if not ok or not result then
			warn("[Monetization] grant failed:", result)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		table.insert(data.Purchases, receipt.PurchaseId)
		while #data.Purchases > MAX_RECEIPTS do
			table.remove(data.Purchases, 1)
		end
		DataService.Push(player)
		Analytics.Event(player, "ProductBought", receipt.CurrencySpent or 0, { [Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = key })
	end

	-- Confirm to Roblox only once the grant is saved; otherwise Roblox retries it on the next join.
	if DataService.WaitForReceiptSaved(player, receipt.PurchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

-- Starter Pack contents are handed out once per account, whenever we first see the pass owned.
local function grantStarter(player: Player)
	local data = DataService.Get(player)
	if not data or data.StarterGranted then
		return
	end
	data.StarterGranted = true
	DataService.AddCash(player, M.Starter.Cash)
	data.ExtraLives += M.Starter.ExtraLives
	local relicId = EconomyService.RollRelic(Random.new(), 1, M.Starter.Rarity)
	local level, isNew = EconomyService.GrantRelic(player, relicId)
	if level then
		Net.Event("RelicFound"):FireClient(player, { RelicId = relicId, Level = level, IsNew = isNew, Source = "StarterPack" })
	end
	EconomyService.Toast(player, `Starter Pack: +{Format.Cash(M.Starter.Cash)}, {M.Starter.ExtraLives} Extra Lives and a Rare relic!`, "rare")
	DataService.Push(player)
end

local function onPassOwned(player: Player, key: string)
	DataService.SetPass(player, key, true)
	if key == "StarterPack" then
		grantStarter(player)
	end
end

-- Asks Roblox whether `player` owns pass `key`, retrying with backoff while the web call fails. Until an
-- answer arrives the pass stays on if a previous session confirmed it (data.OwnedPasses), so a Roblox
-- hiccup at join never locks a paying player out for the whole session.
local function checkPass(player: Player, key: string, id: number)
	local data = DataService.Get(player)
	if data and data.OwnedPasses[key] then
		onPassOwned(player, key)
	end
	for attempt = 0, #PASS_RETRY_DELAYS do
		if attempt > 0 then
			task.wait(PASS_RETRY_DELAYS[attempt])
		end
		if player.Parent ~= Players then
			return
		end
		local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, id)
		data = DataService.Get(player)
		if ok and data then
			if owns then
				data.OwnedPasses[key] = true
				onPassOwned(player, key)
			elseif data.OwnedPasses[key] then
				-- confirmed gone (refund / moderation): drop the cached ownership
				data.OwnedPasses[key] = nil
				DataService.SetPass(player, key, false)
			end
			return
		end
		if attempt == #PASS_RETRY_DELAYS then
			warn(`[Monetization] could not check pass {key} for {player.Name}: {owns}`)
		end
	end
end

local function checkPasses(player: Player)
	for key, id in Config.Passes do
		if id > 0 then
			task.spawn(checkPass, player, key, id)
		end
	end
end

-- Every Extra Life tier key: whichever one a client asks for, the server picks the tier.
local EXTRA_LIFE_KEYS = { ExtraLife = true, ExtraLife2 = true, ExtraLife3 = true }

-- The product a key resolves to for this player right now (Extra Life is priced by depth).
local function resolveKey(player: Player, key: string): string
	if not EXTRA_LIFE_KEYS[key] then
		return key
	end
	local run = ElevatorService.GetRun(player)
	if run then
		return Config.ExtraLifeKey(math.max(run.Floor, 1))
	end
	local data = DataService.Get(player)
	return Config.ExtraLifeKey(if data then data.DeepestFloor else 1)
end

local function prompt(player: Player, key: unknown)
	if typeof(key) ~= "string" or not RateLimit.Check(player, "PromptProduct", 0.5) then
		return
	end
	if key == "BlessElevator" then
		local run = ElevatorService.GetRun(player)
		if run and run.Mode ~= "Normal" then
			EconomyService.Toast(player, "The Daily Elevator stays fair: no blessings here.", "info")
			return
		end
	end
	local resolved = resolveKey(player, key :: string)
	local productId = Config.Products[resolved]
	local passId = Config.Passes[resolved]
	if productId and productId > 0 then
		if EXTRA_LIFE_KEYS[resolved] then
			local run = ElevatorService.GetRun(player)
			if run then
				run:HoldRevive(player, true)
			end
		end
		MarketplaceService:PromptProductPurchase(player, productId)
	elseif passId and passId > 0 then
		if DataService.HasPass(player, resolved) then
			EconomyService.Toast(player, "You already own this!", "info")
		else
			MarketplaceService:PromptGamePassPurchase(player, passId)
		end
	else
		EconomyService.Toast(player, "Coming soon!", "info")
	end
end

local function promptPremium(player: Player)
	if not RateLimit.Check(player, "PromptPremium", 1) then
		return
	end
	if DataService.IsPremium(player) then
		EconomyService.Toast(player, "Your Premium bonus is already active: +10% cash-outs!", "info")
		return
	end
	MarketplaceService:PromptPremiumPurchase(player)
end

function MonetizationService.Start()
	for key, id in Config.Products do
		if id > 0 then
			productKeyById[id] = key
		end
	end
	for key, id in Config.Passes do
		if id > 0 then
			passKeyById[id] = key
		end
	end

	MarketplaceService.ProcessReceipt = processReceipt
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, purchased)
		local player = Players:GetPlayerByUserId(userId)
		local key = productKeyById[productId]
		if player and key and string.sub(key, 1, 9) == "ExtraLife" then
			local run = ElevatorService.GetRun(player)
			if run then
				run:HoldRevive(player, false, purchased)
			end
		end
	end)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		local key = passKeyById[passId]
		if key and purchased then
			-- Studio test purchases grant nothing on Roblox's side, so only live purchases are cached
			local data = DataService.Get(player)
			if data and not RunService:IsStudio() then
				data.OwnedPasses[key] = true
			end
			onPassOwned(player, key)
			EconomyService.Toast(player, "Game pass unlocked!", "rare")
			Analytics.Event(player, "PassBought", passId, { [Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = key })
		end
	end)
	DataService.Loaded:Connect(function(player)
		checkPasses(player)
	end)
	Net.Event("PromptProduct").OnServerEvent:Connect(prompt)
	Net.Event("PromptPremium").OnServerEvent:Connect(promptPremium)
end

return MonetizationService
