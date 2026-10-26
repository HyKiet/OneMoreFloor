-- Rarity tiers shared by relics and UI.

local Rarity = {}

Rarity.Order = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }

Rarity.Info = {
	Common = { Rank = 1, Color = Color3.fromRGB(190, 195, 205), Weight = 60 },
	Uncommon = { Rank = 2, Color = Color3.fromRGB(90, 225, 120), Weight = 25 },
	Rare = { Rank = 3, Color = Color3.fromRGB(70, 155, 255), Weight = 10 },
	Epic = { Rank = 4, Color = Color3.fromRGB(185, 95, 255), Weight = 4 },
	Legendary = { Rank = 5, Color = Color3.fromRGB(255, 195, 45), Weight = 0.9 },
	Mythic = { Rank = 6, Color = Color3.fromRGB(255, 60, 125), Weight = 0.1 },
}

-- Deeper floors push weight toward rarer tiers.
function Rarity.WeightsFor(floor: number): { [string]: number }
	local boost = 1 + math.max(floor - 1, 0) / 10 * 0.35
	local weights = {}
	for _, name in Rarity.Order do
		local info = Rarity.Info[name]
		weights[name] = info.Weight * boost ^ (info.Rank - 1)
	end
	return weights
end

-- Percent chance of each tier at `floor` (shown to players before they buy a Relic Capsule).
function Rarity.Odds(floor: number): { [string]: number }
	local weights = Rarity.WeightsFor(floor)
	local total = 0
	for _, w in weights do
		total += w
	end
	local odds = {}
	for name, w in weights do
		odds[name] = w / total * 100
	end
	return odds
end

function Rarity.Roll(rng: Random, floor: number): string
	local weights = Rarity.WeightsFor(floor)
	local total = 0
	for _, w in weights do
		total += w
	end
	local pick = rng:NextNumber() * total
	for _, name in Rarity.Order do
		pick -= weights[name]
		if pick <= 0 then
			return name
		end
	end
	return "Common"
end

return Rarity
