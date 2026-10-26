-- Client-side cosmetic effects for challenge arenas. Nothing here affects gameplay.
--
-- One-shot effects arrive through the Effect remote as ("Fx", { Kind = ..., ... }):
--   Telegraph { CFrame, Size, EndsAt, Color, Shape?, Sweep? }  outline + fill that grows until impact
--   Impact    { Position, Color, Radius, Debris }              shockwave ring, chunks, sparks, light flash
--   Burst     { Position, Color, Count? }                     spark burst
--   Arcs      { CFrame, Size, Color, Count? }                  lightning bolts across an area
--   Shot      { From, To, Color }                              beam zap from one point to another
--   Chunks    { Positions, Color, Size? }                      falling rubble at a list of points
--   Wave      { Position, Color, Speed, From, To, StartTime }  smooth expanding shockwave ring
--
-- Persistent animations are driven by CollectionService tags on server parts (attributes in brackets):
--   OMF_Spin  [SpinSpeed, SpinAxis, SpinPivot]           rotate about a pivot
--   OMF_Pulse [PulseMin, PulseMax, PulseSpeed, PulsePhase] breathe transparency
--   OMF_Slide [SlideDir, SlideSpeed, SlideSpan, SlideBase, SlidePhase] scroll along a direction, fading at the ends
--   OMF_Orbit [OrbitCenter, OrbitOffset, Angle0, Omega0, Ramp, Dir, StartTime, StopTime, OrbitAxis?]
--             smooth replay of a server-driven rotation (server uses the same formula; axis defaults to +Y)
--   OMF_Swing [SwingPivot, SwingOffset, SwingAmp, SwingOmega, SwingPhase, SwingAxis, StartTime, StopTime]
--             pendulum: angle = Amp * sin(Omega * t + Phase) about SwingAxis (server uses the same formula)

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Net = require(ReplicatedStorage.Shared.Net)

local ArenaFx = {}

local TEXTURES = {
	Sparks = "rbxasset://textures/particles/fire_sparks_main.dds",
	Sparkle = "rbxasset://textures/particles/sparkles_main.dds",
	Glow = "rbxasset://textures/particles/explosion01_core_main.dds",
}

local CULL_DISTANCE = 450 -- skip work for arenas this far from the camera
local MAX_DEBRIS = 70

local folder: Folder
local activeDebris = 0

-- Helpers ------------------------------------------------------------------------

local function nearCamera(position: Vector3, distance: number?): boolean
	local camera = workspace.CurrentCamera
	if not camera then
		return false
	end
	return (camera.CFrame.Position - position).Magnitude <= (distance or CULL_DISTANCE)
end

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function localPart(props: { [string]: any }): BasePart
	local part = Instance.new(props.ClassName or "Part") :: BasePart
	props.ClassName = nil
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(part :: any)[key] = value
	end
	part.Parent = folder
	return part
end

local function tween(instance: Instance, time: number, goals: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): Tween
	local t = TweenService:Create(instance, TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), goals)
	t:Play()
	return t
end

local function expire(instance: Instance, seconds: number)
	task.delay(seconds, function()
		instance:Destroy()
	end)
end

local function anchorAt(position: Vector3): BasePart
	return localPart({ Name = "FxAnchor", Size = Vector3.one * 0.2, Transparency = 1, CFrame = CFrame.new(position) })
end

-- A flat ring lying on the XZ plane (hollow cylinder adornment).
local function ring(anchor: BasePart, color: Color3, radius: number, thickness: number, transparency: number): CylinderHandleAdornment
	local adorn = Instance.new("CylinderHandleAdornment")
	adorn.Adornee = anchor
	adorn.CFrame = CFrame.Angles(math.rad(90), 0, 0)
	adorn.Height = 0.12
	adorn.Radius = radius
	adorn.InnerRadius = math.max(radius - thickness, 0)
	adorn.Color3 = color
	adorn.Transparency = transparency
	adorn.ZIndex = 1
	adorn.Parent = anchor
	return adorn
