-- Elimination moment, the Extra Life revive offer and the spectator console (curse voting, back
-- to lobby, Extra Life / Bless / Curse).
--
-- Revive offer: when `Eliminated` arrives with ReviveUntil in the future, a focused card replaces
-- the console for the window ("Keep your $X bag", drain bar, tier price, one EXTRA LIFE button,
-- a quiet NOT NOW). It closes when the window ends, when you are revived (status back to Alive),
-- when ExtraLifeUsed is set, or when dismissed (B on gamepad). While the Roblox purchase prompt is
-- open it stays up (the server holds the window too).

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Net = require(ReplicatedStorage.Shared.Net)
local Config = require(ReplicatedStorage.Shared.Config)
local Curses = require(ReplicatedStorage.Shared.Curses)
local Format = require(ReplicatedStorage.Shared.Format)
local Theme = require(script.Parent.Parent.UI.Theme)
local Kit = require(script.Parent.Parent.UI.Kit)
local Store = require(script.Parent.Parent.Util.Store)
local Screen = require(script.Parent.Screen)
local State = require(script.Parent.State)
local Audio = require(script.Parent.Audio)
local CameraShake = require(script.Parent.CameraShake)
local Effects = require(script.Parent.Effects)
local Briefing = require(script.Parent.Briefing)

local Children = Fusion.Children
local peek = Fusion.peek
local C = Theme.Color

local Spectator = {}

local scope = Fusion.scoped(Fusion, Kit)

local runV = scope:Value(nil :: any)
local consoleShown = scope:Value(false)
local voteOptions = scope:Value({} :: { string })
local voteEndsAt = scope:Value(0)
local myVote = scope:Value(nil :: string?)
local voteRemaining = scope:Value(0)

-- revive offer
local offerShown = scope:Value(false)
local offerUntil = 0 -- server time; 0 = no offer
local offerTotal = scope:Value(Config.Monetization.ReviveWindow)
local offerLeft = scope:Value(0)
local offerBag = scope:Value(0)
local offerFloor = scope:Value(0)
local offerKey = scope:Value("ExtraLife")
local promptOpen = scope:Value(false)
local reviving = scope:Value(false)
local promptToken = 0
local lastStatus: string? = nil
local reviveButton: GuiObject? = nil

local consoleVisible = scope:Computed(function(use)
	return use(consoleShown) and not use(offerShown)
end)

local overlay: Frame

-- Elimination ---------------------------------------------------------------------------------

