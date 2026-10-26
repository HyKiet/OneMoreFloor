-- Always-on HUD. Lobby: cash plate + navigation (left rail on wide screens, top row on phones).
-- Run: floor dial (top-left), phase strip + curses (top-centre), bag plate (top-right).
-- Both: a "GOLDEN HOUR x2 · mm:ss" pill while the server-wide boost runs (under the cash plate in
-- the lobby, under the floor plate in runs) and a short banner naming the buyer when one starts.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Format = require(ReplicatedStorage.Shared.Format)
local Curses = require(ReplicatedStorage.Shared.Curses)
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(script.Parent.Parent.UI.Theme)
local Kit = require(script.Parent.Parent.UI.Kit)
local Screen = require(script.Parent.Screen)
local State = require(script.Parent.State)
local Panels = require(script.Parent.Panels)
local Audio = require(script.Parent.Audio)
local Celebration = require(script.Parent.Celebration)
local Store = require(script.Parent.Parent.Util.Store)

local Children = Fusion.Children
local peek = Fusion.peek
local C = Theme.Color

local Hud = {}

local PHASE = {
	Descending = { Text = "DESCENDING", Color = C.Brass },
	Briefing = { Text = "GET READY", Color = C.Cyan },
	Challenge = { Text = "SURVIVE", Color = C.Red },
	Results = { Text = "FLOOR CLEARED", Color = C.Green },
	Decision = { Text = "DEEPER OR LEAVE", Color = C.Gold },
	Ended = { Text = "RUN OVER", Color = C.Muted },
}

local NAV = {
	{ Panel = "Upgrades", Icon = "Up", Label = "UPGRADES" },
	{ Panel = "Relics", Icon = "Gem", Label = "RELICS" },
	{ Panel = "Daily", Icon = "Calendar", Label = "DAILY" },
	{ Panel = "Shop", Icon = "Bag", Label = "SHOP" },
}

local scope = Fusion.scoped(Fusion, Kit)

local runV = scope:Value(nil :: any)
local dataV = scope:Value(nil :: any)
local inRun = scope:Value(false)
local remaining = scope:Value(0)
local phaseTotal = scope:Value(1)

local layout = Screen.Layout

-- Briefly sets `v` to 1 then back to 0, for spring "bumps".
local function kick(v: any, hold: number?)
	v:set(1)
	task.delay(hold or 0.08, function()
		v:set(0)
	end)
end

-- Lobby ---------------------------------------------------------------------------------------

local function cashPlate()
	local cash = scope:Computed(function(use)
		local d = use(dataV)
		return d and d.Cash or 0
	end)
	local deepest = scope:Computed(function(use)
		local d = use(dataV)
		return d and d.DeepestFloor or 0
	end)
	local bump = scope:Value(0)
	local lastCash = peek(cash)
	scope:Observer(cash):onChange(function()
		local now = peek(cash)
		if now > lastCash then
			kick(bump)
		end
		lastCash = now
	end)

	return scope:Enter {
		Name = "CashPlate",
		Shown = scope:Computed(function(use)
			return not use(inRun)
		end),
		Size = UDim2.fromOffset(250, 62),
		Position = UDim2.fromOffset(12, 10),
		Offset = UDim2.fromOffset(-20, 0),
		Children = {
			scope:Plate {
				Size = UDim2.fromScale(1, 1),
				Accent = C.Brass,
				Children = {
					scope:New "UIScale" {
						Scale = scope:Spring(scope:Computed(function(use)
							return 1 + use(bump) * 0.06
						end), 40, 0.5),
					},
					scope:Icon {
						Name = "Coin",
						Color = C.Gold,
						Size = UDim2.fromOffset(30, 30),
						Position = UDim2.new(0, 14, 0.5, 0),
						AnchorPoint = Vector2.new(0, 0.5),
					},
					scope:Counter {
						Value = cash,
						Format = Format.Cash,
						TextSize = 24,
						Color = C.Ivory,
						XAlign = Enum.TextXAlignment.Left,
						Size = UDim2.new(1, -60, 0, 28),
						Position = UDim2.fromOffset(54, 9),
					},
					scope:Eyebrow {
						Text = scope:Computed(function(use)
							local f = use(deepest)
							return if f > 0 then "DEEPEST  B" .. tostring(f) else "NEVER DESCENDED"
						end),
						TextSize = 10,
						Height = 14,
						Color = C.Muted,
						BulletColor = C.BrassDim,
						Position = UDim2.fromOffset(55, 38),
					},
				},
			},
		},
	}
