-- Fusion component kit. Every component is `Kit.Name(scope, props)`; controllers create their scope
-- with `Fusion.scoped(Fusion, Kit)` so they can write `scope:Button { ... }`.
--
-- Visual rules (keep new UI consistent):
--   * Panels are ink plates with a brass hairline, an inset second hairline and corner brackets.
--   * Neon colours only signal meaning (see Theme). Text is ivory / muted, numbers use Display.
--   * Motion: springs for scale/position, Theme.Tween.* for colour/transparency, 150–350 ms.

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Theme = require(script.Parent.Theme)
local Icons = require(script.Parent.Icons)

local Children = Fusion.Children
local OnEvent = Fusion.OnEvent
local peek = Fusion.peek

local C = Theme.Color

local Kit = {}

Kit.Icon = Icons.Icon

-- Hooks set by controllers (Audio) so the kit stays dependency-free.
Kit.ClickSound = nil :: (() -> ())?
Kit.HoverSound = nil :: (() -> ())?

-- Resolves a value that may be a state object, inside a Computed.
local function read(use, v)
	if type(v) == "table" and v.type == "State" then
		return use(v)
	end
	return v
end
Kit.read = read

local function isState(v): boolean
	return type(v) == "table" and v.type == "State"
end
Kit.isState = isState

-- Text ----------------------------------------------------------------------------------------

-- props: Text, Font, TextSize, Color, Transparency, XAlign, YAlign, Size, Position, AnchorPoint,
--        AutoSize ("X" | "Y" | "XY"), Wrapped, Rich, Scaled (max size), Stroke (bool), LayoutOrder,
--        ZIndex, Visible, Name, Truncate, Rotation, Children
function Kit.Text(scope: any, props: { [string]: any }): TextLabel
	local auto = props.AutoSize
	local children: { any } = { props.Children }
	if props.Scaled then
		table.insert(children, scope:New "UITextSizeConstraint" { MaxTextSize = props.Scaled, MinTextSize = 8 })
	end
	if props.Stroke then
		table.insert(children, scope:New "UIStroke" {
			Color = C.Ink,
			Thickness = if type(props.Stroke) == "number" then props.Stroke else 1.5,
			Transparency = props.StrokeTransparency or 0.35,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		})
	end
	return scope:New "TextLabel" {
		Name = props.Name or "Text",
		BackgroundTransparency = 1,
		FontFace = props.Font or Theme.Font.Body,
		Text = props.Text or "",
		TextSize = props.TextSize or Theme.Text.Body,
		TextScaled = props.Scaled ~= nil,
		TextColor3 = props.Color or C.Ivory,
		TextTransparency = props.Transparency or 0,
		TextXAlignment = props.XAlign or Enum.TextXAlignment.Center,
		TextYAlignment = props.YAlign or Enum.TextYAlignment.Center,
		TextWrapped = props.Wrapped == true,
		RichText = props.Rich == true,
		TextTruncate = props.Truncate or Enum.TextTruncate.None,
		AutomaticSize = if auto == "X" then Enum.AutomaticSize.X
			elseif auto == "Y" then Enum.AutomaticSize.Y
			elseif auto == "XY" then Enum.AutomaticSize.XY
			else Enum.AutomaticSize.None,
		Size = props.Size or (if auto then UDim2.new() else UDim2.fromScale(1, 1)),
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		LayoutOrder = props.LayoutOrder,
		ZIndex = props.ZIndex,
		Visible = props.Visible,
		Rotation = props.Rotation,
		[Children] = children,
	}
end