local function showEliminated(info)
	if info.Saved then
		local label = if info.Saved == "Phoenix" then "PHOENIX REVIVE" else "SAVED BY SHIELD"
		Briefing.Banner(label, C.Cyan, 1.4)
		Effects.Flash(C.Cyan, 0.4)
		CameraShake.Shake(1, 0.4)
		Audio.Play("Survived")
		return
	end

	Effects.Flash(C.Red, 0.6)
	CameraShake.Shake(2, 0.7)
	Audio.Play("Eliminated")

	local lost = tonumber(info.Lost) or 0
	local kept = tonumber(info.Kept) or 0
	local dropped = tonumber(info.Dropped) or 0
	local parts = {}
	if lost > 0 then
		table.insert(parts, "LOST " .. Format.Cash(lost))
	end
	if kept > 0 then
		table.insert(parts, "INSURANCE KEPT " .. Format.Cash(kept))
	end
	if dropped > 0 then
		table.insert(parts, Format.Cash(dropped) .. " DROPPED FOR THE SURVIVORS")
	end

	local inner = scope:innerScope()
	local shown = inner:Value(false)
	local slam = inner:Spring(inner:Computed(function(use)
		return if use(shown) then 1 else 1.35
	end), 26, 0.55)
	local root = Kit.Reveal(inner, {
		Name = "Eliminated",
		Shown = shown,
		Size = UDim2.new(1, 0, 0, 230),
		Position = UDim2.fromScale(0, 0.4),
		AnchorPoint = Vector2.new(0, 0.5),
		Offset = UDim2.new(),
		HiddenScale = 1,
		Children = {
			inner:New "Frame" {
				Name = "Band",
				BackgroundColor3 = Color3.fromRGB(40, 4, 12),
				BackgroundTransparency = 0.2,
				BorderSizePixel = 0,
				Size = UDim2.new(1, 0, 0, 180),
				Position = UDim2.fromScale(0.5, 0.5),
				AnchorPoint = Vector2.new(0.5, 0.5),
				[Children] = {
					inner:New "UIGradient" {
						Transparency = NumberSequence.new({
							NumberSequenceKeypoint.new(0, 1),
							NumberSequenceKeypoint.new(0.2, 0),
							NumberSequenceKeypoint.new(0.8, 0),
							NumberSequenceKeypoint.new(1, 1),
						}),
					},
				},
			},
			inner:New "Frame" {
				Name = "Content",
				BackgroundTransparency = 1,
				Size = UDim2.new(0, 860, 0, 170),
				Position = UDim2.fromScale(0.5, 0.5),
				AnchorPoint = Vector2.new(0.5, 0.5),
				[Children] = {
					inner:New "UIListLayout" {
						Padding = UDim.new(0, 6),
						HorizontalAlignment = Enum.HorizontalAlignment.Center,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						SortOrder = Enum.SortOrder.LayoutOrder,
					},
					Kit.Eyebrow(inner, {
						Text = if typeof(info.Reason) == "string" and info.Reason ~= "" then string.upper(info.Reason) else "YOU FELL",
						Color = C.Red:Lerp(C.Ivory, 0.3),
						BulletColor = C.Red,
						HAlign = Enum.HorizontalAlignment.Center,
						TextSize = 12,
						Height = 18,
						LayoutOrder = 1,
					}),
					inner:New "Frame" {
						BackgroundTransparency = 1,
						Size = UDim2.new(1, 0, 0, 70),
						LayoutOrder = 2,
						[Children] = {
							inner:New "UIScale" { Scale = slam },
							Kit.Text(inner, {
								Text = "ELIMINATED",
								Font = Theme.Font.Display,
								TextSize = 58,
								Color = C.Red,
								Stroke = 2,
								StrokeTransparency = 0.3,
							}),
						},
					},
					if #parts > 0
						then Kit.Text(inner, {
							Text = table.concat(parts, "   ·   "),
							Font = Theme.Font.Display,
							TextSize = 14,
							Color = C.Gold,
							Size = UDim2.new(1, 0, 0, 20),
							LayoutOrder = 3,
						})
						else nil,
				},
			},
		},
	})
	root.Parent = overlay
	shown:set(true)
	task.delay(2.6, function()
		shown:set(false)
		task.delay(0.5, function()
			Fusion.doCleanup(inner)
		end)
	end)
end

-- Console -------------------------------------------------------------------------------------

local function voteCard(inner: any, index: number, id: string): GuiObject
	local curse = Curses.ById[id]
	local selected = inner:Computed(function(use)
		return use(myVote) == id
	end)
	return Kit.Button(inner, {
		Name = id,
		Variant = "Solid",
		Accent = C.Violet,
		Active = selected,
		LayoutOrder = index,
		Size = UDim2.new(1 / 3, -8, 1, 0),
		OnClick = function()
			if peek(myVote) == id then
				return
			end
			myVote:set(id)
			Net.Event("Vote"):FireServer(id)
		end,
		Children = {
			inner:New "Frame" {
				Name = "Stripe",
				BackgroundColor3 = curse and curse.Color or C.Violet,
				BorderSizePixel = 0,
				Size = UDim2.new(1, -12, 0, 2),
				Position = UDim2.fromOffset(6, 6),
			},
			Kit.Text(inner, {
				Text = string.upper(curse and curse.Name or id),
				Font = Theme.Font.Display,
				TextSize = 13,
				Color = C.Ivory,
				Size = UDim2.new(1, -16, 0, 18),
				Position = UDim2.new(0.5, 0, 0, 16),
				AnchorPoint = Vector2.new(0.5, 0),
			}),
			Kit.Text(inner, {
				Text = curse and curse.Desc or "",
				Font = Theme.Font.Body,
				TextSize = 13,
				Color = C.Muted,
				Wrapped = true,
				Size = UDim2.new(1, -16, 0, 34),
				Position = UDim2.new(0.5, 0, 0, 38),
				AnchorPoint = Vector2.new(0.5, 0),
			}),
			Kit.Text(inner, {
				Text = inner:Computed(function(use)
					return if use(selected) then "YOUR VOTE" else "TAP TO VOTE"
				end),
				Font = Theme.Font.Display,
				TextSize = 9,
				Color = inner:Computed(function(use)
					return if use(selected) then C.Violet:Lerp(C.Ivory, 0.4) else C.Faint
				end),
				Size = UDim2.new(1, -16, 0, 14),
				Position = UDim2.new(0.5, 0, 1, -10),
				AnchorPoint = Vector2.new(0.5, 1),
			}),
		},
	})
