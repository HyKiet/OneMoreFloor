-- Client bootstrap: starts every controller in dependency order.

local Controllers = script:WaitForChild("Controllers")

local ORDER = {
	"State",
	"Screen",
	"Audio",
	"CameraShake",
	"Toast",
	"Briefing",
	"Celebration",
	"Effects",
	"Panels",
	"Hud",
	"Decision",
	"Spectator",
	"Leaderboard",
	"Movement",
	"Spin",
	"Guide",
	"Ambience",
	"ArenaFx",
	"ChatTags",
}

for _, name in ORDER do
	local module = Controllers:WaitForChild(name)
	local ok, err = pcall(function()
		require(module).Start()
	end)
	if not ok then
		warn(`[Client] {name} failed to start: {err}`)
	end
end