end

-- One-shot effects ----------------------------------------------------------------

local function telegraph(args)
	local cf: CFrame, size: Vector3, color: Color3 = args.CFrame, args.Size, args.Color
	if typeof(cf) ~= "CFrame" or typeof(size) ~= "Vector3" or not nearCamera(cf.Position) then
		return
	end
	color = if typeof(color) == "Color3" then color else Color3.fromRGB(255, 60, 60)
	local duration = math.max((tonumber(args.EndsAt) or 0) - serverNow(), 0.08)
	local disc = args.Shape == "Disc"
	local flat = size.Y <= 1.2

	if not flat then
		-- Volumetric warning: a breathing box with a crisp outline
		local box = localPart({ Name = "Telegraph", Size = size, CFrame = cf, Color = color, Transparency = 0.8 })
		local outline = Instance.new("SelectionBox")
		outline.Adornee = box
		outline.Color3 = color
		outline.LineThickness = 0.08
		outline.SurfaceTransparency = 1
		outline.Parent = box
		tween(box, 0.16, { Transparency = 0.55 }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		TweenService:Create(box, TweenInfo.new(0.16, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.9 }):Play()
		expire(box, duration)
		return
	end

	local plateCF = cf
	local plate: BasePart
	if disc then
		local d = math.max(size.X, size.Z)
		plate = localPart({ Name = "Telegraph", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.06, d, d), CFrame = cf * CFrame.Angles(0, 0, math.rad(90)), Color = color, Transparency = 0.85 })
		local edge = anchorAt(cf.Position)
		ring(edge, color, d / 2, 0.35, 0.1)
		expire(edge, duration)
	else
		plate = localPart({ Name = "Telegraph", Size = Vector3.new(size.X, 0.06, size.Z), CFrame = plateCF, Color = color, Transparency = 0.85 })
		local outline = Instance.new("SelectionBox")
		outline.Adornee = plate
		outline.Color3 = color
		outline.LineThickness = 0.12
		outline.SurfaceTransparency = 1
		outline.Parent = plate
	end
	TweenService:Create(plate, TweenInfo.new(0.18, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.7 }):Play()

	-- The fill grows until the hazard lands
	local fill: BasePart
	if disc then
		local d = math.max(size.X, size.Z)
		fill = localPart({ Name = "Fill", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, 0.2, 0.2), CFrame = plate.CFrame * CFrame.new(0.03, 0, 0), Color = color, Transparency = 0.45 })
		tween(fill, duration, { Size = Vector3.new(0.1, d, d) }, Enum.EasingStyle.Linear)
	else
		local sweep = args.Sweep
		local startSize, startCF = Vector3.new(0.2, 0.1, 0.2), plateCF * CFrame.new(0, 0.03, 0)
		local endCF = startCF
		if typeof(sweep) == "Vector3" and sweep.Magnitude > 0 then
			local dir = plateCF:VectorToObjectSpace(sweep)
			if math.abs(dir.X) >= math.abs(dir.Z) then
				local s = math.sign(dir.X)
				startSize = Vector3.new(0.2, 0.1, size.Z)
				startCF = plateCF * CFrame.new(-s * size.X / 2, 0.03, 0)
			else
				local s = math.sign(dir.Z)
				startSize = Vector3.new(size.X, 0.1, 0.2)
				startCF = plateCF * CFrame.new(0, 0.03, -s * size.Z / 2)
			end
		end
		fill = localPart({ Name = "Fill", Size = startSize, CFrame = startCF, Color = color, Transparency = 0.45 })
		tween(fill, duration, { Size = Vector3.new(size.X, 0.1, size.Z), CFrame = endCF }, Enum.EasingStyle.Linear)
	end

	task.delay(duration, function()
		-- final flash as the hazard arrives
		fill.Color = color:Lerp(Color3.new(1, 1, 1), 0.25)
		fill.Transparency = 0.15
		tween(fill, 0.18, { Transparency = 1 })
		plate:Destroy()
		expire(fill, 0.2)
	end)
