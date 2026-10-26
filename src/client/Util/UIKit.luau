-- Small UI toolkit: instance factory, neon-arcade styling helpers and juicy tweens.

local TweenService = game:GetService("TweenService")

local UIKit = {}

UIKit.Colors = {
	Bg = Color3.fromRGB(14, 16, 28),
	Panel = Color3.fromRGB(22, 25, 42),
	PanelLight = Color3.fromRGB(34, 38, 62),
	Cyan = Color3.fromRGB(70, 200, 255),
	Pink = Color3.fromRGB(255, 90, 190),
	Gold = Color3.fromRGB(255, 205, 60),
	Green = Color3.fromRGB(70, 230, 120),
	Red = Color3.fromRGB(255, 70, 80),
	Orange = Color3.fromRGB(255, 140, 50),
	Purple = Color3.fromRGB(170, 100, 255),
	White = Color3.fromRGB(255, 255, 255),
	Muted = Color3.fromRGB(160, 170, 200),
	Dark = Color3.fromRGB(8, 9, 16),
}

UIKit.Fonts = {
	Display = Enum.Font.FredokaOne,
	Bold = Enum.Font.GothamBold,
	Black = Enum.Font.GothamBlack,
	Body = Enum.Font.GothamMedium,
}

-- Instance factory. `props.Parent` is applied last; `children` are parented to the new instance.
function UIKit.new(className: string, props: { [string]: any }?, children: { Instance }?): any
	local inst = Instance.new(className)
	local parent
	if props then
		for key, value in props do
			if key == "Parent" then
				parent = value
			else
				(inst :: any)[key] = value
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = inst
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function UIKit.corner(radius: number?): UICorner
	return UIKit.new("UICorner", { CornerRadius = UDim.new(0, radius or 12) })
end

function UIKit.round(): UICorner
	return UIKit.new("UICorner", { CornerRadius = UDim.new(1, 0) })
end

