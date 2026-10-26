-- Central tunables for One More Floor. Server and client both read this.

local Config = {}

-- Runs ----------------------------------------------------------------------

Config.MaxPlayersPerRun = 8
Config.BoardingCountdown = 10 -- seconds after the first player steps into a boarding zone
Config.BoardingFullCountdown = 3 -- countdown snaps to this when the cab is full

Config.DescendTime = 4
Config.BriefingTime = 3.5
Config.ResultsTime = 2.5
Config.DecisionTime = 8
Config.ShopTime = 10
Config.EndedLinger = 4 -- seconds the "run over" screen stays before spectators are sent home

Config.BossEvery = 5 -- floors 5, 10, 15... are boss floors
Config.ShopAfterBoss = true -- the decision after a boss floor also opens the run shop

-- World layout. Run instances live far from the lobby, one slot each.
Config.SlotOrigin = Vector3.new(3000, 0, 0)
Config.SlotSpacing = 700
Config.MaxSlots = 12
Config.ArenaOffset = CFrame.new(0, 0, -90) -- arena centre relative to the cab floor centre (cab faces -Z)
Config.BoothOffset = CFrame.new(0, 80, 0) -- spectator booth relative to the arena centre
Config.KillDepth = 30 -- falling this far below the arena origin eliminates you
Config.ArenaHalfExtent = 60 -- templates should keep geometry within +-this on X/Z

-- Economy -------------------------------------------------------------------

Config.Bag = {
	Multiplier = 1.25, -- bag growth per floor survived
	BossMultiplier = 1.5,
	DropShare = 0.5, -- share of a dead player's lost bag that drops as a pickup for survivors
}

function Config.FloorReward(floor: number): number
	return 10 + floor * 5
end

function Config.CoinValue(floor: number): number
	return 2 + math.floor(floor * 1.5)
end

-- Zones: each depth band has its own pool of floors (template field `Zone`), so every band plays fresh.
-- A run never repeats a floor until it has seen every eligible one (ChallengeRegistry.Pick).
Config.Zones = {
	{ FromFloor = 1, Name = "Lobby Blue" }, -- zone 1: B1-B9, easy, one idea per floor
	{ FromFloor = 10, Name = "Ultraviolet" }, -- zone 2: B10-B19
	{ FromFloor = 20, Name = "Inferno" }, -- zone 3: B20+, then every floor comes back harder
}

function Config.ZoneFor(floor: number): number
	local zone = 1
	for i, z in Config.Zones do
		if floor >= z.FromFloor then
			zone = i
		end
	end
	return zone
end

-- Difficulty is roughly 0 on floor 1 and 1 around floor 26. Boss floors add a bump.
function Config.Difficulty(floor: number, isBoss: boolean): number
	local d = math.clamp((floor - 1) / 25, 0, 1.25)
	if isBoss then
		d += 0.2
	end
	return d
end

-- Relics --------------------------------------------------------------------

Config.Relic = {
	BaseChance = 0.06,
	PerFloor = 0.006,
	MaxChance = 0.45,
	GuaranteedFirstFloor = 3, -- a player's very first relic is guaranteed on this floor
	MaxLevel = 5,
	LevelBonus = 0.25, -- each extra level adds +25% of the base effect
}

Config.BaseRelicSlots = 1

-- Run shop (opens on the decision after each boss floor). Prices are a share of your current bag.
Config.RunItems = {
	{ Id = "Shield", Name = "Bubble Shield", Desc = "Survive one elimination this run.", Cost = 0.25 },
	{ Id = "Insurance", Name = "Insurance Slip", Desc = "Keep 75% of your bag if you die this run.", Cost = 0.2 },
	{ Id = "Charm", Name = "Lucky Charm", Desc = "Double relic chance for the next 5 floors.", Cost = 0.15 },
}

-- Curses --------------------------------------------------------------------

Config.CurseChance = 0.35 -- chance a random curse hits a floor when nobody voted (from CurseMinFloor)
Config.CurseMinFloor = 6
Config.VoteOptionCount = 3

-- Daily ---------------------------------------------------------------------

Config.DailyRewards = { 100, 150, 250, 400, 600, 900, 2000 } -- index = streak day (loops after 7, scaled)

-- Monetization (ids from the Creator Dashboard; 0 = not created yet, the UI shows "coming soon") -----
-- Design notes live in docs/MONETIZATION.md.

Config.Products = {
	-- Extra Life is priced by how deep you are (what is at stake). Clients always ask for "ExtraLife";
	-- the server picks the tier with Config.ExtraLifeKey. Bought while spectating it revives you with your
	-- bag (once per run, Normal mode); bought any other time it is banked and saves your next elimination.
	ExtraLife = 3721642948, -- floors 1-9
	ExtraLife2 = 3721643053, -- floors 10-19
	ExtraLife3 = 3721643149, -- floors 20+
	CurseElevator = 3721643457, -- spectator: slap a random curse on the survivors' next floor
	BlessElevator = 3721643592, -- spectator: every survivor in your run gets a Bubble Shield
	GoldenElevator = 3721644068, -- whole server: x2 cash-outs for 15 minutes (stacks time)
	CashSmall = 3721644221, -- cash packs scale with your deepest floor (Config.CashPackAmount)
	CashMedium = 3721644327,
	CashLarge = 3721644390,
}

Config.Passes = {
	VIP = 2052275069, -- +1 relic slot, +10% bag growth, VIP chat tag
	DoubleCash = 2053991076, -- x2 cash when leaving with your bag
	LuckyBellhop = 2053439011, -- +25% relic find chance, Relic Capsules 20% cheaper
	StarterPack = 2053247082, -- one-time: $5,000 + 3 Extra Lives + a Rare relic
}