-- Small wide-set caps label in Michroma, optionally with a brass diamond bullet.
function Kit.Eyebrow(scope: any, props: { [string]: any }): Frame
	return scope:New "Frame" {
		Name = props.Name or "Eyebrow",
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, props.Height or 16),
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		LayoutOrder = props.LayoutOrder,
		Visible = props.Visible,
		ZIndex = props.ZIndex,
		[Children] = {
			scope:New "UIListLayout" {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				HorizontalAlignment = props.HAlign or Enum.HorizontalAlignment.Left,
				Padding = UDim.new(0, 7),
				SortOrder = Enum.SortOrder.LayoutOrder,
			},
			if props.Bullet == false
				then nil
				else scope:New "Frame" {
					Name = "Bullet",
					BackgroundColor3 = props.BulletColor or props.Color or C.Brass,
					BorderSizePixel = 0,
					Size = UDim2.fromOffset(6, 6),
					Rotation = 45,
					LayoutOrder = 0,
				},
			Kit.Text(scope, {
				Text = props.Text,
				Font = Theme.Font.Display,
				TextSize = props.TextSize or Theme.Text.Eyebrow,
				Color = props.Color or C.Brass,
				Transparency = props.Transparency,
				AutoSize = "X",
				Size = UDim2.fromOffset(0, props.Height or 16),
				LayoutOrder = 1,
				Stroke = props.Stroke,
			}),
		},
	}
end

-- Ornaments -----------------------------------------------------------------------------------

-- Four L-shaped brass brackets hugging the corners of the parent.
function Kit.Brackets(scope: any, props: { [string]: any }?): { Instance }
	props = props or {}
	local color = (props :: any).Color or C.BrassBright
	local len = (props :: any).Length or 12
	local w = (props :: any).Weight or 2
	local inset = (props :: any).Inset or -1
	local transparency = (props :: any).Transparency or 0
	local out = {}
	for _, corner in { Vector2.new(0, 0), Vector2.new(1, 0), Vector2.new(0, 1), Vector2.new(1, 1) } do
		local sx = if corner.X == 0 then 1 else -1
		local sy = if corner.Y == 0 then 1 else -1
		local base = UDim2.new(corner.X, -sx * inset, corner.Y, -sy * inset)
		table.insert(out, scope:New "Frame" {
			Name = "Bracket",
			BackgroundColor3 = color,
			BackgroundTransparency = transparency,
			BorderSizePixel = 0,
			AnchorPoint = corner,
			Position = base,
			Size = UDim2.fromOffset(len, w),
			ZIndex = (props :: any).ZIndex or 3,
		})
		table.insert(out, scope:New "Frame" {
			Name = "Bracket",
			BackgroundColor3 = color,
			BackgroundTransparency = transparency,
			BorderSizePixel = 0,
			AnchorPoint = corner,
			Position = base,
			Size = UDim2.fromOffset(w, len),
			ZIndex = (props :: any).ZIndex or 3,
		})
	end
	return out
end

-- Horizontal rule with a centred diamond:  ───── ◆ ─────
function Kit.Rule(scope: any, props: { [string]: any }): Frame
	local color = props.Color or C.BrassDim
	return scope:New "Frame" {
		Name = "Rule",
		BackgroundTransparency = 1,
		Size = props.Size or UDim2.new(1, 0, 0, 8),
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		LayoutOrder = props.LayoutOrder,
		[Children] = {
			scope:New "Frame" {
				BackgroundColor3 = color,
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.fromScale(0, 0.5),
				Size = UDim2.new(0.5, -9, 0, 1),
			},
			scope:New "Frame" {
				BackgroundColor3 = color,
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.fromScale(1, 0.5),
				Size = UDim2.new(0.5, -9, 0, 1),
			},
			scope:New "Frame" {
				BackgroundColor3 = props.DiamondColor or C.Brass,
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(6, 6),
				Rotation = 45,
			},
		},
	}
end

-- Panels --------------------------------------------------------------------------------------

