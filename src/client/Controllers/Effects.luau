-- Handles the server's Effect(name, args) event: shake, flash, elevator descent (floor indicator),
-- coin pops, client-side curses (Darkness / Fog / Shaky), sounds, confetti and banners.
-- Curse lighting owns base Lighting props + Atmosphere (save/restore); Ambience owns OMF_Ambience*.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Config = require(ReplicatedStorage.Shared.Config)
local Net = require(ReplicatedStorage.Shared.Net)
local Format = require(ReplicatedStorage.Shared.Format)
local UIKit = require(script.Parent.Parent.Util.UIKit)
local Theme = require(script.Parent.Parent.UI.Theme)
local Kit = require(script.Parent.Parent.UI.Kit)
local Screen = require(script.Parent.Screen)
local Audio = require(script.Parent.Audio)
local CameraShake = require(script.Parent.CameraShake)
local Briefing = require(script.Parent.Briefing)
local Celebration = require(script.Parent.Celebration)

local Children = Fusion.Children
local C = Theme.Color

local Effects = {}

local scope = Fusion.scoped(Fusion, Kit)
local player = Players.LocalPlayer
local effectsLayer: Frame
local overlayLayer: Frame

-- Flash ----------------------------------------------------------------------

function Effects.Flash(color: Color3?, duration: number?)
	if not effectsLayer then
		return
	end
	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = color or C.Ivory
	frame.BackgroundTransparency = 0.45
	frame.BorderSizePixel = 0
	frame.Size = UDim2.fromScale(1, 1)
	frame.ZIndex = 100
	-- vignette-style: stronger at the edges than in the centre
	local gradient = Instance.new("UIGradient")
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.5, 0.6),
		NumberSequenceKeypoint.new(1, 0),
	})
	gradient.Parent = frame
	frame.Parent = effectsLayer
	TweenService:Create(frame, TweenInfo.new(duration or 0.4, Enum.EasingStyle.Quad), { BackgroundTransparency = 1 }):Play()
	task.delay((duration or 0.4) + 0.05, function()
		frame:Destroy()
	end)
end

-- Descend: elevator floor indicator ------------------------------------------------------------

-- The cab the local player is riding in (its Lights folder within 60 studs), plus that folder's lights.
local function findCab(): (Model?, { Light })
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return nil, {}
	end
	local searchRoot = workspace:FindFirstChild("Runs") or workspace
	for _, desc in searchRoot:GetDescendants() do
		if desc.Name == "Lights" and (desc:IsA("Folder") or desc:IsA("Model")) then
			local cab = desc:FindFirstAncestorWhichIsA("Model")
			local pivot = if cab then cab:GetPivot().Position else nil
			if cab and pivot and (pivot - root.Position).Magnitude < 60 then
				local lights = {}
				for _, light in desc:GetDescendants() do
					if light:IsA("Light") then
						table.insert(lights, light)
					end
				end
				return cab, lights
			end
		end
	end
	return nil, {}
end

-- Cab lights on the way down: a soft electrical hum and one or two short brownouts per ride (never a
-- strobe), while the light of each floor you pass sweeps up past the closed doors, tinted with the colour
-- of the depth you are heading to. Client-only: one local light, restored and removed when the ride ends.
local descendToken = 0

local SWEEP_PERIOD = 0.95 -- seconds between passing floors
local SWEEP_TIME = 0.5 -- seconds a floor's light takes to pass the doors

