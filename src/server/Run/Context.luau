-- The API every challenge template receives as `ctx`. One Context exists per floor.
-- Templates must only build inside ctx.Folder and must schedule work through ctx:After / ctx:Every
-- (or check ctx.Ended) so everything stops the moment the floor ends.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Sounds = require(ReplicatedStorage.Shared.Sounds)
local Trove = require(ReplicatedStorage.Packages.Trove)

local Context = {}
Context.__index = Context

export type Context = typeof(setmetatable(
	{} :: {
		Run: any,
		Floor: number,
		IsBoss: boolean,
		Difficulty: number,
		Mode: string,
		Origin: CFrame,
		Folder: Folder,
		HazardFolder: Folder,
		Trove: any,
		Rng: Random,
		Theme: any,
		Curses: { [string]: boolean },
		Ended: boolean,
		Started: boolean,
		Duration: number,
		Spawns: { CFrame }?,
		State: { [any]: any },
	},
	Context
))

function Context.new(run, params): Context
	local folder = Instance.new("Folder")
	folder.Name = "Arena"
	folder.Parent = params.Parent

	local hazards = Instance.new("Folder")
	hazards.Name = "Hazards"
	hazards.Parent = folder

	local self = setmetatable({
		Run = run,
		Floor = params.Floor,
		IsBoss = params.IsBoss,
		Difficulty = params.Difficulty,
		Mode = params.Mode,
		Origin = params.Origin,
		Folder = folder,
		HazardFolder = hazards,
		Trove = Trove.new(),
		Rng = params.Rng,
		Theme = Config.ThemeFor(params.Floor),
		Curses = params.Curses or {},
		Ended = false,
		Started = false,
		Duration = 20,
		Spawns = nil,
		State = {}, -- free scratch space for templates
	}, Context)
	self.Trove:Add(folder)
	return self
end

-- Geometry -------------------------------------------------------------------

-- World CFrame for a point given in arena-local coordinates (x right, y up, z toward the cab is +z).
-- Optional rotations are in degrees.
function Context:At(x: number, y: number, z: number, rx: number?, ry: number?, rz: number?): CFrame
	return self.Origin
		* CFrame.new(x, y, z)
		* CFrame.Angles(math.rad(rx or 0), math.rad(ry or 0), math.rad(rz or 0))
end

local function applyProps(part: BasePart, props: { [string]: any })
	local parent = props.Parent
	for key, value in props do
		if key ~= "Parent" then
			(part :: any)[key] = value
		end
	end
	return parent
end

-- Neon glare guard. Neon emits above the bloom threshold, so a big bright neon face (a whole wall or floor)
-- floods the screen. Opaque neon parts with a face bigger than NEON_SAFE_AREA get their colour value capped,
-- harder the bigger they are; thin trims and small lights keep full brightness. Call after recolouring too.
local NEON_SAFE_AREA = 24 -- studs^2: largest face that may glow at full brightness
local NEON_FLOOR_VALUE = 0.5 -- HSV value cap for huge neon faces (~400 studs^2 and up)

function Context.TameNeon(part: BasePart, color: Color3?): Color3
	local c = color or part.Color
	if part.Material ~= Enum.Material.Neon or part.Transparency >= 0.45 then
		if color then
			part.Color = c
		end
		return c
	end
	local s = part.Size
	local area = math.max(s.X * s.Y, s.Y * s.Z, s.X * s.Z)
	if part:IsA("Part") and part.Shape == Enum.PartType.Cylinder then
		area = math.max(s.Y * s.Z * 0.79, s.X * math.max(s.Y, s.Z))
	end
	if area > NEON_SAFE_AREA then
		local t = math.clamp((math.log(area) - math.log(NEON_SAFE_AREA)) / (math.log(400) - math.log(NEON_SAFE_AREA)), 0, 1)
		local cap = 1 - (1 - NEON_FLOOR_VALUE) * t
		local h, sat, v = c:ToHSV()
		if v > cap then
			c = Color3.fromHSV(h, sat, cap)
		end
	end
	part.Color = c
	return c
end

