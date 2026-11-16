-- Lobby panels in one modal with tabs: Upgrades, Relics (codex + equip), Daily streak, Shop.
-- Opened by ProximityPrompts (prompt or parent with a "Panel" attribute), the server's OpenPanel
-- event and the HUD navigation. Gamepad: first control is selected on open, B closes.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Net = require(ReplicatedStorage.Shared.Net)
local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Relics = require(ReplicatedStorage.Shared.Relics)
local Rarity = require(ReplicatedStorage.Shared.Rarity)
local Upgrades = require(ReplicatedStorage.Shared.Upgrades)
local Theme = require(script.Parent.Parent.UI.Theme)
local Kit = require(script.Parent.Parent.UI.Kit)
local RelicModel = require(script.Parent.Parent.Util.RelicModel)
local Store = require(script.Parent.Parent.Util.Store)
local Screen = require(script.Parent.Screen)
local State = require(script.Parent.State)
local Toast = require(script.Parent.Toast)
local Audio = require(script.Parent.Audio)

local Children = Fusion.Children
local OnEvent = Fusion.OnEvent
local Out = Fusion.Out
local peek = Fusion.peek
local C = Theme.Color
local M = Config.Monetization

local Panels = {}

local PAGES = {
	{ Id = "Upgrades", Title = "UPGRADES", Icon = "Up", Tagline = "Permanent perks, paid in banked cash" },
	{ Id = "Relics", Title = "RELIC VAULT", Icon = "Gem", Tagline = "Equip relics to bend the odds" },
	{ Id = "Daily", Title = "DAILY REWARD", Icon = "Calendar", Tagline = "Come back every day to grow your streak" },
	-- PhoneLayout: on phones the modal fills the screen and is zoomed for readable text (see buildModal);
	-- the page lays itself out for a ~430 px wide canvas in portrait.
	{ Id = "Shop", Title = "SHOP", Icon = "Bag", Tagline = "Support the hotel, ride in style", PhoneLayout = true },
}

local PORTRAIT_WIDTH = 430 -- virtual width of a phone-layout page in portrait (then zoomed to the screen)
local COMPACT_ZOOM = 1.2 -- phone-layout pages on landscape phones
local PAGE_BY_ID = {}
for _, page in PAGES do
	PAGE_BY_ID[page.Id] = page
end

local UPGRADE_ICONS = {
	Insurance = "Doc",
	Greed = "Coin",
	Luck = "Clover",
	Agility = "Up",
	Shield = "Shield",
	Slots = "Gem",
}

local scope = Fusion.scoped(Fusion, Kit)

local current = scope:Value(nil :: string?)
local shown = scope:Value(false)
local dataV = scope:Value(nil :: any)
local selectedRelic = scope:Value(nil :: string?)

Panels.CurrentValue = scope:Computed(function(use)
	return if use(shown) then use(current) else nil
end)

local listeners: { (string?) -> () } = {}

function Panels.OnChanged(fn: (string?) -> ())
	table.insert(listeners, fn)
end

local function notify()
	for _, fn in listeners do
		task.spawn(fn, peek(current))
	end
end

local EMPTY_DATA = {
	Cash = 0,
	Upgrades = {},
	Relics = {},
	Equipped = {},
	Slots = Config.BaseRelicSlots,
	Daily = { Streak = 0, CanClaim = false, NextReward = 0 },
	Passes = {},
}

local function getData(use): any
	return use(dataV) or EMPTY_DATA
end

local function rarityColor(name: string): Color3
	return (Rarity.Info[name] or Rarity.Info.Common).Color
end

-- Stat text ----------------------------------------------------------------------------------

local function pct(v: number): string
	return string.format("%d%%", math.floor(v * 100 + 0.5))
end

local STAT_TEXT = {
	WalkSpeed = function(v)
		return "+" .. pct(v) .. " walk speed"
	end,
	Jump = function(v)
		return "+" .. pct(v) .. " jump power"
	end,
	Gravity = function(v)
		return "-" .. pct(v) .. " gravity"
	end,
	BagMult = function(v)
		return string.format("+%.3f bag multiplier", v)
	end,
	CashOut = function(v)
		return "+" .. pct(v) .. " cash when you leave"
	end,
	PickupRadius = function(v)
		return "+" .. pct(v) .. " pickup radius"
	end,
	RelicChance = function(v)
		return "+" .. pct(v) .. " relic chance"
	end,
	Insurance = function(v)
		return "Keep " .. pct(v) .. " of your bag on death"
	end,
	Shields = function(v)
		return string.format("+%d shield every run", v)
	end,
	Revive = function(v)
		return pct(v) .. " chance to shrug off death"
	end,
	DoubleJump = function()
		return "Double jump"
	end,
	CoinValue = function(v)
		return "+" .. pct(v) .. " coin value"
	end,
}

function Panels.StatLines(stats: { [string]: number }): { string }
	local lines = {}
	for stat, value in stats do
		local fn = STAT_TEXT[stat]
		if fn and value ~= 0 then
			table.insert(lines, fn(value))
		end
	end
	table.sort(lines)
	return lines
end

local function upgradeEffect(id: string, level: number): string
	local value = Upgrades.Value(id, level)
	if id == "Insurance" then
		return "Keep " .. pct(value)
	elseif id == "Greed" then
		return string.format("+%.2f / floor", value)
	elseif id == "Luck" or id == "Agility" then
		return "+" .. pct(value)
	end
	return "+" .. tostring(math.floor(value))
end

-- Shared pieces ------------------------------------------------------------------------------

-- Value that flips true after `delay` seconds (staggered entrances).
local function after(inner: any, delay: number): any
	local v = inner:Value(false)
	local alive = true
	table.insert(inner, function()
		alive = false
	end)
	task.delay(delay, function()
		if alive then
			v:set(true)
		end
	end)
	return v
end

local function scroller(inner: any, props: { [string]: any }): ScrollingFrame
	return inner:New "ScrollingFrame" {
		Name = props.Name or "Scroll",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = props.Size or UDim2.fromScale(1, 1),
		Position = props.Position,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = C.BrassDim,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
		SelectionGroup = true,
		[Children] = {
			inner:New "UIPadding" {
				PaddingTop = UDim.new(0, 4),
				PaddingBottom = UDim.new(0, 10),
				PaddingLeft = UDim.new(0, 2),
				PaddingRight = UDim.new(0, 8),
			},
			props.Children,
		},
	}
end

-- Flat inner card used for rows and tiles (plates inside plates get one hairline only).
local function card(inner: any, props: { [string]: any }): Frame
	return inner:New(props.Class or "Frame") {
		Name = props.Name or "Card",
		BackgroundColor3 = props.Color or C.Panel2,
		BackgroundTransparency = props.Fill or 0.15,
		BorderSizePixel = 0,
		Size = props.Size,
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		LayoutOrder = props.LayoutOrder,
		AutomaticSize = props.AutomaticSize,
		AutoButtonColor = if props.Class == "TextButton" then false else nil,
		Text = if props.Class == "TextButton" then "" else nil,
		[OnEvent "Activated"] = props.OnClick,
		[Children] = {
			inner:New "UICorner" { CornerRadius = UDim.new(0, Theme.Radius) },
			inner:New "UIStroke" {
				Color = props.Accent or C.Line,
				Thickness = props.StrokeWeight or 1,
				Transparency = props.StrokeTransparency or 0,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			},
			props.Children,
		},
	}
end

-- Upgrades -----------------------------------------------------------------------------------

local function upgradeRow(inner: any, upgrade, index: number): GuiObject
	local level = inner:Computed(function(use)
		local d = getData(use)
		return (d.Upgrades and d.Upgrades[upgrade.Id]) or 0
	end)
	local cost = inner:Computed(function(use)
		return Upgrades.CostFor(upgrade.Id, use(level)) or -1
	end)
	local cash = inner:Computed(function(use)
		return getData(use).Cash or 0
	end)
	local maxed = inner:Computed(function(use)
		return use(cost) < 0
	end)
	local affordable = inner:Computed(function(use)
		return not use(maxed) and use(cash) >= use(cost)
	end)

	return Kit.Enter(inner, {
		Name = upgrade.Id,
		Shown = after(inner, 0.03 * index),
		Size = UDim2.new(1, 0, 0, 92),
		LayoutOrder = index,
		Offset = UDim2.fromOffset(0, 14),
		Children = {
			card(inner, {
				Size = UDim2.fromScale(1, 1),
				Children = {
					inner:New "Frame" {
						Name = "IconBox",
						BackgroundColor3 = C.Ink,
						BackgroundTransparency = 0.2,
						Size = UDim2.fromOffset(56, 56),
						Position = UDim2.new(0, 16, 0.5, 0),
						AnchorPoint = Vector2.new(0, 0.5),
						Rotation = 0,
						[Children] = {
							inner:New "UICorner" { CornerRadius = UDim.new(0, Theme.Radius) },
							inner:New "UIStroke" { Color = C.BrassDim, Thickness = 1 },
							Kit.Icon(inner, {
								Name = UPGRADE_ICONS[upgrade.Id] or "Diamond",
								Color = inner:Computed(function(use)
									return if use(level) > 0 then C.BrassBright else C.Brass
								end),
								Size = UDim2.fromOffset(26, 26),
								Position = UDim2.fromScale(0.5, 0.5),
								AnchorPoint = Vector2.new(0.5, 0.5),
							}),
						},
					},
					Kit.Text(inner, {
						Text = string.upper(upgrade.Name),
						Font = Theme.Font.Display,
						TextSize = 15,
						XAlign = Enum.TextXAlignment.Left,
						Size = UDim2.new(1, -300, 0, 20),
						Position = UDim2.fromOffset(88, 14),
					}),
					Kit.Text(inner, {
						Text = upgrade.Desc,
						Font = Theme.Font.Body,
						TextSize = 15,
						Color = C.Muted,
						XAlign = Enum.TextXAlignment.Left,
						Truncate = Enum.TextTruncate.AtEnd,
						Size = UDim2.new(1, -300, 0, 18),
						Position = UDim2.fromOffset(88, 37),
					}),
					Kit.Pips(inner, {
						Level = level,
						Max = upgrade.Max,
						Color = C.Cyan,
						Size = UDim2.new(0, math.min(upgrade.Max * 18, 180), 0, 6),
						Position = UDim2.fromOffset(89, 64),
					}),
					Kit.Text(inner, {
						Text = inner:Computed(function(use)
							local l = use(level)
							if use(maxed) then
								return string.format("LV %d · %s", l, upgradeEffect(upgrade.Id, l))
							end
							return string.format("LV %d  →  %s", l, upgradeEffect(upgrade.Id, l + 1))
						end),
						Font = Theme.Font.Bold,
						TextSize = 13,
						Color = C.Cyan,
						XAlign = Enum.TextXAlignment.Left,
						Size = UDim2.fromOffset(200, 16),
						Position = UDim2.new(0, 89 + math.min(upgrade.Max * 18, 180) + 12, 0, 59),
					}),
					Kit.Button(inner, {
						Name = "Buy",
						Variant = "Primary",
						Accent = C.Gold,
						Enabled = affordable,
						SubColor = inner:Computed(function(use)
							return if use(affordable) then C.Ink else C.Red:Lerp(C.Muted, 0.35)
						end),
						Label = inner:Computed(function(use)
							return if use(maxed) then "MAXED" else Format.Cash(use(cost))
						end),
						Sub = inner:Computed(function(use)
							if use(maxed) then
								return "fully upgraded"
							elseif use(affordable) then
								return "buy level " .. tostring(use(level) + 1)
							end
							return "need " .. Format.Cash(use(cost) - use(cash)) .. " more"
						end),
						TextSize = 17,
						SubSize = 12,
						Size = UDim2.fromOffset(170, 60),
						Position = UDim2.new(1, -16, 0.5, 0),
						AnchorPoint = Vector2.new(1, 0.5),
						OnClick = function()
							if peek(maxed) then
								return
							end
							Net.Event("BuyUpgrade"):FireServer(upgrade.Id)
							Audio.Play("Purchase")
						end,
					}),
				},
			}),
		},
	})