end

local function navButton(def, index: number)
	local open = scope:Computed(function(use)
		return use(Panels.CurrentValue) == def.Panel
	end)
	local badge = scope:Computed(function(use)
		if def.Panel ~= "Daily" then
			return false
		end
		local d = use(dataV)
		return d ~= nil and d.Daily ~= nil and d.Daily.CanClaim == true
	end)
	local pulse = Kit.Pulse(scope, badge, 1.1)
	local compact = scope:Computed(function(use)
		return use(layout) ~= "Wide"
	end)
	return scope:Button {
		Name = def.Panel,
		Variant = "Outline",
		Direction = "Vertical",
		Icon = def.Icon,
		IconSize = 24,
		Label = scope:Computed(function(use)
			return if use(compact) then "" else def.Label
		end),
		TextSize = 10,
		Gap = 8,
		PadX = 4,
		Accent = scope:Computed(function(use)
			return if use(open) then C.BrassBright else C.Brass
		end),
		Active = open,
		LayoutOrder = index,
		Size = scope:Computed(function(use)
			return if use(compact) then UDim2.fromOffset(62, 62) else UDim2.fromOffset(84, 78)
		end),
		OnClick = function()
			Panels.Toggle(def.Panel)
		end,
		Children = {
			scope:New "Frame" {
				Name = "Badge",
				BackgroundColor3 = C.Gold,
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(1, -9, 0, 9),
				Size = scope:Computed(function(use)
					local s = 8 + use(pulse) * 3
					return UDim2.fromOffset(s, s)
				end),
				Rotation = 45,
				Visible = badge,
				ZIndex = 5,
				[Children] = {
					scope:New "UIStroke" { Color = C.Ink, Thickness = 2 },
				},
			},
		},
	}
end

local function navRail()
	local buttons = {}
	for index, def in NAV do
		table.insert(buttons, navButton(def, index))
	end
	local wide = scope:Computed(function(use)
		return use(layout) == "Wide"
	end)
	return scope:Enter {
		Name = "Nav",
		Shown = scope:Computed(function(use)
			return not use(inRun)
		end),
		Offset = UDim2.fromOffset(-24, 0),
		Size = scope:Computed(function(use)
			return if use(wide) then UDim2.fromOffset(100, 380) else UDim2.fromOffset(300, 72)
		end),
		Position = scope:Computed(function(use)
			return if use(wide) then UDim2.new(0, 12, 0.5, -10) else UDim2.fromOffset(272, 10)
		end),
		AnchorPoint = scope:Computed(function(use)
			return if use(wide) then Vector2.new(0, 0.5) else Vector2.new(0, 0)
		end),
		Children = {
			scope:New "UIListLayout" {
				FillDirection = scope:Computed(function(use)
					return if use(wide) then Enum.FillDirection.Vertical else Enum.FillDirection.Horizontal
				end),
				Padding = UDim.new(0, 10),
				HorizontalAlignment = Enum.HorizontalAlignment.Left,
				VerticalAlignment = scope:Computed(function(use)
					return if use(wide) then Enum.VerticalAlignment.Center else Enum.VerticalAlignment.Top
				end),
				SortOrder = Enum.SortOrder.LayoutOrder,
			},
			scope:New "UIPadding" {
				PaddingLeft = UDim.new(0, 2),
				PaddingTop = UDim.new(0, 2),
			},
			buttons,
		},
	}
end

-- Run HUD -------------------------------------------------------------------------------------

local function you(run)
	return (run and run.You) or {}
end

