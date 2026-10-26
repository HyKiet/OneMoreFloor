-- Boarding zones in the lobby, run slots, and routing of run remotes to the player's run.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)

local DataService = require(script.Parent.DataService)
local LobbyService = require(script.Parent.LobbyService)
local RateLimit = require(script.Parent.Parent.Util.RateLimit)
local Run = require(script.Parent.Parent.Run.Run)

local ElevatorService = {}

local runsBySlot: { [number]: any } = {}
local runOf: { [Player]: any } = {}
local zones = {}

local ZONE_LABELS = {
	Normal = { Title = "ELEVATOR", Sub = "Step in to ride down", Color = Color3.fromRGB(70, 200, 255) },
	Daily = { Title = "DAILY ELEVATOR", Sub = "Same floors for everyone today", Color = Color3.fromRGB(255, 200, 60) },
}

function ElevatorService.GetRun(player: Player)
	local run = runOf[player]
	if run and run:HasPlayer(player) then
		return run
	end
	runOf[player] = nil
	return nil
end

local function freeSlot(): number?
	for slot = 1, Config.MaxSlots do
		if not runsBySlot[slot] then
			return slot
		end
	end
	return nil
end

local function startRun(mode: string, players: { Player })
	local slot = freeSlot()
	if not slot then
		return false
	end
	local seed = if mode == "Daily" then DataService.Today() else math.random(1, 2 ^ 30)
	local run
	run = Run.new({
		Slot = slot,
		Mode = mode,
		Seed = seed,
		Players = players,
		OnEnded = function()
			runsBySlot[slot] = nil
			for player, r in runOf do
				if r == run then
					runOf[player] = nil
				end
			end
		end,
	})
	runsBySlot[slot] = run
	for _, player in players do
		runOf[player] = run
	end
	run:Start()
	return true
end

local function makeBillboard(zone: BasePart, mode: string)
	local info = ZONE_LABELS[mode]
	local gui = Instance.new("BillboardGui")
	gui.Name = "BoardingGui"
	gui.Size = UDim2.fromScale(13, 4.2) -- studs, so the two elevators' labels never overlap on screen
	gui.StudsOffsetWorldSpace = Vector3.new(0, zone.Size.Y / 2 + 2.5, 0)
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.MaxDistance = 90

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0.45, 0)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextColor3 = info.Color
	title.TextStrokeTransparency = 0.4
	title.Text = info.Title
	title.Parent = gui

	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.Position = UDim2.fromScale(0, 0.5)
	status.Size = UDim2.new(1, 0, 0.4, 0)
	status.BackgroundTransparency = 1
	status.Font = Enum.Font.GothamBold
	status.TextScaled = true
	status.TextColor3 = Color3.new(1, 1, 1)
	status.TextStrokeTransparency = 0.4
	status.Text = info.Sub
	status.Parent = gui

	gui.Parent = zone
	return status
end

local function playersInZone(zone: BasePart): { Player }
	local inside = {}
	local half = zone.Size / 2
	for _, player in Players:GetPlayers() do
		if player:GetAttribute("InRun") or not DataService.Get(player) then
			continue
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and humanoid and humanoid.Health > 0 then
			local p = zone.CFrame:PointToObjectSpace(root.Position)
			if math.abs(p.X) <= half.X and math.abs(p.Y) <= half.Y and math.abs(p.Z) <= half.Z then
				table.insert(inside, player)
			end
		end
	end
	return inside
end

local function tickZone(zone)
	local inside = playersInZone(zone.Part)
	local now = os.clock()
	local info = ZONE_LABELS[zone.Mode]

	if #inside == 0 then
		zone.DepartAt = nil
		zone.Status.Text = info.Sub
		return
	end
	if not zone.DepartAt then
		zone.DepartAt = now + Config.BoardingCountdown
	end
	if #inside >= Config.MaxPlayersPerRun then
		zone.DepartAt = math.min(zone.DepartAt, now + Config.BoardingFullCountdown)
	end

	local remaining = math.max(0, math.ceil(zone.DepartAt - now))
	zone.Status.Text = `{math.min(#inside, Config.MaxPlayersPerRun)}/{Config.MaxPlayersPerRun} aboard · leaving in {remaining}`

	if now >= zone.DepartAt then
		local riders = {}
		for i = 1, math.min(#inside, Config.MaxPlayersPerRun) do
			riders[i] = inside[i]
		end
		if startRun(zone.Mode, riders) then
			zone.DepartAt = nil
		else
			zone.DepartAt = now + 2
			zone.Status.Text = "All elevators busy — hold on!"
		end
	end
end

local function routed(handler)
	return function(player: Player, ...)
		if not RateLimit.Check(player, "run", 0.05) then
			return
		end
		local run = ElevatorService.GetRun(player)
		if run then
			handler(run, player, ...)
		end
	end
end

function ElevatorService.Start()
	local lobby = LobbyService.GetLobby()
	local elevators = lobby:FindFirstChild("Elevators")
	for _, mode in { "Normal", "Daily" } do
		local model = elevators and elevators:FindFirstChild(mode)
		local part = model and model:FindFirstChild("BoardingZone", true)
		if part and part:IsA("BasePart") then
			table.insert(zones, { Mode = mode, Part = part, Status = makeBillboard(part, mode), DepartAt = nil })
		else
			warn("[Elevator] missing boarding zone for", mode)
		end
	end

	task.spawn(function()
		while true do
			for _, zone in zones do
				local ok, err = pcall(tickZone, zone)
				if not ok then
					warn("[Elevator] zone tick failed:", err)
				end
			end
			task.wait(0.25)
		end
	end)

	Net.Event("Choose").OnServerEvent:Connect(routed(function(run, player, choice)
		if typeof(choice) == "string" then
			run:Choose(player, choice)
		end
	end))
	Net.Event("Vote").OnServerEvent:Connect(routed(function(run, player, curseId)
		if typeof(curseId) == "string" then
			run:Vote(player, curseId)
		end
	end))
	Net.Event("BuyRunItem").OnServerEvent:Connect(routed(function(run, player, itemId)
		if typeof(itemId) == "string" then
			run:BuyRunItem(player, itemId)
		end
	end))
	Net.Event("ReturnToLobby").OnServerEvent:Connect(routed(function(run, player)
		run:ReturnToLobby(player)
	end))

	game:BindToClose(function()
		for _, run in runsBySlot do
			pcall(run.BankEveryone, run)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		local run = runOf[player]
		runOf[player] = nil
		if run then
			run:RemovePlayer(player)
		end
	end)
end

return ElevatorService