end

local function buildUpgrades(inner: any): { Instance }
	local rows = {}
	for index, upgrade in Upgrades.List do
		table.insert(rows, upgradeRow(inner, upgrade, index))
	end
	return {
		scroller(inner, {
			Children = {
				inner:New "UIListLayout" {
					Padding = UDim.new(0, 10),
					SortOrder = Enum.SortOrder.LayoutOrder,
				},
				rows,
			},
		}),
	}
end

-- Relics -------------------------------------------------------------------------------------

local function equippedSlotOf(d, relicId: string): number?
	for slot, id in d.Equipped or {} do
		if id == relicId then
			return slot
		end
	end
	return nil
end

local function toggleEquip(relicId: string)
	local d = peek(dataV) or EMPTY_DATA
	if not (d.Relics and d.Relics[relicId]) then
		return
	end
	local slot = equippedSlotOf(d, relicId)
	if slot then
		Net.Event("Unequip"):FireServer(slot)
		return
	end
	local maxSlots = math.max(d.Slots or Config.BaseRelicSlots, 1)
	local target = maxSlots
	for s = 1, maxSlots do
		if not (d.Equipped or {})[s] then
			target = s
			break
		end
	end
	Net.Event("Equip"):FireServer(relicId, target)
end

local function relicViewport(inner: any, relic, silhouette: boolean, size: UDim2, position: UDim2?, spin: boolean?): ViewportFrame
	local viewport = inner:New "ViewportFrame" {
		BackgroundTransparency = 1,
		Size = size,
		Position = position,
		AnchorPoint = if position then Vector2.new(0.5, 0) else nil,
	}
	local model = RelicModel.mountRelic(viewport, relic, silhouette)
	if spin then
		local stop = RelicModel.spin(viewport, model, 1.2)
		table.insert(inner, stop)
	end
	return viewport
end

local function codexCell(inner: any, relic, index: number): GuiObject
	local owned = inner:Computed(function(use)
		local d = getData(use)
		return d.Relics ~= nil and d.Relics[relic.Id] ~= nil
	end)
	local level = inner:Computed(function(use)
		local d = getData(use)
		return (d.Relics and d.Relics[relic.Id]) or 0
	end)
	local equipped = inner:Computed(function(use)
		return equippedSlotOf(getData(use), relic.Id) ~= nil
	end)
	local selected = inner:Computed(function(use)
		return use(selectedRelic) == relic.Id
	end)
	local hovered = inner:Value(false)
	local color = rarityColor(relic.Rarity)

	return inner:New "TextButton" {
		Name = relic.Id,
		AutoButtonColor = false,
		Text = "",
		BackgroundColor3 = inner:Computed(function(use)
			return if use(owned) then C.Panel2 else C.Ink
		end),
		BackgroundTransparency = 0.1,
		LayoutOrder = index,
		[OnEvent "MouseEnter"] = function()
			hovered:set(true)
		end,
		[OnEvent "MouseLeave"] = function()
			hovered:set(false)
		end,
		[OnEvent "SelectionGained"] = function()
			hovered:set(true)
		end,
		[OnEvent "SelectionLost"] = function()
			hovered:set(false)
		end,
		[OnEvent "Activated"] = function()
			if peek(selectedRelic) == relic.Id and peek(owned) then
				toggleEquip(relic.Id)
			end
			selectedRelic:set(relic.Id)
			Audio.Play("Click")
		end,
		[Children] = {
			inner:New "UICorner" { CornerRadius = UDim.new(0, Theme.Radius) },
			inner:New "UIStroke" {
				Color = inner:Computed(function(use)
					if use(selected) then
						return C.BrassBright
					end
					return if use(owned) then color else C.Line
				end),
				Thickness = inner:Spring(inner:Computed(function(use)
					return if use(selected) then 2.5 elseif use(hovered) then 2 else 1
				end), 30, 1),
				Transparency = inner:Computed(function(use)
					return if use(owned) or use(selected) then 0 else 0.3
				end),
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			},
			inner:New "UIScale" {
				Scale = inner:Spring(inner:Computed(function(use)
					return if use(hovered) then 1.04 else 1
				end), 34, 0.7),
			},
			-- rarity stripe
			inner:New "Frame" {
				BackgroundColor3 = color,
				BackgroundTransparency = inner:Computed(function(use)
					return if use(owned) then 0 else 0.7
				end),
				BorderSizePixel = 0,
				Size = UDim2.new(1, -8, 0, 2),
				Position = UDim2.fromOffset(4, 4),
			},
			inner:Computed(function(use, cellScope)
				return relicViewport(cellScope, relic, not use(owned), UDim2.new(1, -10, 0, 72), UDim2.new(0.5, 0, 0, 10), false)
			end),
			Kit.Text(inner, {
				Text = inner:Computed(function(use)
					return if use(owned) then relic.Name else "???"
				end),
				Font = Theme.Font.Bold,
				TextSize = 13,
				Color = inner:Computed(function(use)
					return if use(owned) then C.Ivory else C.Faint
				end),
				Truncate = Enum.TextTruncate.AtEnd,
				Size = UDim2.new(1, -8, 0, 16),
				Position = UDim2.new(0.5, 0, 0, 86),
				AnchorPoint = Vector2.new(0.5, 0),
			}),
			Kit.Text(inner, {
				Text = inner:Computed(function(use)
					return if use(owned) then "LV " .. tostring(use(level)) else string.upper(relic.Rarity)
				end),
				Font = Theme.Font.Display,
				TextSize = 9,
				Color = inner:Computed(function(use)
					return if use(owned) then color else color:Lerp(C.Ink, 0.4)
				end),
				Size = UDim2.new(1, -8, 0, 12),
				Position = UDim2.new(0.5, 0, 0, 104),
				AnchorPoint = Vector2.new(0.5, 0),
			}),
			inner:New "Frame" {
				Name = "Equipped",
				BackgroundColor3 = C.Cyan,
				BorderSizePixel = 0,
				Size = UDim2.fromOffset(18, 18),
				Position = UDim2.fromOffset(6, 10),
				Visible = equipped,
				ZIndex = 3,
				[Children] = {
					inner:New "UICorner" { CornerRadius = UDim.new(0, 2) },
					Kit.Icon(inner, {
						Name = "Check",
						Color = C.Ink,
						Size = UDim2.fromOffset(14, 14),
						Position = UDim2.fromScale(0.5, 0.5),
						AnchorPoint = Vector2.new(0.5, 0.5),
						ZIndex = 4,
					}),
				},
			},
			Kit.Icon(inner, {
				Name = "Lock",
				Color = C.Faint,
				Size = UDim2.fromOffset(14, 14),
				Position = UDim2.new(1, -8, 0, 12),
				AnchorPoint = Vector2.new(1, 0),
				Visible = inner:Computed(function(use)
					return not use(owned)
				end),
			}),
		},
	}
end

local function relicDetail(inner: any): GuiObject
	-- rebuild only when the selection or its owned-ness changes; level / cash changes update in place
	-- (keeps gamepad selection on the Polish button while you polish)
	local selectionOwned = inner:Computed(function(use)
		local id = use(selectedRelic)
		local d = getData(use)
		return id ~= nil and d.Relics ~= nil and d.Relics[id] ~= nil
	end)
	return inner:Computed(function(use, detailScope)
		local id = use(selectedRelic)
		local relic = id and Relics.ById[id]
		if not relic then
			return Kit.Text(detailScope, {
				Text = "Select a relic in the codex to inspect it. Tap it again to equip.",
				Font = Theme.Font.Body,
				TextSize = 14,
				Color = C.Muted,
				Wrapped = true,
				XAlign = Enum.TextXAlignment.Left,
				YAlign = Enum.TextYAlignment.Top,
				Size = UDim2.new(1, 0, 0, 60),
				LayoutOrder = 20,
			})
		end
		local owned = use(selectionOwned)
		local s = detailScope
		local color = rarityColor(relic.Rarity)
		local level = s:Computed(function(use2)
			return (getData(use2).Relics or {})[relic.Id] or 1
		end)
		local equipped = s:Computed(function(use2)
			return equippedSlotOf(getData(use2), relic.Id) ~= nil
		end)
		local cash = s:Computed(function(use2)
			return getData(use2).Cash or 0
		end)
		local cost = s:Computed(function(use2)
			return Config.PolishCost(relic.Rarity, use2(level)) or -1
		end)
		local maxed = s:Computed(function(use2)
			return use2(cost) < 0
		end)
		local affordable = s:Computed(function(use2)
			return not use2(maxed) and use2(cash) >= use2(cost)
		end)
		local bump = s:Value(0)

		return card(s, {
			Name = "Detail",
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 20,
			Accent = color,
			StrokeTransparency = 0.3,
			Children = {
				s:New "UIPadding" {
					PaddingTop = UDim.new(0, 10),
					PaddingBottom = UDim.new(0, 12),
					PaddingLeft = UDim.new(0, 12),
					PaddingRight = UDim.new(0, 12),
				},
				s:New "UIListLayout" {
					Padding = UDim.new(0, 4),
					SortOrder = Enum.SortOrder.LayoutOrder,
				},
				Kit.Eyebrow(s, {
					Text = s:Computed(function(use2)
						return string.upper(relic.Rarity) .. (if owned then "  ·  LV " .. tostring(use2(level)) else "")
					end),
					Color = color,
					TextSize = 10,
					LayoutOrder = 1,
				}),
				Kit.Text(s, {
					Text = if owned then relic.Name else "Undiscovered",
					Font = Theme.Font.Display,
					TextSize = 15,
					XAlign = Enum.TextXAlignment.Left,
					Size = UDim2.new(1, 0, 0, 22),
					LayoutOrder = 2,
				}),
				Kit.Text(s, {
					Text = if owned
						then s:Computed(function(use2)
							local lv = use2(level)
							local scaled = {}
							for stat, value in relic.Stats do
								scaled[stat] = if stat == "Shields" or stat == "DoubleJump" then value else value * (1 + (lv - 1) * Config.Relic.LevelBonus)
							end
							return table.concat(Panels.StatLines(scaled), "\n")
						end)
						else "Found " .. (if relic.Rarity == "Common" then "on early floors" else "deeper in the shaft") .. ". Rarer relics drop more often the deeper you go.",
					Font = Theme.Font.Body,
					TextSize = 14,
					Color = if owned then C.Cyan else C.Muted,
					Wrapped = true,
					XAlign = Enum.TextXAlignment.Left,
					YAlign = Enum.TextYAlignment.Top,
					AutoSize = "Y",
					Size = UDim2.new(1, 0, 0, 0),
					LayoutOrder = 3,
					Children = s:New "UIScale" {
						Scale = s:Spring(s:Computed(function(use2)
							return 1 + use2(bump) * 0.06
						end), 34, 0.5),
					},
				}),
				if owned
					then s:New "Frame" {
						Name = "LevelRow",
						BackgroundTransparency = 1,
						Size = UDim2.new(1, 0, 0, 14),
						LayoutOrder = 4,
						[Children] = {
							Kit.Pips(s, {
								Level = level,
								Max = Config.Relic.MaxLevel,
								Color = color,
								Size = UDim2.new(1, 0, 0, 5),
								Position = UDim2.fromScale(0, 0.5),
								AnchorPoint = Vector2.new(0, 0.5),
							}),
						},
					}
					else nil,
				if owned
					then Kit.Button(s, {
						Name = "EquipButton",
						Variant = "Solid",
						Accent = s:Computed(function(use2)
							return if use2(equipped) then C.Muted else C.Cyan
						end),
						Label = s:Computed(function(use2)
							return if use2(equipped) then "UNEQUIP" else "EQUIP"
						end),
						TextSize = 13,
						Size = UDim2.new(1, 0, 0, 40),
						LayoutOrder = 5,
						OnClick = function()
							toggleEquip(relic.Id)
						end,
					})
					else nil,
				if owned
					then Kit.Button(s, {
						Name = "PolishButton",
						Variant = "Primary",
						Accent = C.Gold,
						Enabled = affordable,
						Label = s:Computed(function(use2)
							return if use2(maxed) then "MAX LEVEL" else "POLISH  " .. Format.Cash(use2(cost))
						end),
						Sub = s:Computed(function(use2)
							if use2(maxed) then
								return "fully polished"
							elseif use2(affordable) then
								return "to level " .. tostring(use2(level) + 1)
							end
							return "need " .. Format.Cash(use2(cost) - use2(cash)) .. " more"
						end),
						SubColor = s:Computed(function(use2)
							return if use2(affordable) then C.Ink else C.Red:Lerp(C.Muted, 0.35)
						end),
						TextSize = 13,
						SubSize = 11,
						Size = UDim2.new(1, 0, 0, 50),
						LayoutOrder = 6,
						OnClick = function()
							if not peek(affordable) then
								return
							end
							Net.Event("PolishRelic"):FireServer(relic.Id)
							Audio.Play("Purchase")
							bump:set(1)
							task.delay(0.1, function()
								bump:set(0)
							end)
						end,
					})
					else nil,
			},
		}) :: any
	end) :: any