end

local function spawnDebris(position: Vector3, color: Color3, count: number, power: number, sizeScale: number?)
	for _ = 1, count do
		if activeDebris >= MAX_DEBRIS then
			return
		end
		activeDebris += 1
		local s = (0.45 + math.random() * 0.8) * (sizeScale or 1)
		local chunk = localPart({
			Name = "Chunk",
			Size = Vector3.new(s, s, s),
			CFrame = CFrame.new(position + Vector3.new(math.random() - 0.5, 0.5, math.random() - 0.5)) * CFrame.Angles(math.random() * 6, math.random() * 6, 0),
			Color = color:Lerp(Color3.new(0, 0, 0), math.random() * 0.45),
			Material = if math.random() < 0.5 then Enum.Material.Neon else Enum.Material.SmoothPlastic,
			Anchored = false,
			CanCollide = true,
		})
		chunk.CollisionGroup = "Default"
		local angle = math.random() * math.pi * 2
		local out = (10 + math.random() * 18) * power
		chunk.AssemblyLinearVelocity = Vector3.new(math.cos(angle) * out, (18 + math.random() * 20) * power, math.sin(angle) * out)
		chunk.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 20
		task.delay(0.8 + math.random() * 0.3, function()
			tween(chunk, 0.35, { Transparency = 1, Size = chunk.Size * 0.3 })
		end)
		task.delay(1.25, function()
			activeDebris -= 1
			chunk:Destroy()
		end)
	end
end

local function sparks(position: Vector3, color: Color3, count: number, speed: number?)
	local anchor = anchorAt(position)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = TEXTURES.Sparks
	emitter.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.35), color)
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) })
	emitter.Speed = NumberRange.new((speed or 1) * 18, (speed or 1) * 42)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Lifetime = NumberRange.new(0.25, 0.55)
	emitter.Drag = 3
	emitter.Acceleration = Vector3.new(0, -35, 0)
	emitter.Rate = 0
	emitter.Parent = anchor
	emitter:Emit(count)
	expire(anchor, 1)
end

local function impact(args)
	local position: Vector3 = args.Position
	if typeof(position) ~= "Vector3" or not nearCamera(position) then
		return
	end
	local color: Color3 = if typeof(args.Color) == "Color3" then args.Color else Color3.fromRGB(255, 80, 80)
	local radius = math.clamp(tonumber(args.Radius) or 12, 2, 60)

	local anchor = anchorAt(position + Vector3.new(0, 0.15, 0))
	-- Shockwave: a bright thin ring that races outward plus a soft inner wash
	local outer = ring(anchor, color:Lerp(Color3.new(1, 1, 1), 0.4), 1, 0.8, 0)
	local wash = ring(anchor, color, 1, 1, 0.55)
	local time = 0.35 + radius / 90
	tween(outer, time, { Radius = radius, InnerRadius = radius - 0.9, Transparency = 1 })
	tween(wash, time * 0.8, { Radius = radius * 0.7, Transparency = 1 })

	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = math.min(radius * 1.8, 60)
	light.Brightness = 5
	light.Shadows = false
	light.Parent = anchor
	tween(light, 0.4, { Brightness = 0 })
	expire(anchor, time + 0.1)

	sparks(position + Vector3.new(0, 0.5, 0), color, math.clamp(math.floor(radius * 1.6), 10, 40), 0.6 + radius / 30)
	local debris = math.clamp(tonumber(args.Debris) or 6, 0, 16)
	if debris > 0 then
		spawnDebris(position + Vector3.new(0, 0.4, 0), color, debris, 0.6 + radius / 40)
	end
end

local function burst(args)
	if typeof(args.Position) == "Vector3" and nearCamera(args.Position) then
		sparks(args.Position, if typeof(args.Color) == "Color3" then args.Color else Color3.new(1, 1, 1), math.clamp(tonumber(args.Count) or 24, 4, 60))
	end
end

