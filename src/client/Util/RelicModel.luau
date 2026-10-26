-- Relic models for ViewportFrames: authored Blender meshes (ReplicatedStorage.RelicModels) with a
-- primitive fallback (Ball/Block/Cylinder/Wedge/Diamond/Coin).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local RelicModel = {}

local function newPart(className: string, props: { [string]: any }): BasePart
	local part = Instance.new(className) :: BasePart
	part.Anchored = true
	part.CanCollide = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
	for key, value in props do
		(part :: any)[key] = value
	end
	return part
end

-- Returns a Model centred on the origin, roughly 3 studs across.
function RelicModel.build(shape: string, color: Color3): Model
	local model = Instance.new("Model")
	model.Name = "Relic"
	local main: BasePart
	if shape == "Ball" then
		main = newPart("Part", { Shape = Enum.PartType.Ball, Size = Vector3.new(3, 3, 3), Color = color })
		local ring = newPart("Part", {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.25, 3.8, 3.8),
			Color = color:Lerp(Color3.new(1, 1, 1), 0.5),
			Material = Enum.Material.Neon,
			Transparency = 0.3,
			CFrame = CFrame.Angles(0, 0, math.rad(90)) * CFrame.Angles(math.rad(20), 0, 0),
		})
		ring.Parent = model
	elseif shape == "Cylinder" then
		main = newPart("Part", {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(3, 2.2, 2.2),
			Color = color,
			CFrame = CFrame.Angles(0, 0, math.rad(90)),
		})
		for _, y in { -1.3, 1.3 } do
			newPart("Part", {
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.35, 2.6, 2.6),
				Color = color:Lerp(Color3.new(1, 1, 1), 0.45),
				Material = Enum.Material.Neon,
				CFrame = CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.rad(90)),
			}).Parent = model
		end
	elseif shape == "Wedge" then
		main = newPart("WedgePart", { Size = Vector3.new(2.4, 2.8, 2.8), Color = color, CFrame = CFrame.Angles(0, math.rad(30), 0) })
	elseif shape == "Diamond" then
		main = newPart("Part", {
			Size = Vector3.new(2.2, 2.2, 2.2),
			Color = color,
			Material = Enum.Material.Glass,
			Transparency = 0.05,
			CFrame = CFrame.Angles(math.rad(45), 0, math.rad(35.26)),
		})
		newPart("Part", {
			Size = Vector3.new(1.2, 1.2, 1.2),
			Color = color:Lerp(Color3.new(1, 1, 1), 0.5),
			Material = Enum.Material.Neon,
			CFrame = CFrame.Angles(math.rad(45), 0, math.rad(35.26)),
		}).Parent = model
	elseif shape == "Coin" then
		main = newPart("Part", {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.5, 3.2, 3.2),
			Color = color,
			Material = Enum.Material.Metal,
			CFrame = CFrame.Angles(0, math.rad(90), 0),
		})
		newPart("Part", {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.6, 2.2, 2.2),
			Color = color:Lerp(Color3.new(1, 1, 1), 0.35),
			Material = Enum.Material.Neon,
			CFrame = CFrame.Angles(0, math.rad(90), 0),
		}).Parent = model
	else -- Block
		main = newPart("Part", {
			Size = Vector3.new(2.4, 2.4, 2.4),
			Color = color,
			CFrame = CFrame.Angles(math.rad(20), math.rad(35), 0),
		})
		for _, axis in { Vector3.new(2.6, 0.25, 0.25), Vector3.new(0.25, 2.6, 0.25), Vector3.new(0.25, 0.25, 2.6) } do
			newPart("Part", {
				Size = axis,
				Color = color:Lerp(Color3.new(1, 1, 1), 0.5),
				Material = Enum.Material.Neon,
				CFrame = CFrame.Angles(math.rad(20), math.rad(35), 0),
			}).Parent = model
		end
	end
	main.Name = "Main"
	main.Parent = model
	model.PrimaryPart = main
	model.WorldPivot = CFrame.new()
	return model
end

-- Clears a ViewportFrame, parents `model` into it and frames it with the standard relic camera.
local function present(viewport: ViewportFrame, model: Model, silhouette: boolean?): Model
	for _, child in viewport:GetChildren() do
		if child:IsA("Model") or child:IsA("Camera") or child:IsA("WorldModel") then
			child:Destroy()
		end
	end
	model.Parent = viewport
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 1.8, 8), Vector3.zero)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	viewport.Ambient = Color3.fromRGB(170, 170, 190)
	viewport.LightColor = Color3.fromRGB(255, 255, 255)
	viewport.LightDirection = Vector3.new(-1, -1.5, -1)
	viewport.ImageColor3 = if silhouette then Color3.new(0, 0, 0) else Color3.new(1, 1, 1)
	viewport.BackgroundTransparency = 1
	return model
end

-- Fills a ViewportFrame with a primitive relic model and a camera. Returns the model.
-- silhouette = true renders the model black (unowned codex entries).
function RelicModel.mount(viewport: ViewportFrame, shape: string, color: Color3, silhouette: boolean?): Model
	return present(viewport, RelicModel.build(shape, color), silhouette)
end

-- Returns a fresh copy of a relic's model, centred on the origin and ~3 studs across.
-- Uses the authored mesh model (ReplicatedStorage.RelicModels.<Id>, built in Blender) when present,
-- otherwise the primitive fallback.
function RelicModel.clone(relic: { Id: string, Shape: string, Color: Color3 }): Model
	local folder = ReplicatedStorage:FindFirstChild("RelicModels")
	local authored = folder and folder:FindFirstChild(relic.Id)
	if authored and authored:IsA("Model") then
		local model = authored:Clone()
		model.Name = "Relic"
		model:PivotTo(CFrame.new())
		return model
	end
	return RelicModel.build(relic.Shape, relic.Color)
end

-- Mounts a relic definition (from Shared.Relics). UI code should call this rather than `mount`.
function RelicModel.mountRelic(viewport: ViewportFrame, relic: { Id: string, Shape: string, Color: Color3 }, silhouette: boolean?): Model
	return present(viewport, RelicModel.clone(relic), silhouette)
end

-- Spins a mounted model until the viewport is destroyed. Returns a stop function.
function RelicModel.spin(viewport: ViewportFrame, model: Model, speed: number?): () -> ()
	local angle = 0
	local base = model:GetPivot()
	local connection
	connection = RunService.RenderStepped:Connect(function(dt)
		if not viewport.Parent or not model.Parent then
			connection:Disconnect()
			return
		end
		angle += dt * (speed or 1.6)
		model:PivotTo(CFrame.Angles(0, angle, 0) * base * CFrame.new(0, math.sin(angle * 1.5) * 0.15, 0))
	end)
	return function()
		connection:Disconnect()
	end
end

return RelicModel