end

-- Relic Capsule ------------------------------------------------------------------------------
-- A random relic for cash. Paid random item (cash can be bought with Robux), so the exact odds
-- (Rarity.Odds at Data.CapsuleFloor) sit on the machine itself, next to the price, and it is
-- disabled where policy restricts paid random items (Data.PaidRandomAllowed == false).

local function oddsText(p: number): string
	if p >= 1 then
		return string.format("%.1f%%", p)
	elseif p >= 0.1 then
		return string.format("%.2f%%", p)
	end
	return string.format("%.3f%%", p)
end

-- Gacha capsule drawn from primitives: a brass-ringed sphere, upper shell tinted, a band and a latch.
local function capsuleGlyph(inner: any, wobble: any): GuiObject
	return inner:New "CanvasGroup" {
		Name = "Capsule",
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 0,
		Size = UDim2.fromOffset(46, 46),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Rotation = inner:Spring(inner:Computed(function(use)
			return use(wobble) * -14
		end), 26, 0.35),
		[Children] = {
			inner:New "UICorner" { CornerRadius = UDim.new(1, 0) },
			inner:New "UIStroke" { Color = C.Brass, Thickness = 2 },
			inner:New "Frame" {
				Name = "Shell",
				BackgroundColor3 = C.Gold,
				BackgroundTransparency = 0.15,
				BorderSizePixel = 0,
				Size = UDim2.fromScale(1, 0.5),
			},
			inner:New "Frame" {
				Name = "Band",
				BackgroundColor3 = C.Ink,
				BorderSizePixel = 0,
				Size = UDim2.new(1, 0, 0, 4),
				Position = UDim2.fromScale(0, 0.5),
				AnchorPoint = Vector2.new(0, 0.5),
			},
			inner:New "Frame" {
				Name = "Latch",
				BackgroundColor3 = C.Ink,
				Size = UDim2.fromOffset(14, 14),
				Position = UDim2.fromScale(0.5, 0.5),
				AnchorPoint = Vector2.new(0.5, 0.5),
				[Children] = {
					inner:New "UICorner" { CornerRadius = UDim.new(1, 0) },
					inner:New "UIStroke" { Color = C.BrassBright, Thickness = 2 },
				},
			},
		},
	}
end

local function capsuleCard(inner: any, narrow: any): GuiObject
	local floor = inner:Computed(function(use)
		return Store.CapsuleFloor(getData(use))
	end)
	local cost = inner:Computed(function(use)
		return Store.CapsuleCost(getData(use))
	end)
	local cash = inner:Computed(function(use)
		return getData(use).Cash or 0
	end)
	local allowed = inner:Computed(function(use)
		return getData(use).PaidRandomAllowed ~= false
	end)
	local lucky = inner:Computed(function(use)
		return Store.OwnsPass(getData(use), "LuckyBellhop")
	end)
	local cooling = inner:Value(false)
	local affordable = inner:Computed(function(use)
		return use(allowed) and use(cash) >= use(cost)
	end)
	local odds = inner:Computed(function(use)
		return Rarity.Odds(use(floor))
	end)
	local wobble = inner:Value(0)

	local segments = {}
	local legend = {}
	for index, name in Rarity.Order do
		local color = rarityColor(name)
		local share = inner:Computed(function(use)
			return use(odds)[name] or 0
		end)
		table.insert(segments, inner:New "Frame" {
			Name = name,
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Size = inner:Computed(function(use)
				return UDim2.fromScale(use(share) / 100, 1)
			end),
			LayoutOrder = index,
		})
		table.insert(legend, inner:New "Frame" {
			Name = name,
			BackgroundTransparency = 1,
			LayoutOrder = index,
			[Children] = {
				inner:New "Frame" {
					Name = "Dot",
					BackgroundColor3 = color,
					BorderSizePixel = 0,
					Size = UDim2.fromOffset(6, 6),
					Position = UDim2.fromOffset(3, 8),
					AnchorPoint = Vector2.new(0.5, 0.5),
					Rotation = 45,
				},
				Kit.Text(inner, {
					Text = string.upper(name),
					Font = Theme.Font.Display,
					TextSize = 9,
					Color = color,
					XAlign = Enum.TextXAlignment.Left,
					Size = UDim2.new(1, -12, 0, 14),
					Position = UDim2.fromOffset(12, 1),
				}),
				Kit.Text(inner, {
					Text = inner:Computed(function(use)
						return oddsText(use(share))
					end),
					Font = Theme.Font.Display,
					TextSize = 12,
					Color = C.Ivory,
					XAlign = Enum.TextXAlignment.Left,
					Size = UDim2.new(1, -12, 0, 16),
					Position = UDim2.fromOffset(12, 16),
				}),
			},
		})
	end

	return card(inner, {
		Name = "RelicCapsule",
		-- wide: button beside the copy; narrow: odds in two rows and the button below them
		Size = inner:Computed(function(use)
			return UDim2.new(1, 0, 0, if use(narrow) then 268 else 166)
		end),
		LayoutOrder = 1,
		Accent = C.BrassDim,
		Children = {
			inner:New "Frame" {
				Name = "Machine",
				BackgroundColor3 = C.Ink,
				BackgroundTransparency = 0.2,
				Size = UDim2.fromOffset(64, 64),
				Position = UDim2.fromOffset(14, 14),
				[Children] = {
					inner:New "UICorner" { CornerRadius = UDim.new(0, Theme.Radius) },
					inner:New "UIStroke" { Color = C.BrassDim, Thickness = 1 },
					capsuleGlyph(inner, wobble),
				},
			},
			inner:New "Frame" {
				Name = "Copy",
				BackgroundTransparency = 1,
				Size = inner:Computed(function(use)
					return UDim2.new(1, if use(narrow) then -106 else -(92 + 188), 0, 64)
				end),
				Position = UDim2.fromOffset(92, 14),
				[Children] = {
					inner:New "UIListLayout" {
						Padding = UDim.new(0, 3),
						VerticalAlignment = Enum.VerticalAlignment.Center,
						SortOrder = Enum.SortOrder.LayoutOrder,
					},
					inner:New "Frame" {
						Name = "TitleRow",
						BackgroundTransparency = 1,
						Size = UDim2.new(1, 0, 0, 20),
						LayoutOrder = 1,
						[Children] = {
							inner:New "UIListLayout" {
								FillDirection = Enum.FillDirection.Horizontal,
								VerticalAlignment = Enum.VerticalAlignment.Center,
								Padding = UDim.new(0, 8),
								SortOrder = Enum.SortOrder.LayoutOrder,
							},
							Kit.Text(inner, {
								Text = "RELIC CAPSULE",
								Font = Theme.Font.Display,
								TextSize = 15,
								AutoSize = "X",
								Size = UDim2.new(0, 0, 1, 0),
								LayoutOrder = 1,
							}),
							Kit.Tag(inner, {
								Text = string.format("-%s BELLHOP", pct(M.LuckyCapsuleDiscount)),
								Icon = "Clover",
								Accent = C.Green,
								Height = 18,
								TextSize = 9,
								Visible = lucky,
								LayoutOrder = 2,
							}),
						},
					},
					Kit.Text(inner, {
						Text = inner:Computed(function(use)
							if not use(allowed) then
								return "Not available in your region."
							end
							return string.format("A random relic for cash. Odds follow your deepest floor (B%d) and are shown below.", use(floor))
						end),
						Font = Theme.Font.Body,
						TextSize = 13,
						Color = inner:Computed(function(use)
							return if use(allowed) then C.Muted else C.Red:Lerp(C.Muted, 0.35)
						end),
						Wrapped = true,
						XAlign = Enum.TextXAlignment.Left,
						YAlign = Enum.TextYAlignment.Top,
						AutoSize = "Y",
						Size = UDim2.new(1, 0, 0, 0),
						LayoutOrder = 2,
					}),
				},
			},
			Kit.Button(inner, {
				Name = "BuyCapsule",
				Variant = "Primary",
				Accent = C.Gold,
				Enabled = inner:Computed(function(use)
					return use(affordable) and not use(cooling)
				end),
				Label = inner:Computed(function(use)
					return if use(allowed) then Format.Cash(use(cost)) else "UNAVAILABLE"
				end),
				Sub = inner:Computed(function(use)
					if not use(allowed) then
						return "in your region"
					elseif use(cooling) then
						return "opening…"
					elseif use(affordable) then
						return "open one"
					end
					return "need " .. Format.Cash(use(cost) - use(cash)) .. " more"
				end),
				SubColor = inner:Computed(function(use)
					return if use(affordable) then C.Ink else C.Red:Lerp(C.Muted, 0.35)
				end),
				TextSize = 16,
				SubSize = 11,
				Size = inner:Computed(function(use)
					return if use(narrow) then UDim2.new(1, -28, 0, 52) else UDim2.fromOffset(170, 58)
				end),
				Position = inner:Computed(function(use)
					return if use(narrow) then UDim2.new(0.5, 0, 1, -14) else UDim2.new(1, -14, 0, 17)
				end),
				AnchorPoint = inner:Computed(function(use)
					return if use(narrow) then Vector2.new(0.5, 1) else Vector2.new(1, 0)
				end),
				OnClick = function()
					if not peek(affordable) or peek(cooling) then
						return
					end
					Net.Event("BuyCapsule"):FireServer()
					Audio.Play("Purchase")
					cooling:set(true)
					wobble:set(1)
					task.delay(0.12, function()
						wobble:set(0)
					end)
					task.delay(1.3, function()
						cooling:set(false)
					end)
				end,
			}),
			-- odds, always on the machine (before buying)
			inner:New "Frame" {
				Name = "Odds",
				BackgroundTransparency = 1,
				Size = inner:Computed(function(use)
					return UDim2.new(1, -28, 0, if use(narrow) then 104 else 64)
				end),
				Position = UDim2.fromOffset(14, 88),
				[Children] = {
					Kit.Eyebrow(inner, {
						Text = inner:Computed(function(use)
							return string.format("ODDS PER CAPSULE  ·  B%d", use(floor))
						end),
						Color = C.Muted,
						BulletColor = C.BrassDim,
						TextSize = 8,
						Height = 12,
					}),
					inner:New "Frame" {
						Name = "Bar",
						BackgroundColor3 = C.Ink,
						BorderSizePixel = 0,
						ClipsDescendants = true,
						Size = UDim2.new(1, 0, 0, 5),
						Position = UDim2.fromOffset(0, 18),
						[Children] = {
							inner:New "UIListLayout" {
								FillDirection = Enum.FillDirection.Horizontal,
								SortOrder = Enum.SortOrder.LayoutOrder,
							},
							segments,
						},
					},
					inner:New "Frame" {
						Name = "Legend",
						BackgroundTransparency = 1,
						Size = UDim2.new(1, 0, 1, -30),
						Position = UDim2.fromOffset(0, 30),
						[Children] = {
							inner:New "UIGridLayout" {
								CellSize = inner:Computed(function(use)
									return if use(narrow) then UDim2.new(1 / 3, -6, 0, 34) else UDim2.new(1 / 6, -6, 0, 34)
								end),
								CellPadding = UDim2.fromOffset(6, 6),
								SortOrder = Enum.SortOrder.LayoutOrder,
							},
							legend,
						},
					},
				},
			},
		},
	})