local function cabRide(duration: number, floor: number, token: number)
	local cab, lights = findCab()
	local original = {}
	for _, light in lights do
		original[light] = light.Brightness
	end
	local rng = Random.new()
	-- brownouts: (start, length) pairs
	local dips = { { rng:NextNumber(0.6, 1.4), rng:NextNumber(0.1, 0.18) } }
	if duration > 2.5 and rng:NextNumber() < 0.7 then
		table.insert(dips, { rng:NextNumber(duration * 0.55, duration - 0.6), rng:NextNumber(0.08, 0.14) })
	end

	local sweep: Part? = nil
	local sweepLight: PointLight? = nil
	if cab then
		sweep = Instance.new("Part")
		sweep.Name = "OMF_PassingFloor"
		sweep.Anchored = true
		sweep.CanCollide = false
		sweep.CanQuery = false
		sweep.CanTouch = false
		sweep.Transparency = 1
		sweep.Size = Vector3.one
		sweepLight = Instance.new("PointLight")
		sweepLight.Range = 18
		sweepLight.Shadows = false
		sweepLight.Color = Config.ThemeFor(math.max(floor, 1)).Primary:Lerp(Color3.new(1, 1, 0.9), 0.45)
		sweepLight.Brightness = 0
		sweepLight.Parent = sweep
		sweep.Parent = workspace
	end
	local pivot = if cab then cab:GetPivot() else CFrame.identity

	local start = os.clock()
	local phase = rng:NextNumber(0, math.pi * 2)
	local connection
	connection = RunService.Heartbeat:Connect(function()
		local t = os.clock() - start
		if t >= duration or token ~= descendToken then
			connection:Disconnect()
			for light, base in original do
				if light.Parent then
					light.Brightness = base
				end
			end
			if sweep then
				sweep:Destroy()
			end
			return
		end
		local level = 0.94 + 0.06 * math.sin(t * 9 + phase)
		for _, dip in dips do
			local into = t - dip[1]
			if into >= 0 and into < dip[2] then
				level = 0.35
			end
		end
		for light, base in original do
			if light.Parent then
				light.Brightness = base * level
			end
		end
		if sweep and sweepLight then
			-- a floor's light rises from below the cab to above it, just outside the doors
			local k = (t % SWEEP_PERIOD) / SWEEP_TIME
			if k <= 1 then
				sweep.CFrame = pivot * CFrame.new(0, -8 + k * 30, -13)
				sweepLight.Brightness = 2.4 * math.sin(k * math.pi)
			else
				sweepLight.Brightness = 0
			end
		end
	end)
end

-- Indicator plate: "B6" rolls up out of a window and "B7" rolls in when the cab arrives.
-- Returns arrive() and close() callbacks.
local function indicator(fromFloor: number, toFloor: number): (() -> (), () -> ())
	local inner = scope:innerScope()
	local shown = inner:Value(false)
	local arrived = inner:Value(false)
	local roll = inner:Spring(inner:Computed(function(use)
		return if use(arrived) then 1 else 0
	end), 22, 0.7)
	local chevronPulse = Kit.Pulse(inner, inner:Computed(function(use)
		return use(shown) and not use(arrived)
	end), 2.4)
	local isBoss = toFloor % 5 == 0
	local accent = if isBoss then C.Red else C.Brass

	local root = Kit.Reveal(inner, {
		Name = "DescendIndicator",
		Shown = shown,
		Size = UDim2.fromOffset(230, 132),
		Position = UDim2.fromScale(0.5, 0.3),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Offset = UDim2.fromOffset(0, -16),
		Children = {
			inner:New "UIScale" {
				Scale = inner:Computed(function(use)
					return if use(Screen.Layout) == "Wide" then 1 else 0.85
				end),
			},
			Kit.Plate(inner, {
				Size = UDim2.fromScale(1, 1),
				Accent = accent,
				Children = {
					Kit.Eyebrow(inner, {
						Text = inner:Computed(function(use)
							if use(arrived) then
								return if isBoss then "BOSS FLOOR" else "ARRIVED"
							end
							return "DESCENDING"
						end),
						Color = accent,
						HAlign = Enum.HorizontalAlignment.Center,
						TextSize = 10,
						Height = 14,
						Position = UDim2.new(0.5, 0, 0, 12),
						AnchorPoint = Vector2.new(0.5, 0),
					}),
					inner:New "Frame" {
						Name = "Window",
						BackgroundColor3 = C.Ink,
						BackgroundTransparency = 0.2,
						ClipsDescendants = true,
						Size = UDim2.fromOffset(150, 64),
						Position = UDim2.new(0.5, 0, 0, 34),
						AnchorPoint = Vector2.new(0.5, 0),
						[Children] = {
							inner:New "UICorner" { CornerRadius = UDim.new(0, 2) },
							inner:New "UIStroke" { Color = C.BrassDim, Thickness = 1 },
							Kit.Text(inner, {
								Text = "B" .. tostring(fromFloor),
								Font = Theme.Font.Display,
								TextSize = 40,
								Color = C.Muted,
								Size = UDim2.fromScale(1, 1),
								Position = inner:Computed(function(use)
									return UDim2.fromScale(0, -use(roll))
								end),
							}),
							Kit.Text(inner, {
								Text = "B" .. tostring(toFloor),
								Font = Theme.Font.Display,
								TextSize = 40,
								Color = if isBoss then C.Red else C.Ivory,
								Size = UDim2.fromScale(1, 1),
								Position = inner:Computed(function(use)
									return UDim2.fromScale(0, 1 - use(roll))
								end),
							}),
						},
					},
					Kit.Icon(inner, {
						Name = "Down",
						Color = inner:Computed(function(use)
							return C.BrassDim:Lerp(C.BrassBright, use(chevronPulse))
						end),
						Size = UDim2.fromOffset(18, 18),
						Position = UDim2.new(0.5, 0, 1, -10),
						AnchorPoint = Vector2.new(0.5, 1),
					}),
				},
			}),
		},
	})
	root.Parent = overlayLayer
	shown:set(true)
	local closed = false
	return function()
		arrived:set(true)
	end, function()
		if closed then
			return
		end
		closed = true
		shown:set(false)
		task.delay(0.4, function()
			Fusion.doCleanup(inner)
		end)
	end
