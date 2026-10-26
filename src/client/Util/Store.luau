-- Client-side storefront helpers shared by the Shop, the revive offer, the decision screen and the
-- HUD: product ids, cached Robux prices, purchase prompts, Data fields with Config fallbacks (the
-- server may not send every field yet) and the server-wide Golden Hour clock.

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Net = require(ReplicatedStorage.Shared.Net)
local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)

local peek = Fusion.peek

local Store = {}

local scope = Fusion.scoped(Fusion)

-- Products / passes ------------------------------------------------------------------------------

function Store.IsPass(key: string): boolean
	return Config.Passes[key] ~= nil
end

function Store.Id(key: string): number
	return Config.Passes[key] or Config.Products[key] or 0
end

-- id 0 = not created in the Creator Dashboard yet ("COMING SOON").
function Store.Available(key: string): boolean
	return Store.Id(key) > 0
end

local prices: { [string]: any } = {}

-- Robux price of `key` as a state: 0 until fetched (or while the item does not exist yet).
-- Fetched once per key with GetProductInfo and cached for the session.
function Store.Price(key: string): any
	local cached = prices[key]
	if cached then
		return cached
	end
	local value = scope:Value(0)
	prices[key] = value
	local id = Store.Id(key)
	if id <= 0 then
		return value
	end
	local infoType = if Store.IsPass(key) then Enum.InfoType.GamePass else Enum.InfoType.Product
	task.spawn(function()
		for attempt = 1, 3 do
			local ok, info = pcall(function()
				return MarketplaceService:GetProductInfo(id, infoType)
			end)
			local price = ok and info and tonumber(info.PriceInRobux)
			if price then
				value:set(price)
				return
			end
			task.wait(2 * attempt)
		end
	end)
	return value
end

function Store.Robux(amount: number): string
	return "R$ " .. Format.Comma(amount)
end

-- "R$ 49" for `key`, or `fallback` while the price is unknown. Call inside a Computed.
function Store.PriceText(use: any, key: string, fallback: string?): string
	local price = use(Store.Price(key))
	if price > 0 then
		return Store.Robux(price)
	end
	return fallback or ""
end

-- Asks the server to open the purchase prompt ("ExtraLife": the server picks the tier).
function Store.Prompt(key: string)
	Net.Event("PromptProduct"):FireServer(key)
end

function Store.PromptPremium()
	Net.Event("PromptPremium"):FireServer()
end

-- Data with Config fallbacks ---------------------------------------------------------------------

function Store.Deepest(d: any): number
	return (d and tonumber(d.DeepestFloor)) or 0
end

function Store.OwnsPass(d: any, key: string): boolean
	return d ~= nil and d.Passes ~= nil and d.Passes[key] == true
end

function Store.CashPack(d: any, key: string): number
	local packs = d and d.CashPacks
	local amount = packs and tonumber(packs[key])
	return amount or Config.CashPackAmount(key, Store.Deepest(d))
end

function Store.CapsuleFloor(d: any): number
	return (d and tonumber(d.CapsuleFloor)) or Config.CapsuleFloor(Store.Deepest(d))
end

function Store.CapsuleCost(d: any): number
	return (d and tonumber(d.CapsuleCost)) or Config.CapsuleCost(Store.Deepest(d), Store.OwnsPass(d, "LuckyBellhop"))
end

-- Extra Life tier for the lobby (the server prices it by your deepest floor there).
function Store.LobbyExtraLifeKey(d: any): string
	return Config.ExtraLifeKey(math.max(Store.Deepest(d), 1))
end

-- Time --------------------------------------------------------------------------------------------

-- 754 -> "12:34", 3725 -> "1:02:05"
function Store.Clock(seconds: number): string
	local s = math.max(math.ceil(seconds), 0)
	local h = s // 3600
	local m = (s % 3600) // 60
	local r = s % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, r)
	end
	return string.format("%d:%02d", m, r)
end

-- Golden Hour --------------------------------------------------------------------------------------
-- workspace attributes OMF_GoldenUntil (server time) / OMF_GoldenBy (display name).

Store.GoldenLeft = scope:Value(0) -- whole seconds left, 0 when inactive
Store.GoldenBy = scope:Value("")
Store.GoldenActive = scope:Computed(function(use)
	return use(Store.GoldenLeft) > 0
end)

local startedListeners: { (by: string) -> () } = {}

-- `fn(byName)` runs when a Golden Hour starts while this client is in the server (not on join).
function Store.OnGoldenStarted(fn: (string) -> ())
	table.insert(startedListeners, fn)
end

local function goldenUntil(): number
	return tonumber(workspace:GetAttribute("OMF_GoldenUntil")) or 0
end

local function tickGolden()
	local left = math.max(math.ceil(goldenUntil() - workspace:GetServerTimeNow()), 0)
	if left ~= peek(Store.GoldenLeft) then
		Store.GoldenLeft:set(left)
	end
end

do
	local function readBy()
		local by = workspace:GetAttribute("OMF_GoldenBy")
		Store.GoldenBy:set(if typeof(by) == "string" then by else "")
	end
	readBy()
	tickGolden()

	local lastUntil = goldenUntil()
	workspace:GetAttributeChangedSignal("OMF_GoldenBy"):Connect(readBy)
	workspace:GetAttributeChangedSignal("OMF_GoldenUntil"):Connect(function()
		local now = workspace:GetServerTimeNow()
		local newUntil = goldenUntil()
		local wasActive = lastUntil > now
		lastUntil = newUntil
		tickGolden()
		if newUntil > now and not wasActive then
			-- both attributes replicate together, but their signals fire one by one
			task.defer(function()
				readBy()
				for _, fn in startedListeners do
					task.spawn(fn, peek(Store.GoldenBy))
				end
			end)
		end
	end)

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= 0.2 then
			acc = 0
			tickGolden()
		end
	end)
end

return Store