end

local function buildRelics(inner: any): { Instance }
	local slots = inner:Computed(function(use)
		return math.max(getData(use).Slots or Config.BaseRelicSlots, 1)
	end)
	local slotList = inner:Computed(function(use)
		local list = {}
		for i = 1, use(slots) do
			list[i] = i
		end
		return list
	end)
	local ownedCount = inner:Computed(function(use)
		local n = 0
		for _ in getData(use).Relics or {} do
			n += 1
		end
		return n
	end)

	local sorted = table.clone(Relics.List)
	table.sort(sorted, function(a, b)
		local ra = (Rarity.Info[a.Rarity] or Rarity.Info.Common).Rank
		local rb = (Rarity.Info[b.Rarity] or Rarity.Info.Common).Rank
		if ra ~= rb then
			return ra < rb
		end
		return a.Name < b.Name
	end)
	local cells = {}
	for index, relic in sorted do
		table.insert(cells, codexCell(inner, relic, index))
	end

	local leftWidth = 250

	local left = scroller(inner, {
		Name = "Loadout",
		Size = UDim2.new(0, leftWidth, 1, 0),
		Children = {
			inner:New "UIListLayout" {
				Padding = UDim.new(0, 8),
				SortOrder = Enum.SortOrder.LayoutOrder,
			},
			Kit.Eyebrow(inner, {
				Text = inner:Computed(function(use)
					return string.format("EQUIPPED  %d/%d", #(getData(use).Equipped or {}), use(slots))
				end),
				LayoutOrder = 1,
			}),
			inner:ForValues(slotList, function(_use, slotScope, slot)
				local relicId = slotScope:Computed(function(use)
					return (getData(use).Equipped or {})[slot]
				end)
				-- primitives only, so the slot (and its viewport) rebuilds only when it really changes
				local slotLevel = slotScope:Computed(function(use)
					local id = use(relicId)
					return if id then (getData(use).Relics or {})[id] or 1 else 0
				end)
				return slotScope:Computed(function(use, s)
					local id = use(relicId)
					local relic = id and Relics.ById[id]
					return card(s, {
						Class = "TextButton",
						Name = "Slot" .. slot,
						Size = UDim2.new(1, 0, 0, 64),
						LayoutOrder = 1 + slot,
						Accent = if relic then rarityColor(relic.Rarity) else C.Line,
						OnClick = function()
							if relic then
								selectedRelic:set(relic.Id)
								Audio.Play("Click")
							end
						end,
						Children = if relic
							then {
								relicViewport(s, relic, false, UDim2.fromOffset(58, 58), UDim2.new(0, 33, 0, 3), true),
								Kit.Text(s, {
									Text = relic.Name,
									Font = Theme.Font.Bold,
									TextSize = 15,
									XAlign = Enum.TextXAlignment.Left,
									Truncate = Enum.TextTruncate.AtEnd,
									Size = UDim2.new(1, -78, 0, 18),
									Position = UDim2.fromOffset(68, 14),
								}),
								Kit.Text(s, {
									Text = string.upper(relic.Rarity) .. " · LV " .. tostring(use(slotLevel)),
									Font = Theme.Font.Display,
									TextSize = 9,
									Color = rarityColor(relic.Rarity),
									XAlign = Enum.TextXAlignment.Left,
									Size = UDim2.new(1, -78, 0, 14),
									Position = UDim2.fromOffset(68, 36),
								}),
							}
							else {
								Kit.Icon(s, {
									Name = "Diamond",
									Color = C.Line,
									Size = UDim2.fromOffset(16, 16),
									Position = UDim2.new(0, 22, 0.5, 0),
									AnchorPoint = Vector2.new(0, 0.5),
								}),
								Kit.Text(s, {
									Text = "Empty slot",
									Font = Theme.Font.Body,
									TextSize = 14,
									Color = C.Faint,
									XAlign = Enum.TextXAlignment.Left,
									Size = UDim2.new(1, -60, 1, 0),
									Position = UDim2.fromOffset(52, 0),
								}),
							},
					})
				end)
			end),
			Kit.Eyebrow(inner, { Text = "ACTIVE BONUSES", LayoutOrder = 10 }),
			Kit.Text(inner, {
				Text = inner:Computed(function(use)
					local d = getData(use)
					local lines = Panels.StatLines(Relics.SumStats(d.Equipped or {}, d.Relics or {}))
					return if #lines > 0 then table.concat(lines, "\n") else "Nothing equipped yet."
				end),
				Font = Theme.Font.Body,
				TextSize = 14,
				Color = C.Cyan,
				Wrapped = true,
				XAlign = Enum.TextXAlignment.Left,
				YAlign = Enum.TextYAlignment.Top,
				AutoSize = "Y",
				Size = UDim2.new(1, 0, 0, 0),
				LayoutOrder = 11,
			}),
			Kit.Rule(inner, { LayoutOrder = 12 }),
			relicDetail(inner),
		},
	})

	-- Right column scrolls as one: the capsule machine on top, then the codex grid.
	local narrow = inner:Computed(function(use)
		local canvas: Vector2 = use(Screen.Canvas)
		local content = math.max(math.min(940, canvas.X - 40), 300) - 40
		return content - (leftWidth + 18) < 560
	end)
	local right = scroller(inner, {
		Name = "Codex",
		Size = UDim2.new(1, -(leftWidth + 18), 1, 0),
		Position = UDim2.fromOffset(leftWidth + 18, 0),
		Children = {
			inner:New "UIListLayout" {
				Padding = UDim.new(0, 10),
				SortOrder = Enum.SortOrder.LayoutOrder,
			},
			Kit.Enter(inner, {
				Name = "CapsuleSlot",
				Shown = after(inner, 0.03),
				Size = inner:Computed(function(use)
					return UDim2.new(1, 0, 0, if use(narrow) then 268 else 166)
				end),
				LayoutOrder = 1,
				Offset = UDim2.fromOffset(0, 14),
				Children = { capsuleCard(inner, narrow) },
			}),
			Kit.Eyebrow(inner, {
				Text = inner:Computed(function(use)
					return string.format("CODEX  %d / %d FOUND", use(ownedCount), #Relics.List)
				end),
				LayoutOrder = 2,
			}),
			inner:New "Frame" {
				Name = "Grid",
				BackgroundTransparency = 1,
				AutomaticSize = Enum.AutomaticSize.Y,
				Size = UDim2.new(1, 0, 0, 0),
				LayoutOrder = 3,
				[Children] = {
					inner:New "UIGridLayout" {
						CellSize = UDim2.fromOffset(100, 122),
						CellPadding = UDim2.fromOffset(8, 8),
						SortOrder = Enum.SortOrder.LayoutOrder,
					},
					cells,
				},
			},
		},
	})
	return { left, right }
end

-- Daily --------------------------------------------------------------------------------------

local function buildDaily(inner: any): { Instance }
	local daily = inner:Computed(function(use)
		return getData(use).Daily or { Streak = 0, CanClaim = false, NextReward = 0 }
	end)
	local canClaim = inner:Computed(function(use)
		return use(daily).CanClaim == true
	end)
	local claimedInCycle = inner:Computed(function(use)
		local d = use(daily)
		local streak = d.Streak or 0
		if streak == 0 then
			return 0
		end
		return if d.CanClaim then streak % 7 else ((streak - 1) % 7) + 1
	end)
	local claimPulse = Kit.Pulse(inner, canClaim, 0.9)

	local tiles = {}
	for day = 1, 7 do
		local isJackpot = day == 7
		local claimed = inner:Computed(function(use)
			return day <= use(claimedInCycle)
		end)
		local today = inner:Computed(function(use)
			return use(canClaim) and use(claimedInCycle) + 1 == day
		end)
		local accent = inner:Computed(function(use)
			if use(today) then
				return C.Gold
			elseif use(claimed) then
				return C.Brass
			end
			return C.Line
		end)
		table.insert(tiles, Kit.Enter(inner, {
			Name = "Day" .. day,
			Shown = after(inner, 0.04 * day),
			LayoutOrder = day,
			Size = UDim2.fromScale(1, 1),
			Offset = UDim2.fromOffset(0, 16),
			Children = {
				card(inner, {
					Size = UDim2.fromScale(1, 1),
					Accent = accent,
					StrokeWeight = 1,
					Color = inner:Computed(function(use)
						return if use(today) then C.Panel3 else C.Panel2
					end),
					Children = {
						inner:New "UIStroke" {
							Name = "Glow",
							Color = C.Gold,
							Thickness = inner:Computed(function(use)
								return if use(today) then 1 + use(claimPulse) * 2 else 0
							end),
							Transparency = inner:Computed(function(use)
								return if use(today) then 0.2 + use(claimPulse) * 0.5 else 1
							end),
							ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
						},
						Kit.Text(inner, {
							Text = if isJackpot then "JACKPOT" else "DAY " .. day,
							Font = Theme.Font.Display,
							TextSize = 11,
							Color = inner:Computed(function(use)
								return if use(today) then C.Gold else C.Muted
							end),
							Size = UDim2.new(1, 0, 0, 16),
							Position = UDim2.fromOffset(0, 12),
						}),
						Kit.Icon(inner, {
							Name = if isJackpot then "Diamond" else "Coin",
							Color = inner:Computed(function(use)
								return if use(claimed) then C.BrassDim elseif use(today) then C.Gold else C.Faint
							end),
							Size = UDim2.fromOffset(if isJackpot then 40 else 30, if isJackpot then 40 else 30),
							Position = UDim2.fromScale(0.5, 0.48),
							AnchorPoint = Vector2.new(0.5, 0.5),
						}),
						Kit.Icon(inner, {
							Name = "Check",
							Color = C.BrassBright,
							Size = UDim2.fromOffset(18, 18),
							Position = UDim2.new(1, -8, 0, 8),
							AnchorPoint = Vector2.new(1, 0),
							Visible = claimed,
						}),
						Kit.Text(inner, {
							Text = Format.Cash(Config.DailyRewards[day] or 0),
							Font = Theme.Font.Display,
							TextSize = if isJackpot then 16 else 13,
							Color = inner:Computed(function(use)
								return if use(claimed) then C.Muted else C.Ivory
							end),
							Size = UDim2.new(1, 0, 0, 20),
							Position = UDim2.new(0, 0, 1, -14),
							AnchorPoint = Vector2.new(0, 1),
						}),
					},
				}),
			},
		}))
	end

	return {
		inner:New "Frame" {
			Name = "Daily",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			[Children] = {
				Kit.Eyebrow(inner, {
					Text = inner:Computed(function(use)
						local streak = use(daily).Streak or 0
						return string.format("STREAK  %d DAY%s", streak, if streak == 1 then "" else "S")
					end),
					Color = C.Gold,
					TextSize = 14,
					Height = 20,
					Position = UDim2.new(0.5, 0, 0, 6),
					AnchorPoint = Vector2.new(0.5, 0),
				}),
				inner:New "Frame" {
					Name = "Track",
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 1, -186),
					Position = UDim2.fromOffset(0, 44),
					[Children] = {
						inner:New "UIGridLayout" {
							CellSize = UDim2.new(1 / 7, -9, 1, 0),
							CellPadding = UDim2.fromOffset(10, 10),
							HorizontalAlignment = Enum.HorizontalAlignment.Center,
							SortOrder = Enum.SortOrder.LayoutOrder,
						},
						tiles,
					},
				},
				Kit.Text(inner, {
					Text = "Missing a day only drops your streak by one. Week two pays 50% more.",
					Font = Theme.Font.Body,
					TextSize = 14,
					Color = C.Muted,
					Size = UDim2.new(1, 0, 0, 18),
					Position = UDim2.new(0.5, 0, 1, -82),
					AnchorPoint = Vector2.new(0.5, 1),
				}),
				Kit.Button(inner, {
					Name = "Claim",
					Variant = "Primary",
					Accent = C.Gold,
					Enabled = canClaim,
					Label = inner:Computed(function(use)
						return if use(canClaim) then "CLAIM " .. Format.Cash(use(daily).NextReward or 0) else "COME BACK TOMORROW"
					end),
					TextSize = 17,
					Size = UDim2.fromOffset(340, 58),
					Position = UDim2.new(0.5, 0, 1, -12),
					AnchorPoint = Vector2.new(0.5, 1),
					GamepadHint = Enum.KeyCode.ButtonA,
					OnClick = function()
						local d = peek(dataV)
						if d and d.Daily and d.Daily.CanClaim then
							Net.Event("ClaimDaily"):FireServer()
							Audio.Play("Purchase")
						end
					end,
				}),
			},
		},
	}
end

-- Shop ---------------------------------------------------------------------------------------
-- A storefront, top to bottom: Starter Pack hero (until owned), the server-wide Golden Elevator,
-- passes, Extra Life + Premium perk, then cash packs sized to your deepest floor. Prices come from
-- MarketplaceService (Store.Price, cached); id 0 shows "COMING SOON". Value tags are computed from
-- the real pack sizes and prices and hidden while any price is unknown.

local PASSES = {
	{
		Key = "VIP",
		Name = "VIP",
		Icon = "VIP",
		Accent = C.Gold,
		-- the exact per-floor multiplier, so nobody reads "+10%" as +10 points or x1.1 on the whole bag
		Desc = string.format(
			"+1 relic slot, your bag grows x%.3f per floor instead of x%.2f, and a gold [VIP] chat tag.",
			Config.Bag.Multiplier + M.VipBagBonus * (Config.Bag.Multiplier - 1),
			Config.Bag.Multiplier
		),
	},
	{
		Key = "DoubleCash",
		Name = "2x Cash",
		Icon = "DoubleCash",
		Accent = C.Gold,
		Desc = "Double cash every time you leave with your bag.",
	},
	{
		Key = "LuckyBellhop",
		Name = "Lucky Bellhop",
		Icon = "LuckyBellhop",
		Accent = C.Green,
		Desc = string.format("+%s relic find chance. Relic Capsules cost %s less.", pct(M.LuckyRelicChance), pct(M.LuckyCapsuleDiscount)),
	},
}

local CASH_PACKS = {
	{ Key = "CashSmall", Name = "Cash Stack", Icon = "CashSmall" },
	{ Key = "CashMedium", Name = "Cash Case", Icon = "CashMedium" },
	{ Key = "CashLarge", Name = "Cash Vault", Icon = "CashLarge" },
}

local function extraLifeTier(floor: number): string
	if floor >= 20 then
		return "B20+"
	elseif floor >= 10 then
		return "B10-19"
	end
	return "B1-9"
end

-- Robux purchase button. props.PriceKey (string or state) decides price + availability;
-- props.PromptKey is what the server is asked for (defaults to the price key).
local function buyButton(inner: any, props: { [string]: any }): TextButton
	local priceKey = props.PriceKey
	local variant = props.Variant or "Solid"
	local available = inner:Computed(function(use)
		return Store.Available(Kit.read(use, priceKey))
	end)
	return Kit.Button(inner, {
		Name = props.Name or "Buy",
		Variant = variant,
		Accent = props.Accent,
		Enabled = available,
		Icon = props.Icon,
		IconSize = props.IconSize,
		Label = inner:Computed(function(use)
			if not use(available) then
				return "COMING SOON"
			end
			return Store.PriceText(use, Kit.read(use, priceKey), props.Fallback or "BUY")
		end),
		Sub = props.Sub,
		SubColor = if variant == "Primary"
			then inner:Computed(function(use)
				return if use(available) then C.Ink else C.Faint
			end)
			else nil,
		TextSize = props.TextSize or 15,
		SubSize = props.SubSize or 11,
		Size = props.Size,
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		LayoutOrder = props.LayoutOrder,
		Visible = props.Visible,
		OnClick = function()
			Store.Prompt(props.PromptKey or peek(priceKey))
		end,
	})
end

-- Static "you have this" plate used where a buy button would sit.
local function ownedBadge(inner: any, props: { [string]: any }): Frame
	return inner:New "Frame" {
		Name = "Owned",
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		Size = props.Size,
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		Visible = props.Visible,
		[Children] = {
			inner:New "UICorner" { CornerRadius = UDim.new(0, Theme.Radius) },
			inner:New "UIStroke" { Color = props.Accent or C.BrassDim, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border },
			inner:New "UIListLayout" {
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 8),
				SortOrder = Enum.SortOrder.LayoutOrder,
			},
			Kit.Icon(inner, { Name = "Check", Color = props.TextColor or C.BrassBright, Size = UDim2.fromOffset(14, 14), LayoutOrder = 1 }),
			Kit.Text(inner, {
				Text = props.Text or "OWNED",
				Font = Theme.Font.Display,
				TextSize = 12,
				Color = props.TextColor or C.BrassBright,
				AutoSize = "X",
				Size = UDim2.new(0, 0, 1, 0),
				LayoutOrder = 2,
			}),
		},
	}