-- Semicircular floor dial like the lobby's elevator indicators. Five stops per boss cycle; the
-- needle springs to the current stop and the last stop (boss) is red.
local function dial()
	local R = 40
	local stops = Config.BossEvery
	local cycleStop = scope:Computed(function(use)
		local run = use(runV)
		local floor = run and run.Floor or 1
		return ((math.max(floor, 1) - 1) % stops) + 1
	end)
	local angle = scope:Spring(scope:Computed(function(use)
		return -90 + (use(cycleStop) - 1) * (180 / (stops - 1))
	end), 16, 0.45)

	local ticks = {}
	for i = 1, stops do
		local a = math.rad(-180 + (i - 1) * (180 / (stops - 1)))
		local isBoss = i == stops
		table.insert(ticks, scope:New "Frame" {
			Name = "Stop" .. i,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, math.cos(a) * R, 1, math.sin(a) * R),
			Size = UDim2.fromOffset(if isBoss then 4 else 2, if isBoss then 12 else 9),
			Rotation = math.deg(a) + 90,
			BackgroundColor3 = scope:Computed(function(use)
				local passed = use(cycleStop) >= i
				if isBoss then
					return if passed then C.Red else C.Red:Lerp(C.Ink, 0.45)
				end
				return if passed then C.BrassBright else C.BrassDim
			end),
		})
	end
	for i = 0, 16 do
		local a = math.rad(-180 + i * (180 / 16))
		table.insert(ticks, scope:New "Frame" {
			BorderSizePixel = 0,
			BackgroundColor3 = C.BrassDim,
			BackgroundTransparency = 0.4,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, math.cos(a) * (R + 9), 1, math.sin(a) * (R + 9)),
			Size = UDim2.fromOffset(1, 4),
			Rotation = math.deg(a) + 90,
		})
	end

	return scope:New "Frame" {
		Name = "Dial",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(2 * R + 24, R + 14),
		Position = UDim2.new(0.5, 0, 0, 28),
		AnchorPoint = Vector2.new(0.5, 0),
		[Children] = {
			ticks,
			scope:New "Frame" {
				Name = "NeedleHolder",
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 1),
				Size = UDim2.fromOffset(2 * R, 2 * R),
				Rotation = angle,
				[Children] = {
					scope:New "Frame" {
						BorderSizePixel = 0,
						BackgroundColor3 = scope:Computed(function(use)
							return if use(cycleStop) == stops then C.Red else C.Cyan
						end),
						AnchorPoint = Vector2.new(0.5, 1),
						Position = UDim2.fromScale(0.5, 0.5),
						Size = UDim2.fromOffset(2, R - 6),
					},
				},
			},
			scope:New "Frame" {
				Name = "Hub",
				BackgroundColor3 = C.BrassBright,
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 1),
				Size = UDim2.fromOffset(8, 8),
				Rotation = 45,
			},
		},
	}
end

