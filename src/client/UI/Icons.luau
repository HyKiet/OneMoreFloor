-- Product keys use full-colour uploaded art; navigation icons use the existing Frame drawings.
-- Product Name may be a Fusion state (the depth-priced Extra Life tier).
--
--   scope:Icon { Name = "Gem", Color = colorOrState, Size = UDim2.fromOffset(28, 28) }

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Images = require(ReplicatedStorage.Shared.Images)
local Theme = require(script.Parent.Theme)

local Children = Fusion.Children

type Draw = (scope: any, color: any) -> { Instance }

local STROKE = 0.13 -- line weight as a fraction of the icon box

-- Filled bar centred at (x, y) in scale units.
local function bar(scope, color, x: number, y: number, w: number, h: number, rotation: number?): Instance
	return scope:New "Frame" {
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(x, y),
		Size = UDim2.fromScale(w, h),
		Rotation = rotation or 0,
		[Children] = { scope:New "UICorner" { CornerRadius = UDim.new(0, 1) } },
	}
end

local function dot(scope, color, x: number, y: number, d: number): Instance
	return scope:New "Frame" {
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(x, y),
		Size = UDim2.fromScale(d, d),
		[Children] = { scope:New "UICorner" { CornerRadius = UDim.new(1, 0) } },
	}
end

-- Outline box using a UIStroke (thickness tracks the container via AbsoluteSize ratio).
local function outline(scope, color, x: number, y: number, w: number, h: number, rotation: number?, radius: UDim?): Instance
	return scope:New "Frame" {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(x, y),
		Size = UDim2.fromScale(w, h),
		Rotation = rotation or 0,
		[Children] = {
			scope:New "UICorner" { CornerRadius = radius or UDim.new(0, 2) },
			scope:New "UIStroke" {
				Name = "IconStroke",
				Color = color,
				Thickness = 2,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			},
		},
	}
end

local DRAW: { [string]: Draw } = {
	Up = function(scope, c)
		return {
			bar(scope, c, 0.35, 0.36, 0.42, STROKE, -45),
			bar(scope, c, 0.65, 0.36, 0.42, STROKE, 45),
			bar(scope, c, 0.35, 0.66, 0.42, STROKE, -45),
			bar(scope, c, 0.65, 0.66, 0.42, STROKE, 45),
		}
	end,
	Down = function(scope, c)
		return {
			bar(scope, c, 0.35, 0.34, 0.42, STROKE, 45),
			bar(scope, c, 0.65, 0.34, 0.42, STROKE, -45),
			bar(scope, c, 0.35, 0.64, 0.42, STROKE, 45),
			bar(scope, c, 0.65, 0.64, 0.42, STROKE, -45),
		}
	end,
	Gem = function(scope, c)
		return {
			outline(scope, c, 0.5, 0.5, 0.58, 0.58, 45),
			bar(scope, c, 0.5, 0.5, 0.2, 0.2, 45),
		}
	end,
	Calendar = function(scope, c)
		return {
			outline(scope, c, 0.5, 0.56, 0.78, 0.66),
			bar(scope, c, 0.5, 0.33, 0.78, 0.16),
			bar(scope, c, 0.32, 0.16, STROKE, 0.2),
			bar(scope, c, 0.68, 0.16, STROKE, 0.2),
			bar(scope, c, 0.36, 0.62, 0.14, 0.14),
			bar(scope, c, 0.64, 0.62, 0.14, 0.14),
		}
	end,
	Bag = function(scope, c)
		return {
			outline(scope, c, 0.5, 0.62, 0.74, 0.58),
			bar(scope, c, 0.34, 0.26, STROKE, 0.24),
			bar(scope, c, 0.66, 0.26, STROKE, 0.24),
			bar(scope, c, 0.5, 0.15, 0.32 + STROKE, STROKE),
		}
	end,
	Coin = function(scope, c)
		return {
			dot(scope, c, 0.5, 0.5, 0.92),
			scope:New "TextLabel" {
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.52),
				Size = UDim2.fromScale(0.7, 0.7),
				FontFace = Theme.Font.Heavy,
				Text = "$",
				TextScaled = true,
				TextColor3 = Theme.Color.Ink,
			},
		}
	end,
	Close = function(scope, c)
		return {
			bar(scope, c, 0.5, 0.5, 0.78, STROKE, 45),
			bar(scope, c, 0.5, 0.5, 0.78, STROKE, -45),
		}
	end,
	Check = function(scope, c)
		return {
			bar(scope, c, 0.34, 0.6, 0.34, STROKE, 45),
			bar(scope, c, 0.6, 0.48, 0.6, STROKE, -50),
		}
	end,
	Shield = function(scope, c)
		return {
			bar(scope, c, 0.5, 0.34, 0.7, 0.4),
			bar(scope, c, 0.5, 0.56, 0.5, 0.5, 45),
		}
	end,
	Doc = function(scope, c)
		return {
			outline(scope, c, 0.5, 0.5, 0.62, 0.82),
			bar(scope, c, 0.5, 0.36, 0.34, STROKE * 0.8),
			bar(scope, c, 0.5, 0.52, 0.34, STROKE * 0.8),
			bar(scope, c, 0.44, 0.68, 0.22, STROKE * 0.8),
		}
	end,
	Clover = function(scope, c)
		return {
			dot(scope, c, 0.35, 0.35, 0.36),
			dot(scope, c, 0.65, 0.35, 0.36),
			dot(scope, c, 0.35, 0.65, 0.36),
			dot(scope, c, 0.65, 0.65, 0.36),
		}
	end,
	Person = function(scope, c)
		return {
			dot(scope, c, 0.5, 0.3, 0.36),
			scope:New "Frame" {
				BackgroundColor3 = c,
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.fromScale(0.5, 0.95),
				Size = UDim2.fromScale(0.72, 0.42),
				[Children] = { scope:New "UICorner" { CornerRadius = UDim.new(0.5, 0) } },
			},
		}
	end,
	Home = function(scope, c)
		return {
			bar(scope, c, 0.31, 0.36, 0.5, STROKE, -42),
			bar(scope, c, 0.69, 0.36, 0.5, STROKE, 42),
			outline(scope, c, 0.5, 0.68, 0.5, 0.42),
		}
	end,
	Ticket = function(scope, c)
		return {
			outline(scope, c, 0.5, 0.5, 0.84, 0.54),
			bar(scope, c, 0.64, 0.5, STROKE * 0.7, 0.3),
		}
	end,
	Clock = function(scope, c)
		return {
			outline(scope, c, 0.5, 0.5, 0.82, 0.82, 0, UDim.new(1, 0)),
			bar(scope, c, 0.5, 0.38, STROKE, 0.3),
			bar(scope, c, 0.6, 0.52, 0.24, STROKE, 30),
		}
	end,
	Star = function(scope, c)
		return {
			bar(scope, c, 0.5, 0.5, 0.56, 0.56, 45),
			bar(scope, c, 0.5, 0.5, 0.56, 0.56, 0),
		}
	end,
	Skull = function(scope, c)
		return {
			outline(scope, c, 0.5, 0.5, 0.82, 0.82, 0, UDim.new(1, 0)),
			bar(scope, c, 0.5, 0.5, 0.5, STROKE, 45),
			bar(scope, c, 0.5, 0.5, 0.5, STROKE, -45),
		}
	end,
	Heart = function(scope, c)
		return {
			dot(scope, c, 0.36, 0.38, 0.4),
			dot(scope, c, 0.64, 0.38, 0.4),
			bar(scope, c, 0.5, 0.56, 0.42, 0.42, 45),
		}
	end,
	Curse = function(scope, c)
		return {
			outline(scope, c, 0.5, 0.5, 0.6, 0.6, 45),
			dot(scope, c, 0.5, 0.5, 0.22),
			bar(scope, c, 0.5, 0.1, STROKE, 0.18),
			bar(scope, c, 0.5, 0.9, STROKE, 0.18),
		}
	end,
	Lock = function(scope, c)
		return {
			bar(scope, c, 0.5, 0.66, 0.66, 0.46),
			outline(scope, c, 0.5, 0.36, 0.42, 0.44, 0, UDim.new(0.5, 0)),
		}
	end,
	Diamond = function(scope, c)
		return { bar(scope, c, 0.5, 0.5, 0.6, 0.6, 45) }
	end,
}