end

-- Console purchase button: label + Robux price underneath ("coming soon" while the id is 0).
local function productButton(props: { [string]: any }): TextButton
	local available = scope:Computed(function(use)
		return Store.Available(Kit.read(use, props.PriceKey))
	end)
	local used = props.Used or false
	return scope:Button {
		Name = props.Name,
		Variant = "Solid",
		Icon = props.PriceKey,
		IconSize = 28,
		Label = props.Label,
		Sub = scope:Computed(function(use)
			if Kit.read(use, used) then
				return "used this run"
			elseif not use(available) then
				return "coming soon"
			end
			return Store.PriceText(use, Kit.read(use, props.PriceKey), "")
		end),
		TextSize = 12,
		SubSize = 11,
		Gap = 9,
		Accent = props.Accent,
		Enabled = scope:Computed(function(use)
			return use(available) and not Kit.read(use, used)
		end),
		Visible = props.Visible,
		Size = UDim2.fromOffset(180, 48),
		LayoutOrder = props.LayoutOrder,
		OnClick = function()
			Store.Prompt(props.PromptKey or peek(props.PriceKey))
		end,
	}
end

local function buildConsole(layer: Frame)
	local notDaily = scope:Computed(function(use)
		local run = use(runV)
		return not (run ~= nil and run.Mode == "Daily")
	end)
	local lifeKey = scope:Computed(function(use)
		local run = use(runV)
		return Config.ExtraLifeKey(math.max(run and run.Floor or 1, 1))
	end)
	local lifeUsed = scope:Computed(function(use)
		local run = use(runV)
		return run ~= nil and run.You ~= nil and run.You.ExtraLifeUsed == true
	end)
	local hasVote = scope:Computed(function(use)
		return #use(voteOptions) > 0
	end)
	local root = scope:Reveal {
		Name = "Spectator",
		Shown = consoleVisible,
		Size = UDim2.fromOffset(720, 250),
		Position = UDim2.new(0.5, 0, 1, -14),
		AnchorPoint = Vector2.new(0.5, 1),
		Offset = UDim2.fromOffset(0, 40),
		Children = {
			scope:New "UIScale" {
				Scale = scope:Computed(function(use)
					return if use(Screen.Layout) == "Wide" then 1 else 0.84
				end),
			},
			scope:Plate {
				Size = UDim2.fromScale(1, 1),
				Accent = C.Violet,
				Children = {
					scope:Eyebrow {
						Text = "SPECTATING",
						Color = C.Violet,
						TextSize = 11,
						Position = UDim2.fromOffset(18, 14),
					},
					scope:Text {
						Text = scope:Computed(function(use)
							return if use(hasVote) then "CURSE THE NEXT FLOOR" else "WATCH THE SURVIVORS"
						end),
						Font = Theme.Font.Display,
						TextSize = 18,
						XAlign = Enum.TextXAlignment.Left,
						Size = UDim2.new(1, -160, 0, 24),
						Position = UDim2.fromOffset(18, 32),
					},
					scope:New "Frame" {
						Name = "Timer",
						BackgroundTransparency = 1,
						Size = UDim2.fromOffset(110, 30),
						Position = UDim2.new(1, -18, 0, 20),
						AnchorPoint = Vector2.new(1, 0),
						Visible = hasVote,
						[Children] = {
							scope:New "UIListLayout" {
								FillDirection = Enum.FillDirection.Horizontal,
								HorizontalAlignment = Enum.HorizontalAlignment.Right,
								VerticalAlignment = Enum.VerticalAlignment.Center,
								Padding = UDim.new(0, 8),
							},
							scope:Icon { Name = "Clock", Color = C.Muted, Size = UDim2.fromOffset(16, 16) },
							scope:Text {
								Text = scope:Computed(function(use)
									return tostring(math.ceil(use(voteRemaining)))
								end),
								Font = Theme.Font.Display,
								TextSize = 20,
								AutoSize = "X",
								Size = UDim2.fromOffset(0, 26),
							},
						},
					},
					scope:New "Frame" {
						Name = "Votes",
						BackgroundTransparency = 1,
						Size = UDim2.new(1, -36, 0, 104),
						Position = UDim2.fromOffset(18, 66),
						Visible = hasVote,
						[Children] = {
							scope:New "UIListLayout" {
								FillDirection = Enum.FillDirection.Horizontal,
								Padding = UDim.new(0, 10),
								SortOrder = Enum.SortOrder.LayoutOrder,
							},
							scope:ForPairs(voteOptions, function(_use, inner, index, id)
								return index, voteCard(inner, index, id)
							end),
						},
					},
					scope:Text {
						Text = "Voting opens between floors. A blessing gives every survivor a Bubble Shield; a curse hits their next floor.",
						Font = Theme.Font.Body,
						TextSize = 15,
						Color = C.Muted,
						Wrapped = true,
						Size = UDim2.new(1, -36, 0, 104),
						Position = UDim2.fromOffset(18, 66),
						Visible = scope:Computed(function(use)
							return not use(hasVote)
						end),
					},
					scope:New "Frame" {
						Name = "Actions",
						BackgroundTransparency = 1,
						Size = UDim2.new(1, -36, 0, 48),
						Position = UDim2.new(0, 18, 1, -16),
						AnchorPoint = Vector2.new(0, 1),
						[Children] = {
							scope:New "UIListLayout" {
								FillDirection = Enum.FillDirection.Horizontal,
								Padding = UDim.new(0, 10),
								SortOrder = Enum.SortOrder.LayoutOrder,
							},
							scope:Button {
								Name = "Lobby",
								Variant = "Ghost",
								Icon = "Home",
								IconSize = 16,
								Label = "LOBBY",
								TextSize = 12,
								Accent = C.Muted,
								Size = UDim2.fromOffset(112, 48),
								LayoutOrder = 1,
								OnClick = function()
									Net.Event("ReturnToLobby"):FireServer()
								end,
							},
							productButton {
								Name = "ExtraLife",
								Icon = "Heart",
								Label = "EXTRA LIFE",
								Accent = C.Cyan,
								PriceKey = lifeKey,
								PromptKey = "ExtraLife",
								Used = lifeUsed,
								Visible = notDaily,
								LayoutOrder = 2,
							},
							productButton {
								Name = "Bless",
								Icon = "Shield",
								Label = "BLESS THEM",
								Accent = C.Green,
								PriceKey = "BlessElevator",
								Visible = notDaily,
								LayoutOrder = 3,
							},
							productButton {
								Name = "Curse",
								Icon = "Curse",
								Label = "CURSE THEM",
								Accent = C.Violet,
								PriceKey = "CurseElevator",
								LayoutOrder = 4,
							},
						},
					},
				},
			},
		},
	}
	root.Parent = layer