-- The signature plate: ink fill, brass hairline, inset hairline, corner brackets.
-- props: Accent, Fill (bg transparency), Color, Inset (bool), Brackets (bool), plus layout props
--        and Children. Pass Class = "CanvasGroup" to get a fadeable plate (GroupTransparency).
function Kit.Plate(scope: any, props: { [string]: any }): GuiObject
	local accent = props.Accent or C.Brass
	local class = props.Class or "Frame"
	local plate = scope:New(class) {
		Name = props.Name or "Plate",
		BackgroundColor3 = props.Color or C.Panel,
		BackgroundTransparency = props.Fill or 0.08,
		BorderSizePixel = 0,
		Size = props.Size,
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		LayoutOrder = props.LayoutOrder,
		ZIndex = props.ZIndex,
		Visible = props.Visible,
		AutomaticSize = props.AutomaticSize,
		ClipsDescendants = props.Clips,
		Rotation = props.Rotation,
		GroupTransparency = if class == "CanvasGroup" then props.GroupTransparency else nil,
		[Children] = {
			scope:New "UICorner" { CornerRadius = UDim.new(0, Theme.Radius) },
			scope:New "UIStroke" {
				Name = "Hairline",
				Color = accent,
				Thickness = props.StrokeWeight or 1,
				Transparency = props.StrokeTransparency or 0.2,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			},
			-- top highlight: reads as a bevel without a gradient
			scope:New "Frame" {
				Name = "Bevel",
				BackgroundColor3 = C.Ivory,
				BackgroundTransparency = 0.93,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(2, 2),
				Size = UDim2.new(1, -4, 0, 1),
			},
			if props.Inset == false
				then nil
				else scope:New "Frame" {
					Name = "Inset",
					BackgroundTransparency = 1,
					Position = UDim2.fromOffset(4, 4),
					Size = UDim2.new(1, -8, 1, -8),
					[Children] = {
						scope:New "UICorner" { CornerRadius = UDim.new(0, 2) },
						scope:New "UIStroke" {
							Color = accent,
							Thickness = 1,
							Transparency = 0.78,
							ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
						},
					},
				},
			if props.Brackets == false then nil else Kit.Brackets(scope, { Color = props.BracketColor or accent }),
			props.Children,
		},
	}
	return plate
end

-- Fade + lift wrapper. props.Shown (state bool) drives a spring; the group hides itself when
-- fully transparent so hidden UI costs nothing. Offset is the hidden position delta.
function Kit.Reveal(scope: any, props: { [string]: any }): CanvasGroup
	local shown = props.Shown
	local alphaGoal = scope:Computed(function(use)
		return if use(shown) then 1 else 0
	end)
	local speed = props.Speed or 22
	local alpha = scope:Spring(alphaGoal, speed, props.Damping or 0.85)
	local offset = props.Offset or UDim2.fromOffset(0, 18)
	local position = props.Position or UDim2.new()
	local hiddenScale = props.HiddenScale or 0.97
	return scope:New "CanvasGroup" {
		Name = props.Name or "Reveal",
		BackgroundTransparency = 1,
		Size = props.Size or UDim2.fromScale(1, 1),
		AnchorPoint = props.AnchorPoint,
		ZIndex = props.ZIndex,
		LayoutOrder = props.LayoutOrder,
		Position = scope:Computed(function(use)
			local a = math.clamp(use(alpha), -0.2, 1.2)
			local p = read(use, position)
			return p + UDim2.new(offset.X.Scale * (1 - a), offset.X.Offset * (1 - a), offset.Y.Scale * (1 - a), offset.Y.Offset * (1 - a))
		end),
		GroupTransparency = scope:Computed(function(use)
			return 1 - math.clamp(use(alpha), 0, 1)
		end),
		Visible = scope:Computed(function(use)
			return use(alpha) > 0.01 or use(shown)
		end),
		[Children] = {
			scope:New "UIScale" {
				Scale = scope:Computed(function(use)
					local a = math.clamp(use(alpha), 0, 1.2)
					return hiddenScale + (1 - hiddenScale) * a
				end),
			},
			props.Children,
		},
	}
end

-- Lightweight entrance for list items (no CanvasGroup): slides + scales the body in once
-- props.Shown turns true. Use for rows/cards in scrolling lists.
function Kit.Enter(scope: any, props: { [string]: any }): Frame
	local alpha = scope:Spring(scope:Computed(function(use)
		return if use(props.Shown) then 1 else 0
	end), props.Speed or 24, props.Damping or 0.78)
	local offset = props.Offset or UDim2.fromOffset(0, 16)
	return scope:New "Frame" {
		Name = props.Name or "Enter",
		BackgroundTransparency = 1,
		Size = props.Size or UDim2.fromScale(1, 1),
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		LayoutOrder = props.LayoutOrder,
		[Children] = {
			scope:New "Frame" {
				Name = "Body",
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				Position = scope:Computed(function(use)
					local k = 1 - use(alpha)
					return UDim2.new(offset.X.Scale * k, offset.X.Offset * k, offset.Y.Scale * k, offset.Y.Offset * k)
				end),
				Visible = scope:Computed(function(use)
					return use(alpha) > 0.02
				end),
				[Children] = {
					scope:New "UIScale" {
						Scale = scope:Computed(function(use)
							return 0.95 + 0.05 * math.clamp(use(alpha), 0, 1.1)
						end),
					},
					props.Children,
				},
			},
		},
	}