-- Jagged lightning bolts between random points inside an area.
local function arcs(args)
	local cf: CFrame, size: Vector3 = args.CFrame, args.Size
	if typeof(cf) ~= "CFrame" or typeof(size) ~= "Vector3" or not nearCamera(cf.Position) then
		return
	end
	local color: Color3 = if typeof(args.Color) == "Color3" then args.Color else Color3.fromRGB(150, 220, 255)
	local count = math.clamp(tonumber(args.Count) or 6, 1, 14)
	for _ = 1, count do
		local from = Vector3.new((math.random() - 0.5) * size.X, 0.3, (math.random() - 0.5) * size.Z)
		local angle = math.random() * math.pi * 2
		local length = 6 + math.random() * 14
		local to = from + Vector3.new(math.cos(angle) * length, 0, math.sin(angle) * length)
		local points = { from }
		for k = 1, 3 do
			local p = from:Lerp(to, k / 4)
			table.insert(points, p + Vector3.new((math.random() - 0.5) * 3, math.random() * 1.2, (math.random() - 0.5) * 3))
		end
		table.insert(points, to)
		local life = 0.12 + math.random() * 0.18
		for k = 1, #points - 1 do
			local a, b = cf * points[k], cf * points[k + 1]
			local seg = localPart({
				Name = "Arc",
				Size = Vector3.new(0.22, 0.22, (b - a).Magnitude),
				CFrame = CFrame.lookAt((a + b) / 2, b),
				Color = color:Lerp(Color3.new(1, 1, 1), 0.5),
			})
			expire(seg, life)
		end
	end
	sparks(cf.Position, color, 8)
end

local function shot(args)
	local from: Vector3, to: Vector3 = args.From, args.To
	if typeof(from) ~= "Vector3" or typeof(to) ~= "Vector3" or not nearCamera(to) then
		return
	end
	local color: Color3 = if typeof(args.Color) == "Color3" then args.Color else Color3.fromRGB(255, 60, 60)
	local beam = localPart({ Name = "Shot", Size = Vector3.new(0.9, 0.9, (to - from).Magnitude), CFrame = CFrame.lookAt((from + to) / 2, to), Color = color })
	tween(beam, 0.3, { Size = Vector3.new(0.05, 0.05, beam.Size.Z), Transparency = 1 })
	expire(beam, 0.32)
	impact({ Position = to, Color = color, Radius = 6, Debris = 3 })
end

local function chunks(args)
	local list = args.Positions
	if typeof(list) ~= "table" or #list == 0 or typeof(list[1]) ~= "Vector3" or not nearCamera(list[1]) then
		return
	end
	local color: Color3 = if typeof(args.Color) == "Color3" then args.Color else Color3.fromRGB(120, 120, 140)
	for _, position in list do
		if typeof(position) == "Vector3" then
			spawnDebris(position, color, 1, 0.35, tonumber(args.Size) or 1.4)
		end
	end
end

-- A hollow ring that expands at a constant speed (mirrors a server shockwave hazard, but smooth).
local function wave(args)
	local position: Vector3 = args.Position
	if typeof(position) ~= "Vector3" or not nearCamera(position) then
		return
	end
	local color: Color3 = if typeof(args.Color) == "Color3" then args.Color else Color3.fromRGB(255, 60, 60)
	local speed = tonumber(args.Speed) or 20
	local r0 = tonumber(args.From) or 4
	local r1 = tonumber(args.To) or 60
	local startedAt = tonumber(args.StartTime) or serverNow()
	local anchor = anchorAt(position + Vector3.new(0, 0.7, 0))
	local band = ring(anchor, color, r0, 0.8, 0.05)
	band.Height = 1.3
	local glow = ring(anchor, color:Lerp(Color3.new(1, 1, 1), 0.3), r0, 2.4, 0.6)
	glow.Height = 0.2
	glow.CFrame = CFrame.new(0, -0.6, 0) * CFrame.Angles(math.rad(90), 0, 0)
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local r = r0 + (serverNow() - startedAt) * speed
		if r >= r1 or not anchor.Parent then
			connection:Disconnect()
			anchor:Destroy()
			return
		end
		band.Radius = r + 0.4
		band.InnerRadius = math.max(r - 0.4, 0)
		glow.Radius = r + 1.2
		glow.InnerRadius = math.max(r - 1.2, 0)
		local fade = math.clamp((r - (r1 - 12)) / 12, 0, 1)
		band.Transparency = 0.05 + 0.9 * fade
		glow.Transparency = 0.6 + 0.4 * fade
	end)