end

-- Revive offer -------------------------------------------------------------------------------------

local function selectConsole()
	local console = Screen.Get("Run"):FindFirstChild("Spectator", true)
	if not console then
		return
	end
	local votes = console:FindFirstChild("Votes", true)
	local first = votes and votes:FindFirstChildWhichIsA("GuiButton")
	if not (first and first.Visible) then
		local actions = console:FindFirstChild("Actions", true)
		first = actions and actions:FindFirstChild("Lobby")
	end
	Kit.Select(first)
end

local function bindDismiss(on: boolean)
	if on then
		ContextActionService:BindActionAtPriority("OMF_ReviveDismiss", function(_, inputState)
			if inputState == Enum.UserInputState.Begin then
				Spectator.DismissOffer()
			end
			return Enum.ContextActionResult.Sink
		end, false, 3000, Enum.KeyCode.ButtonB)
	else
		ContextActionService:UnbindAction("OMF_ReviveDismiss")
	end
end

local reviveRoot: GuiObject? = nil

local function closeOffer()
	offerUntil = 0
	promptToken += 1
	promptOpen:set(false)
	reviving:set(false)
	if not peek(offerShown) then
		return
	end
	offerShown:set(false)
	bindDismiss(false)
	local selected = GuiService.SelectedObject
	if selected and reviveRoot and selected:IsDescendantOf(reviveRoot) then
		GuiService.SelectedObject = nil
	end
	if peek(consoleShown) then
		task.delay(0.35, selectConsole)
	end