Config.Monetization = {
	ReviveWindow = 10, -- seconds a fresh elimination keeps the run alive for an Extra Life purchase
	GoldenMinutes = 15,
	GoldenCashMult = 2,
	PremiumCashMult = 1.1, -- Roblox Premium members: +10% cash-outs
	VipBagBonus = 0.1, -- share of the base bag growth added for VIP
	LuckyRelicChance = 0.25,
	LuckyCapsuleDiscount = 0.2,
	Starter = { Cash = 5000, ExtraLives = 3, Rarity = "Rare" },
	CashPackShare = { CashSmall = 1, CashMedium = 3.6, CashLarge = 12 }, -- x a typical bag at your depth
	CashPackMin = { CashSmall = 1500, CashMedium = 6000, CashLarge = 25000 },
}

Config.ProductCash = {} -- legacy (fixed-amount packs); kept empty until the shop UI moves to CashPackAmount

-- Which Extra Life product applies at `floor`.
function Config.ExtraLifeKey(floor: number): string
	if floor >= 20 then
		return "ExtraLife3"
	elseif floor >= 10 then
		return "ExtraLife2"
	end
	return "ExtraLife"
end

-- Bag of a player with no upgrades or relics who clears floors 1..floor (matches Run:_results).
function Config.TypicalBag(floor: number): number
	local bag = 0
	for f = 1, math.floor(floor) do
		local mult = if f % Config.BossEvery == 0 then Config.Bag.BossMultiplier else Config.Bag.Multiplier
		bag = math.floor((bag + Config.FloorReward(f)) * mult)
	end
	return bag
end

-- Cash granted by a cash pack, scaled to the buyer's deepest floor so packs never go stale.
function Config.CashPackAmount(key: string, deepestFloor: number): number
	local share = Config.Monetization.CashPackShare[key]
	if not share then
		return 0
	end
	local typical = Config.TypicalBag(math.clamp(deepestFloor, 8, 40))
	local amount = math.max(Config.Monetization.CashPackMin[key], typical * share)
	-- round to 2 significant digits so the number reads cleanly
	local magnitude = 10 ^ math.max(math.floor(math.log10(amount)) - 1, 0)
	return math.floor(amount / magnitude + 0.5) * magnitude
end

-- Cash sinks ------------------------------------------------------------------

-- Cost to polish a relic from `level` to level + 1 (nil when maxed).
Config.PolishRarityMult = { Common = 1, Uncommon = 2, Rare = 4, Epic = 8, Legendary = 16, Mythic = 32 }
function Config.PolishCost(rarity: string, level: number): number?
	if level >= Config.Relic.MaxLevel then
		return nil
	end
	return 1500 * (Config.PolishRarityMult[rarity] or 1) * 4 ^ (level - 1)
end

-- Relic Capsule: a random relic for cash. Odds follow Rarity.Odds(Config.CapsuleFloor(deepest)).
function Config.CapsuleFloor(deepestFloor: number): number
	return math.clamp(deepestFloor, 5, 40)
end

function Config.CapsuleCost(deepestFloor: number, lucky: boolean?): number
	local cost = math.max(1000, Config.TypicalBag(Config.CapsuleFloor(deepestFloor)) * 0.6)
	if lucky then
		cost *= 1 - Config.Monetization.LuckyCapsuleDiscount
	end
	return math.floor(cost / 100 + 0.5) * 100
end

-- Badge ids (create badges in the Creator Dashboard, then paste ids here; 0 = skip).
Config.Badges = {
	Welcome = 0,
	FirstCashOut = 0,
	Floor10 = 0,
	Floor25 = 0,
	Floor50 = 0,
	LegendaryRelic = 0,
}

Config.Codes = {
	LAUNCH = 500,
	ONEMOREFLOOR = 1000,
}

-- Visual themes by depth. Templates read ctx.Theme for their colours. Floor is a mid tone (HSV value ~0.4;
-- The Void a little darker): arenas sit under a night sky, and templates darken it further for trims and
-- housings. No accent is pure white: white neon blooms out (Context:Rim and many trims use Primary as is).
Config.Themes = {
	{ FromFloor = 1, Name = "Lobby Blue", Floor = Color3.fromRGB(66, 78, 118), Primary = Color3.fromRGB(70, 200, 255), Secondary = Color3.fromRGB(255, 120, 200), Hazard = Color3.fromRGB(255, 60, 60) },
	{ FromFloor = 10, Name = "Ultraviolet", Floor = Color3.fromRGB(76, 60, 118), Primary = Color3.fromRGB(170, 90, 255), Secondary = Color3.fromRGB(80, 255, 200), Hazard = Color3.fromRGB(255, 70, 70) },
	{ FromFloor = 20, Name = "Inferno", Floor = Color3.fromRGB(110, 56, 50), Primary = Color3.fromRGB(255, 120, 50), Secondary = Color3.fromRGB(255, 220, 80), Hazard = Color3.fromRGB(255, 40, 90) },
	{ FromFloor = 30, Name = "Gold Vault", Floor = Color3.fromRGB(104, 88, 56), Primary = Color3.fromRGB(255, 210, 70), Secondary = Color3.fromRGB(236, 230, 214), Hazard = Color3.fromRGB(255, 50, 50) },
	{ FromFloor = 45, Name = "The Void", Floor = Color3.fromRGB(62, 62, 82), Primary = Color3.fromRGB(200, 204, 226), Secondary = Color3.fromRGB(255, 60, 120), Hazard = Color3.fromRGB(255, 30, 30) },
}

function Config.ThemeFor(floor: number)
	local theme = Config.Themes[1]
	for _, t in Config.Themes do
		if floor >= t.FromFloor then
			theme = t
		end
	end
	return theme
end

return Config
