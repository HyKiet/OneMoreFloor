-- Chat name tags: a gold [VIP] prefix for players the server marks with the VIP attribute
-- (VIP pass owners). TextChatService only; the legacy chat has no per-message hook here.

local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")

local ChatTags = {}

local VIP_COLOR = "#FFCC58" -- Theme.Color.Gold

local function isVip(userId: number): boolean
	local player = Players:GetPlayerByUserId(userId)
	return player ~= nil and player:GetAttribute("VIP") == true
end

function ChatTags.Start()
	if TextChatService.ChatVersion ~= Enum.ChatVersion.TextChatService then
		return
	end
	TextChatService.OnIncomingMessage = function(message: TextChatMessage)
		local source = message.TextSource
		if not source or not isVip(source.UserId) then
			return nil
		end
		local properties = Instance.new("TextChatMessageProperties")
		properties.PrefixText = string.format('<font color="%s">[VIP]</font> %s', VIP_COLOR, message.PrefixText)
		return properties
	end
end

return ChatTags
