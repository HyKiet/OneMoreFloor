-- Per-player, per-key cooldown guard for remote handlers.

local Players = game:GetService("Players")

local RateLimit = {}

local lastCall: { [Player]: { [string]: number } } = {}

-- Returns true if the call is allowed (and records it).
function RateLimit.Check(player: Player, key: string, interval: number): boolean
	local now = os.clock()
	local calls = lastCall[player]
	if not calls then
		calls = {}
		lastCall[player] = calls
	end
	local last = calls[key]
	if last and now - last < interval then
		return false
	end
	calls[key] = now
	return true
end

Players.PlayerRemoving:Connect(function(player)
	lastCall[player] = nil
end)

return RateLimit
