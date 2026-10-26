-- Elevator cab + spectator booth for one run. Clones ServerStorage.Assets.ElevatorCab when present,
-- otherwise builds a procedural cab with the same anchors (see docs/ARCHITECTURE.md "Map contract").

local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local Cab = {}
Cab.__index = Cab

local DOOR_SLIDE = 5.5

local function part(parent: Instance, props): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end

-- Procedural cab in local space: floor top at y=0, door in the -Z wall.
local function buildProcedural(): Model
	local model = Instance.new("Model")
	model.Name = "ElevatorCab"
	local wall = Color3.fromRGB(40, 36, 52)
	local trim = Color3.fromRGB(255, 200, 90)

	local floor = part(model, { Name = "Floor", Size = Vector3.new(26, 1, 22), CFrame = CFrame.new(0, -0.5, 0), Color = Color3.fromRGB(30, 28, 36), Material = Enum.Material.Marble })
	part(model, { Name = "Ceiling", Size = Vector3.new(26, 1, 22), CFrame = CFrame.new(0, 14.5, 0), Color = wall })
	part(model, { Name = "BackWall", Size = Vector3.new(26, 14, 1), CFrame = CFrame.new(0, 7, 10.5), Color = wall })
	part(model, { Name = "LeftWall", Size = Vector3.new(1, 14, 22), CFrame = CFrame.new(-12.5, 7, 0), Color = wall })
	part(model, { Name = "RightWall", Size = Vector3.new(1, 14, 22), CFrame = CFrame.new(12.5, 7, 0), Color = wall })
	-- front wall with a 10x10 opening
	part(model, { Name = "FrontLeft", Size = Vector3.new(8, 14, 1), CFrame = CFrame.new(-9, 7, -10.5), Color = wall })
	part(model, { Name = "FrontRight", Size = Vector3.new(8, 14, 1), CFrame = CFrame.new(9, 7, -10.5), Color = wall })
	part(model, { Name = "FrontTop", Size = Vector3.new(10, 4, 1), CFrame = CFrame.new(0, 12, -10.5), Color = wall })
	part(model, { Name = "Trim", Size = Vector3.new(25, 0.3, 0.3), CFrame = CFrame.new(0, 4, 9.9), Color = trim, Material = Enum.Material.Neon })

	part(model, { Name = "DoorL", Size = Vector3.new(5, 10, 0.6), CFrame = CFrame.new(-2.5, 5, -10.6), Color = trim, Material = Enum.Material.Metal })
	part(model, { Name = "DoorR", Size = Vector3.new(5, 10, 0.6), CFrame = CFrame.new(2.5, 5, -10.6), Color = trim, Material = Enum.Material.Metal })

	-- Display faces into the cab (+Z): its Front face (-Z local) must point +Z, so rotate 180 degrees.
	part(model, { Name = "Display", Size = Vector3.new(8, 2.5, 0.4), CFrame = CFrame.new(0, 12, -9.8) * CFrame.Angles(0, math.pi, 0), Color = Color3.fromRGB(10, 10, 14) })

	local lights = Instance.new("Folder")
	lights.Name = "Lights"
	lights.Parent = model
	local lamp = part(lights, { Name = "Lamp", Size = Vector3.new(14, 0.3, 2), CFrame = CFrame.new(0, 13.9, 0), Color = Color3.fromRGB(255, 240, 210), Material = Enum.Material.Neon })
	local light = Instance.new("PointLight")
	light.Range = 26
	light.Brightness = 1.5
	light.Color = Color3.fromRGB(255, 225, 180)
	light.Parent = lamp

	local spawns = Instance.new("Folder")
	spawns.Name = "Spawns"
	spawns.Parent = model
	for i = 0, 7 do
		local x = -7.5 + (i % 4) * 5
		local z = if i < 4 then 2 else 6.5
		part(spawns, { Name = "Spawn" .. (i + 1), Size = Vector3.new(2, 1, 2), CFrame = CFrame.new(x, 0.5, z), Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false })
	end

	model.PrimaryPart = floor
	model.WorldPivot = CFrame.new(0, 0, 0)
	return model
end