-- Creates an anchored part inside the arena. `props` may set any BasePart property
-- (CFrame is a world CFrame; use ctx:At to build one). Pass ClassName = "WedgePart" etc. for other shapes.
-- Large neon parts are toned down (Context.TameNeon); pass NeonGuard = false to opt out.
function Context:Part(props: { [string]: any }): BasePart
	local className = props.ClassName or "Part"
	props.ClassName = nil
	local guard = props.NeonGuard ~= false
	props.NeonGuard = nil
	local part = Instance.new(className) :: BasePart
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
	part.Color = self.Theme.Floor
	local parent = applyProps(part, props)
	if guard then
		Context.TameNeon(part)
		-- keep guarding when a template recolours / fades the part in later (lights switching red/green etc.)
		local function retame()
			Context.TameNeon(part)
		end
		part:GetPropertyChangedSignal("Color"):Connect(retame)
		part:GetPropertyChangedSignal("Transparency"):Connect(retame)
		part:GetPropertyChangedSignal("Material"):Connect(retame)
	end
	part.Parent = parent or self.Folder
	return part
end

-- A copy of ServerStorage.Assets.Props[name] (Blender meshes / vetted Creator Store models) parented to the
-- arena, or nil when the place has no such prop: templates dress up with it and fall back to primitives.
-- Scripts inside are stripped so a store model can never run code.
function Context:Prop(name: string): Instance?
	local assets = ServerStorage:FindFirstChild("Assets")
	local props = assets and assets:FindFirstChild("Props")
	local source = props and props:FindFirstChild(name)
	if not source then
		return nil
	end
	local copy = source:Clone()
	for _, d in copy:GetDescendants() do
		if d:IsA("LuaSourceContainer") then
			d:Destroy()
		end
	end
	copy.Parent = self.Folder
	return copy
end

-- Text on one face of a part (SurfaceGui), unlit so it reads in any arena without glowing.
-- `props` sets TextLabel properties; `props.Face` picks the face (default Front), `props.PixelsPerStud` the detail.
function Context:Sign(part: BasePart, text: string, props: { [string]: any }?): TextLabel
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Sign"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 24
	gui.LightInfluence = 0
	gui.MaxDistance = 500
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(245, 240, 230)
	label.Text = text
	if props then
		for key, value in props do
			if key == "Face" or key == "PixelsPerStud" then
				(gui :: any)[key] = value
			else
				(label :: any)[key] = value
			end
		end
	end
	label.Parent = gui
	gui.Parent = part
	return label
end

