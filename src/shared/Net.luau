-- Remote registry. The server creates every remote at startup; clients wait for them.
--
-- Server -> client events
--   RunUpdate(state)          full run snapshot for this player (see docs/ARCHITECTURE.md), or nil when not in a run
--   Data(snapshot)            profile snapshot (cash, upgrades, relics...) whenever it changes
--   Toast(text, style)        short notification; style = "info" | "good" | "bad" | "rare"
--   Eliminated(info)          { Reason, Lost, Kept, Dropped, Saved = "Shield" | "Phoenix" | nil }
--   CashedOut(info)           { Amount, Floor, Bonus }
--   RelicFound(info)          { RelicId, Level, IsNew }
--   VoteOptions(info)         { Options = { curseId... }, EndsAt } for spectators; nil options closes the vote
--   Effect(name, args)        client-only effects: "Shake", "Flash", "Descend", "CoinPop", "Curses", "Confetti"
--   OpenPanel(name)           ask the client to open a lobby panel ("Upgrades" | "Relics" | "Daily" | "Shop")
--   Leaderboards(boards)      { Deepest = {...}, Daily = {...}, Cash = {...} } rows of { Name, UserId, Value }
--
-- Client -> server events
--   Choose(choice)            "Deeper" | "Leave" during the decision phase
--   Vote(curseId)             spectators vote for the next curse
--   BuyUpgrade(upgradeId)
--   BuyRunItem(itemId)        during the run shop
--   Equip(relicId, slot)      slot is 1-based
--   Unequip(slot)
--   ClaimDaily()
--   ReturnToLobby()           spectators can leave early
--   PromptProduct(key)        key from Config.Products / Config.Passes ("ExtraLife" = server picks the tier)
--   PromptPremium()           open the Roblox Premium upsell
--   PolishRelic(relicId)      spend cash to level a relic up
--   BuyCapsule()              spend cash on a random relic (result arrives as RelicFound)
--
-- Client -> server functions
--   RedeemCode(code) -> (ok, message)

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = {}

Net.Events = {
	"RunUpdate",
	"Data",
	"Toast",
	"Eliminated",
	"CashedOut",
	"RelicFound",
	"VoteOptions",
	"Effect",
	"OpenPanel",
	"Leaderboards",
	"Choose",
	"Vote",
	"BuyUpgrade",
	"BuyRunItem",
	"Equip",
	"Unequip",
	"ClaimDaily",
	"ReturnToLobby",
	"PromptProduct",
	"PromptPremium",
	"PolishRelic",
	"BuyCapsule",
}

Net.Functions = {
	"RedeemCode",
}

local FOLDER_NAME = "Remotes"

local function getFolder(): Folder
	if RunService:IsServer() then
		local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = FOLDER_NAME
			for _, name in Net.Events do
				local remote = Instance.new("RemoteEvent")
				remote.Name = name
				remote.Parent = folder
			end
			for _, name in Net.Functions do
				local remote = Instance.new("RemoteFunction")
				remote.Name = name
				remote.Parent = folder
			end
			folder.Parent = ReplicatedStorage
		end
		return folder
	end
	return ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
end

function Net.Event(name: string): RemoteEvent
	return getFolder():WaitForChild(name) :: RemoteEvent
end

function Net.Function(name: string): RemoteFunction
	return getFolder():WaitForChild(name) :: RemoteFunction
end

return Net