end

local handlers = {
	Wave = wave,
	Telegraph = telegraph,
	Impact = impact,
	Burst = burst,
	Arcs = arcs,
	Shot = shot,
	Chunks = chunks,
}

-- Tag animators ----------------------------------------------------------------------

type Entry = { [string]: any }
local animated: { [string]: { [BasePart]: Entry } } = {
	OMF_Spin = {},
	OMF_Pulse = {},
	OMF_Slide = {},
	OMF_Orbit = {},
	OMF_Swing = {},
}

local function readEntry(tag: string, part: BasePart): Entry
	if tag == "OMF_Spin" then
		local pivot = part:GetAttribute("SpinPivot")
		pivot = if typeof(pivot) == "CFrame" then pivot else part.CFrame
		local axis = part:GetAttribute("SpinAxis")
		return {
			Pivot = pivot,
			Offset = pivot:ToObjectSpace(part.CFrame),
			Axis = if typeof(axis) == "Vector3" and axis.Magnitude > 0 then axis.Unit else Vector3.yAxis,
			Speed = part:GetAttribute("SpinSpeed") or 1,
		}
	elseif tag == "OMF_Pulse" then
		return {
			Min = part:GetAttribute("PulseMin") or 0,
			Max = part:GetAttribute("PulseMax") or 0.7,
			Speed = part:GetAttribute("PulseSpeed") or 1,
			Phase = part:GetAttribute("PulsePhase") or 0,
		}
	elseif tag == "OMF_Slide" then
		local dir = part:GetAttribute("SlideDir")
		return {
			Base = part.CFrame,
			Dir = if typeof(dir) == "Vector3" and dir.Magnitude > 0 then dir.Unit else Vector3.xAxis,
			Speed = part:GetAttribute("SlideSpeed") or 4,
			Span = math.max(part:GetAttribute("SlideSpan") or 10, 1),
			BaseTransparency = part:GetAttribute("SlideBase") or part.Transparency,
			Phase = part:GetAttribute("SlidePhase") or 0, -- shared phase keeps multi-part shapes together
		}
	elseif tag == "OMF_Swing" then
		local axis = part:GetAttribute("SwingAxis")
		return {
			Pivot = part:GetAttribute("SwingPivot"),
			Offset = part:GetAttribute("SwingOffset"),
			Amp = part:GetAttribute("SwingAmp") or 1,
			Omega = part:GetAttribute("SwingOmega") or 1,
			Phase = part:GetAttribute("SwingPhase") or 0,
			Axis = if typeof(axis) == "Vector3" and axis.Magnitude > 0 then axis.Unit else Vector3.xAxis,
			StartTime = part:GetAttribute("StartTime") or serverNow(),
		}
	else -- OMF_Orbit
		local axis = part:GetAttribute("OrbitAxis")
		return {
			Axis = if typeof(axis) == "Vector3" and axis.Magnitude > 0 then axis.Unit else Vector3.yAxis,
			Center = part:GetAttribute("OrbitCenter"),
			Offset = part:GetAttribute("OrbitOffset"),
			Angle0 = part:GetAttribute("Angle0") or 0,
			Omega0 = part:GetAttribute("Omega0") or 1,
			Ramp = part:GetAttribute("Ramp") or 0,
			Dir = part:GetAttribute("Dir") or 1,
			StartTime = part:GetAttribute("StartTime") or serverNow(),
		}
	end
end