end

-- Vertical product tile: accent stripe, icon, optional top-right tag, title, description; the
-- caller adds the bottom row (button / badge) through props.Children. props.Narrow (portrait phones):
-- a full-width row with the icon on the left and title + description beside it.
local NARROW_TEXT_X = 86 -- where title / description start in a narrow tile

local function tile(inner: any, props: { [string]: any }): Frame
	local narrow = props.Narrow == true
	return card(inner, {
		Name = props.Name,
		Size = props.Size or UDim2.fromScale(1, 1),
		LayoutOrder = props.LayoutOrder,
		Accent = props.Stroke or C.Line,
		Children = {
			inner:New "Frame" {
				Name = "Stripe",
				BackgroundColor3 = props.Accent,
				BorderSizePixel = 0,
				Size = UDim2.new(1, -8, 0, 2),
				Position = UDim2.fromOffset(4, 4),
			},
			Kit.Icon(inner, {
				Name = props.Icon,
				Color = props.Accent,
				Size = if narrow then UDim2.fromOffset(60, 60) else UDim2.fromOffset(64, 64),
				Position = if narrow then UDim2.fromOffset(14, 14) else UDim2.fromOffset(16, 12),
			}),
			props.Tag,
			Kit.Text(inner, {
				Name = "Title",
				Text = props.Title,
				Font = Theme.Font.Display,
				TextSize = 14,
				XAlign = Enum.TextXAlignment.Left,
				Truncate = Enum.TextTruncate.AtEnd,
				-- narrow: leave room for a top-right tag
				Size = if narrow then UDim2.new(1, if props.Tag then -196 else -(NARROW_TEXT_X + 14), 0, 18) else UDim2.new(1, -32, 0, 18),
				Position = if narrow then UDim2.fromOffset(NARROW_TEXT_X, 18) else UDim2.fromOffset(16, 82),
			}),
			if props.Desc
				then Kit.Text(inner, {
					Name = "Desc",
					Text = props.Desc,
					Font = Theme.Font.Body,
					TextSize = 14,
					Color = C.Muted,
					Wrapped = true,
					XAlign = Enum.TextXAlignment.Left,
					YAlign = Enum.TextYAlignment.Top,
					Size = UDim2.new(1, if narrow then -(NARROW_TEXT_X + 16) else -32, 0, props.DescHeight or 54),
					Position = if narrow then UDim2.fromOffset(NARROW_TEXT_X, 40) else UDim2.fromOffset(16, 104),
				})
				else nil,
			props.Children,
		},
	})
end

local function bottomButtonProps(t: { [string]: any }): { [string]: any }
	t.Size = t.Size or UDim2.new(1, -24, 0, 44)
	t.Position = t.Position or UDim2.new(0.5, 0, 1, -12)
	t.AnchorPoint = t.AnchorPoint or Vector2.new(0.5, 1)
	return t
end

