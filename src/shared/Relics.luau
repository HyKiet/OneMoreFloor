-- Relic definitions. Relics are permanent collectibles; equipped relics give passive stats in runs.
-- Each Stats entry is the level-1 value; higher levels add Config.Relic.LevelBonus of it per level.
--
-- Stat keys (all additive, summed across equipped relics):
--   WalkSpeed    +fraction of base walk speed
--   Jump         +fraction of base jump power
--   Gravity      fraction of gravity removed (personal low gravity)
--   BagMult      added to the per-floor bag multiplier
--   CashOut      +fraction cash when leaving with your bag
--   PickupRadius +fraction coin/bag pickup radius
--   RelicChance  +fraction relic drop chance
--   Insurance    fraction of bag kept on death
--   Shields      shields at the start of every run (not scaled by level)
--   Revive       chance to shrug off an elimination (Phoenix)
--   DoubleJump   1 = can double jump (not scaled by level)
--   CoinValue    +fraction value of coins picked up

local Config = require(script.Parent.Config)

local Relics = {}

Relics.List = {
	-- Common
	{ Id = "Sneakers", Name = "Sneakers", Rarity = "Common", Shape = "Block", Color = Color3.fromRGB(240, 240, 240), Desc = "+8% walk speed", Stats = { WalkSpeed = 0.08 } },
	{ Id = "Spring", Name = "Spring Coil", Rarity = "Common", Shape = "Cylinder", Color = Color3.fromRGB(180, 200, 220), Desc = "+8% jump power", Stats = { Jump = 0.08 } },
	{ Id = "Feather", Name = "Feather", Rarity = "Common", Shape = "Wedge", Color = Color3.fromRGB(255, 255, 255), Desc = "-8% gravity", Stats = { Gravity = 0.08 } },
	{ Id = "CopperCoin", Name = "Copper Coin", Rarity = "Common", Shape = "Coin", Color = Color3.fromRGB(205, 125, 70), Desc = "+15% coin value", Stats = { CoinValue = 0.15 } },
	{ Id = "LuckyPenny", Name = "Lucky Penny", Rarity = "Common", Shape = "Coin", Color = Color3.fromRGB(230, 160, 90), Desc = "+8% relic chance", Stats = { RelicChance = 0.08 } },
	{ Id = "RubberDuck", Name = "Rubber Duck", Rarity = "Common", Shape = "Ball", Color = Color3.fromRGB(255, 220, 60), Desc = "Keep 4% of your bag on death", Stats = { Insurance = 0.04 } },

	-- Uncommon
	{ Id = "Magnet", Name = "Magnet", Rarity = "Uncommon", Shape = "Block", Color = Color3.fromRGB(230, 60, 60), Desc = "+60% pickup radius", Stats = { PickupRadius = 0.6 } },
	{ Id = "PiggyBank", Name = "Piggy Bank", Rarity = "Uncommon", Shape = "Ball", Color = Color3.fromRGB(255, 150, 190), Desc = "+8% cash when you leave", Stats = { CashOut = 0.08 } },
	{ Id = "RunningShoes", Name = "Running Shoes", Rarity = "Uncommon", Shape = "Wedge", Color = Color3.fromRGB(80, 200, 255), Desc = "+12% walk speed", Stats = { WalkSpeed = 0.12 } },
	{ Id = "Pogo", Name = "Pogo Stick", Rarity = "Uncommon", Shape = "Cylinder", Color = Color3.fromRGB(120, 255, 140), Desc = "+14% jump power", Stats = { Jump = 0.14 } },
	{ Id = "FourLeaf", Name = "Four-Leaf Clover", Rarity = "Uncommon", Shape = "Diamond", Color = Color3.fromRGB(60, 200, 90), Desc = "+15% relic chance", Stats = { RelicChance = 0.15 } },

	-- Rare
	{ Id = "Bubble", Name = "Bubble", Rarity = "Rare", Shape = "Ball", Color = Color3.fromRGB(140, 220, 255), Desc = "Start every run with a shield", Stats = { Shields = 1 } },
	{ Id = "GhostBoots", Name = "Ghost Boots", Rarity = "Rare", Shape = "Block", Color = Color3.fromRGB(200, 220, 255), Desc = "Double jump", Stats = { DoubleJump = 1 } },
	{ Id = "GoldenTooth", Name = "Golden Tooth", Rarity = "Rare", Shape = "Wedge", Color = Color3.fromRGB(255, 210, 60), Desc = "+0.02 bag multiplier per floor", Stats = { BagMult = 0.02 } },
	{ Id = "SafetyNet", Name = "Safety Net", Rarity = "Rare", Shape = "Block", Color = Color3.fromRGB(120, 255, 200), Desc = "Keep 10% of your bag on death", Stats = { Insurance = 0.1 } },
	{ Id = "Balloon", Name = "Balloon", Rarity = "Rare", Shape = "Ball", Color = Color3.fromRGB(255, 80, 80), Desc = "-18% gravity", Stats = { Gravity = 0.18 } },

	-- Epic
	{ Id = "TreasureMap", Name = "Treasure Map", Rarity = "Epic", Shape = "Block", Color = Color3.fromRGB(230, 200, 140), Desc = "+50% coin value, +20% relic chance", Stats = { CoinValue = 0.5, RelicChance = 0.2 } },
	{ Id = "VaultKey", Name = "Vault Key", Rarity = "Epic", Shape = "Cylinder", Color = Color3.fromRGB(255, 200, 80), Desc = "+20% cash when you leave", Stats = { CashOut = 0.2 } },
	{ Id = "Rocket", Name = "Rocket", Rarity = "Epic", Shape = "Cylinder", Color = Color3.fromRGB(255, 120, 60), Desc = "+15% speed and jump", Stats = { WalkSpeed = 0.15, Jump = 0.15 } },
	{ Id = "DiamondTooth", Name = "Diamond Tooth", Rarity = "Epic", Shape = "Diamond", Color = Color3.fromRGB(160, 240, 255), Desc = "+0.04 bag multiplier per floor", Stats = { BagMult = 0.04 } },

	-- Legendary
	{ Id = "Phoenix", Name = "Phoenix Feather", Rarity = "Legendary", Shape = "Wedge", Color = Color3.fromRGB(255, 110, 40), Desc = "35% chance to shrug off an elimination", Stats = { Revive = 0.35 } },
	{ Id = "Crown", Name = "Crown", Rarity = "Legendary", Shape = "Diamond", Color = Color3.fromRGB(255, 215, 50), Desc = "+40% cash when you leave", Stats = { CashOut = 0.4 } },
	{ Id = "BlackHole", Name = "Black Hole", Rarity = "Legendary", Shape = "Ball", Color = Color3.fromRGB(40, 20, 60), Desc = "x3 pickup radius, +0.03 bag multiplier", Stats = { PickupRadius = 2, BagMult = 0.03 } },

	-- Mythic
	{ Id = "ElevatorKey", Name = "The Elevator Key", Rarity = "Mythic", Shape = "Diamond", Color = Color3.fromRGB(255, 60, 125), Desc = "+0.08 bag multiplier and a shield every run", Stats = { BagMult = 0.08, Shields = 1 } },
}

Relics.ById = {}
Relics.ByRarity = {}
for _, relic in Relics.List do
	Relics.ById[relic.Id] = relic
	Relics.ByRarity[relic.Rarity] = Relics.ByRarity[relic.Rarity] or {}
	table.insert(Relics.ByRarity[relic.Rarity], relic)
end

local UNSCALED = { Shields = true, DoubleJump = true }

-- Sums the stats of the equipped relics. `owned` maps relicId -> level.
function Relics.SumStats(equipped: { string }, owned: { [string]: number }): { [string]: number }
	local total = {}
	for _, id in equipped do
		local relic = Relics.ById[id]
		local level = owned[id]
		if relic and level then
			local scale = 1 + (level - 1) * Config.Relic.LevelBonus
			for stat, value in relic.Stats do
				local add = if UNSCALED[stat] then value else value * scale
				total[stat] = (total[stat] or 0) + add
			end
		end
	end
	if total.DoubleJump then
		total.DoubleJump = math.min(total.DoubleJump, 1)
	end
	return total
end

return Relics
