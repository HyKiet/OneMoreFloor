-- Client-side lighting moods, "Midnight Deco". The lobby look lives in the place's Lighting service (a
-- warm lounge: golden pools under the ceiling lights, dim surroundings, cyan / magenta / brass accents).
-- Inside a run this switches mood by phase:
--   Elevator (Descending, riding in the cab): low-key; the cab's own warm lights carry the scene
--   Arena (every other phase): the night sky lifted so floors, players and hazards always read, a colour
--     grade per depth theme and a theme-tinted haze that gives the shaft depth
-- It writes its own OMF_Ambience* effects plus the Lighting properties in `Light` and the Atmosphere,
-- and never fights the curses in Effects: Darkness owns those Lighting properties while its OMF_Darkness
-- grade exists, and the Fog curse owns the Atmosphere while Lighting has the OMF_FogCurse attribute.
-- Each curse's end re-applies the current target.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local State = require(script.Parent.State)

local Ambience = {}

type Grade = { Tint: Color3, Contrast: number, Saturation: number, Brightness: number, Bloom: number }

local NEUTRAL: Grade = { Tint = Color3.new(1, 1, 1), Contrast = 0, Saturation = 0, Brightness = 0, Bloom = 0 }

-- Keyed by Config.Themes[].Name. Unknown themes fall back to NEUTRAL. Stylised neon: a little more
-- saturation and bloom the deeper you go, contrast kept modest so dark floors never crush to black.
local THEME_GRADES: { [string]: Grade } = {
	["Lobby Blue"] = { Tint = Color3.fromRGB(236, 244, 255), Contrast = 0.05, Saturation = 0.1, Brightness = 0.02, Bloom = 0.02 },
	["Ultraviolet"] = { Tint = Color3.fromRGB(240, 226, 255), Contrast = 0.08, Saturation = 0.14, Brightness = 0.01, Bloom = 0.05 },
	["Inferno"] = { Tint = Color3.fromRGB(255, 228, 210), Contrast = 0.1, Saturation = 0.1, Brightness = 0.01, Bloom = 0.06 },
	-- near-white accents (Secondary 236, 230, 214): almost no extra bloom, or step lips and trims glare
	["Gold Vault"] = { Tint = Color3.fromRGB(255, 242, 218), Contrast = 0.08, Saturation = 0.04, Brightness = 0.02, Bloom = 0 },
	-- modest contrast: more crushes the dark floors of the deepest arenas to black
	["The Void"] = { Tint = Color3.fromRGB(222, 226, 242), Contrast = 0.12, Saturation = -0.25, Brightness = 0, Bloom = 0.03 },
}

-- Arenas sit under the lobby's night sky, so a run lifts the light enough for floors and walls to read (the
-- lobby itself runs a dimmer moon for its lounge pools). The Darkness curse in Effects saves and restores
-- these same Lighting properties: they are only written while its OMF_Darkness grade is absent, and its
-- removal re-applies the current target.
type Light = { Ambient: Color3, OutdoorAmbient: Color3, Brightness: number, ExposureCompensation: number }

local RUN_LIGHT: Light = { Ambient = Color3.fromRGB(104, 98, 124), OutdoorAmbient = Color3.fromRGB(132, 132, 156), Brightness = 2, ExposureCompensation = 0.25 }
local VOID_LIGHT: Light = { Ambient = Color3.fromRGB(94, 92, 112), OutdoorAmbient = Color3.fromRGB(120, 120, 142), Brightness = 2, ExposureCompensation = 0.25 }
-- the closed cab on the way down: low ambient so its warm panels light the riders from above
local CAB_LIGHT: Light = { Ambient = Color3.fromRGB(66, 56, 74), OutdoorAmbient = Color3.fromRGB(72, 64, 86), Brightness = 1, ExposureCompensation = 0.25 }

-- Arena haze per theme: the accent colour deepened, so the far shaft fades into the depth's colour. Kept
-- thin so hazards across the arena stay sharp.
type Haze = { Density: number, Haze: number, Color: Color3, Decay: Color3, Glare: number, Offset: number }

local function arenaHaze(theme): Haze
	local void = theme.Name == "The Void"
	return {
		Density = if void then 0.2 else 0.24,
		Haze = 1.1,
		Color = theme.Primary:Lerp(Color3.new(0, 0, 0), 0.62),
		Decay = theme.Floor:Lerp(Color3.new(0, 0, 0), 0.5),
		Glare = 0,
		Offset = 0.05,
	}
end

local TWEEN = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local grade: ColorCorrectionEffect
local glow: BloomEffect
local atmosphere: Atmosphere?
local lobbyLight: Light
local lobbyHaze: Haze?
local lightTarget: Light? = nil
local hazeTarget: Haze? = nil