end

function Spectator.DismissOffer()
	closeOffer()
end

local function openOffer(info)
	local untilT = tonumber(info.ReviveUntil) or 0
	local now = workspace:GetServerTimeNow()
	if untilT <= now + 0.5 then
		return
	end
	local floor = tonumber(info.Floor) or 1
	offerUntil = untilT
	offerTotal:set(math.max(untilT - now, 1))
	offerLeft:set(untilT - now)
	offerBag:set(tonumber(info.ReviveBag) or tonumber(info.Lost) or 0)
	offerFloor:set(floor)
	offerKey:set(if typeof(info.ExtraLifeKey) == "string" then info.ExtraLifeKey else Config.ExtraLifeKey(math.max(floor, 1)))
	promptOpen:set(false)
	reviving:set(false)
	-- let the ELIMINATED slam land first
	task.delay(0.35, function()
		if offerUntil ~= untilT or workspace:GetServerTimeNow() >= untilT then
			return
		end
		offerShown:set(true)
		bindDismiss(true)
		task.delay(0.25, function()
			if peek(offerShown) then
				Kit.Select(reviveButton)
			end
		end)
	end)
end

-- Test / preview hook: Spectator.PreviewOffer({ ReviveUntil = now + 10, ReviveBag = 12345, Floor = 12 })
function Spectator.PreviewOffer(info)
	openOffer(info)
end

local function buyRevive()
	if peek(promptOpen) or peek(reviving) or not Store.Available(peek(offerKey)) then
		return
	end
	promptToken += 1
	local token = promptToken
	promptOpen:set(true)
	Store.Prompt("ExtraLife")
	-- safety net if the prompt-closed event never reaches us
	task.delay(35, function()
		if token == promptToken and peek(promptOpen) then
			promptOpen:set(false)
		end
	end)
end