-- narrow (portrait phones): icon + heading on top, contents chips below, full-width button at the bottom.
local function starterHero(inner: any, narrow: boolean): GuiObject
	local starter = M.Starter
	local function chip(icon: string, text: string, accent: Color3, order: number)
		return Kit.Tag(inner, {
			Text = text,
			Icon = icon,
			Accent = accent,
			Font = Theme.Font.Bold,
			TextSize = if narrow then 13 else 14,
			Height = if narrow then 28 else 30,
			LayoutOrder = order,
		})
	end
	return card(inner, {
		Name = "StarterPack",
		Size = UDim2.fromScale(1, 1),
		Color = C.Panel2,
		Fill = 0.02,
		Accent = C.Gold,
		StrokeTransparency = 0.15,
		Children = {
			Kit.Brackets(inner, { Color = C.Gold, Length = 14 }),
			Kit.Icon(inner, {
				Name = "StarterPack",
				Size = if narrow then UDim2.fromOffset(72, 72) else UDim2.fromOffset(84, 84),
				Position = if narrow then UDim2.fromOffset(16, 16) else UDim2.new(0, 16, 0.5, 0),
				AnchorPoint = if narrow then Vector2.zero else Vector2.new(0, 0.5),
			}),
			inner:New "Frame" {
				Name = "Inset",
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(4, 4),
				Size = UDim2.new(1, -8, 1, -8),
				[Children] = {
					inner:New "UICorner" { CornerRadius = UDim.new(0, 2) },
					inner:New "UIStroke" { Color = C.Gold, Thickness = 1, Transparency = 0.8, ApplyStrokeMode = Enum.ApplyStrokeMode.Border },
				},
			},
			inner:New "Frame" {
				Name = "Copy",
				BackgroundTransparency = 1,
				Size = if narrow then UDim2.new(1, -116, 0, 72) else UDim2.new(1, -358, 1, -36),
				Position = if narrow then UDim2.fromOffset(100, 16) else UDim2.fromOffset(112, 18),
				[Children] = {
					inner:New "UIListLayout" {
						Padding = UDim.new(0, 6),
						VerticalAlignment = Enum.VerticalAlignment.Center,
						SortOrder = Enum.SortOrder.LayoutOrder,
					},
					Kit.Eyebrow(inner, {
						Text = "STARTER PACK  ·  ONE-TIME",
						Color = C.Gold,
						TextSize = 10,
						Height = 16,
						LayoutOrder = 1,
					}),
					Kit.Text(inner, {
						Text = "HEAD START",
						Font = Theme.Font.Display,
						TextSize = if narrow then 24 else 26,
						XAlign = Enum.TextXAlignment.Left,
						Size = UDim2.new(1, 0, 0, 34),
						LayoutOrder = 2,
					}),
					-- wide: the chips sit under the heading
					if narrow then nil else inner:New "Frame" {
						Name = "Contents",
						BackgroundTransparency = 1,
						Size = UDim2.new(1, 0, 0, 30),
						LayoutOrder = 3,
						[Children] = {
							inner:New "UIListLayout" {
								FillDirection = Enum.FillDirection.Horizontal,
								VerticalAlignment = Enum.VerticalAlignment.Center,
								Padding = UDim.new(0, 8),
								SortOrder = Enum.SortOrder.LayoutOrder,
							},
							chip("Coin", "$" .. Format.Comma(starter.Cash), C.Gold, 1),
							chip("Heart", string.format("%d Extra Lives", starter.ExtraLives), C.Cyan, 2),
							chip("Gem", "a " .. starter.Rarity .. " relic", rarityColor(starter.Rarity), 3),
						},
					},
				},
			},
			-- narrow: the chips get their own (wrapping) row under the icon
			if narrow
				then inner:New "Frame" {
					Name = "Contents",
					BackgroundTransparency = 1,
					Size = UDim2.new(1, -32, 0, 64),
					Position = UDim2.fromOffset(16, 100),
					[Children] = {
						inner:New "UIListLayout" {
							FillDirection = Enum.FillDirection.Horizontal,
							Wraps = true,
							Padding = UDim.new(0, 8),
							SortOrder = Enum.SortOrder.LayoutOrder,
						},
						chip("Coin", "$" .. Format.Comma(starter.Cash), C.Gold, 1),
						chip("Heart", string.format("%d Extra Lives", starter.ExtraLives), C.Cyan, 2),
						chip("Gem", "a " .. starter.Rarity .. " relic", rarityColor(starter.Rarity), 3),
					},
				}
				else inner:New "Frame" {
					Name = "Divider",
					BackgroundColor3 = C.Gold,
					BackgroundTransparency = 0.7,
					BorderSizePixel = 0,
					Size = UDim2.new(0, 1, 1, -44),
					Position = UDim2.new(1, -238, 0.5, 0),
					AnchorPoint = Vector2.new(0.5, 0.5),
				},
			buyButton(inner, {
				Name = "BuyStarter",
				PriceKey = "StarterPack",
				Variant = "Primary",
				Accent = C.Gold,
				Fallback = "GET PACK",
				Sub = "get the pack",
				TextSize = 18,
				SubSize = 12,
				Size = if narrow then UDim2.new(1, -32, 0, 56) else UDim2.fromOffset(196, 64),
				Position = if narrow then UDim2.new(0.5, 0, 1, -16) else UDim2.new(1, -22, 0.5, 0),
				AnchorPoint = if narrow then Vector2.new(0.5, 1) else Vector2.new(1, 0.5),
			}),
		},
	})
end

-- narrow (portrait phones): icon + copy on top, full-width button at the bottom.
local function goldenCard(inner: any, narrow: boolean): GuiObject
	local active = Store.GoldenActive
	local glow = Kit.Pulse(inner, active, 0.5)
	return card(inner, {
		Name = "GoldenElevator",
		Size = UDim2.fromScale(1, 1),
		Accent = inner:Computed(function(use)
			return if use(active) then C.Gold else C.Line
		end),
		StrokeWeight = inner:Computed(function(use)
			return if use(active) then 1 + use(glow) * 1.2 else 1
		end),
		Children = {
			Kit.Icon(inner, {
				Name = "GoldenElevator",
				Size = if narrow then UDim2.fromOffset(64, 64) else UDim2.fromOffset(76, 76),
				Position = if narrow then UDim2.fromOffset(14, 14) else UDim2.new(0, 12, 0.5, 0),
				AnchorPoint = if narrow then Vector2.zero else Vector2.new(0, 0.5),
			}),
			inner:New "Frame" {
				Name = "Copy",
				BackgroundTransparency = 1,
				Size = if narrow then UDim2.new(1, -102, 0, 104) else UDim2.new(1, -(96 + 232), 1, -16),
				Position = if narrow then UDim2.fromOffset(88, 10) else UDim2.new(0, 96, 0.5, 0),
				AnchorPoint = if narrow then Vector2.zero else Vector2.new(0, 0.5),
				[Children] = {
					inner:New "UIListLayout" {
						Padding = UDim.new(0, 4),
						VerticalAlignment = Enum.VerticalAlignment.Center,
						SortOrder = Enum.SortOrder.LayoutOrder,
					},
					inner:New "Frame" {
						Name = "TitleRow",
						BackgroundTransparency = 1,
						Size = UDim2.new(1, 0, 0, 22),
						LayoutOrder = 1,
						[Children] = {
							inner:New "UIListLayout" {
								FillDirection = Enum.FillDirection.Horizontal,
								VerticalAlignment = Enum.VerticalAlignment.Center,
								Padding = UDim.new(0, 10),
								SortOrder = Enum.SortOrder.LayoutOrder,
							},
							Kit.Text(inner, {
								Text = "GOLDEN ELEVATOR",
								Font = Theme.Font.Display,
								TextSize = 16,
								AutoSize = "X",
								Size = UDim2.new(0, 0, 1, 0),
								LayoutOrder = 1,
							}),
							Kit.Tag(inner, {
								Text = "LIVE",
								Accent = C.Gold,
								Height = 18,
								TextSize = 9,
								Visible = active,
								LayoutOrder = 2,
							}),
						},
					},
					Kit.Text(inner, {
						Text = string.format("Everyone in this server earns x%d cash-outs for %d minutes.", M.GoldenCashMult, M.GoldenMinutes),
						Font = Theme.Font.Body,
						TextSize = 14,
						Color = C.Muted,
						Wrapped = true,
						XAlign = Enum.TextXAlignment.Left,
						AutoSize = "Y",
						Size = UDim2.new(1, 0, 0, 0),
						LayoutOrder = 2,
					}),
					Kit.Text(inner, {
						Text = inner:Computed(function(use)
							if not use(active) then
								return string.format("Stacks: buying during a Golden Hour adds %d minutes.", M.GoldenMinutes)
							end
							local by = use(Store.GoldenBy)
							local left = Store.Clock(use(Store.GoldenLeft)) .. " LEFT"
							return if by ~= "" then "GOLDEN HOUR BY " .. string.upper(by) .. "  ·  " .. left else "GOLDEN HOUR  ·  " .. left
						end),
						Font = inner:Computed(function(use)
							return if use(active) then Theme.Font.Display else Theme.Font.Body
						end),
						TextSize = inner:Computed(function(use)
							return if use(active) then 11 else 13
						end),
						Color = inner:Computed(function(use)
							return if use(active) then C.Gold else C.Faint
						end),
						XAlign = Enum.TextXAlignment.Left,
						Truncate = Enum.TextTruncate.AtEnd,
						Size = UDim2.new(1, 0, 0, 16),
						LayoutOrder = 3,
					}),
				},
			},
			buyButton(inner, {
				Name = "BuyGolden",
				PriceKey = "GoldenElevator",
				Variant = "Primary",
				Accent = C.Gold,
				Fallback = "BUY",
				Sub = inner:Computed(function(use)
					return string.format(if use(active) then "add %d min" else "start · %d min", M.GoldenMinutes)
				end),
				TextSize = 17,
				SubSize = 12,
				Size = if narrow then UDim2.new(1, -28, 0, 56) else UDim2.fromOffset(196, 60),
				Position = if narrow then UDim2.new(0.5, 0, 1, -14) else UDim2.new(1, -16, 0.5, 0),
				AnchorPoint = if narrow then Vector2.new(0.5, 1) else Vector2.new(1, 0.5),
			}),
		},
	})
end

-- Heights of the narrow (portrait phone) tiles; wide tiles share their row's height.
local NARROW = { Pass = 160, ExtraLife = 182, Premium = 164, Cash = 152, Starter = 250, Golden = 192 }

local function passTile(inner: any, pass, narrow: boolean): GuiObject
	local owned = inner:Computed(function(use)
		return Store.OwnsPass(getData(use), pass.Key)
	end)
	return tile(inner, {
		Name = pass.Key,
		Icon = pass.Icon,
		Accent = pass.Accent,
		Title = string.upper(pass.Name),
		Desc = pass.Desc,
		Narrow = narrow,
		Stroke = inner:Computed(function(use)
			return if use(owned) then C.BrassDim else C.Line
		end),
		Size = if narrow then UDim2.new(1, 0, 0, NARROW.Pass) else UDim2.new(1 / 3, -7, 1, 0),
		Children = {
			buyButton(inner, bottomButtonProps({
				PriceKey = pass.Key,
				Accent = pass.Accent,
				Fallback = "GET PASS",
				Visible = inner:Computed(function(use)
					return not use(owned)
				end),
			})),
			ownedBadge(inner, bottomButtonProps({
				Text = "OWNED",
				Visible = owned,
			})),
		},
	})
end

local function extraLifeTile(inner: any, narrow: boolean): GuiObject
	local deepest = inner:Computed(function(use)
		return math.max(Store.Deepest(getData(use)), 1)
	end)
	local banked = inner:Computed(function(use)
		return tonumber(getData(use).ExtraLives) or 0
	end)
	return tile(inner, {
		Name = "ExtraLife",
		Icon = inner:Computed(function(use)
			return Config.ExtraLifeKey(use(deepest))
		end),
		Accent = C.Cyan,
		Title = "EXTRA LIFE",
		Desc = "Saves you on the spot the next time you'd lose a bag in a Normal run. Already out? It revives you, bag restored.",
		DescHeight = 72,
		Narrow = narrow,
		Size = if narrow then UDim2.new(1, 0, 0, NARROW.ExtraLife) else UDim2.new(0.6, -5, 1, 0),
		Tag = Kit.Tag(inner, {
			Text = inner:Computed(function(use)
				return "x" .. tostring(use(banked)) .. " BANKED"
			end),
			Icon = "ExtraLife",
			Accent = C.Cyan,
			Height = 20,
			TextSize = 9,
			Position = UDim2.new(1, -12, 0, 18),
			AnchorPoint = Vector2.new(1, 0),
			Visible = inner:Computed(function(use)
				return use(banked) > 0
			end),
		}),
		Children = {
			buyButton(inner, bottomButtonProps({
				PriceKey = inner:Computed(function(use)
					return Config.ExtraLifeKey(use(deepest))
				end),
				PromptKey = "ExtraLife",
				Accent = C.Cyan,
				Fallback = "BANK ONE",
				Sub = inner:Computed(function(use)
					return "priced for your deepest floor (" .. extraLifeTier(use(deepest)) .. ")"
				end),
				SubSize = 11,
				Size = UDim2.new(1, -24, 0, 48),
			})),
		},
	})
end

