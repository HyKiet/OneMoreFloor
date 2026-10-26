-- Client-side lighting moods. The lobby look lives in the place's Lighting service; inside a run
-- this layers a colour grade per depth theme and per phase (dim ride down, boss tension,
-- desaturated spectating). It only touches its own OMF_Ambience* effects so it never fights the
-- Darkness / Fog curses in Effects, which own the base Lighting properties.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local State = require(script.Parent.State)

local Ambience = {}

type Grade = { Tint: Color3, Contrast: number, Saturation: number, Brightness: number, Bloom: number }

local NEUTRAL: Grade = { Tint = Color3.new(1, 1, 1), Contrast = 0, Saturation = 0, Brightness = 0, Bloom = 0 }

-- Keyed by Config.Themes[].Name. Unknown themes fall back to NEUTRAL.
local THEME_GRADES: { [string]: Grade } = {
	["Lobby Blue"] = { Tint = Color3.fromRGB(236, 244, 255), Contrast = 0.05, Saturation = 0.06, Brightness = 0.02, Bloom = 0 },
	["Ultraviolet"] = { Tint = Color3.fromRGB(238, 224, 255), Contrast = 0.08, Saturation = 0.1, Brightness = 0, Bloom = 0.04 },
	["Inferno"] = { Tint = Color3.fromRGB(255, 226, 208), Contrast = 0.12, Saturation = 0.08, Brightness = 0, Bloom = 0.06 },
	["Gold Vault"] = { Tint = Color3.fromRGB(255, 241, 214), Contrast = 0.08, Saturation = 0.02, Brightness = 0.03, Bloom = 0.06 },
	-- modest contrast: more crushes the dark floors of the deepest arenas to black
	["The Void"] = { Tint = Color3.fromRGB(222, 226, 242), Contrast = 0.12, Saturation = -0.25, Brightness = 0, Bloom = 0.03 },
}

-- Arenas sit under the lobby's night sky, so a run lifts the ambient light enough for floors and walls to
-- read. The Darkness curse in Effects saves and restores these same Lighting properties: they are only
-- written while its OMF_Darkness grade is absent, and its removal re-applies the current target.
type Light = { Ambient: Color3, OutdoorAmbient: Color3 }

local RUN_LIGHT: Light = { Ambient = Color3.fromRGB(104, 98, 124), OutdoorAmbient = Color3.fromRGB(132, 132, 156) }
local VOID_LIGHT: Light = { Ambient = Color3.fromRGB(94, 92, 112), OutdoorAmbient = Color3.fromRGB(120, 120, 142) }

local TWEEN = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local grade: ColorCorrectionEffect
local glow: BloomEffect
local lobbyLight: Light
local lightTarget: Light? = nil

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

local function blend(base: Grade, phase: string?, isBoss: boolean, spectating: boolean): Grade
	local g = table.clone(base)
	if phase == "Descending" then
		-- the ride down: dimmer and flatter, so the doors opening onto the arena pops
		g.Brightness -= 0.06
		g.Saturation -= 0.12
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
		return
	end
	local theme = Config.ThemeFor(math.max(run.Floor or 1, 1))
	applyLight(if theme.Name == "The Void" then VOID_LIGHT else RUN_LIGHT)
	local base = THEME_GRADES[theme.Name] or NEUTRAL
	local spectating = run.You and run.You.Status == "Dead"
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

	lobbyLight = { Ambient = Lighting.Ambient, OutdoorAmbient = Lighting.OutdoorAmbient }
	Lighting.ChildRemoved:Connect(function(child)
		if child.Name == "OMF_Darkness" and lightTarget then
			applyLight(lightTarget, true)
		end
	end)

	State.RunChanged:Connect(refresh)
	refresh()
end

return Ambience
