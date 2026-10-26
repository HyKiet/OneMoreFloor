-- Thin wrapper over AnalyticsService (Creator Dashboard > Analytics). Every call is best-effort.
-- Onboarding funnel steps: 1 Joined, 2 Boarded, 3 Cleared floor 1, 4 Cleared floor 3,
-- 5 First cash out, 6 First upgrade.

local AnalyticsService = game:GetService("AnalyticsService")

local Analytics = {}

local STEP_NAMES = { "Joined", "Boarded", "Floor1", "Floor3", "FirstCashOut", "FirstUpgrade" }

local reached: { [Player]: { [number]: boolean } } = {}

function Analytics.Step(player: Player, step: number)
	reached[player] = reached[player] or {}
	if reached[player][step] then
		return
	end
	reached[player][step] = true
	pcall(AnalyticsService.LogOnboardingFunnelStepEvent, AnalyticsService, player, step, STEP_NAMES[step])
end

function Analytics.Event(player: Player, name: string, value: number?, fields: { [string]: any }?)
	pcall(AnalyticsService.LogCustomEvent, AnalyticsService, player, name, value or 1, fields)
end

function Analytics.Forget(player: Player)
	reached[player] = nil
end

return Analytics