end

-- Buttons -------------------------------------------------------------------------------------

local function selectionImage(scope: any, accent: any): Frame
	return scope:New "Frame" {
		Name = "Selection",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 10, 1, 10),
		Position = UDim2.fromOffset(-5, -5),
		[Children] = {
			scope:New "UICorner" { CornerRadius = UDim.new(0, Theme.Radius + 2) },
			scope:New "UIStroke" { Color = accent, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border },
		},
	}
end

-- props: Label, Sub, Icon, IconSize, Accent, Variant ("Solid" | "Outline" | "Ghost"), Enabled,
--        Active (state: draws as pressed/locked), OnClick, TextSize, SubSize, Font, Hint (KeyCode
--        hint text shown on Mouse input), GamepadHint (KeyCode), Direction ("Horizontal" |
--        "Vertical"), plus layout props, Name, Children, Selectable, NextSelection*.
function Kit.Button(scope: any, props: { [string]: any }): TextButton
	local accent = props.Accent or C.Brass
	local variant = props.Variant or "Outline"
	local enabled = if props.Enabled == nil then true else props.Enabled
	local active = props.Active or false
	local hovered = scope:Value(false)
	local pressed = scope:Value(false)

	local scaleGoal = scope:Computed(function(use)
		if not read(use, enabled) then
			return 1
		end
		if use(pressed) then
			return 0.95
		elseif use(hovered) then
			return 1.035
		end
		return 1
	end)
	local scale = scope:Spring(scaleGoal, 38, 0.62)

	local heat = scope:Spring(scope:Computed(function(use)
		if not read(use, enabled) then
			return 0
		end
		if read(use, active) then
			return 1
		end
		return if use(pressed) then 1 elseif use(hovered) then 0.7 else 0
	end), 30, 1)

	local accentColor = scope:Computed(function(use)
		return if read(use, enabled) then read(use, accent) else C.Faint
	end)

	local fillColor = scope:Computed(function(use)
		local a = use(accentColor)
		local h = math.clamp(use(heat), 0, 1)
		if variant == "Primary" then
			if not read(use, enabled) then
				return C.Panel2
			end
			return a:Lerp(C.Ink, 0.12 - 0.12 * h)
		elseif variant == "Solid" then
			return C.Panel2:Lerp(a, 0.2 + 0.14 * h)
		elseif variant == "Ghost" then
			return C.Panel:Lerp(a, 0.12 * h)
		end
		return C.Panel:Lerp(a, 0.1 + 0.16 * h)
	end)

	local labelColor = scope:Computed(function(use)
		if not read(use, enabled) then
			return C.Muted:Lerp(C.Faint, 0.4)
		end
		if variant == "Primary" then
			return C.Ink
		end
		if variant == "Ghost" then
			return C.Ivory:Lerp(use(accentColor), 0.25)
		end
		return C.Ivory
	end)

	local horizontal = props.Direction ~= "Vertical"
	local hasSub = props.Sub ~= nil
	local content: { any } = {}

	if props.Icon then
		table.insert(content, Kit.Icon(scope, {
			Name = props.Icon,
			Color = scope:Computed(function(use)
				if not read(use, enabled) then
					return C.Faint
				elseif variant == "Primary" then
					return C.Ink
				end
				return if variant == "Ghost" then use(accentColor) else C.Ivory:Lerp(use(accentColor), 0.35)
			end),
			Size = UDim2.fromOffset(props.IconSize or 22, props.IconSize or 22),
			LayoutOrder = 0,
		}))
	end
	if props.Label then
		local labelBlock = scope:New "Frame" {
			Name = "LabelBlock",
			BackgroundTransparency = 1,
			AutomaticSize = Enum.AutomaticSize.XY,
			Size = UDim2.new(),
			LayoutOrder = 1,
			[Children] = {
				scope:New "UIListLayout" {
					FillDirection = Enum.FillDirection.Vertical,
					HorizontalAlignment = if horizontal and props.Icon then Enum.HorizontalAlignment.Left else Enum.HorizontalAlignment.Center,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, 2),
					SortOrder = Enum.SortOrder.LayoutOrder,
				},
				Kit.Text(scope, {
					Name = "Label",
					Text = props.Label,
					Font = props.Font or Theme.Font.Display,
					TextSize = props.TextSize or 16,
					Color = labelColor,
					AutoSize = "XY",
					LayoutOrder = 1,
				}),
				if hasSub
					then Kit.Text(scope, {
						Name = "Sub",
						Text = props.Sub,
						Font = Theme.Font.Bold,
						TextSize = props.SubSize or 14,
						Color = scope:Computed(function(use)
							if props.SubColor then
								return read(use, props.SubColor)
							end
							return if read(use, enabled) then C.Muted else C.Faint
						end),
						AutoSize = "XY",
						LayoutOrder = 2,
						Rich = true,
					})
					else nil,
			},
		}
		table.insert(content, labelBlock)
	end

	local hint = nil
	if props.Hint or props.GamepadHint then
		hint = Kit.KeyHint(scope, {
			Key = props.Hint,
			Gamepad = props.GamepadHint,
			Position = UDim2.new(1, -6, 0, 6),
			AnchorPoint = Vector2.new(1, 0),
			ZIndex = 4,
		})
	end

	local button
	button = scope:New "TextButton" {
		Name = props.Name or "Button",
		AutoButtonColor = false,
		Text = "",
		BackgroundColor3 = scope:Tween(fillColor, Theme.Tween.Fast),
		BackgroundTransparency = if variant == "Ghost" then 0.4 else 0.04,
		BorderSizePixel = 0,
		Size = props.Size or UDim2.fromOffset(180, 52),
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		LayoutOrder = props.LayoutOrder,
		ZIndex = props.ZIndex,
		Visible = props.Visible,
		AutomaticSize = props.AutomaticSize,
		Selectable = scope:Computed(function(use)
			return read(use, enabled) and props.Selectable ~= false
		end),
		SelectionImageObject = selectionImage(scope, accentColor),
		NextSelectionLeft = props.NextSelectionLeft,
		NextSelectionRight = props.NextSelectionRight,
		NextSelectionUp = props.NextSelectionUp,
		NextSelectionDown = props.NextSelectionDown,

		[OnEvent "MouseEnter"] = function()
			hovered:set(true)
			if peek(enabled) ~= false and Kit.HoverSound then
				Kit.HoverSound()
			end
		end,
		[OnEvent "MouseLeave"] = function()
			hovered:set(false)
			pressed:set(false)
		end,
		[OnEvent "SelectionGained"] = function()
			hovered:set(true)
		end,
		[OnEvent "SelectionLost"] = function()
			hovered:set(false)
		end,
		[OnEvent "MouseButton1Down"] = function()
			pressed:set(true)
		end,
		[OnEvent "MouseButton1Up"] = function()
			pressed:set(false)
		end,
		[OnEvent "Activated"] = function()
			pressed:set(false)
			local isEnabled = if isState(enabled) then peek(enabled) else enabled
			if not isEnabled then
				return
			end
			if Kit.ClickSound then
				Kit.ClickSound()
			end
			if props.OnClick then
				props.OnClick()
			end
		end,

		[Children] = {
			scope:New "UICorner" { CornerRadius = UDim.new(0, Theme.Radius) },
			scope:New "UIScale" { Scale = scale },
			scope:New "UIStroke" {
				Color = accentColor,
				Thickness = scope:Computed(function(use)
					return 1 + math.clamp(use(heat), 0, 1) * 1.2
				end),
				Transparency = scope:Computed(function(use)
					if variant == "Ghost" then
						return 0.75 - 0.5 * math.clamp(use(heat), 0, 1)
					end
					return 0.3 - 0.3 * math.clamp(use(heat), 0, 1)
				end),
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			},
			if variant == "Ghost"
				then nil
				else scope:New "Frame" {
					Name = "Inset",
					BackgroundTransparency = 1,
					Position = UDim2.fromOffset(3, 3),
					Size = UDim2.new(1, -6, 1, -6),
					[Children] = {
						scope:New "UICorner" { CornerRadius = UDim.new(0, 2) },
						scope:New "UIStroke" {
							Color = accentColor,
							Transparency = 0.8,
							Thickness = 1,
							ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
						},
					},
				},
			scope:New "Frame" {
				Name = "Content",
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				[Children] = {
					scope:New "UIListLayout" {
						FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical,
						HorizontalAlignment = Enum.HorizontalAlignment.Center,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						Padding = UDim.new(0, props.Gap or 10),
						SortOrder = Enum.SortOrder.LayoutOrder,
					},
					scope:New "UIPadding" {
						PaddingLeft = UDim.new(0, props.PadX or 12),
						PaddingRight = UDim.new(0, props.PadX or 12),
					},
					content,
				},
			},
			hint,
			props.Children,
		},
	}
	return button