local function premiumTile(inner: any, narrow: boolean): GuiObject
	local premium = inner:Computed(function(use)
		return getData(use).Premium == true
	end)
	return tile(inner, {
		Name = "Premium",
		Icon = "Diamond",
		Accent = C.Ivory,
		Title = "ROBLOX PREMIUM",
		Desc = string.format("Premium members earn +%s on every cash-out.", pct(M.PremiumCashMult - 1)),
		Narrow = narrow,
		Size = if narrow then UDim2.new(1, 0, 0, NARROW.Premium) else UDim2.new(0.4, -5, 1, 0),
		Stroke = inner:Computed(function(use)
			return if use(premium) then C.BrassDim else C.Line
		end),
		Children = {
			Kit.Button(inner, bottomButtonProps({
				Name = "GetPremium",
				Variant = "Outline",
				Accent = C.Ivory,
				Label = "GET PREMIUM",
				TextSize = 12,
				Size = UDim2.new(1, -24, 0, 48),
				Visible = inner:Computed(function(use)
					return not use(premium)
				end),
				OnClick = function()
					Store.PromptPremium()
				end,
			})),
			ownedBadge(inner, bottomButtonProps({
				Text = "ACTIVE",
				Accent = C.Green,
				TextColor = C.Green,
				Size = UDim2.new(1, -24, 0, 48),
				Visible = premium,
			})),
		},
	})
end

-- { [key] = whole % more cash per Robux than the Small pack, Best = key } (empty while prices load).
-- Rounded down so a tag never overstates the value.
local function packValues(inner: any): any
	return inner:Computed(function(use)
		local d = getData(use)
		local out = {}
		local smallPrice = use(Store.Price("CashSmall"))
		local smallCash = Store.CashPack(d, "CashSmall")
		if smallPrice <= 0 or smallCash <= 0 then
			return out
		end
		local base = smallCash / smallPrice
		local best = 0
		for _, key in { "CashMedium", "CashLarge" } do
			local price = use(Store.Price(key))
			if price > 0 then
				local gain = math.floor((Store.CashPack(d, key) / price / base - 1) * 100)
				if gain >= 5 then
					out[key] = gain
					if gain > best then
						best = gain
						out.Best = key
					end
				end
			end
		end
		return out
	end)
end

local function cashTile(inner: any, pack, values: any, narrow: boolean): GuiObject
	local amount = inner:Computed(function(use)
		return Store.CashPack(getData(use), pack.Key)
	end)
	local gain = inner:Computed(function(use)
		return use(values)[pack.Key]
	end)
	local isBest = inner:Computed(function(use)
		return use(values).Best == pack.Key
	end)
	return tile(inner, {
		Name = pack.Key,
		Icon = pack.Icon,
		Accent = C.Gold,
		Title = string.upper(pack.Name),
		Narrow = narrow,
		Size = if narrow then UDim2.new(1, 0, 0, NARROW.Cash) else UDim2.new(1 / 3, -7, 1, 0),
		Tag = Kit.Tag(inner, {
			Text = inner:Computed(function(use)
				local g = use(gain)
				if not g then
					return ""
				end
				return if use(isBest) then string.format("BEST VALUE +%d%%", g) else string.format("+%d%% VALUE", g)
			end),
			Accent = inner:Computed(function(use)
				return if use(isBest) then C.Gold else C.Brass
			end),
			TextColor = inner:Computed(function(use)
				return if use(isBest) then C.Gold else C.Ivory
			end),
			Height = 20,
			TextSize = 9,
			Position = UDim2.new(1, -12, 0, 18),
			AnchorPoint = Vector2.new(1, 0),
			Visible = inner:Computed(function(use)
				return use(gain) ~= nil
			end),
		}),
		Children = {
			Kit.Text(inner, {
				Name = "Amount",
				Text = inner:Computed(function(use)
					return "$" .. Format.Comma(use(amount))
				end),
				Font = Theme.Font.Display,
				TextSize = 22,
				Color = C.Gold,
				XAlign = Enum.TextXAlignment.Left,
				Size = UDim2.new(1, if narrow then -(NARROW_TEXT_X + 16) else -32, 0, 28),
				Position = if narrow then UDim2.fromOffset(NARROW_TEXT_X, 40) else UDim2.fromOffset(16, 104),
			}),
			Kit.Text(inner, {
				Text = "banked instantly",
				Font = Theme.Font.Body,
				TextSize = 13,
				Color = C.Faint,
				XAlign = Enum.TextXAlignment.Left,
				Size = UDim2.new(1, if narrow then -(NARROW_TEXT_X + 16) else -32, 0, 16),
				Position = if narrow then UDim2.fromOffset(NARROW_TEXT_X, 68) else UDim2.fromOffset(16, 132),
			}),
			buyButton(inner, bottomButtonProps({
				PriceKey = pack.Key,
				Accent = C.Gold,
			})),
		},
	})
end

local function codeRow(inner: any): GuiObject
	local text = inner:Value("")
	local busy = inner:Value(false)
	local box: TextBox
	local function redeem()
		local code = string.gsub(peek(text), "^%s*(.-)%s*$", "%1")
		if code == "" or peek(busy) then
			return
		end
		busy:set(true)
		task.spawn(function()
			local ok, success, message = pcall(function()
				return Net.Function("RedeemCode"):InvokeServer(code)
			end)
			busy:set(false)
			if not ok then
				Toast.Show("Could not reach the server. Try again.", "bad")
			elseif success then
				Toast.Show(typeof(message) == "string" and message or "Code redeemed!", "good")
				box.Text = ""
			else
				Toast.Show(typeof(message) == "string" and message or "Invalid code.", "bad")
			end
		end)
	end
	box = inner:New "TextBox" {
		Name = "CodeBox",
		PlaceholderText = "Enter a code",
		Text = "",
		ClearTextOnFocus = false,
		FontFace = Theme.Font.Bold,
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.Ivory,
		PlaceholderColor3 = C.Faint,
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 0.1,
		Size = UDim2.new(1, -176, 1, 0),
		[Out "Text"] = text,
		[OnEvent "FocusLost"] = function(enter)
			if enter then
				redeem()
			end
		end,
		[Children] = {
			inner:New "UICorner" { CornerRadius = UDim.new(0, Theme.Radius) },
			inner:New "UIStroke" { Color = C.Line, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border },
			inner:New "UIPadding" { PaddingLeft = UDim.new(0, 46), PaddingRight = UDim.new(0, 12) },
		},
	}
	return inner:New "Frame" {
		Name = "Codes",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 52),
		Position = UDim2.new(0, 0, 1, 0),
		AnchorPoint = Vector2.new(0, 1),
		[Children] = {
			box,
			Kit.Icon(inner, {
				Name = "Ticket",
				Color = C.Brass,
				Size = UDim2.fromOffset(22, 22),
				Position = UDim2.new(0, 14, 0.5, 0),
				AnchorPoint = Vector2.new(0, 0.5),
				ZIndex = 2,
			}),
			Kit.Button(inner, {
				Name = "Redeem",
				Variant = "Outline",
				Accent = C.Cyan,
				Label = inner:Computed(function(use)
					return if use(busy) then "…" else "REDEEM"
				end),
				TextSize = 14,
				Size = UDim2.new(0, 164, 1, 0),
				Position = UDim2.fromScale(1, 0),
				AnchorPoint = Vector2.new(1, 0),
				OnClick = redeem,
			}),
		},
	}
end

