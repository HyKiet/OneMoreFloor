-- Root ScreenGuis plus the responsive state every UI controller reads.
--
-- Each layer has a "Root" frame laid out on a virtual canvas: one UIScale shrinks/grows the whole
-- canvas so 1 virtual px ≈ 1 px on a 1280x720 screen. Layout picks the arrangement:
--   "Wide"     desktop / tablet / console
--   "Compact"  phones in landscape (short screens): fewer labels, bigger hit targets
--   "Portrait" tall screens
-- Input is "Mouse" | "Touch" | "Gamepad" (last used), for key/button hints.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Fusion = require(ReplicatedStorage.Packages.Fusion)

local Screen = {}

local REFERENCE = Vector2.new(1280, 720)

local LAYERS = {
	{ Name = "World", Order = 0, Insets = Enum.ScreenInsets.None },
	{ Name = "HUD", Order = 1, Insets = Enum.ScreenInsets.CoreUISafeInsets },
	{ Name = "Run", Order = 3, Insets = Enum.ScreenInsets.CoreUISafeInsets },
	{ Name = "Panels", Order = 5, Insets = Enum.ScreenInsets.CoreUISafeInsets },
	{ Name = "Overlay", Order = 8, Insets = Enum.ScreenInsets.DeviceSafeInsets },
	{ Name = "Effects", Order = 10, Insets = Enum.ScreenInsets.None },
	{ Name = "Toasts", Order = 12, Insets = Enum.ScreenInsets.CoreUISafeInsets },
}

local scope = Fusion.scoped(Fusion)

Screen.Scope = scope
Screen.ScaleValue = scope:Value(1)
Screen.Layout = scope:Value("Wide")
Screen.Input = scope:Value("Mouse")
Screen.Canvas = scope:Value(REFERENCE) -- virtual canvas size of a CoreUISafeInsets layer

Screen.Scale = 1

local roots: { [string]: Frame } = {}
local guis: { [string]: ScreenGui } = {}
local scales: { UIScale } = {}

local function isTouch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

local function computeScale(viewport: Vector2): number
	local s = math.min(viewport.X / REFERENCE.X, viewport.Y / REFERENCE.Y)
	if isTouch() then
		s *= 1.18 -- thumbs need bigger targets than cursors
	elseif GuiService:IsTenFootInterface() then
		s *= 1.12
	end
	return math.clamp(s, 0.5, 2.4)
end

local function computeLayout(viewport: Vector2): string
	if viewport.Y > viewport.X * 1.05 then
		return "Portrait"
	end
	if viewport.Y < 560 or (isTouch() and viewport.Y < 700) then
		return "Compact"
	end
	return "Wide"
end

local function applyScale()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local viewport = camera.ViewportSize
	if viewport.X < 2 or viewport.Y < 2 then
		return
	end
	local s = computeScale(viewport)
	Screen.Scale = s
	Screen.ScaleValue:set(s)
	Screen.Layout:set(computeLayout(viewport))
	for _, root in roots do
		root.Size = UDim2.fromScale(1 / s, 1 / s)
	end
	for _, uiScale in scales do
		uiScale.Scale = s
	end
	local hud = roots.HUD
	if hud then
		Screen.Canvas:set(hud.AbsoluteSize / s)
	end
end

local function inputKind(inputType: Enum.UserInputType): string?
	if inputType == Enum.UserInputType.Touch then
		return "Touch"
	elseif inputType.Name:sub(1, 7) == "Gamepad" then
		return "Gamepad"
	elseif inputType == Enum.UserInputType.Keyboard or inputType.Name:sub(1, 5) == "Mouse" then
		return "Mouse"
	end
	return nil
end

function Screen.Get(name: string): Frame
	return roots[name]
end

function Screen.Gui(name: string): ScreenGui
	return guis[name]
end

function Screen.IsTouch(): boolean
	return Fusion.peek(Screen.Input) == "Touch"
end

function Screen.Start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	for _, layer in LAYERS do
		local gui = Instance.new("ScreenGui")
		gui.Name = "OMF_" .. layer.Name
		gui.ResetOnSpawn = false
		gui.DisplayOrder = layer.Order
		gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		gui.ScreenInsets = layer.Insets
		gui.IgnoreGuiInset = layer.Insets == Enum.ScreenInsets.None

		local root = Instance.new("Frame")
		root.Name = "Root"
		root.BackgroundTransparency = 1
		root.AnchorPoint = Vector2.new(0.5, 0.5)
		root.Position = UDim2.fromScale(0.5, 0.5)
		root.Size = UDim2.fromScale(1, 1)
		root.Parent = gui
		local uiScale = Instance.new("UIScale")
		uiScale.Parent = root
		table.insert(scales, uiScale)

		roots[layer.Name] = root
		guis[layer.Name] = gui
		gui.Parent = playerGui
	end

	local initial = inputKind(UserInputService:GetLastInputType())
	Screen.Input:set(initial or (if isTouch() then "Touch" else "Mouse"))
	UserInputService.LastInputTypeChanged:Connect(function(inputType)
		local kind = inputKind(inputType)
		if kind then
			Screen.Input:set(kind)
		end
	end)

	applyScale()
	local function hookCamera()
		local camera = workspace.CurrentCamera
		if camera then
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyScale)
		end
		applyScale()
	end
	hookCamera()
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(hookCamera)
	roots.HUD:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		Screen.Canvas:set(roots.HUD.AbsoluteSize / Screen.Scale)
	end)
end

return Screen