local function floorPlate()
	local floor = scope:Computed(function(use)
		local run = use(runV)
		return run and run.Floor or 0
	end)
	local isBoss = scope:Computed(function(use)
		local run = use(runV)
		return run ~= nil and run.IsBoss == true
	end)
	local floorBump = scope:Value(0)
	scope:Observer(floor):onChange(function()
		kick(floorBump, 0.1)
	end)
	return scope:Plate {
		Name = "FloorPlate",
		Size = UDim2.fromOffset(150, 168),
		Accent = scope:Computed(function(use)
			return if use(isBoss) then C.Red else C.Brass
		end),
		Children = {
			scope:Eyebrow {
				Text = "FLOOR",
				Position = UDim2.new(0.5, 0, 0, 10),
				AnchorPoint = Vector2.new(0.5, 0),
				HAlign = Enum.HorizontalAlignment.Center,
				TextSize = 10,
				Height = 14,
			},
			dial(),
			scope:Text {
				Name = "Floor",
				Text = scope:Computed(function(use)
					return "B" .. tostring(use(floor))
				end),
				Font = Theme.Font.Display,
				TextSize = 34,
				Color = scope:Computed(function(use)
					return if use(isBoss) then C.Red else C.Ivory
				end),
				Size = UDim2.new(1, -16, 0, 40),
				Position = UDim2.new(0.5, 0, 0, 86),
				AnchorPoint = Vector2.new(0.5, 0),
				Children = {
					scope:New "UIScale" {
						Scale = scope:Spring(scope:Computed(function(use)
							return 1 + use(floorBump) * 0.25
						end), 30, 0.45),
					},
				},
			},
			scope:New "Frame" {
				Name = "AliveRow",
				BackgroundTransparency = 1,
				Size = UDim2.new(1, -16, 0, 18),
				Position = UDim2.new(0.5, 0, 0, 134),
				AnchorPoint = Vector2.new(0.5, 0),
				[Children] = {
					scope:New "UIListLayout" {
						FillDirection = Enum.FillDirection.Horizontal,
						HorizontalAlignment = Enum.HorizontalAlignment.Center,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						Padding = UDim.new(0, 6),
						SortOrder = Enum.SortOrder.LayoutOrder,
					},
					scope:Icon { Name = "Person", Color = C.Muted, Size = UDim2.fromOffset(13, 13), LayoutOrder = 1 },
					scope:Text {
						Text = scope:Computed(function(use)
							local run = use(runV)
							return string.format("%d/%d", run and run.Alive or 0, run and run.Total or 0)
						end),
						Font = Theme.Font.Display,
						TextSize = 12,
						Color = C.Muted,
						AutoSize = "X",
						Size = UDim2.fromOffset(0, 18),
						LayoutOrder = 2,
					},
				},
			},
			scope:Tag {
				Text = scope:Computed(function(use)
					local run = use(runV)
					return if run and run.IsBoss then "BOSS FLOOR" else "DAILY"
				end),
				Accent = scope:Computed(function(use)
					local run = use(runV)
					return if run and run.IsBoss then C.Red else C.Magenta
				end),
				Visible = scope:Computed(function(use)
					local run = use(runV)
					return run ~= nil and (run.IsBoss == true or run.Mode == "Daily")
				end),
				Height = 20,
				TextSize = 10,
				Position = UDim2.new(0.5, 0, 1, 8),
				AnchorPoint = Vector2.new(0.5, 0),
			},
		},
	}
end

local function phaseStrip()
	local phase = scope:Computed(function(use)
		local run = use(runV)
		return run and run.Phase or "Descending"
	end)
	local info = scope:Computed(function(use)
		return PHASE[use(phase)] or PHASE.Descending
	end)
	local urgent = scope:Computed(function(use)
		local r = use(remaining)
		return use(phase) == "Challenge" and r <= 3.05 and r > 0
	end)
	local urgentPulse = Kit.Pulse(scope, urgent, 2)
	local color = scope:Computed(function(use)
		return if use(urgent) then C.Red else use(info).Color
	end)
	local smoothColor = scope:Tween(color, Theme.Tween.Fast)
	local curses = scope:Computed(function(use)
		local run = use(runV)
		return (run and run.Curses) or {}
	end)

	return scope:New "Frame" {
		Name = "PhaseStrip",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(380, 110),
		Position = UDim2.new(0.5, 0, 0, 10),
		AnchorPoint = Vector2.new(0.5, 0),
		[Children] = {
			scope:New "UIScale" {
				Scale = scope:Computed(function(use)
					return (if use(layout) == "Wide" then 1 else 0.86) * (1 + use(urgentPulse) * 0.035)
				end),
			},
			scope:Plate {
				Size = UDim2.new(1, 0, 0, 58),
				Accent = smoothColor,
				Children = {
					scope:Eyebrow {
						Text = scope:Computed(function(use)
							return use(info).Text
						end),
						Color = smoothColor,
						TextSize = 13,
						Height = 18,
						Position = UDim2.fromOffset(16, 11),
					},
					scope:Text {
						Name = "Sub",
						Text = scope:Computed(function(use)
							local run = use(runV)
							local challenge = run and run.Challenge
							local p = use(phase)
							if challenge and (p == "Briefing" or p == "Challenge") then
								return string.upper(challenge.Name or "")
							end
							return if run and run.Mode == "Daily" then "DAILY ELEVATOR" else "ONE MORE FLOOR"
						end),
						Font = Theme.Font.Bold,
						TextSize = 13,
						Color = C.Muted,
						XAlign = Enum.TextXAlignment.Left,
						Truncate = Enum.TextTruncate.AtEnd,
						Size = UDim2.new(1, -120, 0, 16),
						Position = UDim2.fromOffset(16, 31),
					},
					scope:Text {
						Name = "Timer",
						Text = scope:Computed(function(use)
							local r = use(remaining)
							return if r > 0 then string.format("%d", math.ceil(r)) else "–"
						end),
						Font = Theme.Font.Display,
						TextSize = 28,
						Color = scope:Computed(function(use)
							return if use(urgent) then C.Red else C.Ivory
						end),
						XAlign = Enum.TextXAlignment.Right,
						Size = UDim2.fromOffset(90, 34),
						Position = UDim2.new(1, -16, 0, 10),
						AnchorPoint = Vector2.new(1, 0),
					},
					scope:Bar {
						Progress = scope:Computed(function(use)
							return use(remaining) / math.max(use(phaseTotal), 0.1)
						end),
						Color = smoothColor,
						Position = UDim2.new(0.5, 0, 1, -7),
						AnchorPoint = Vector2.new(0.5, 1),
						Size = UDim2.new(1, -24, 0, 2),
					},
				},
			},
			scope:New "Frame" {
				Name = "Curses",
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 120, 0, 24),
				Position = UDim2.new(0.5, 0, 0, 68),
				AnchorPoint = Vector2.new(0.5, 0),
				[Children] = {
					scope:New "UIListLayout" {
						FillDirection = Enum.FillDirection.Horizontal,
						HorizontalAlignment = Enum.HorizontalAlignment.Center,
						Padding = UDim.new(0, 6),
						SortOrder = Enum.SortOrder.LayoutOrder,
					},
					scope:ForPairs(curses, function(_use, inner, index, id)
						local curse = Curses.ById[id]
						return index, Kit.Tag(inner, {
							Text = string.upper(curse and curse.Name or tostring(id)),
							Icon = "Curse",
							Accent = C.Violet,
							Height = 22,
							TextSize = 10,
							LayoutOrder = index,
						})
					end),
				},
			},
		},
	}