local function buildRevive(layer: Frame)
	local available = scope:Computed(function(use)
		return Store.Available(use(offerKey))
	end)
	local busy = scope:Computed(function(use)
		return use(promptOpen) or use(reviving)
	end)
	local urgent = scope:Computed(function(use)
		return use(offerLeft) <= 3 and not use(busy)
	end)
	local pulse = Kit.Pulse(scope, urgent, 1)
	local accent = scope:Tween(scope:Computed(function(use)
		return if use(urgent) then C.Red else C.Cyan
	end), Theme.Tween.Base)
	local seconds = scope:Computed(function(use)
		return math.max(math.ceil(use(offerLeft)), 0)
	end)

	local button = scope:Button {
		Name = "ExtraLife",
		Variant = "Primary",
		Accent = C.Cyan,
		Icon = offerKey,
		IconSize = 30,
		Enabled = scope:Computed(function(use)
			return use(available) and not use(busy)
		end),
		Label = scope:Computed(function(use)
			if use(reviving) then
				return "REVIVING…"
			elseif use(promptOpen) then
				return "WAITING FOR PURCHASE…"
			elseif not use(available) then
				return "EXTRA LIFE  ·  COMING SOON"
			end
			local price = Store.PriceText(use, use(offerKey), "")
			return if price ~= "" then "EXTRA LIFE  ·  " .. price else "EXTRA LIFE"
		end),
		TextSize = 17,
		Size = UDim2.new(1, -44, 0, 58),
		Position = UDim2.new(0.5, 0, 1, -50),
		AnchorPoint = Vector2.new(0.5, 1),
		OnClick = buyRevive,
	}
	reviveButton = button

	local root = scope:Reveal {
		Name = "Revive",
		Shown = offerShown,
		Size = UDim2.fromOffset(540, 244),
		Position = UDim2.new(0.5, 0, 1, -14),
		AnchorPoint = Vector2.new(0.5, 1),
		Offset = UDim2.fromOffset(0, 40),
		HiddenScale = 0.94,
		Speed = 24,
		Children = {
			scope:New "UIScale" {
				Scale = scope:Computed(function(use)
					return if use(Screen.Layout) == "Wide" then 1 else 0.84
				end),
			},
			scope:Plate {
				Size = UDim2.fromScale(1, 1),
				Accent = C.Cyan,
				Fill = 0.03,
				Children = {
					-- the window, draining along the top edge
					scope:Bar {
						Name = "Window",
						Progress = scope:Computed(function(use)
							return use(offerLeft) / math.max(use(offerTotal), 0.1)
						end),
						Color = accent,
						Size = UDim2.new(1, -20, 0, 3),
						Position = UDim2.new(0.5, 0, 0, 10),
						AnchorPoint = Vector2.new(0.5, 0),
					},
					scope:Eyebrow {
						Text = "SECOND CHANCE",
						Color = C.Cyan,
						TextSize = 11,
						Position = UDim2.fromOffset(22, 26),
					},
					-- seconds left inside a deco diamond
					scope:New "Frame" {
						Name = "Timer",
						BackgroundTransparency = 1,
						Size = UDim2.fromOffset(56, 56),
						Position = UDim2.new(1, -20, 0, 22),
						AnchorPoint = Vector2.new(1, 0),
						[Children] = {
							scope:New "UIScale" {
								Scale = scope:Computed(function(use)
									return 1 + use(pulse) * 0.08
								end),
							},
							scope:New "Frame" {
								Name = "Diamond",
								BackgroundColor3 = C.Ink,
								BackgroundTransparency = 0.1,
								Size = UDim2.fromOffset(38, 38),
								Position = UDim2.fromScale(0.5, 0.5),
								AnchorPoint = Vector2.new(0.5, 0.5),
								Rotation = 45,
								[Children] = {
									scope:New "UICorner" { CornerRadius = UDim.new(0, 2) },
									scope:New "UIStroke" { Color = accent, Thickness = 1.5 },
								},
							},
							scope:Text {
								Text = scope:Computed(function(use)
									return if use(busy) then "–" else tostring(use(seconds))
								end),
								Font = Theme.Font.Display,
								TextSize = 18,
								Color = accent,
							},
						},
					},
					scope:Text {
						Name = "Headline",
						Text = scope:Computed(function(use)
							return string.format('KEEP YOUR <font color="#FFCC58">$%s</font> BAG', Format.Comma(use(offerBag)))
						end),
						Font = Theme.Font.Display,
						Scaled = 24,
						Rich = true,
						XAlign = Enum.TextXAlignment.Left,
						Size = UDim2.new(1, -112, 0, 30),
						Position = UDim2.fromOffset(22, 48),
					},
					scope:Text {
						Name = "Detail",
						Text = scope:Computed(function(use)
							return string.format("Back in the cab on B%d with your bag restored. One Extra Life per run.", use(offerFloor))
						end),
						Font = Theme.Font.Body,
						TextSize = 15,
						Color = C.Muted,
						Wrapped = true,
						XAlign = Enum.TextXAlignment.Left,
						YAlign = Enum.TextYAlignment.Top,
						Size = UDim2.new(1, -44, 0, 40),
						Position = UDim2.fromOffset(22, 86),
					},
					button,
					scope:Text {
						Name = "Fine",
						Text = scope:Computed(function(use)
							local key = use(offerKey)
							local tier = if key == "ExtraLife3" then "B20+" elseif key == "ExtraLife2" then "B10-19" else "B1-9"
							return "Price for floors " .. tier .. "  ·  Normal runs only"
						end),
						Font = Theme.Font.Body,
						TextSize = 12,
						Color = C.Faint,
						XAlign = Enum.TextXAlignment.Left,
						Size = UDim2.new(1, -180, 0, 30),
						Position = UDim2.new(0, 22, 1, -12),
						AnchorPoint = Vector2.new(0, 1),
					},
					scope:Button {
						Name = "Dismiss",
						Variant = "Ghost",
						Label = "NOT NOW",
						TextSize = 10,
						Accent = C.Muted,
						GamepadHint = Enum.KeyCode.ButtonB,
						Size = UDim2.fromOffset(120, 30),
						Position = UDim2.new(1, -22, 1, -12),
						AnchorPoint = Vector2.new(1, 1),
						OnClick = closeOffer,
					},
				},
			},
		},
	}
	root.Parent = layer
	reviveRoot = root