local function buildShop(inner: any): { Instance }
	local starterOwned = inner:Computed(function(use)
		return Store.OwnsPass(getData(use), "StarterPack")
	end)
	local values = packValues(inner)
	-- The modal rebuilds the page when the layout changes. Portrait phones get one product per row;
	-- every phone gets the code box at the end of the scroll list instead of a fixed bottom bar.
	local layout = peek(Screen.Layout)
	local narrow = layout == "Portrait"
	local phone = layout ~= "Wide"

	local order = 0
	local function header(text: any): GuiObject
		order += 1
		return inner:New "Frame" {
			Name = "Header",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 22),
			LayoutOrder = order,
			[Children] = {
				Kit.Eyebrow(inner, {
					Text = text,
					TextSize = 10,
					Height = 16,
					Position = UDim2.new(0, 0, 1, 0),
					AnchorPoint = Vector2.new(0, 1),
				}),
			},
		}
	end
	local function section(name: string, height: number, children: any, visible: any?): GuiObject
		order += 1
		return inner:New "Frame" {
			Name = name,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, height),
			LayoutOrder = order,
			Visible = visible,
			[Children] = {
				Kit.Enter(inner, {
					Name = "Enter",
					Shown = after(inner, 0.04 * order),
					Offset = UDim2.fromOffset(0, 14),
					Children = children,
				}),
			},
		}
	end
	-- tiles side by side; stacked in narrow mode
	local function row(children: { any }): { any }
		return {
			inner:New "UIListLayout" {
				FillDirection = if narrow then Enum.FillDirection.Vertical else Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, 10),
				SortOrder = Enum.SortOrder.LayoutOrder,
			},
			children,
		}
	end
	-- height of a section holding `count` stacked narrow tiles of `height` each
	local function stack(count: number, height: number): number
		return count * height + (count - 1) * 10
	end

	local passTiles = {}
	for index, pass in PASSES do
		local t = passTile(inner, pass, narrow)
		t.LayoutOrder = index
		table.insert(passTiles, t)
	end
	local cashTiles = {}
	for index, pack in CASH_PACKS do
		local t = cashTile(inner, pack, values, narrow)
		t.LayoutOrder = index
		table.insert(cashTiles, t)
	end
	local supplies = { extraLifeTile(inner, narrow), premiumTile(inner, narrow) }
	supplies[1].LayoutOrder = 1
	supplies[2].LayoutOrder = 2

	local codes = codeRow(inner)
	if phone then
		codes.Size = UDim2.new(1, 0, 0, 52)
		codes.LayoutOrder = 200
	end
	return {
		scroller(inner, {
			Name = "Store",
			Size = if phone then UDim2.fromScale(1, 1) else UDim2.new(1, 0, 1, -66),
			Children = {
				inner:New "UIListLayout" {
					Padding = UDim.new(0, 10),
					SortOrder = Enum.SortOrder.LayoutOrder,
				},
				section("Starter", if narrow then NARROW.Starter else 140, { starterHero(inner, narrow) }, inner:Computed(function(use)
					return not use(starterOwned)
				end)),
				header("SERVER BOOST"),
				section("Golden", if narrow then NARROW.Golden else 104, { goldenCard(inner, narrow) }),
				header("GAME PASSES  ·  YOURS FOREVER"),
				section("Passes", if narrow then stack(#passTiles, NARROW.Pass) else 236, row(passTiles)),
				header("SUPPLIES"),
				section("Supplies", if narrow then NARROW.ExtraLife + 10 + NARROW.Premium else 236, row(supplies)),
				header(if narrow then "CASH PACKS  ·  SIZED TO YOUR DEPTH" else "CASH PACKS  ·  SIZED TO YOUR DEEPEST FLOOR"),
				section("Cash", if narrow then stack(#cashTiles, NARROW.Cash) else 240, row(cashTiles)),
				Kit.Text(inner, {
					Name = "Fine",
					Text = "Value tags compare cash per Robux with the Cash Stack.",
					Font = Theme.Font.Body,
					TextSize = 13,
					Color = C.Faint,
					Wrapped = true,
					XAlign = Enum.TextXAlignment.Left,
					AutoSize = "Y",
					Size = UDim2.new(1, 0, 0, 0),
					LayoutOrder = 100,
					Visible = inner:Computed(function(use)
						return next(use(values)) ~= nil
					end),
				}),
				if phone then codes else nil,
			},
		}),
		if phone then nil else codes,
	}
end

local BUILDERS = {
	Upgrades = buildUpgrades,
	Relics = buildRelics,
	Daily = buildDaily,
	Shop = buildShop,
}

-- Modal --------------------------------------------------------------------------------------

local function tabButton(page, index: number)
	local active = scope:Computed(function(use)
		return use(current) == page.Id
	end)
	return scope:Button {
		Name = page.Id,
		Variant = "Ghost",
		Icon = page.Icon,
		IconSize = 16,
		Label = scope:Computed(function(use)
			return if use(Screen.Layout) == "Wide" then page.Title else ""
		end),
		TextSize = 11,
		Gap = 8,
		Accent = scope:Computed(function(use)
			return if use(active) then C.BrassBright else C.Muted
		end),
		Active = active,
		Size = scope:Computed(function(use)
			return if use(Screen.Layout) == "Wide" then UDim2.fromOffset(if page.Id == "Relics" then 178 else 150, 38) else UDim2.fromOffset(52, 38)
		end),
		LayoutOrder = index,
		OnClick = function()
			Panels.Open(page.Id)
		end,
	}
end

local function buildModal(layer: Frame)
	local canvas = Screen.Canvas
	local pageInfo = scope:Computed(function(use)
		return PAGE_BY_ID[use(current) or "Upgrades"] or PAGES[1]
	end)
	-- Phones: a PhoneLayout page fills the screen and the whole modal is zoomed so text stays readable
	-- (portrait: laid out PORTRAIT_WIDTH wide, then scaled up to the screen; landscape: COMPACT_ZOOM with
	-- the tabs moved onto the title row to save height). Other pages keep the regular modal.
	local phone = scope:Computed(function(use)
		return use(Screen.Layout) ~= "Wide" and use(pageInfo).PhoneLayout == true
	end)
	local inlineTabs = scope:Computed(function(use)
		return use(phone) and use(Screen.Layout) == "Compact"
	end)
	local zoom = scope:Computed(function(use)
		if not use(phone) then
			return 1
		end
		if use(Screen.Layout) == "Portrait" then
			local c: Vector2 = use(canvas)
			return math.clamp((c.X - 24) / PORTRAIT_WIDTH, 1, 2)
		end
		return COMPACT_ZOOM
	end)
	local panelSize = scope:Computed(function(use)
		local c: Vector2 = use(canvas)
		if use(phone) then
			local z = use(zoom)
			return UDim2.fromOffset(math.min(940, (c.X - 24) / z), (c.Y - 16) / z)
		end
		local w = math.min(940, c.X - 40)
		local h = math.min(600, c.Y - 30)
		return UDim2.fromOffset(math.max(w, 300), math.max(h, 260))
	end)
	-- header height: the regular header has the tabs on a second row
	local contentTop = scope:Computed(function(use)
		return if use(inlineTabs) then 82 else 138
	end)
	local cash = scope:Computed(function(use)
		return getData(use).Cash or 0
	end)

	local tabs = {}
	for index, page in PAGES do
		table.insert(tabs, tabButton(page, index))
	end

	-- Backdrop: dims the world, click outside closes.
	scope:New "TextButton" {
		Name = "Backdrop",
		Parent = layer,
		AutoButtonColor = false,
		Text = "",
		Selectable = false,
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = scope:Spring(scope:Computed(function(use)
			return if use(shown) then 0.38 else 1
		end), 20, 1),
		Size = UDim2.fromScale(3, 3),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Visible = shown,
		[OnEvent "Activated"] = function()
			Panels.Close()
		end,
	}

	-- Enter (not Reveal): ViewportFrames do not render inside CanvasGroups.
	local modal = scope:Enter {
		Name = "Modal",
		Shown = shown,
		Size = panelSize,
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Offset = UDim2.fromOffset(0, 24),
		Speed = 26,
		Children = {
			scope:Plate {
				Name = "Panel",
				Size = UDim2.fromScale(1, 1),
				Fill = 0.03,
				Children = {
					-- swallow clicks so tapping the panel doesn't hit the backdrop
					scope:New "TextButton" {
						Name = "Sink",
						AutoButtonColor = false,
						Text = "",
						Selectable = false,
						BackgroundTransparency = 1,
						Size = UDim2.fromScale(1, 1),
						ZIndex = 0,
					},
					-- Header
					scope:New "Frame" {
						Name = "Header",
						BackgroundTransparency = 1,
						Size = UDim2.new(1, -40, 0, 64),
						Position = UDim2.fromOffset(20, 10),
						[Children] = {
							Kit.Icon(scope, {
								Name = "GameIcon",
								Size = UDim2.fromOffset(52, 52),
								Position = UDim2.fromOffset(0, 6),
							}),
							scope:Eyebrow {
								Text = scope:Computed(function(use)
									return string.upper(use(pageInfo).Tagline)
								end),
								TextSize = 9,
								Height = 14,
								Color = C.Muted,
								BulletColor = C.Brass,
								Position = UDim2.fromOffset(62, 8),
								Visible = scope:Computed(function(use)
									return use(Screen.Layout) == "Wide"
								end),
							},
							scope:Text {
								Text = scope:Computed(function(use)
									return use(pageInfo).Title
								end),
								Font = Theme.Font.Display,
								TextSize = 24,
								XAlign = Enum.TextXAlignment.Left,
								AutoSize = "X",
								Size = UDim2.fromOffset(0, 30),
								Position = scope:Computed(function(use)
									return if use(Screen.Layout) == "Wide" then UDim2.fromOffset(62, 26) else UDim2.fromOffset(62, 14)
								end),
								-- inline tabs take the title's place (the active tab shows the page)
								Visible = scope:Computed(function(use)
									return not use(inlineTabs)
								end),
							},
							-- cash + close (right)
							scope:New "Frame" {
								Name = "Right",
								BackgroundTransparency = 1,
								AutomaticSize = Enum.AutomaticSize.X,
								Size = UDim2.fromOffset(0, 44),
								Position = UDim2.new(1, 0, 0, 10),
								AnchorPoint = Vector2.new(1, 0),
								[Children] = {
									scope:New "UIListLayout" {
										FillDirection = Enum.FillDirection.Horizontal,
										VerticalAlignment = Enum.VerticalAlignment.Center,
										HorizontalAlignment = Enum.HorizontalAlignment.Right,
										Padding = UDim.new(0, 12),
										SortOrder = Enum.SortOrder.LayoutOrder,
									},
									scope:Icon { Name = "Coin", Color = C.Gold, Size = UDim2.fromOffset(22, 22), LayoutOrder = 1 },
									scope:Counter {
										Value = cash,
										Format = Format.Cash,
										TextSize = 18,
										Color = C.Ivory,
										AutoSize = "X",
										Size = UDim2.fromOffset(0, 24),
										LayoutOrder = 2,
									},
									scope:IconButton {
										Name = "Close",
										Icon = "Close",
										Accent = C.Muted,
										Variant = "Outline",
										Size = UDim2.fromOffset(44, 44),
										IconSize = 16,
										LayoutOrder = 3,
										GamepadHint = Enum.KeyCode.ButtonB,
										OnClick = function()
											Panels.Close()
										end,
									},
								},
							},
						},
					},
					-- Tabs
					scope:New "Frame" {
						Name = "Tabs",
						BackgroundTransparency = 1,
						Size = UDim2.new(1, -40, 0, 40),
						Position = scope:Computed(function(use)
							return if use(inlineTabs) then UDim2.fromOffset(82, 22) else UDim2.fromOffset(20, 78)
						end),
						[Children] = {
							scope:New "UIListLayout" {
								FillDirection = Enum.FillDirection.Horizontal,
								Padding = UDim.new(0, 8),
								SortOrder = Enum.SortOrder.LayoutOrder,
							},
							tabs,
						},
					},
					scope:New "Frame" {
						Name = "Divider",
						BackgroundColor3 = C.BrassDim,
						BackgroundTransparency = 0.4,
						BorderSizePixel = 0,
						Size = UDim2.new(1, -40, 0, 1),
						Position = scope:Computed(function(use)
							return UDim2.fromOffset(20, use(contentTop) - 12)
						end),
					},
					-- Page content (rebuilt when the tab or the screen layout changes)
					scope:New "Frame" {
						Name = "Content",
						BackgroundTransparency = 1,
						ClipsDescendants = true,
						Size = scope:Computed(function(use)
							return UDim2.new(1, -40, 1, -(use(contentTop) + 14))
						end),
						Position = scope:Computed(function(use)
							return UDim2.fromOffset(20, use(contentTop))
						end),
						[Children] = {
							scope:Computed(function(use, pageScope)
								local id = use(current)
								use(Screen.Layout)
								if not id then
									return nil
								end
								local builder = BUILDERS[id]
								if not builder then
									return nil
								end
								local ok, result = pcall(builder, pageScope)
								if not ok then
									warn("[Panels] build failed:", id, result)
									return nil
								end
								return result
							end),
						},
					},
				},
			},
		},
	}
	scope:New "UIScale" {
		Name = "PhoneZoom",
		Scale = zoom,
		Parent = modal,
	}
	modal.Parent = layer
end

-- API ----------------------------------------------------------------------------------------

local function bindBack(on: boolean)
	if on then
		ContextActionService:BindAction("OMF_ClosePanel", function(_, inputState)
			if inputState == Enum.UserInputState.Begin then
				Panels.Close()
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.KeyCode.ButtonB)
	else
		ContextActionService:UnbindAction("OMF_ClosePanel")
	end
end

function Panels.Close()
	if not peek(shown) then
		return
	end
	shown:set(false)
	bindBack(false)
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(Screen.Get("Panels")) then
		GuiService.SelectedObject = nil
	end
	task.delay(0.25, function()
		if not peek(shown) then
			current:set(nil)
			notify()
		end
	end)
	notify()
end

function Panels.Open(name: string)
	if not PAGE_BY_ID[name] then
		return
	end
	if State.InRun() then
		Toast.Show("Finish your run first!", "info")
		return
	end
	if peek(current) == name and peek(shown) then
		return
	end
	selectedRelic:set(nil)
	current:set(name)
	if not peek(shown) then
		shown:set(true)
		bindBack(true)
	end
	notify()
	task.delay(0.15, function()
		local layer = Screen.Get("Panels")
		local content = layer:FindFirstChild("Content", true)
		if content then
			for _, d in content:GetDescendants() do
				if d:IsA("GuiButton") and d.Selectable then
					Kit.Select(d)
					break
				end
			end
		end
	end)
end

function Panels.Toggle(name: string)
	if peek(current) == name and peek(shown) then
		Panels.Close()
	else
		Panels.Open(name)
	end
end

function Panels.Current(): string?
	return if peek(shown) then peek(current) else nil
end

function Panels.Start()
	buildModal(Screen.Get("Panels"))
	dataV:set(State.Data)
	State.DataChanged:Connect(function(data)
		dataV:set(data)
	end)

	Net.Event("OpenPanel").OnClientEvent:Connect(function(name)
		if typeof(name) == "string" then
			Panels.Open(name)
		end
	end)

	ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
		if who ~= Players.LocalPlayer then
			return
		end
		local name = prompt:GetAttribute("Panel")
		if name == nil and prompt.Parent then
			name = prompt.Parent:GetAttribute("Panel")
		end
		if typeof(name) == "string" then
			Panels.Open(name)
		end
	end)

	Players.LocalPlayer:GetAttributeChangedSignal("InRun"):Connect(function()
		if Players.LocalPlayer:GetAttribute("InRun") then
			Panels.Close()
		end
	end)
end

return Panels