end

local function bagPlate()
	local dead = scope:Computed(function(use)
		return you(use(runV)).Status == "Dead"
	end)
	local bag = scope:Computed(function(use)
		return you(use(runV)).Bag or 0
	end)
	local bump = scope:Value(0)
	local lastBag = 0
	local lastRunId: string? = nil
	scope:Observer(bag):onChange(function()
		local run = peek(runV)
		local now = peek(bag)
		if run and run.RunId == lastRunId and now > lastBag then
			kick(bump, 0.1)
			Audio.Play("BagGrow")
		end
		lastBag = now
		lastRunId = run and run.RunId
	end)

	local perks = scope:Computed(function(use)
		local y = you(use(runV))
		local list = {}
		if (y.Shields or 0) > 0 then
			table.insert(list, { Icon = "Shield", Text = "x" .. tostring(y.Shields), Accent = C.Cyan })
		end
		if y.Insured then
			table.insert(list, { Icon = "Doc", Text = "INSURED", Accent = C.Green })
		end
		if (y.CharmFloors or 0) > 0 then
			table.insert(list, { Icon = "Clover", Text = tostring(y.CharmFloors), Accent = C.Green })
		end
		return list
	end)

	return scope:Plate {
		Name = "BagPlate",
		Size = UDim2.fromOffset(250, 128),
		Accent = scope:Computed(function(use)
			return if use(dead) then C.Red else C.Gold
		end),
		Children = {
			scope:New "UIScale" {
				Scale = scope:Spring(scope:Computed(function(use)
					return 1 + use(bump) * 0.07
				end), 34, 0.45),
			},
			scope:Eyebrow {
				Text = scope:Computed(function(use)
					return if use(dead) then "ELIMINATED" else "YOUR BAG"
				end),
				Color = scope:Computed(function(use)
					return if use(dead) then C.Red else C.Brass
				end),
				TextSize = 10,
				Height = 14,
				Position = UDim2.fromOffset(16, 12),
			},
			scope:Counter {
				Name = "Bag",
				Value = bag,
				Format = Format.Cash,
				TextSize = 30,
				Color = scope:Computed(function(use)
					return if use(dead) then C.Faint else C.Gold
				end),
				XAlign = Enum.TextXAlignment.Left,
				Size = UDim2.new(1, -28, 0, 36),
				Position = UDim2.fromOffset(15, 30),
			},
			scope:Text {
				Name = "Mult",
				Text = scope:Computed(function(use)
					local run = use(runV)
					if use(dead) then
						return "SPECTATING · VOTE A CURSE"
					end
					return string.format("x%.2f IF YOU CLEAR THE NEXT FLOOR", run and run.Multiplier or Config.Bag.Multiplier)
				end),
				Font = Theme.Font.Bold,
				TextSize = 12,
				Color = scope:Computed(function(use)
					return if use(dead) then C.Violet else C.Cyan
				end),
				XAlign = Enum.TextXAlignment.Left,
				Size = UDim2.new(1, -28, 0, 16),
				Position = UDim2.fromOffset(16, 70),
			},
			scope:New "Frame" {
				Name = "Perks",
				BackgroundTransparency = 1,
				Size = UDim2.new(1, -28, 0, 20),
				Position = UDim2.fromOffset(15, 94),
				[Children] = {
					scope:New "UIListLayout" {
						FillDirection = Enum.FillDirection.Horizontal,
						Padding = UDim.new(0, 6),
						SortOrder = Enum.SortOrder.LayoutOrder,
					},
					scope:ForPairs(perks, function(_use, inner, index, perk)
						return index, Kit.Tag(inner, {
							Text = perk.Text,
							Icon = perk.Icon,
							Accent = perk.Accent,
							Height = 20,
							TextSize = 10,
							LayoutOrder = index,
						})
					end),
				},
			},
		},
	}