end

-- Square icon button (close, nav). props: Icon, Accent, Size, OnClick, ...
function Kit.IconButton(scope: any, props: { [string]: any }): TextButton
	local p = table.clone(props)
	p.Label = nil
	p.PadX = 0
	p.Size = props.Size or UDim2.fromOffset(44, 44)
	p.IconSize = props.IconSize or 18
	return Kit.Button(scope, p)
end

-- Key / gamepad hint chip: shows `Key` (string) on mouse+keyboard and the gamepad glyph on pads.
function Kit.KeyHint(scope: any, props: { [string]: any }): Frame
	local Screen = require(script.Parent.Parent.Controllers.Screen)
	local input = Screen.Input
	return scope:New "Frame" {
		Name = "KeyHint",
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 0.2,
		Size = UDim2.fromOffset(22, 22),
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		ZIndex = props.ZIndex,
		LayoutOrder = props.LayoutOrder,
		Visible = scope:Computed(function(use)
			local kind = use(input)
			return (kind == "Mouse" and props.Key ~= nil) or (kind == "Gamepad" and props.Gamepad ~= nil)
		end),
		[Children] = {
			scope:New "UICorner" { CornerRadius = UDim.new(0, 3) },
			scope:New "UIStroke" { Color = C.BrassDim, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border },
			Kit.Text(scope, {
				Text = props.Key or "",
				Font = Theme.Font.Heavy,
				TextSize = 13,
				Color = C.Muted,
				Visible = scope:Computed(function(use)
					return use(input) ~= "Gamepad"
				end),
			}),
			scope:New "ImageLabel" {
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				Image = if props.Gamepad then UserInputService:GetImageForKeyCode(props.Gamepad) else "",
				Visible = scope:Computed(function(use)
					return use(input) == "Gamepad"
				end),
			},
		},
	}