local Icons = {}

Icons.Names = {}
for name in DRAW do
	table.insert(Icons.Names, name)
end

function Icons.Icon(scope: any, props: { [string]: any }): GuiObject
	local dynamic = type(props.Name) == "table" and props.Name.type == "State"
	if dynamic or Images[props.Name] then
		return scope:New "ImageLabel" {
			Name = if dynamic then "ProductArt" else "Icon_" .. props.Name,
			BackgroundTransparency = 1,
			Image = scope:Computed(function(use)
				local key = if dynamic then use(props.Name) else props.Name
				return "rbxassetid://" .. tostring(Images[key] or 0)
			end),
			-- Keep the authored colours and native alpha, including on coloured purchase buttons.
			ImageColor3 = Color3.new(1, 1, 1),
			ImageTransparency = props.Transparency or 0,
			ScaleType = Enum.ScaleType.Fit,
			Size = props.Size or UDim2.fromOffset(24, 24),
			Position = props.Position,
			AnchorPoint = props.AnchorPoint,
			LayoutOrder = props.LayoutOrder,
			Rotation = props.Rotation,
			ZIndex = props.ZIndex,
			Visible = props.Visible,
			[Children] = { scope:New "UIAspectRatioConstraint" { AspectRatio = 1 } },
		}
	end
	local draw = DRAW[props.Name] or DRAW.Diamond
	local color = props.Color or Theme.Color.Ivory
	local box = scope:Value(Vector2.new(24, 24))
	local frame = scope:New "Frame" {
		Name = "Icon_" .. tostring(props.Name),
		BackgroundTransparency = 1,
		Size = props.Size or UDim2.fromOffset(24, 24),
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		LayoutOrder = props.LayoutOrder,
		Rotation = props.Rotation,
		ZIndex = props.ZIndex,
		Visible = props.Visible,
		[Fusion.Out "AbsoluteSize"] = box,
		[Children] = {
			scope:New "UIAspectRatioConstraint" { AspectRatio = 1 },
			draw(scope, color),
		},
	}
	-- Outline strokes keep the same visual weight as the filled bars.
	scope:Observer(box):onBind(function()
		local size = Fusion.peek(box)
		local thickness = math.max(1, math.floor(size.X * STROKE * 0.85 + 0.5))
		for _, desc in frame:GetDescendants() do
			if desc:IsA("UIStroke") and desc.Name == "IconStroke" then
				desc.Thickness = thickness
			end
		end
	end)
	return frame
end

return Icons