end

-- "+$230" rising from the bag plate when a floor is cleared.
local gainLayer: Frame
local function gainPop(amount: number)
	local inner = scope:innerScope()
	local shown = inner:Value(false)
	local label = Kit.Reveal(inner, {
		Shown = shown,
		Size = UDim2.fromOffset(250, 40),
		Position = UDim2.new(1, -12, 0, 148),
		AnchorPoint = Vector2.new(1, 0),
		Offset = UDim2.fromOffset(0, 26),
		HiddenScale = 0.8,
		Speed = 16,
		Children = {
			Kit.Text(inner, {
				Text = "+" .. Format.Cash(amount),
				Font = Theme.Font.Display,
				TextSize = 26,
				Color = C.Gold,
				XAlign = Enum.TextXAlignment.Right,
				Stroke = 2,
			}),
		},
	})
	label.Parent = gainLayer
	shown:set(true)
	task.delay(1.2, function()
		shown:set(false)
		task.delay(0.6, function()
			Fusion.doCleanup(inner)
		end)
	end)
end

local function runHud()
	local wide = scope:Computed(function(use)
		return use(layout) == "Wide"
	end)
	return scope:Enter {
		Name = "RunHud",
		Shown = inRun,
		Offset = UDim2.fromOffset(0, -16),
		Children = {
			scope:New "Frame" {
				Name = "Left",
				BackgroundTransparency = 1,
				Size = UDim2.fromOffset(150, 200),
				Position = UDim2.fromOffset(12, 10),
				[Children] = {
					scope:New "UIScale" {
						Scale = scope:Computed(function(use)
							return if use(wide) then 1 else 0.82
						end),
					},
					floorPlate(),
				},
			},
			phaseStrip(),
			scope:New "Frame" {
				Name = "Right",
				BackgroundTransparency = 1,
				Size = UDim2.fromOffset(250, 128),
				Position = UDim2.new(1, -12, 0, 10),
				AnchorPoint = Vector2.new(1, 0),
				[Children] = {
					scope:New "UIScale" {
						Scale = scope:Computed(function(use)
							return if use(wide) then 1 else 0.86
						end),
					},
					bagPlate(),
				},
			},
		},
	}
end

-- Golden Hour -------------------------------------------------------------------------------