end

-- Data display --------------------------------------------------------------------------------

-- Number that tweens to its target. props.Value: number state; props.Format: (number) -> string.
function Kit.Counter(scope: any, props: { [string]: any }): TextLabel
	local tweened = scope:Tween(props.Value, props.TweenInfo or Theme.Tween.Count)
	local format = props.Format or function(n)
		return tostring(math.floor(n + 0.5))
	end
	local p = table.clone(props)
	p.Text = scope:Computed(function(use)
		return format(use(tweened))
	end)
	p.Value = nil
	p.Format = nil
	p.TweenInfo = nil
	p.Font = props.Font or Theme.Font.Display
	return Kit.Text(scope, p)
end

-- Thin progress bar. props.Progress: 0..1 state, Color, Height.
function Kit.Bar(scope: any, props: { [string]: any }): Frame
	return scope:New "Frame" {
		Name = props.Name or "Bar",
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		Size = props.Size or UDim2.new(1, 0, 0, props.Height or 4),
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		LayoutOrder = props.LayoutOrder,
		ZIndex = props.ZIndex,
		[Children] = {
			scope:New "Frame" {
				Name = "Fill",
				BackgroundColor3 = props.Color or C.Brass,
				BorderSizePixel = 0,
				Size = scope:Computed(function(use)
					return UDim2.fromScale(math.clamp(read(use, props.Progress) or 0, 0, 1), 1)
				end),
				ZIndex = props.ZIndex,
			},
		},
	}