end

local function descend(args)
	descendToken += 1
	local token = descendToken
	local duration = math.clamp(tonumber(args.Duration) or 4, 0.5, 12)
	local floor = tonumber(args.Floor) or 1

	CameraShake.SetConstant("Descend", 0.18)
	CameraShake.Shake(0.8, 0.5)
	Audio.Loop("ElevatorHum", true)

	local arrive, close = indicator(math.max(floor - 1, 0), floor)
	cabRide(duration, floor, token)

	task.delay(duration, function()
		if token ~= descendToken then
			close()
			return
		end
		CameraShake.SetConstant("Descend", nil)
		CameraShake.Shake(1, 0.35)
		Audio.Loop("ElevatorHum", false)
		Audio.Play("ElevatorDing")
		arrive()
		task.wait(0.9)
		close()
	end)
end

-- Coin pops ----------------------------------------------------------------------

local function coinPop(args)
	local position = args.Position
	if typeof(position) ~= "Vector3" then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.WorldPosition = position
	attachment.Parent = workspace.Terrain
	local billboard = Instance.new("BillboardGui")
	billboard.Adornee = attachment
	billboard.Size = UDim2.fromOffset(150, 40)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 1.5, 0)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.FontFace = Theme.Font.Display
	label.TextSize = 24
	label.TextColor3 = C.Gold
	label.Text = "+" .. Format.Cash(tonumber(args.Amount) or 0)
	label.Parent = billboard
	local stroke = Instance.new("UIStroke")
	stroke.Color = C.Ink
	stroke.Thickness = 2
	stroke.Transparency = 0.3
	stroke.Parent = label
	billboard.Parent = player:WaitForChild("PlayerGui")
	TweenService:Create(billboard, TweenInfo.new(0.9, Enum.EasingStyle.Quart), { StudsOffsetWorldSpace = Vector3.new(0, 5, 0) }):Play()
	task.delay(0.45, function()
		TweenService:Create(label, TweenInfo.new(0.45), { TextTransparency = 1 }):Play()
		TweenService:Create(stroke, TweenInfo.new(0.45), { Transparency = 1 }):Play()
	end)
	task.delay(1, function()
		billboard:Destroy()
		attachment:Destroy()
	end)
	Audio.Play("Coin", 0.95 + math.random() * 0.15)
end

-- Curses ----------------------------------------------------------------------

local activeCurses: { [string]: boolean } = {}
local savedLighting: { [string]: any }? = nil
local darkness: { Instance } = {}
local fogState: { Atmosphere: Atmosphere?, Created: boolean, Saved: { [string]: any }? }? = nil

local LIGHTING_KEYS = { "Brightness", "Ambient", "OutdoorAmbient", "ExposureCompensation", "EnvironmentDiffuseScale", "EnvironmentSpecularScale" }

local function attachDarkLight()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and not root:FindFirstChild("OMF_DarkLight") then
		local light = UIKit.new("PointLight", {
			Name = "OMF_DarkLight",
			Range = 18,
			Brightness = 2.2,
			Color = Color3.fromRGB(200, 210, 255),
			Shadows = false,
			Parent = root,
		})
		table.insert(darkness, light)
	end
end

local function setDarkness(on: boolean)
	if on then
		if savedLighting then
			return
		end
		savedLighting = {}
		for _, key in LIGHTING_KEYS do
			(savedLighting :: any)[key] = (Lighting :: any)[key]
		end
		UIKit.tween(Lighting, 0.6, {
			Brightness = 0,
			Ambient = Color3.new(0, 0, 0),
			OutdoorAmbient = Color3.new(0, 0, 0),
			ExposureCompensation = -1.5,
			EnvironmentDiffuseScale = 0,
			EnvironmentSpecularScale = 0,
		})
		local cc = UIKit.new("ColorCorrectionEffect", {
			Name = "OMF_Darkness",
			Brightness = -0.05,
			Saturation = -0.35,
			Contrast = 0.15,
			Parent = Lighting,
		})
		table.insert(darkness, cc)
		attachDarkLight()
	else
		if not savedLighting then
			return
		end
		UIKit.tween(Lighting, 0.6, savedLighting :: any)
		savedLighting = nil
		for _, inst in darkness do
			inst:Destroy()
		end
		table.clear(darkness)
	end