local function goldenPill()
	local active = Store.GoldenActive
	local pulse = Kit.Pulse(scope, active, 0.8)
	return scope:Enter {
		Name = "GoldenHour",
		Shown = active,
		Size = UDim2.fromOffset(250, 30),
		Position = scope:Computed(function(use)
			if not use(inRun) then
				return UDim2.fromOffset(12, 80) -- under the cash plate
			end
			-- under the floor plate (+ its tag), which is scaled down on small screens
			return if use(layout) == "Wide" then UDim2.fromOffset(12, 214) else UDim2.fromOffset(12, 180)
		end),
		Offset = UDim2.fromOffset(-20, 0),
		Children = {
			scope:New "Frame" {
				Name = "Pill",
				BackgroundColor3 = C.Ink,
				BackgroundTransparency = 0.12,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, 30),
				[Children] = {
					scope:New "UICorner" { CornerRadius = UDim.new(0, Theme.Radius) },
					scope:New "UIStroke" {
						Color = C.Gold,
						Thickness = 1,
						Transparency = scope:Computed(function(use)
							return 0.1 + use(pulse) * 0.45
						end),
						ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
					},
					scope:New "UIPadding" { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) },
					scope:New "UIListLayout" {
						FillDirection = Enum.FillDirection.Horizontal,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						Padding = UDim.new(0, 8),
						SortOrder = Enum.SortOrder.LayoutOrder,
					},
					scope:New "Frame" {
						Name = "Bullet",
						BackgroundColor3 = C.Gold,
						BorderSizePixel = 0,
						Size = UDim2.fromOffset(6, 6),
						Rotation = 45,
						LayoutOrder = 1,
					},
					scope:Text {
						Text = "GOLDEN HOUR x" .. tostring(Config.Monetization.GoldenCashMult),
						Font = Theme.Font.Display,
						TextSize = 10,
						Color = C.Gold,
						AutoSize = "X",
						Size = UDim2.new(0, 0, 1, 0),
						LayoutOrder = 2,
					},
					scope:Text {
						Text = "·",
						Font = Theme.Font.Bold,
						TextSize = 14,
						Color = C.BrassDim,
						AutoSize = "X",
						Size = UDim2.new(0, 0, 1, 0),
						LayoutOrder = 3,
					},
					scope:Text {
						Text = scope:Computed(function(use)
							return Store.Clock(use(Store.GoldenLeft))
						end),
						Font = Theme.Font.Display,
						TextSize = 11,
						Color = C.Ivory,
						AutoSize = "X",
						Size = UDim2.new(0, 0, 1, 0),
						LayoutOrder = 4,
					},
				},
			},
		},
	}
end

-- Centre banner when someone starts a Golden Hour: what it does + who to thank.
local function goldenBanner(layer: Frame, by: string)
	local inner = scope:innerScope()
	local shown = inner:Value(false)
	local punch = inner:Spring(inner:Computed(function(use)
		return if use(shown) then 1 else 1.25
	end), 26, 0.6)
	local root = Kit.Reveal(inner, {
		Name = "GoldenBanner",
		Shown = shown,
		Size = UDim2.fromOffset(760, 150),
		Position = UDim2.fromScale(0.5, 0.25),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Offset = UDim2.fromOffset(0, -12),
		HiddenScale = 1,
		Speed = 20,
		Children = {
			inner:New "UIScale" {
				Scale = inner:Computed(function(use)
					return (if use(layout) == "Wide" then 1 else 0.85) * use(punch)
				end),
			},
			-- ink band fading out at both ends, so the banner reads over the world or an open panel
			inner:New "Frame" {
				Name = "Band",
				BackgroundColor3 = C.Ink,
				BackgroundTransparency = 0.2,
				BorderSizePixel = 0,
				Size = UDim2.new(1, 240, 1, 0),
				Position = UDim2.fromScale(0.5, 0.5),
				AnchorPoint = Vector2.new(0.5, 0.5),
				[Children] = {
					inner:New "UIGradient" {
						Transparency = NumberSequence.new({
							NumberSequenceKeypoint.new(0, 1),
							NumberSequenceKeypoint.new(0.22, 0),
							NumberSequenceKeypoint.new(0.78, 0),
							NumberSequenceKeypoint.new(1, 1),
						}),
					},
				},
			},
			inner:New "Frame" {
				Name = "Content",
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				[Children] = {
					inner:New "UIListLayout" {
						Padding = UDim.new(0, 4),
						HorizontalAlignment = Enum.HorizontalAlignment.Center,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						SortOrder = Enum.SortOrder.LayoutOrder,
					},
					Kit.Eyebrow(inner, {
						Text = "SERVER BOOST",
						Color = C.Brass,
						HAlign = Enum.HorizontalAlignment.Center,
						TextSize = 11,
						Stroke = 1.5,
						LayoutOrder = 1,
					}),
					Kit.Text(inner, {
						Text = "GOLDEN HOUR",
						Font = Theme.Font.Display,
						TextSize = 50,
						Color = C.Gold,
						Stroke = 2,
						StrokeTransparency = 0.3,
						Size = UDim2.new(1, 0, 0, 60),
						LayoutOrder = 2,
					}),
					inner:New "Frame" {
						Name = "Rule",
						BackgroundColor3 = C.Gold,
						BorderSizePixel = 0,
						Size = inner:Spring(inner:Computed(function(use)
							return if use(shown) then UDim2.fromOffset(260, 2) else UDim2.fromOffset(0, 2)
						end), 16, 1),
						LayoutOrder = 3,
					},
					Kit.Text(inner, {
						Text = string.format(
							"x%d CASH-OUTS FOR EVERYONE  ·  %d MIN",
							Config.Monetization.GoldenCashMult,
							Config.Monetization.GoldenMinutes
						),
						Font = Theme.Font.Display,
						TextSize = 14,
						Color = C.Ivory,
						Stroke = 1.5,
						Size = UDim2.new(1, 0, 0, 22),
						LayoutOrder = 4,
					}),
					if by ~= ""
						then Kit.Text(inner, {
							Text = "Thanks to " .. by,
							Font = Theme.Font.Bold,
							TextSize = 17,
							Color = C.BrassBright,
							Stroke = 1.5,
							Size = UDim2.new(1, 0, 0, 22),
							LayoutOrder = 5,
						})
						else nil,
				},
			},
		},
	})
	root.Parent = layer
	shown:set(true)
	task.delay(3.4, function()
		shown:set(false)
		task.delay(0.6, function()
			Fusion.doCleanup(inner)
		end)
	end)