end

-- Segmented level meter. props.Level, props.Max (numbers or states), Color.
function Kit.Pips(scope: any, props: { [string]: any }): Frame
	return scope:New "Frame" {
		Name = "Pips",
		BackgroundTransparency = 1,
		Size = props.Size or UDim2.fromOffset(150, 8),
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		LayoutOrder = props.LayoutOrder,
		[Children] = {
			scope:New "UIListLayout" {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, 3),
				SortOrder = Enum.SortOrder.LayoutOrder,
				VerticalAlignment = Enum.VerticalAlignment.Center,
			},
			scope:Computed(function(use, inner)
				local max = read(use, props.Max) or 1
				local level = read(use, props.Level) or 0
				local list = {}
				for i = 1, max do
					table.insert(list, inner:New "Frame" {
						BackgroundColor3 = if i <= level then (props.Color or C.Cyan) else C.Line,
						BorderSizePixel = 0,
						Size = UDim2.new(1 / max, -3, 1, 0),
						LayoutOrder = i,
					})
				end
				return list
			end),
		},
	}
end

-- Small tag: coloured hairline box with caps text. props.Text, Accent, Icon.
function Kit.Tag(scope: any, props: { [string]: any }): Frame
	local accent = props.Accent or C.Brass
	return scope:New "Frame" {
		Name = props.Name or "Tag",
		BackgroundColor3 = scope:Computed(function(use)
			return C.Ink:Lerp(read(use, accent), 0.18)
		end),
		BackgroundTransparency = 0.1,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, props.Height or 24),
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		LayoutOrder = props.LayoutOrder,
		Visible = props.Visible,
		ZIndex = props.ZIndex,
		Rotation = props.Rotation,
		[Children] = {
			scope:New "UICorner" { CornerRadius = UDim.new(0, 2) },
			scope:New "UIStroke" { Color = accent, Thickness = 1, Transparency = 0.15, ApplyStrokeMode = Enum.ApplyStrokeMode.Border },
			scope:New "UIPadding" { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 9) },
			scope:New "UIListLayout" {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 6),
				SortOrder = Enum.SortOrder.LayoutOrder,
			},
			if props.Icon
				then Kit.Icon(scope, { Name = props.Icon, Color = accent, Size = UDim2.fromOffset(12, 12), LayoutOrder = 0 })
				else nil,
			Kit.Text(scope, {
				Text = props.Text,
				Font = props.Font or Theme.Font.Display,
				TextSize = props.TextSize or 11,
				Color = props.TextColor or C.Ivory,
				AutoSize = "X",
				Size = UDim2.new(0, 0, 1, 0),
				LayoutOrder = 1,
			}),
		},
	}
end

-- Helpers -------------------------------------------------------------------------------------

-- Pulse 0..1 while `on` is true (sine), else 0. Cheap: a Value updated from Heartbeat only
-- while enabled. Returns the state.
function Kit.Pulse(scope: any, on: any, hz: number?): any
	local RunService = game:GetService("RunService")
	local value = scope:Value(0)
	local connection: RBXScriptConnection? = nil
	local function stop()
		if connection then
			connection:Disconnect()
			connection = nil
		end
		value:set(0)
	end
	scope:Observer(on):onBind(function()
		if peek(on) then
			if not connection then
				local t0 = os.clock()
				connection = RunService.Heartbeat:Connect(function()
					value:set(0.5 + 0.5 * math.sin((os.clock() - t0) * math.pi * 2 * (hz or 1.2)))
				end)
			end
		else
			stop()
		end
	end)
	table.insert(scope, stop)
	return value
end

-- Moves gamepad selection onto `object` if a gamepad is in use.
function Kit.Select(object: GuiObject?)
	local Screen = require(script.Parent.Parent.Controllers.Screen)
	if peek(Screen.Input) == "Gamepad" then
		GuiService.SelectedObject = object
	end
end

return Kit
