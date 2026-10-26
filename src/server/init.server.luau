-- Server bootstrap for One More Floor.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Create every remote before anything can fire one.
require(ReplicatedStorage.Shared.Net).Event("Data")

local Services = script.Services

local ORDER = {
	"DataService",
	"LobbyService",
	"EconomyService",
	"LeaderboardService",
	"ElevatorService",
	"MonetizationService",
}

for _, name in ORDER do
	local service = require(Services[name])
	local ok, err = pcall(service.Start)
	if not ok then
		warn(`[Server] {name} failed to start: {err}`)
	end
end

print("[Server] One More Floor ready")
