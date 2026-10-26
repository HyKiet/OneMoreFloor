-- Lobby glue: spawn point, station prompts, and a fallback lobby when the map is missing.

local Players = game:GetService("Players")

local LobbyService = {}

local PANEL_TEXT = {
	Upgrades = "Upgrades",
	Relics = "Relic Vault",
	Daily = "Daily Reward",
	Shop = "Shop",
}

local function part(props): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		if k ~= "Parent" then
			(p :: any)[k] = v
		end
	end
	p.Parent = props.Parent
	return p
end

local function folder(name: string, parent: Instance): Instance
	local existing = parent:FindFirstChild(name)
	if existing then
		return existing
	end
	local f = Instance.new("Model")
	f.Name = name
	f.Parent = parent
	return f
end

-- Builds the bare minimum lobby so the game runs before (or without) the real map.
local function ensureLobby(): Model
	local lobby = workspace:FindFirstChild("Lobby")
	if not lobby then
		lobby = Instance.new("Model")
		lobby.Name = "Lobby"
		lobby.Parent = workspace
		part({ Name = "FallbackFloor", Size = Vector3.new(140, 2, 140), Position = Vector3.new(0, -1, 0), Color = Color3.fromRGB(30, 30, 40), Material = Enum.Material.Marble, Parent = lobby })
		warn("[Lobby] Workspace.Lobby missing — using fallback lobby")
	end

	if not lobby:FindFirstChild("Spawn") then
		local spawn = Instance.new("SpawnLocation")
		spawn.Name = "Spawn"
		spawn.Anchored = true
		spawn.Neutral = true
		spawn.Duration = 0
		spawn.Size = Vector3.new(12, 1, 12)
		spawn.Position = Vector3.new(0, 0.5, 30)
		spawn.Transparency = 1
		spawn.CanCollide = false
		spawn.Parent = lobby
	end

	local elevators = folder("Elevators", lobby)
	for i, mode in { "Normal", "Daily" } do
		local model = folder(mode, elevators)
		if not model:FindFirstChild("BoardingZone") then
			part({
				Name = "BoardingZone",
				Size = Vector3.new(18, 10, 12),
				Position = Vector3.new(if i == 1 then -20 else 20, 5, -30),
				Transparency = 1,
				CanCollide = false,
				CanQuery = false,
				CanTouch = false,
				Parent = model,
			})
			part({
				Name = "FallbackMarker",
				Size = Vector3.new(18, 0.2, 12),
				Position = Vector3.new(if i == 1 then -20 else 20, 0.1, -30),
				Color = if i == 1 then Color3.fromRGB(70, 200, 255) else Color3.fromRGB(255, 200, 60),
				Material = Enum.Material.Neon,
				CanCollide = false,
				Parent = model,
			})
		end
	end

	local stations = folder("Stations", lobby)
	for i, name in { "Upgrades", "Relics", "Daily", "Shop" } do
		local station = folder(name, stations)
		if not station:FindFirstChild("PromptPart", true) then
			part({
				Name = "PromptPart",
				Size = Vector3.new(4, 6, 4),
				Position = Vector3.new(-30 + (i - 1) * 20, 3, 40),
				Color = Color3.fromRGB(60, 60, 80),
				Material = Enum.Material.Neon,
				Parent = station,
			})
		end
		if station:GetAttribute("Panel") == nil then
			station:SetAttribute("Panel", name)
		end
	end

	return lobby
end

function LobbyService.GetLobby(): Model
	return workspace:FindFirstChild("Lobby") or ensureLobby()
end

-- A CFrame on the lobby spawn, jittered so players don't stack.
function LobbyService.GetSpawnCFrame(): CFrame
	local lobby = LobbyService.GetLobby()
	local spawn = lobby:FindFirstChild("Spawn") :: BasePart?
	local base = if spawn then spawn.CFrame else CFrame.new(0, 1, 30)
	local offset = Vector3.new(math.random(-4, 4), 4, math.random(-4, 4))
	return base + offset
end

function LobbyService.SendToLobby(player: Player)
	local character = player.Character
	if character and character.Parent then
		character:PivotTo(LobbyService.GetSpawnCFrame())
	end
end

local function setupPrompts(lobby: Model)
	local stations = lobby:FindFirstChild("Stations")
	if not stations then
		return
	end
	for _, station in stations:GetChildren() do
		local panel = station:GetAttribute("Panel") or station.Name
		local promptPart = station:FindFirstChild("PromptPart", true)
		if promptPart and promptPart:IsA("BasePart") and not promptPart:FindFirstChildOfClass("ProximityPrompt") then
			local prompt = Instance.new("ProximityPrompt")
			prompt.ActionText = "Open"
			prompt.ObjectText = PANEL_TEXT[panel] or panel
			prompt.HoldDuration = 0
			prompt.MaxActivationDistance = 12
			prompt.RequiresLineOfSight = false
			prompt.Parent = promptPart
			-- the client opens the panel from this attribute (ProximityPromptService.PromptTriggered)
			promptPart:SetAttribute("Panel", panel)
		end
	end
end

function LobbyService.Start()
	Players.RespawnTime = 3
	local lobby = ensureLobby()
	setupPrompts(lobby)
	local spawn = lobby:FindFirstChild("Spawn")
	if spawn and spawn:IsA("SpawnLocation") then
		spawn.Neutral = true
		spawn.Duration = 0
	end
end

return LobbyService