-- Floating text above a part (BillboardGui), e.g. a label over a pad. Size in studs; `props` sets TextLabel props.
function Context:Billboard(part: BasePart, text: string, size: Vector2?, offsetY: number?, props: { [string]: any }?): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Name = "Billboard"
	local s = size or Vector2.new(6, 2)
	gui.Size = UDim2.fromScale(s.X, s.Y)
	gui.StudsOffsetWorldSpace = Vector3.new(0, offsetY or 3, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = 300
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(245, 240, 230)
	label.TextStrokeTransparency = 0.4
	label.Text = text
	if props then
		for key, value in props do
			(label :: any)[key] = value
		end
	end
	label.Parent = gui
	gui.Adornee = part
	gui.Parent = part
	return label
end

-- Creates a part that eliminates any player overlapping it. Defaults to red neon, no collision.
function Context:Hazard(props: { [string]: any }): BasePart
	props.Parent = self.HazardFolder
	if props.Color == nil then
		props.Color = self.Theme.Hazard
	end
	if props.Material == nil then
		props.Material = Enum.Material.Neon
	end
	if props.CanCollide == nil then
		props.CanCollide = false
	end
	return self:Part(props)
end

-- Turns an existing arena part into a hazard (or back into a safe part with `false`).
function Context:MakeHazard(part: BasePart, isHazard: boolean?)
	if isHazard == false then
		part.Parent = self.Folder
	else
		part.Parent = self.HazardFolder
	end
end

-- Purely visual part: no collision, queries, touches or shadows.
function Context:Decor(props: { [string]: any }): BasePart
	if props.CanCollide == nil then
		props.CanCollide = false
	end
	props.CanQuery = false
	props.CanTouch = false
	if props.CastShadow == nil then
		props.CastShadow = false
	end
	return self:Part(props)
end

-- Telegraphs an incoming hazard. Drawn on each client (outline + fill that grows until impact),
-- so it costs the server nothing. `opts.Shape = "Disc"` draws a circle; `opts.Sweep` is an
-- arena-local direction the fill grows toward (e.g. Vector3.new(0, 0, -1)).
function Context:Warn(cframe: CFrame, size: Vector3, duration: number, color: Color3?, opts: { [string]: any }?)
	local args = {
		CFrame = cframe,
		Size = size,
		EndsAt = workspace:GetServerTimeNow() + duration,
		Color = color or self.Theme.Hazard,
	}
	if opts then
		args.Shape = opts.Shape
		args.Sweep = opts.Sweep and self.Origin:VectorToWorldSpace(opts.Sweep)
	end
	self:Fx("Telegraph", args)
end

-- Fires a client-side cosmetic effect for everyone on this run (see client ArenaFx).
function Context:Fx(kind: string, args: { [string]: any })
	args.Kind = kind
	self.Run:FireEffect("Fx", args)
end

-- Landing/explosion juice: ground shockwave ring, debris chunks, sparks and a light flash.
function Context:Impact(position: Vector3, color: Color3?, radius: number?, debris: number?)
	self:Fx("Impact", {
		Position = position,
		Color = color or self.Theme.Hazard,
		Radius = radius or 12,
		Debris = debris or 6,
	})
end

-- Tags a part for a client-side animation (see client ArenaFx): "OMF_Spin", "OMF_Pulse", "OMF_Slide", "OMF_Orbit".
function Context:Animate(part: BasePart, tag: string, attributes: { [string]: any }?)
	if attributes then
		for key, value in attributes do
			part:SetAttribute(key, value)
		end
	end
	part:AddTag(tag)
	return part
end

-- Glowing slab edges around a rectangular floor (x/z half sizes, floor top at y = 0):
-- a bright inset line on the top edge and a soft underglow skirt below.
function Context:Rim(halfX: number, halfZ: number, color: Color3?, underColor: Color3?)
	-- default edge line: the theme accent capped at value 0.8 (full-value orange / gold rims glare)
	local h, s, v = self.Theme.Primary:ToHSV()
	local top = color or Color3.fromHSV(h, s, math.min(v, 0.8))
	local under = underColor or self.Theme.Secondary
	for _, s in { { 0, halfZ - 0.25, halfX * 2, 0.5 }, { 0, -halfZ + 0.25, halfX * 2, 0.5 }, { halfX - 0.25, 0, 0.5, halfZ * 2 - 1 }, { -halfX + 0.25, 0, 0.5, halfZ * 2 - 1 } } do
		self:Decor({ Name = "RimLine", Size = Vector3.new(s[3], 0.12, s[4]), CFrame = self:At(s[1], 0.04, s[2]), Color = top, Material = Enum.Material.Neon })
	end
	self:Decor({ Name = "Skirt", Size = Vector3.new(halfX * 2 + 0.6, 0.85, halfZ * 2 + 0.6), CFrame = self:At(0, -1.6, 0), Color = self.Theme.Floor:Lerp(Color3.new(0, 0, 0), 0.5), Material = Enum.Material.SmoothPlastic })
	self:Decor({ Name = "Underglow", Size = Vector3.new(halfX * 2 + 1.2, 0.3, halfZ * 2 + 1.2), CFrame = self:At(0, -2.1, 0), Color = under, Material = Enum.Material.Neon })
end

-- Circular version of Rim for round floors. The rim disc stays well below the floor top: a disc whose
-- top face is coplanar with the floor z-fights across the whole platform.
-- Rule for all flat decor: stack thin layers at least 0.04 studs apart.
function Context:RoundRim(radius: number, color: Color3?, underColor: Color3?)
	self:Decor({ Name = "RimLine", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, radius * 2 + 0.6, radius * 2 + 0.6), CFrame = self:At(0, -0.3, 0, 0, 0, 90), Color = color or self.Theme.Primary, Material = Enum.Material.Neon })
	self:Decor({ Name = "Underglow", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, radius * 2 + 1.4, radius * 2 + 1.4), CFrame = self:At(0, -2.1, 0, 0, 0, 90), Color = underColor or self.Theme.Secondary, Material = Enum.Material.Neon })
end

-- Adds a PointLight to a part (keep these few: they are the most expensive decoration).
function Context:Glow(part: BasePart, color: Color3?, range: number?, brightness: number?): PointLight
	local light = Instance.new("PointLight")
	light.Color = color or part.Color
	light.Range = range or 12
	light.Brightness = brightness or 1.5
	light.Shadows = false
	light.Parent = part
	return light
end