local function applyLight(target: Light, force: boolean?)
	if target == lightTarget and not force then
		return
	end
	lightTarget = target
	if Lighting:FindFirstChild("OMF_Darkness") then
		return
	end
	TweenService:Create(Lighting, TWEEN, target :: any):Play()
end

local function sameHaze(a: Haze?, b: Haze?): boolean
	return a ~= nil and b ~= nil and a.Density == b.Density and a.Color == b.Color and a.Decay == b.Decay and a.Haze == b.Haze
end

local function applyHaze(target: Haze?, force: boolean?)
	if not atmosphere or not target or (sameHaze(target, hazeTarget) and not force) then
		return
	end
	hazeTarget = target
	if Lighting:GetAttribute("OMF_FogCurse") then
		return
	end
	TweenService:Create(atmosphere, TWEEN, target :: any):Play()
end

local function blend(base: Grade, phase: string?, isBoss: boolean, spectating: boolean): Grade
	local g = table.clone(base)
	if phase == "Descending" then
		-- the ride down: low-key and warm, so the doors opening onto the neon arena pops
		g.Brightness -= 0.03
		g.Saturation -= 0.1
		g.Contrast += 0.05
		g.Tint = g.Tint:Lerp(Color3.fromRGB(255, 226, 196), 0.35)
	elseif phase == "Decision" then
		-- money moment: a touch of warmth
		g.Tint = g.Tint:Lerp(Color3.fromRGB(255, 236, 205), 0.4)
	end
	if isBoss and (phase == "Briefing" or phase == "Challenge") then
		g.Contrast += 0.1
		g.Tint = g.Tint:Lerp(Color3.fromRGB(255, 212, 212), 0.5)
		g.Bloom += 0.05
	end
	if spectating then
		g.Saturation -= 0.55
		g.Brightness -= 0.03
	end
	return g
end

local current: Grade? = nil

local function apply(target: Grade)
	if current and current.Tint == target.Tint and current.Contrast == target.Contrast
		and current.Saturation == target.Saturation and current.Brightness == target.Brightness
		and current.Bloom == target.Bloom then
		return
	end
	current = target
	TweenService:Create(grade, TWEEN, {
		TintColor = target.Tint,
		Contrast = target.Contrast,
		Saturation = target.Saturation,
		Brightness = target.Brightness,
	}):Play()
	TweenService:Create(glow, TWEEN, { Intensity = target.Bloom }):Play()
end

local function refresh()
	local run = State.Run
	if not State.InRun() or run.Phase == "Ended" then
		apply(NEUTRAL)
		applyLight(lobbyLight)
		applyHaze(lobbyHaze)
		return
	end
	local theme = Config.ThemeFor(math.max(run.Floor or 1, 1))
	local spectating = run.You and run.You.Status == "Dead"
	-- spectators watch the arena from the booth while the cab rides down: they keep the arena light
	if run.Phase == "Descending" and not spectating then
		applyLight(CAB_LIGHT)
	else
		applyLight(if theme.Name == "The Void" then VOID_LIGHT else RUN_LIGHT)
	end
	applyHaze(arenaHaze(theme))
	local base = THEME_GRADES[theme.Name] or NEUTRAL
	apply(blend(base, run.Phase, run.IsBoss == true, spectating == true))
end

function Ambience.Start()
	grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "OMF_AmbienceGrade"
	grade.Parent = Lighting
	-- extra bloom layered on the place's own Bloom; high threshold so only neon/hazards bloom more
	glow = Instance.new("BloomEffect")
	glow.Name = "OMF_AmbienceBloom"
	glow.Intensity = 0
	glow.Size = 24
	glow.Threshold = 1.6
	glow.Parent = Lighting

	lobbyLight = {
		Ambient = Lighting.Ambient,
		OutdoorAmbient = Lighting.OutdoorAmbient,
		Brightness = Lighting.Brightness,
		ExposureCompensation = Lighting.ExposureCompensation,
	}
	atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		lobbyHaze = {
			Density = atmosphere.Density,
			Haze = atmosphere.Haze,
			Color = atmosphere.Color,
			Decay = atmosphere.Decay,
			Glare = atmosphere.Glare,
			Offset = atmosphere.Offset,
		}
	end
	Lighting.ChildRemoved:Connect(function(child)
		if child.Name == "OMF_Darkness" and lightTarget then
			applyLight(lightTarget, true)
		end
	end)
	Lighting:GetAttributeChangedSignal("OMF_FogCurse"):Connect(function()
		if not Lighting:GetAttribute("OMF_FogCurse") then
			applyHaze(hazeTarget, true)
		end
	end)

	State.RunChanged:Connect(refresh)
	refresh()
end

return Ambience
