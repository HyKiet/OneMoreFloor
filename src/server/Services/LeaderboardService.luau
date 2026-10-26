-- Global leaderboards (OrderedDataStore): deepest floor, today's Daily Elevator, lifetime cash.
-- Writes are batched per player; boards are refreshed and broadcast every minute.
-- Without DataStore access (e.g. Studio without API access) boards fall back to players in this server.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local DataService = require(script.Parent.DataService)

local LeaderboardService = {}

local REFRESH_INTERVAL = 60
local TOP = 10

local dirty: { [Player]: boolean } = {}
local cached = { Deepest = {}, Daily = {}, Cash = {} }
local names: { [number]: string } = {}
local remote = Net.Event("Leaderboards")
local online = true

local function storeFor(board: string): OrderedDataStore?
	local name = board
	if board == "Daily" then
		name = "Daily_" .. DataService.Today()
	end
	local ok, store = pcall(DataStoreService.GetOrderedDataStore, DataStoreService, "OMF_" .. name)
	return if ok then store else nil
end

local function valuesFor(player: Player): { [string]: number }?
	local data = DataService.Get(player)
	if not data then
		return nil
	end
	local today = DataService.Today()
	return {
		Deepest = data.DeepestFloor,
		Daily = if data.DailyBest.Day == today then data.DailyBest.Floor else 0,
		Cash = math.floor(data.LifetimeCash),
	}
end

function LeaderboardService.MarkDirty(player: Player)
	dirty[player] = true
end

local function flush(player: Player)
	local values = valuesFor(player)
	if not values or not online then
		return
	end
	for board, value in values do
		if value > 0 then
			local store = storeFor(board)
			if store then
				local ok, err = pcall(function()
					store:UpdateAsync(tostring(player.UserId), function(old)
						if old and old >= value then
							return nil
						end
						return value
					end)
				end)
				if not ok then
					warn("[Leaderboard] write failed:", err)
					online = false
				end
			end
		end
	end
end

local function nameOf(userId: number): string
	if names[userId] then
		return names[userId]
	end
	local player = Players:GetPlayerByUserId(userId)
	if player then
		names[userId] = player.DisplayName
		return player.DisplayName
	end
	local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
	names[userId] = if ok then name else "Player"
	return names[userId]
end

local function localBoards()
	local boards = { Deepest = {}, Daily = {}, Cash = {} }
	for _, player in Players:GetPlayers() do
		local values = valuesFor(player)
		if values then
			for board, value in values do
				if value > 0 then
					table.insert(boards[board], { Name = player.DisplayName, UserId = player.UserId, Value = value })
				end
			end
		end
	end
	for _, rows in boards do
		table.sort(rows, function(a, b)
			return a.Value > b.Value
		end)
		while #rows > TOP do
			table.remove(rows)
		end
	end
	return boards
end

local function refresh()
	if not online then
		cached = localBoards()
		return
	end
	local boards = { Deepest = {}, Daily = {}, Cash = {} }
	for board in boards do
		local store = storeFor(board)
		if store then
			local ok, pages = pcall(store.GetSortedAsync, store, false, TOP)
			if ok then
				for _, entry in pages:GetCurrentPage() do
					local userId = tonumber(entry.key)
					if userId then
						table.insert(boards[board], { Name = nameOf(userId), UserId = userId, Value = entry.value })
					end
				end
			else
				online = false
				cached = localBoards()
				return
			end
		else
			online = false
			cached = localBoards()
			return
		end
	end
	cached = boards
end

function LeaderboardService.Get()
	return cached
end

function LeaderboardService.Start()
	Players.PlayerRemoving:Connect(function(player)
		if dirty[player] then
			dirty[player] = nil
			task.spawn(flush, player)
		end
	end)
	DataService.Loaded:Connect(function(player)
		task.delay(2, function()
			if player.Parent == Players then
				remote:FireClient(player, cached)
			end
		end)
	end)

	task.spawn(function()
		while true do
			for player in dirty do
				dirty[player] = nil
				if player.Parent == Players then
					flush(player)
				end
			end
			refresh()
			remote:FireAllClients(cached)
			task.wait(if online then REFRESH_INTERVAL else 10)
		end
	end)
end

return LeaderboardService