-- Neon trail behind a moving part, between two attachments offset along the part's local axis.
function Context:Trail(part: BasePart, offsetA: Vector3, offsetB: Vector3, color: Color3?, lifetime: number?): Trail
	local a0 = Instance.new("Attachment")
	a0.Position = offsetA
	a0.Parent = part
	local a1 = Instance.new("Attachment")
	a1.Position = offsetB
	a1.Parent = part
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new(color or part.Color)
	trail.LightEmission = 1
	trail.Lifetime = lifetime or 0.25
	trail.FaceCamera = false
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
	trail.WidthScale = NumberSequence.new(1)
	trail.Parent = part
	return trail
end

-- Continuous particle emitter on a part using one of the engine's built-in textures.
-- `texture`: "Sparks" | "Sparkle" | "Smoke" | "Square" | "Glow" (or a full content id).
local TEXTURES = {
	Sparks = "rbxasset://textures/particles/fire_sparks_main.dds",
	Sparkle = "rbxasset://textures/particles/sparkles_main.dds",
	Smoke = "rbxasset://textures/particles/smoke_main.dds",
	Square = "rbxasset://textures/particles/SquareParticle.png",
	Glow = "rbxasset://textures/particles/explosion01_core_main.dds",
	Ring = "rbxasset://textures/particles/explosion01_shockwave_main.dds",
}
Context.Textures = TEXTURES

function Context:Emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Texture = TEXTURES.Sparks
	for key, value in props do
		if key == "Texture" then
			emitter.Texture = TEXTURES[value] or value
		else
			(emitter :: any)[key] = value
		end
	end
	emitter.Parent = parent
	return emitter
end

function Context:Tween(instance: Instance, info: TweenInfo, goals: { [string]: any }): Tween
	local tween = TweenService:Create(instance, info, goals)
	self.Trove:Add(function()
		tween:Cancel()
	end)
	tween:Play()
	return tween
end

-- Time ----------------------------------------------------------------------

-- Runs fn after `seconds` unless the floor has ended by then.
function Context:After(seconds: number, fn: () -> ())
	task.delay(seconds, function()
		if not self.Ended then
			fn()
		end
	end)
end

-- Calls fn(elapsed) every `interval` seconds until the floor ends (or fn returns false).
function Context:Every(interval: number, fn: (elapsed: number) -> boolean?)
	task.spawn(function()
		local start = os.clock()
		while not self.Ended do
			task.wait(interval)
			if self.Ended then
				break
			end
			local ok, keepGoing = pcall(fn, os.clock() - start)
			if not ok then
				warn("[Challenge] Every callback errored:", keepGoing)
				break
			end
			if keepGoing == false then
				break
			end
		end
	end)
end

-- Yields; returns false if the floor ended meanwhile (so loops can `if not ctx:Wait(1) then return end`).
function Context:Wait(seconds: number): boolean
	task.wait(seconds)
	return not self.Ended
end

-- Seconds since Start was called.
function Context:Elapsed(): number
	return if self.StartedAt then os.clock() - self.StartedAt else 0
end

-- Seconds left before time is up.
function Context:Remaining(): number
	return math.max(0, self.Duration - self:Elapsed())
end

-- Calls fn(dt) every frame until the floor ends.
function Context:Heartbeat(fn: (dt: number) -> ())
	local connection
	connection = game:GetService("RunService").Heartbeat:Connect(function(dt)
		if self.Ended then
			connection:Disconnect()
			return
		end
		fn(dt)
	end)
	self.Trove:Add(connection)
end

-- Ends the challenge early (everyone still alive survives, after Judge runs).
function Context:Finish()
	self.Run:FinishChallengeEarly(self)
end

-- Players --------------------------------------------------------------------

function Context:GetAlive(): { Player }
	return self.Run:GetAliveInChallenge()
end

function Context:GetCharacter(player: Player): Model?
	local character = player.Character
	if character and character.Parent then
		return character
	end
	return nil
end

function Context:GetRoot(player: Player): BasePart?
	local character = self:GetCharacter(player)
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

function Context:GetHumanoid(player: Player): Humanoid?
	local character = self:GetCharacter(player)
	return character and character:FindFirstChildOfClass("Humanoid")
end

-- Position of a player in arena-local space (nil if no character).
function Context:LocalPosition(player: Player): Vector3?
	local root = self:GetRoot(player)
	return root and self.Origin:PointToObjectSpace(root.Position)
end

function Context:Eliminate(player: Player, reason: string?)
	self.Run:EliminateFromChallenge(player, reason or "Eliminated")