end

-- Wiring --------------------------------------------------------------------------------------

local lastPhaseKey = ""

local function onRun(run, old)
	runV:set(run)
	inRun:set(State.InRun())
	if run and run.EndsAt then
		local key = tostring(run.RunId) .. tostring(run.Phase) .. tostring(run.Floor) .. tostring(run.EndsAt)
		if key ~= lastPhaseKey then
			lastPhaseKey = key
			phaseTotal:set(math.max(run.EndsAt - workspace:GetServerTimeNow(), 0.1))
		end
	end
	if run and run.Phase == "Results" and (not old or old.Phase ~= "Results") and run.You and run.You.Status == "Alive" then
		local gain = run.You.LastGain or 0
		if gain > 0 then
			gainPop(gain)
			Audio.Play("Survived")
		end
	end
end

function Hud.Start()
	gainLayer = Screen.Get("Run")

	scope:New "Frame" {
		Name = "LobbyHud",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = Screen.Get("HUD"),
		[Children] = { cashPlate(), navRail(), goldenPill() },
	}
	local overlay = Screen.Get("Overlay")
	Store.OnGoldenStarted(function(by)
		goldenBanner(overlay, by)
		Audio.Play("CashOut")
		-- confetti only in the lobby: mid-challenge it would cover the arena
		if not peek(inRun) then
			Celebration.Confetti(50)
		end
	end)
	runHud().Parent = Screen.Get("Run")

	State.DataChanged:Connect(function(data)
		dataV:set(data)
	end)
	State.RunChanged:Connect(onRun)
	dataV:set(State.Data)
	onRun(State.Run, nil)
	Players.LocalPlayer:GetAttributeChangedSignal("InRun"):Connect(function()
		inRun:set(State.InRun())
	end)

	-- Timer: only ticks while a run is on screen.
	local lastWhole = -1
	RunService.RenderStepped:Connect(function()
		if not peek(inRun) then
			return
		end
		local run = State.Run
		if not run or not run.EndsAt then
			if peek(remaining) ~= 0 then
				remaining:set(0)
			end
			return
		end
		local r = math.max(run.EndsAt - workspace:GetServerTimeNow(), 0)
		remaining:set(r)
		local whole = math.ceil(r)
		if whole ~= lastWhole then
			lastWhole = whole
			if run.Phase == "Challenge" and whole <= 3 and whole > 0 then
				Audio.Play("Countdown", 1.15)
			end
		end
	end)
end

return Hud
