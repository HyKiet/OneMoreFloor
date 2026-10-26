-- Permanent upgrades bought with banked cash in the lobby.

local Upgrades = {}

Upgrades.List = {
	{ Id = "Insurance", Name = "Insurance", Desc = "Keep +4% of your bag when you die.", Max = 10, BaseCost = 150, Growth = 1.8, Per = 0.04 },
	{ Id = "Greed", Name = "Greed", Desc = "+0.01 bag multiplier every floor.", Max = 10, BaseCost = 250, Growth = 1.9, Per = 0.01 },
	{ Id = "Luck", Name = "Luck", Desc = "+10% relic drop chance.", Max = 10, BaseCost = 200, Growth = 1.8, Per = 0.1 },
	{ Id = "Agility", Name = "Agility", Desc = "+2% walk speed and jump power.", Max = 10, BaseCost = 120, Growth = 1.7, Per = 0.02 },
	{ Id = "Shield", Name = "Starting Shield", Desc = "Start every run with +1 shield.", Max = 2, BaseCost = 5000, Growth = 6, Per = 1 },
	{ Id = "Slots", Name = "Relic Slot", Desc = "+1 relic slot.", Max = 2, BaseCost = 1500, Growth = 5, Per = 1 },
}

Upgrades.ById = {}
for _, upgrade in Upgrades.List do
	Upgrades.ById[upgrade.Id] = upgrade
end

-- Cost of buying the next level when you currently own `level`. nil when maxed.
function Upgrades.CostFor(id: string, level: number): number?
	local upgrade = Upgrades.ById[id]
	if not upgrade or level >= upgrade.Max then
		return nil
	end
	return math.floor(upgrade.BaseCost * upgrade.Growth ^ level)
end

function Upgrades.Value(id: string, level: number): number
	local upgrade = Upgrades.ById[id]
	return if upgrade then upgrade.Per * level else 0
end

return Upgrades