local function track(tag: string)
	local list = animated[tag]
	local function add(instance: Instance)
		if instance:IsA("BasePart") then
			list[instance] = readEntry(tag, instance)
			-- Server-side changes (belt flips, speed ramps) refresh the cached entry
			instance.AttributeChanged:Connect(function(name)
				if list[instance] and name ~= "StopTime" then
					local fresh = readEntry(tag, instance)
					if tag == "OMF_Slide" then
						fresh.Base = list[instance].Base
						fresh.Phase = list[instance].Phase
					end
					list[instance] = fresh
				end
			end)
		end
	end
	for _, instance in CollectionService:GetTagged(tag) do
		add(instance)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(add)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(instance)
		list[instance] = nil
	end)
end

local function step(dt: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local camPos = camera.CFrame.Position
	local t = os.clock()
	local now = serverNow()
	local limit = CULL_DISTANCE * CULL_DISTANCE

	local function near(part: BasePart): boolean
		local offset = part.Position - camPos
		return offset:Dot(offset) <= limit
	end

	for part, e in animated.OMF_Spin do
		if not part.Parent then
			animated.OMF_Spin[part] = nil
		elseif near(part) then
			part.CFrame = e.Pivot * CFrame.fromAxisAngle(e.Axis, t * e.Speed) * e.Offset
		end
	end
	for part, e in animated.OMF_Pulse do
		if not part.Parent then
			animated.OMF_Pulse[part] = nil
		elseif near(part) then
			local a = 0.5 + 0.5 * math.sin((t * e.Speed + e.Phase) * math.pi * 2)
			part.Transparency = e.Min + (e.Max - e.Min) * a
		end
	end
	for part, e in animated.OMF_Slide do
		if not part.Parent then
			animated.OMF_Slide[part] = nil
		elseif near(part) then
			e.Phase += dt * e.Speed -- integrate so speed changes never make the arrows jump
			local travel = e.Phase % e.Span
			local frac = travel / e.Span
			part.CFrame = e.Base + e.Dir * (travel - e.Span / 2)
			part.Transparency = 1 - (1 - e.BaseTransparency) * math.sin(frac * math.pi)
		end
	end
	for part, e in animated.OMF_Orbit do
		if not part.Parent then
			animated.OMF_Orbit[part] = nil
		elseif typeof(e.Center) == "CFrame" and typeof(e.Offset) == "CFrame" and near(part) then
			local stop = part:GetAttribute("StopTime")
			local elapsed = (if stop then math.min(now, stop) else now) - e.StartTime
			elapsed = math.max(elapsed, 0)
			local angle = e.Angle0 + e.Dir * (e.Omega0 * elapsed + 0.5 * e.Ramp * elapsed * elapsed)
			part.CFrame = e.Center * CFrame.fromAxisAngle(e.Axis, angle) * e.Offset
		end
	end
	for part, e in animated.OMF_Swing do
		if not part.Parent then
			animated.OMF_Swing[part] = nil
		elseif typeof(e.Pivot) == "CFrame" and typeof(e.Offset) == "CFrame" and near(part) then
			local stop = part:GetAttribute("StopTime")
			local elapsed = math.max((if stop then math.min(now, stop) else now) - e.StartTime, 0)
			local angle = e.Amp * math.sin(e.Omega * elapsed + e.Phase)
			part.CFrame = e.Pivot * CFrame.fromAxisAngle(e.Axis, angle) * e.Offset
		end
	end
end

function ArenaFx.Start()
	folder = Instance.new("Folder")
	folder.Name = "OMF_LocalFx"
	folder.Parent = workspace

	for tag in animated do
		track(tag)
	end
	RunService.RenderStepped:Connect(step)

	Net.Event("Effect").OnClientEvent:Connect(function(name, args)
		if name ~= "Fx" or typeof(args) ~= "table" then
			return
		end
		local handler = handlers[args.Kind]
		if handler then
			local ok, err = pcall(handler, args)
			if not ok then
				warn("[ArenaFx]", args.Kind, err)
			end
		end
	end)
end

return ArenaFx