function UIKit.stroke(color: Color3?, thickness: number?, transparency: number?): UIStroke
	return UIKit.new("UIStroke", {
		Color = color or UIKit.Colors.Cyan,
		Thickness = thickness or 2,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function UIKit.textStroke(color: Color3?, thickness: number?): UIStroke
	return UIKit.new("UIStroke", {
		Color = color or UIKit.Colors.Dark,
		Thickness = thickness or 2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
	})
end

function UIKit.padding(all: number, horizontal: number?): UIPadding
	local h = horizontal or all
	return UIKit.new("UIPadding", {
		PaddingTop = UDim.new(0, all),
		PaddingBottom = UDim.new(0, all),
		PaddingLeft = UDim.new(0, h),
		PaddingRight = UDim.new(0, h),
	})
end

function UIKit.gradient(top: Color3, bottom: Color3, rotation: number?): UIGradient
	return UIKit.new("UIGradient", {
		Color = ColorSequence.new(top, bottom),
		Rotation = rotation or 90,
	})
end

function UIKit.list(direction: Enum.FillDirection?, padding: number?, hAlign: Enum.HorizontalAlignment?, vAlign: Enum.VerticalAlignment?): UIListLayout
	return UIKit.new("UIListLayout", {
		FillDirection = direction or Enum.FillDirection.Vertical,
		Padding = UDim.new(0, padding or 8),
		HorizontalAlignment = hAlign or Enum.HorizontalAlignment.Center,
		VerticalAlignment = vAlign or Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
end

function UIKit.textConstraint(maxSize: number, minSize: number?): UITextSizeConstraint
	return UIKit.new("UITextSizeConstraint", { MaxTextSize = maxSize, MinTextSize = minSize or 8 })
end

-- Scaled text label with a dark outline for readability over the 3D world.
function UIKit.text(props: { [string]: any }): TextLabel
	local maxSize = props.MaxTextSize or 48
	props.MaxTextSize = nil
	local outline = props.Outline
	props.Outline = nil
	local label = UIKit.new("TextLabel", {
		BackgroundTransparency = 1,
		Font = UIKit.Fonts.Display,
		TextColor3 = UIKit.Colors.White,
		TextScaled = true,
		Size = UDim2.fromScale(1, 1),
	})
	for key, value in props do
		if key ~= "Parent" then
			(label :: any)[key] = value
		end
	end
	UIKit.textConstraint(maxSize).Parent = label
	if outline ~= false then
		UIKit.textStroke(nil, if typeof(outline) == "number" then outline else 2).Parent = label
	end
	if props.Parent then
		label.Parent = props.Parent
	end
	return label
end

-- Dark translucent panel with neon border.
function UIKit.panel(props: { [string]: any }, accent: Color3?): Frame
	local frame = UIKit.new("Frame", {
		BackgroundColor3 = UIKit.Colors.Panel,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
	})
	for key, value in props do
		if key ~= "Parent" then
			(frame :: any)[key] = value
		end
	end
	UIKit.corner(16).Parent = frame
	UIKit.stroke(accent or UIKit.Colors.Cyan, 2, 0.25).Parent = frame
	UIKit.new("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(170, 175, 200)),
		Rotation = 90,
	}).Parent = frame
	if props.Parent then
		frame.Parent = props.Parent
	end
	return frame
end

local function lighten(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(1, 1, 1), amount)
end

local function darken(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(0, 0, 0), amount)
end

UIKit.lighten = lighten
UIKit.darken = darken

-- Chunky arcade button with press animation. Returns the TextButton.
-- props: Text, Color, Size, Position, AnchorPoint, MaxTextSize, Sub (subtitle text), LayoutOrder, Parent
function UIKit.button(props: { [string]: any }, onClick: (() -> ())?): TextButton
	local color = props.Color or UIKit.Colors.Cyan
	local button = UIKit.new("TextButton", {
		Name = props.Name or "Button",
		AutoButtonColor = false,
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Text = "",
		Size = props.Size or UDim2.fromOffset(160, 56),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		LayoutOrder = props.LayoutOrder or 0,
		Visible = if props.Visible == nil then true else props.Visible,
	})
	UIKit.corner(props.Radius or 14).Parent = button
	UIKit.stroke(darken(color, 0.55), 3, 0).Parent = button
	UIKit.gradient(lighten(color, 0.25), darken(color, 0.2)).Parent = button
	local scale = UIKit.new("UIScale", { Scale = 1, Parent = button })

	local hasSub = props.Sub ~= nil
	UIKit.text({
		Name = "Title",
		Text = props.Text or "",
		Size = if hasSub then UDim2.new(1, -12, 0.58, 0) else UDim2.new(1, -12, 1, -8),
		Position = if hasSub then UDim2.new(0.5, 0, 0.06, 0) else UDim2.fromScale(0.5, 0.5),
		AnchorPoint = if hasSub then Vector2.new(0.5, 0) else Vector2.new(0.5, 0.5),
		MaxTextSize = props.MaxTextSize or 32,
		Font = props.Font or UIKit.Fonts.Display,
		Parent = button,
	})
	if hasSub then
		UIKit.text({
			Name = "Sub",
			Text = props.Sub,
			Size = UDim2.new(1, -12, 0.3, 0),
			Position = UDim2.new(0.5, 0, 0.64, 0),
			AnchorPoint = Vector2.new(0.5, 0),
			MaxTextSize = props.SubMaxTextSize or 20,
			Font = UIKit.Fonts.Bold,
			Parent = button,
		})
	end

	local hoverInfo = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	button.MouseEnter:Connect(function()
		if button.Active then
			TweenService:Create(scale, hoverInfo, { Scale = 1.05 }):Play()
		end
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(scale, hoverInfo, { Scale = 1 }):Play()
	end)
	button.MouseButton1Down:Connect(function()
		if button.Active then
			TweenService:Create(scale, TweenInfo.new(0.06), { Scale = 0.92 }):Play()
		end
	end)
	button.MouseButton1Up:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end)
	if onClick then
		button.Activated:Connect(function()
			if not button.Active then
				return
			end
			if UIKit.ClickSound then
				UIKit.ClickSound()
			end
			onClick()
		end)
	end
	if props.Parent then
		button.Parent = props.Parent
	end
	return button
end

-- Recolours a button made by UIKit.button.
function UIKit.setButtonColor(button: GuiObject, color: Color3)
	button.BackgroundColor3 = color
	local stroke = button:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = darken(color, 0.55)
	end
	local grad = button:FindFirstChildOfClass("UIGradient")
	if grad then
		grad.Color = ColorSequence.new(lighten(color, 0.25), darken(color, 0.2))
	end
end

function UIKit.setButtonText(button: GuiObject, text: string?, sub: string?)
	local title = button:FindFirstChild("Title") :: TextLabel?
	if title and text then
		title.Text = text
	end
	local subLabel = button:FindFirstChild("Sub") :: TextLabel?
	if subLabel and sub then
		subLabel.Text = sub
	end
end

function UIKit.setEnabled(button: GuiButton, enabled: boolean)
	button.Active = enabled
	button.AutoButtonColor = false
	button.BackgroundTransparency = if enabled then 0 else 0.45
end

-- Pops a GuiObject in with an overshoot. Adds/uses a UIScale child.
function UIKit.pop(gui: GuiObject, from: number?, duration: number?)
	local scale = gui:FindFirstChild("PopScale") :: UIScale?
	if not scale then
		scale = UIKit.new("UIScale", { Name = "PopScale", Parent = gui })
	end
	(scale :: UIScale).Scale = from or 0.5
	TweenService:Create(
		scale :: UIScale,
		TweenInfo.new(duration or 0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }
	):Play()
end

-- Quick squash-and-stretch bump, e.g. when a number changes.
function UIKit.bump(gui: GuiObject, amount: number?)
	local scale = gui:FindFirstChild("PopScale") :: UIScale?
	if not scale then
		scale = UIKit.new("UIScale", { Name = "PopScale", Parent = gui })
	end
	(scale :: UIScale).Scale = 1 + (amount or 0.15)
	TweenService:Create(
		scale :: UIScale,
		TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }
	):Play()
end

function UIKit.tween(instance: Instance, duration: number, goals: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): Tween
	local tween = TweenService:Create(
		instance,
		TweenInfo.new(duration, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out),
		goals
	)
	tween:Play()
	return tween
end

-- Number roll-up on a text label. Keeps one roll per label; returns nothing.
local rolling: { [Instance]: NumberValue } = {}
function UIKit.roll(label: TextLabel, from: number, to: number, duration: number, formatter: (number) -> string)
	local existing = rolling[label]
	if existing then
		existing:Destroy()
	end
	if from == to or duration <= 0 then
		label.Text = formatter(to)
		rolling[label] = nil
		return
	end
	local value = Instance.new("NumberValue")
	value.Value = from
	rolling[label] = value
	value.Changed:Connect(function(v)
		label.Text = formatter(v)
	end)
	local tween = TweenService:Create(value, TweenInfo.new(duration, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Value = to })
	tween.Completed:Connect(function()
		if rolling[label] == value then
			rolling[label] = nil
			label.Text = formatter(to)
		end
		value:Destroy()
	end)
	tween:Play()
end

-- Destroys all GuiObject children (keeps layouts/constraints).
function UIKit.clear(container: Instance)
	for _, child in container:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

return UIKit