end

local function setFog(on: boolean)
	if on then
		if fogState then
			return
		end
		local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
		local created = false
		local saved = nil
		if atmosphere then
			saved = {
				Density = atmosphere.Density,
				Offset = atmosphere.Offset,
				Haze = atmosphere.Haze,
				Color = atmosphere.Color,
				Decay = atmosphere.Decay,
				Glare = atmosphere.Glare,
			}
		else
			atmosphere = UIKit.new("Atmosphere", { Name = "OMF_Fog", Density = 0, Parent = Lighting })
			created = true
		end
		fogState = { Atmosphere = atmosphere, Created = created, Saved = saved }
		-- Ambience leaves the Atmosphere alone while this is set
		Lighting:SetAttribute("OMF_FogCurse", true)
		UIKit.tween(atmosphere :: Atmosphere, 0.8, {
			Density = 0.78,
			Offset = 0,
			Haze = 3,
			Glare = 0,
			Color = Color3.fromRGB(170, 175, 190),
			Decay = Color3.fromRGB(120, 125, 140),
		})
	else
		local state = fogState
		if not state then
			return
		end
		fogState = nil
		local atmosphere = state.Atmosphere
		if atmosphere then
			if state.Created then
				UIKit.tween(atmosphere, 0.6, { Density = 0 })
				task.delay(0.65, function()
					atmosphere:Destroy()
				end)
			elseif state.Saved then
				UIKit.tween(atmosphere, 0.6, state.Saved :: any)
			end
		end
		-- cleared after the restore starts, so Ambience's own haze tween takes over from it
		Lighting:SetAttribute("OMF_FogCurse", nil)
	end
end

local function applyCurses(list: { string }?)
	local wanted = {}
	if typeof(list) == "table" then
		for _, id in list do
			wanted[id] = true
		end
	end
	setDarkness(wanted.Darkness == true)
	setFog(wanted.Fog == true)
	CameraShake.SetConstant("Curse", if wanted.Shaky then 0.35 else nil)
	local anyNew = false
	for id in wanted do
		if not activeCurses[id] then
			anyNew = true
		end
	end
	activeCurses = wanted
	if anyNew then
		Audio.Play("CurseApplied")
	end
end

function Effects.ClearCurses()
	applyCurses({})
end

-- Dispatcher ----------------------------------------------------------------------

local handlers = {
	Shake = function(args)
		CameraShake.Shake(tonumber(args.Intensity) or 1, tonumber(args.Duration) or 0.4)
	end,
	Flash = function(args)
		Effects.Flash(if typeof(args.Color) == "Color3" then args.Color else nil, tonumber(args.Duration))
	end,
	Descend = descend,
	CoinPop = coinPop,
	Curses = function(args)
		applyCurses(args.List)
	end,
	Sound = function(args)
		if typeof(args.Name) == "string" then
			Audio.Play(args.Name)
		end
	end,
	Confetti = function()
		Celebration.Confetti()
	end,
	Banner = function(args)
		if typeof(args.Text) == "string" then
			Briefing.Banner(args.Text, if typeof(args.Color) == "Color3" then args.Color else nil)
		end
	end,
	-- Server-requested shove (bumpers, gusts, blasts): the client owns its character's physics.
	Knockback = function(args)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not root or not humanoid or typeof(args.Velocity) ~= "Vector3" then
			return
		end
		if args.Velocity.Y > 1 then
			humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
		end
		root.AssemblyLinearVelocity = args.Velocity
	end,
}

function Effects.Start()
	effectsLayer = Screen.Get("Effects")
	overlayLayer = Screen.Get("Overlay")

	Net.Event("Effect").OnClientEvent:Connect(function(name, args)
		local handler = handlers[name]
		if handler then
			local ok, err = pcall(handler, if typeof(args) == "table" then args else {})
			if not ok then
				warn("[Effects]", name, err)
			end
		end
	end)

	-- Curses never outlive the run; the dark light follows respawns.
	player:GetAttributeChangedSignal("InRun"):Connect(function()
		if not player:GetAttribute("InRun") then
			Effects.ClearCurses()
		end
	end)
	player.CharacterAdded:Connect(function()
		if savedLighting then
			task.wait(0.2)
			attachDarkLight()
		end
	end)
end

return Effects