end

-- Spawn CFrames (world space) players are teleported to when the doors open. Call from Build.
-- Default: a ring of radius 12 around the arena centre.
function Context:SetSpawns(spawns: { CFrame })
	self.Spawns = spawns
end

-- Arena-local height of a player's feet (nil without a character): ~0 standing on a floor whose top is y = 0,
-- higher while jumping. Position-based, so it works on the server where humanoid states lag or lie.
function Context:FeetY(player: Player): number?
	local root = self:GetRoot(player)
	local humanoid = self:GetHumanoid(player)
	if not root or not humanoid then
		return nil
	end
	local rootY = self.Origin:PointToObjectSpace(root.Position).Y
	if humanoid.RigType == Enum.HumanoidRigType.R15 then
		return rootY - (humanoid.HipHeight + root.Size.Y / 2)
	end
	return rootY - 3
end

-- Shoves a player: their own client applies `velocity` (world studs/s) to the character, so the push is instant
-- and smooth. Include upward speed (Y >= 15) for sideways shoves, or ground friction eats most of it.
function Context:Knockback(player: Player, velocity: Vector3)
	self.Run:FireEffectTo(player, "Knockback", { Velocity = velocity })
end

-- Continuous push on a player (wind, currents): `acceleration` in world studs/s^2, nil or zero to stop.
-- A VectorForce on the character root, scaled by its mass; removed automatically when the floor ends.
function Context:SetPush(player: Player, acceleration: Vector3?)
	self._pushes = self._pushes or {}
	local entry = self._pushes[player]
	local root = self:GetRoot(player)
	if acceleration == nil or acceleration.Magnitude < 1e-3 or not root then
		if entry and entry.Force.Parent then
			entry.Force.Force = Vector3.zero
		end
		return
	end
	if not entry or entry.Root ~= root or not entry.Force.Parent then
		if entry then
			entry.Attachment:Destroy()
		end
		local attachment = Instance.new("Attachment")
		attachment.Name = "OMF_PushAtt"
		attachment.Parent = root
		local force = Instance.new("VectorForce")
		force.Name = "OMF_Push"
		force.Attachment0 = attachment
		force.RelativeTo = Enum.ActuatorRelativeTo.World
		force.ApplyAtCenterOfMass = true
		force.Force = Vector3.zero
		force.Parent = attachment
		entry = { Force = force, Attachment = attachment, Root = root }
		self._pushes[player] = entry
		self.Trove:Add(attachment)
	end
	entry.Force.Force = acceleration * root.AssemblyMass
end

-- Moves a player to a CFrame (world). Useful for templates that relocate players mid-challenge.
function Context:Teleport(player: Player, cframe: CFrame)
	local character = self:GetCharacter(player)
	if character then
		character:PivotTo(cframe)
	end
end

-- Pickups & feedback -----------------------------------------------------------

-- Spawns a coin worth `value` (defaults to Config.CoinValue(floor)) that adds to the bag of whoever grabs it.
function Context:SpawnCoin(position: Vector3, value: number?)
	return self.Run:SpawnPickup(self, position, "Coin", value or Config.CoinValue(self.Floor))
end

-- Short banner text for everyone on this run (e.g. "RED LIGHT!").
function Context:Announce(text: string, color: Color3?)
	self.Run:Announce(text, color)
end

function Context:Shake(intensity: number?, duration: number?)
	self.Run:FireEffect("Shake", { Intensity = intensity or 1, Duration = duration or 0.4 })
end

-- Plays a sound from the Sounds library at a part/position (or globally for the run if `at` is nil).
function Context:Sound(name: string, at: (BasePart | Vector3)?)
	local def = Sounds[name]
	if not def or def.Id == 0 then
		return
	end
	if at == nil then
		self.Run:FireEffect("Sound", { Name = name })
		return
	end
	local host: BasePart
	if typeof(at) == "Vector3" then
		host = self:Part({
			Name = "SoundHost",
			Size = Vector3.one,
			CFrame = CFrame.new(at),
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
		})
		task.delay(6, function()
			host:Destroy()
		end)
	else
		host = at
	end
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://" .. def.Id
	sound.Volume = def.Volume or 0.5
	sound.RollOffMaxDistance = 250
	sound.Parent = host
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
end

-- Internal --------------------------------------------------------------------

function Context:_destroy()
	self.Ended = true
	self.Trove:Destroy()
end

return Context
