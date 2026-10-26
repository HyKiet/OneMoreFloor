-- Awards badges listed in Config.Badges (ids of 0 are skipped).

local BadgeService = game:GetService("BadgeService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Badges = {}

local awarded: { [Player]: { [string]: boolean } } = {}

function Badges.Award(player: Player, key: string)
	local id = Config.Badges[key]
	if not id or id == 0 then
		return
	end
	awarded[player] = awarded[player] or {}
	if awarded[player][key] then
		return
	end
	awarded[player][key] = true
	task.spawn(function()
		local ok, has = pcall(BadgeService.UserHasBadgeAsync, BadgeService, player.UserId, id)
		if ok and not has then
			pcall(BadgeService.AwardBadge, BadgeService, player.UserId, id)
		end
	end)
end

function Badges.OnFloor(player: Player, floor: number)
	if floor >= 10 then
		Badges.Award(player, "Floor10")
	end
	if floor >= 25 then
		Badges.Award(player, "Floor25")
	end
	if floor >= 50 then
		Badges.Award(player, "Floor50")
	end
end

game:GetService("Players").PlayerRemoving:Connect(function(player)
	awarded[player] = nil
end)

return Badges