local function buildBooth(parent: Instance, origin: CFrame): { CFrame }
	local booth = Instance.new("Model")
	booth.Name = "SpectatorBooth"
	local glass = { Material = Enum.Material.Glass, Transparency = 0.7, Color = Color3.fromRGB(170, 220, 255) }
	local function glassPart(name, size, cf)
		local p = part(booth, { Name = name, Size = size, CFrame = origin * cf })
		p.Material = glass.Material
		p.Transparency = glass.Transparency
		p.Color = glass.Color
		p.CastShadow = false
		return p
	end
	glassPart("Floor", Vector3.new(44, 1, 44), CFrame.new(0, -0.5, 0))
	glassPart("WallN", Vector3.new(44, 12, 1), CFrame.new(0, 6, -22))
	glassPart("WallS", Vector3.new(44, 12, 1), CFrame.new(0, 6, 22))
	glassPart("WallE", Vector3.new(1, 12, 44), CFrame.new(22, 6, 0))
	glassPart("WallW", Vector3.new(1, 12, 44), CFrame.new(-22, 6, 0))
	local roof = glassPart("Roof", Vector3.new(44, 1, 44), CFrame.new(0, 12.5, 0))
	roof.Transparency = 1
	-- Faint tint under the spectators' feet. Glass, not neon: a 45x45 neon sheet right under the camera
	-- floods the whole spectator view with bloom.
	local rim = part(booth, { Name = "Rim", Size = Vector3.new(45, 0.4, 45), CFrame = origin * CFrame.new(0, 0.1, 0), Color = Color3.fromRGB(150, 60, 90), Material = Enum.Material.Glass, CanCollide = false, Transparency = 0.9 })
	rim.CastShadow = false
	-- Neon frame: floor and roof edges plus corner posts, so the booth reads as a lit gallery box. Dim rose:
	-- the frame sits right beside the spectator camera, so bright neon here glares.
	local frame = Color3.fromRGB(150, 52, 84)
	local function edge(size: Vector3, cf: CFrame)
		local e = part(booth, { Name = "Frame", Size = size, CFrame = origin * cf, Color = frame, Material = Enum.Material.Neon, CanCollide = false, CanQuery = false, CanTouch = false })
		e.CastShadow = false
	end
	for _, y in { 0, 12 } do
		edge(Vector3.new(44.6, 0.35, 0.35), CFrame.new(0, y, -22))
		edge(Vector3.new(44.6, 0.35, 0.35), CFrame.new(0, y, 22))
		edge(Vector3.new(0.35, 0.35, 44.6), CFrame.new(-22, y, 0))
		edge(Vector3.new(0.35, 0.35, 44.6), CFrame.new(22, y, 0))
	end
	for _, c in { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } } do
		edge(Vector3.new(0.35, 12, 0.35), CFrame.new(c[1] * 22, 6, c[2] * 22))
	end
	booth.Parent = parent

	local spawns = {}
	for i = 0, 7 do
		local angle = i / 8 * math.pi * 2
		table.insert(spawns, origin * CFrame.new(math.cos(angle) * 10, 3, math.sin(angle) * 10))
	end
	return spawns
end

function Cab.new(parent: Instance, pivot: CFrame, arenaOrigin: CFrame)
	local template = ServerStorage:FindFirstChild("Assets") and ServerStorage.Assets:FindFirstChild("ElevatorCab")
	local model = if template then template:Clone() else buildProcedural()
	model:PivotTo(pivot)
	model.Parent = parent

	local self = setmetatable({
		Model = model,
		Pivot = pivot,
		DoorsOpen = false,
		_doors = {},
	}, Cab)

	for _, name in { "DoorL", "DoorR" } do
		local door = model:FindFirstChild(name, true)
		if door then
			local sign = if name == "DoorL" then -1 else 1
			local closed = door:GetPivot()
			local open = closed + pivot.RightVector * DOOR_SLIDE * sign
			table.insert(self._doors, { Instance = door, Closed = closed, Open = open })
		end
	end

	-- Floor-number display
	local display = model:FindFirstChild("Display", true)
	if display and display:IsA("BasePart") then
		local gui = Instance.new("SurfaceGui")
		gui.Name = "FloorGui"
		gui.Face = Enum.NormalId.Front
		gui.LightInfluence = 0
		gui.PixelsPerStud = 40
		gui.Parent = display
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.TextScaled = true
		label.Font = Enum.Font.GothamBlack
		label.TextColor3 = Color3.fromRGB(255, 200, 90)
		label.Text = "B0"
		label.Parent = gui
		self._displayLabel = label
	end

	self.BoothSpawns = buildBooth(parent, arenaOrigin * Config.BoothOffset)
	return self
end

-- World CFrames for players standing inside the cab.
function Cab:GetSpawns(): { CFrame }
	local spawns = {}
	local folder = self.Model:FindFirstChild("Spawns", true)
	if folder then
		for _, p in folder:GetChildren() do
			if p:IsA("BasePart") then
				table.insert(spawns, p.CFrame + Vector3.new(0, 3, 0))
			end
		end
	end
	if #spawns == 0 then
		for i = 0, 7 do
			table.insert(spawns, self.Pivot * CFrame.new(-7.5 + (i % 4) * 5, 3, if i < 4 then 2 else 6.5))
		end
	end
	-- face the door
	for i, cf in spawns do
		spawns[i] = CFrame.lookAt(cf.Position, cf.Position + self.Pivot.LookVector)
	end
	return spawns
end

local function moveDoor(door: Instance, target: CFrame, duration: number)
	if door:IsA("BasePart") then
		TweenService:Create(door, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { CFrame = target }):Play()
	elseif door:IsA("Model") then
		-- tween a CFrameValue and pivot the model along
		local value = Instance.new("CFrameValue")
		value.Value = door:GetPivot()
		value.Changed:Connect(function(cf)
			door:PivotTo(cf)
		end)
		local tween = TweenService:Create(value, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { Value = target })
		tween.Completed:Once(function()
			value:Destroy()
		end)
		tween:Play()
	end
end

function Cab:SetDoors(open: boolean)
	if self.DoorsOpen == open then
		return
	end
	self.DoorsOpen = open
	for _, door in self._doors do
		moveDoor(door.Instance, if open then door.Open else door.Closed, 0.9)
	end
end

function Cab:SetDisplay(text: string, color: Color3?)
	if self._displayLabel then
		self._displayLabel.Text = text
		self._displayLabel.TextColor3 = color or Color3.fromRGB(255, 200, 90)
	end
end

return Cab