end

-- Wiring ------------------------------------------------------------------------------------------

local function refresh(run)
	runV:set(run)
	local you = run and run.You
	local status = you and you.Status

	-- revive offer bookkeeping
	if offerUntil > 0 or peek(offerShown) then
		if not run or not you or run.Phase == "Ended" or status == "Left" or you.ExtraLifeUsed == true then
			closeOffer()
		elseif status == "Alive" and lastStatus == "Dead" then
			closeOffer() -- revived
		elseif you.ReviveUntil ~= nil then
			local u = tonumber(you.ReviveUntil) or 0
			if u > 0 then
				offerUntil = u
			elseif not peek(promptOpen) and not peek(reviving) then
				closeOffer()
			end
		end
	end
	lastStatus = status

	local show = run ~= nil and you ~= nil and status == "Dead" and run.Phase ~= "Ended"
	if show and not peek(consoleShown) and not peek(offerShown) and offerUntil == 0 then
		task.delay(0.4, selectConsole)
	end
	consoleShown:set(show)
	if not show then
		voteOptions:set({})
		myVote:set(nil)
	end
end

function Spectator.Start()
	overlay = Screen.Get("Overlay")
	buildConsole(Screen.Get("Run"))
	buildRevive(Screen.Get("Run"))

	Net.Event("Eliminated").OnClientEvent:Connect(function(info)
		if typeof(info) == "table" then
			showEliminated(info)
			if not info.Saved then
				openOffer(info)
			end
		end
	end)
	Net.Event("VoteOptions").OnClientEvent:Connect(function(info)
		myVote:set(nil)
		if typeof(info) == "table" and typeof(info.Options) == "table" and #info.Options > 0 then
			voteOptions:set(table.clone(info.Options))
			voteEndsAt:set(tonumber(info.EndsAt) or 0)
		else
			voteOptions:set({})
			voteEndsAt:set(0)
		end
	end)
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, _productId, purchased)
		if userId ~= Players.LocalPlayer.UserId or not peek(promptOpen) then
			return
		end
		promptOpen:set(false)
		if purchased then
			-- the receipt revives us; RunUpdate (status Alive) closes the card
			reviving:set(true)
			local token = promptToken
			task.delay(8, function()
				if token == promptToken and peek(reviving) then
					closeOffer()
				end
			end)
		end
	end)
	State.RunChanged:Connect(refresh)
	refresh(State.Run)

	RunService.RenderStepped:Connect(function()
		local now = workspace:GetServerTimeNow()
		if peek(offerShown) and not peek(promptOpen) and not peek(reviving) then
			local left = offerUntil - now
			offerLeft:set(math.max(left, 0))
			if left <= 0 then
				closeOffer()
			end
		end
		if not peek(consoleShown) then
			return
		end
		local endsAt = peek(voteEndsAt)
		if endsAt > 0 then
			voteRemaining:set(math.max(endsAt - now, 0))
		end
	end)
end

return Spectator
