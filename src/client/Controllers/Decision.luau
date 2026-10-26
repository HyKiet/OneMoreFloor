-- The DEEPER / LEAVE moment: countdown, both outcomes side by side (what you bank now vs. what the
-- next floor could pay and what you risk), live choices of the other riders, and the run shop
-- after boss floors. Keyboard 1 / 2, gamepad X / Y (or select + A).

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Net = require(ReplicatedStorage.Shared.Net)
local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Relics = require(ReplicatedStorage.Shared.Relics)
local Theme = require(script.Parent.Parent.UI.Theme)
local Kit = require(script.Parent.Parent.UI.Kit)
local Store = require(script.Parent.Parent.Util.Store)
local Screen = require(script.Parent.Screen)
local State = require(script.Parent.State)
local Audio = require(script.Parent.Audio)
local CameraShake = require(script.Parent.CameraShake)

local Children = Fusion.Children
local peek = Fusion.peek
local C = Theme.Color

local Decision = {}

local scope = Fusion.scoped(Fusion, Kit)

local runV = scope:Value(nil :: any)
local dataV = scope:Value(nil :: any)
local visible = scope:Value(false)
local localChoice = scope:Value(nil :: string?)
local remaining = scope:Value(0)
local total = scope:Value(Config.DecisionTime)

local decisionKey: string? = nil
local lastSecond = -1
local deeperButton: GuiObject
local actionsBound = false

local function cashOutMultiplier(): number
	local data = State.Data
	if not data then
		return 1
	end
	local stats = Relics.SumStats(data.Equipped or {}, data.Relics or {})
	local mult = 1 + (stats.CashOut or 0)
	if data.Passes and data.Passes.DoubleCash then
		mult *= 2
	end
	-- mirrors Run:_cashOut: Golden Hour and Premium multiply on top
	if peek(Store.GoldenActive) then
		mult *= Config.Monetization.GoldenCashMult
	end
	if data.Premium == true then
		mult *= Config.Monetization.PremiumCashMult
	end
	return mult
end

local function you(run)
	return (run and run.You) or {}
end

function Decision.Choose(choice: string)
	if peek(localChoice) then
		return
	end
	local run = State.Run
	if not run or run.Phase ~= "Decision" or not run.You or run.You.Status ~= "Alive" then
		return
	end
	localChoice:set(choice)
	Net.Event("Choose"):FireServer(choice)
	if choice == "Deeper" then
		CameraShake.Shake(0.5, 0.3)
		Audio.Play("Countdown", 0.8)
	else
		Audio.Play("Purchase")
	end
end

-- Pieces ----------------------------------------------------------------------------------------

local function choiceChip(inner: any, info, index: number): GuiObject
	local status = info.Status
	local choice = info.Choice
	local accent, icon, label
	if status == "Dead" then
		accent, icon, label = C.Faint, "Skull", "OUT"
	elseif status == "Left" or choice == "Leave" then
		accent, icon, label = C.Gold, "Coin", "LEAVING"
	elseif choice == "Deeper" then
		accent, icon, label = C.Cyan, "Down", "DEEPER"
	else
		accent, icon, label = C.Muted, "Clock", "THINKING"
	end
	return Kit.Tag(inner, {
		Name = tostring(info.UserId),
		Text = string.format("%s · %s", tostring(info.Name or "?"), label),
		Icon = icon,
		Accent = accent,
		TextColor = if status == "Dead" then C.Faint else C.Ivory,
		Font = Theme.Font.Bold,
		TextSize = 12,
		Height = 24,
		LayoutOrder = index,
	})
end

local function choiceCard(props: { [string]: any }): GuiObject
	local mine = scope:Computed(function(use)
		return use(localChoice) == props.Choice
	end)
	local locked = scope:Computed(function(use)
		return use(localChoice) ~= nil
	end)
	local enabled = scope:Computed(function(use)
		return not use(locked) or use(mine)
	end)
	local button = scope:Button {
		Name = props.Choice,
		Variant = "Solid",
		Accent = props.Accent,
		Enabled = enabled,
		Active = mine,
		Size = UDim2.fromScale(1, 1),
		Hint = props.Key,
		GamepadHint = props.Pad,
		PadX = 18,
		OnClick = function()
			Decision.Choose(props.Choice)
		end,
		Children = {
			scope:New "Frame" {
				Name = "Body",
				BackgroundTransparency = 1,
				Size = UDim2.new(1, -36, 1, -28),
				Position = UDim2.fromScale(0.5, 0.5),
				AnchorPoint = Vector2.new(0.5, 0.5),
				[Children] = {
					scope:New "UIListLayout" {
						Padding = UDim.new(0, 4),
						SortOrder = Enum.SortOrder.LayoutOrder,
						HorizontalAlignment = Enum.HorizontalAlignment.Left,
						VerticalAlignment = Enum.VerticalAlignment.Center,
					},
					scope:New "Frame" {
						Name = "TitleRow",
						BackgroundTransparency = 1,
						Size = UDim2.new(1, 0, 0, 34),
						LayoutOrder = 1,
						[Children] = {
							scope:New "UIListLayout" {
								FillDirection = Enum.FillDirection.Horizontal,
								VerticalAlignment = Enum.VerticalAlignment.Center,
								Padding = UDim.new(0, 12),
								SortOrder = Enum.SortOrder.LayoutOrder,
							},
							scope:Icon {
								Name = props.Icon,
								Color = props.Accent,
								Size = UDim2.fromOffset(28, 28),
								LayoutOrder = 1,
								Position = props.IconOffset,
							},
							scope:Text {
								Text = scope:Computed(function(use)
									return if use(mine) then "LOCKED IN" else props.Title
								end),
								Font = Theme.Font.Display,
								TextSize = 26,
								Color = C.Ivory,
								AutoSize = "X",
								Size = UDim2.fromOffset(0, 34),
								LayoutOrder = 2,
							},
						},
					},
					scope:Text {
						Name = "Headline",
						Text = props.Headline,
						Font = Theme.Font.Display,
						TextSize = 20,
						Color = props.Accent,
						XAlign = Enum.TextXAlignment.Left,
						Size = UDim2.new(1, 0, 0, 26),
						LayoutOrder = 2,
						Rich = true,
					},
					scope:Text {
						Name = "Detail",
						Text = props.Detail,
						Font = Theme.Font.Bold,
						TextSize = 14,
						Color = C.Muted,
						XAlign = Enum.TextXAlignment.Left,
						Size = UDim2.new(1, 0, 0, 18),
						LayoutOrder = 3,
						Rich = true,
					},
				},
			},
			props.Extra,
		},
	}
	if props.Choice == "Deeper" then
		deeperButton = button
	end
	return button
end

local function shopStrip(): GuiObject
	local items = scope:Computed(function(use)
		local run = use(runV)
		return if run and run.ShopOpen then Config.RunItems else {}
	end)
	return scope:Reveal {
		Name = "RunShop",
		Shown = scope:Computed(function(use)
			local run = use(runV)
			return run ~= nil and run.ShopOpen == true
		end),
		Size = UDim2.new(1, 0, 0, 112),
		Position = UDim2.fromOffset(0, 0),
		Offset = UDim2.fromOffset(0, 16),
		Children = {
			scope:New "UIListLayout" {
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				Padding = UDim.new(0, 10),
				SortOrder = Enum.SortOrder.LayoutOrder,
			},
			scope:ForPairs(items, function(_use, inner, index, item)
				local owned = inner:Computed(function(use)
					local bought = you(use(runV)).Bought
					return bought ~= nil and bought[item.Id] == true
				end)
				local cost = inner:Computed(function(use)
					return math.floor((you(use(runV)).Bag or 0) * item.Cost)
				end)
				return index, Kit.Plate(inner, {
					Name = item.Id,
					Size = UDim2.new(1 / 3, -7, 1, 0),
					LayoutOrder = index,
					Accent = C.Brass,
					Brackets = false,
					Children = {
						Kit.Text(inner, {
							Text = string.upper(item.Name),
							Font = Theme.Font.Display,
							TextSize = 12,
							Color = C.BrassBright,
							XAlign = Enum.TextXAlignment.Left,
							Size = UDim2.new(1, -24, 0, 16),
							Position = UDim2.fromOffset(12, 10),
						}),
						Kit.Text(inner, {
							Text = item.Desc,
							Font = Theme.Font.Body,
							TextSize = 13,
							Color = C.Muted,
							Wrapped = true,
							XAlign = Enum.TextXAlignment.Left,
							YAlign = Enum.TextYAlignment.Top,
							Size = UDim2.new(1, -24, 0, 34),
							Position = UDim2.fromOffset(12, 28),
						}),
						Kit.Button(inner, {
							Variant = "Solid",
							Accent = C.Gold,
							Enabled = inner:Computed(function(use)
								return not use(owned)
							end),
							Label = inner:Computed(function(use)
								if use(owned) then
									return "OWNED"
								end
								return string.format("%s · %d%% OF BAG", Format.Cash(use(cost)), math.floor(item.Cost * 100 + 0.5))
							end),
							TextSize = 11,
							Size = UDim2.new(1, -20, 0, 34),
							Position = UDim2.new(0.5, 0, 1, -10),
							AnchorPoint = Vector2.new(0.5, 1),
							OnClick = function()
								if peek(owned) then
									return
								end
								Net.Event("BuyRunItem"):FireServer(item.Id)
								Audio.Play("Purchase")
							end,
						}),
					},
				})
			end),
		},
	}
end

-- Secondary action under the two choices: protect the bag with an Extra Life (banked now, it saves
-- the next elimination in this Normal run). Shows "x<N> banked" instead of selling when you have one.
local PROTECT_H = 50

local function protectRow(bag: any): GuiObject
	local banked = scope:Computed(function(use)
		local d = use(dataV)
		return (d and tonumber(d.ExtraLives)) or 0
	end)
	local relevant = scope:Computed(function(use)
		local run = use(runV)
		return run ~= nil and run.Mode ~= "Daily" and use(localChoice) ~= "Leave" and use(bag) > 0
	end)
	local tierKey = scope:Computed(function(use)
		local run = use(runV)
		return Config.ExtraLifeKey(math.max(run and run.Floor or 1, 1))
	end)
	local available = scope:Computed(function(use)
		return Store.Available(use(tierKey))
	end)
	return scope:New "Frame" {
		Name = "Protect",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 40),
		Position = UDim2.new(0.5, 0, 1, 0),
		AnchorPoint = Vector2.new(0.5, 1),
		Visible = relevant,
		[Children] = {
			scope:Button {
				Name = "ExtraLife",
				Variant = "Ghost",
				Icon = tierKey,
				IconSize = 26,
				Gap = 8,
				Accent = C.Cyan,
				Enabled = available,
				Label = scope:Computed(function(use)
					local price = if use(available) then Store.PriceText(use, use(tierKey), "") else "COMING SOON"
					local text = "EXTRA LIFE  ·  PROTECT " .. Format.Cash(use(bag))
					return if price ~= "" then text .. "  ·  " .. price else text
				end),
				TextSize = 11,
				Size = UDim2.fromOffset(470, 40),
				PadX = 18,
				Position = UDim2.fromScale(0.5, 0.5),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Visible = scope:Computed(function(use)
					return use(banked) <= 0
				end),
				OnClick = function()
					Store.Prompt("ExtraLife")
				end,
			},
			scope:Tag {
				Name = "Banked",
				Text = scope:Computed(function(use)
					return string.format("EXTRA LIFE x%d BANKED  ·  SAVES YOUR NEXT FALL", use(banked))
				end),
				Icon = tierKey,
				Accent = C.Cyan,
				Height = 28,
				TextSize = 10,
				Position = UDim2.fromScale(0.5, 0.5),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Visible = scope:Computed(function(use)
					return use(banked) > 0
				end),
			},
		},
	}
end

local function build(layer: Frame)
	local bag = scope:Computed(function(use)
		return you(use(runV)).Bag or 0
	end)
	local mult = scope:Computed(function(use)
		local run = use(runV)
		return run and run.Multiplier or Config.Bag.Multiplier
	end)
	local nextFloor = scope:Computed(function(use)
		local run = use(runV)
		return (run and run.Floor or 0) + 1
	end)
	local nextIsBoss = scope:Computed(function(use)
		return use(nextFloor) % Config.BossEvery == 0
	end)
	local projected = scope:Computed(function(use)
		return math.floor((use(bag) + Config.FloorReward(use(nextFloor))) * use(mult))
	end)
	local bank = scope:Computed(function(use)
		use(runV)
		use(Store.GoldenActive)
		return math.floor(use(bag) * cashOutMultiplier())
	end)
	local urgent = scope:Computed(function(use)
		local r = use(remaining)
		return r <= 3.05 and r > 0 and use(localChoice) == nil
	end)
	local pulse = Kit.Pulse(scope, urgent, 2.2)
	local timerColor = scope:Computed(function(use)
		return if use(urgent) then C.Red else C.BrassBright
	end)
	local players = scope:Computed(function(use)
		local run = use(runV)
		return (run and run.Players) or {}
	end)
	local wide = scope:Computed(function(use)
		return use(Screen.Layout) == "Wide"
	end)

	local root = scope:Reveal {
		Name = "Decision",
		Shown = visible,
		Size = UDim2.fromOffset(760, 424 + PROTECT_H),
		Position = UDim2.new(0.5, 0, 1, -14),
		AnchorPoint = Vector2.new(0.5, 1),
		Offset = UDim2.fromOffset(0, 50),
		HiddenScale = 0.94,
		Speed = 20,
		Children = {
			scope:New "UIScale" {
				Scale = scope:Computed(function(use)
					return if use(wide) then 1 else 0.86
				end),
			},
			-- Other riders
			scope:New "Frame" {
				Name = "Riders",
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 24),
				Position = UDim2.fromOffset(0, 124),
				[Children] = {
					scope:New "UIListLayout" {
						FillDirection = Enum.FillDirection.Horizontal,
						HorizontalAlignment = Enum.HorizontalAlignment.Center,
						Padding = UDim.new(0, 6),
						SortOrder = Enum.SortOrder.LayoutOrder,
					},
					scope:ForPairs(players, function(_use, inner, index, info)
						return index, choiceChip(inner, info, index)
					end),
				},
			},
			-- Countdown
			scope:New "Frame" {
				Name = "Countdown",
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 70),
				Position = UDim2.fromOffset(0, 156),
				[Children] = {
					scope:Eyebrow {
						Text = scope:Computed(function(use)
							if use(localChoice) then
								return "WAITING FOR THE OTHERS"
							end
							return string.format("FLOOR B%d CLEARED  ·  NO CHOICE = DEEPER", use(nextFloor) - 1)
						end),
						Color = C.Ivory:Lerp(C.Muted, 0.3),
						BulletColor = C.Brass,
						TextSize = 10,
						Height = 14,
						Stroke = 1.5,
						Position = UDim2.new(0.5, 0, 0, 0),
						AnchorPoint = Vector2.new(0.5, 0),
					},
					scope:Text {
						Name = "Seconds",
						Text = scope:Computed(function(use)
							return tostring(math.max(math.ceil(use(remaining)), 0))
						end),
						Font = Theme.Font.Display,
						TextSize = 40,
						Stroke = 2,
						Color = scope:Tween(timerColor, Theme.Tween.Fast),
						Size = UDim2.fromOffset(120, 44),
						Position = UDim2.new(0.5, 0, 0, 18),
						AnchorPoint = Vector2.new(0.5, 0),
						Children = {
							scope:New "UIScale" {
								Scale = scope:Computed(function(use)
									return 1 + use(pulse) * 0.12
								end),
							},
						},
					},
					-- drain bar flanking the number
					scope:Bar {
						Progress = scope:Computed(function(use)
							return use(remaining) / math.max(use(total), 0.1)
						end),
						Color = scope:Tween(timerColor, Theme.Tween.Fast),
						Size = UDim2.new(0.5, -80, 0, 2),
						Position = UDim2.new(0.5, -80, 0, 40),
						AnchorPoint = Vector2.new(1, 0.5),
						Name = "DrainL",
					},
					scope:Bar {
						Progress = scope:Computed(function(use)
							return use(remaining) / math.max(use(total), 0.1)
						end),
						Color = scope:Tween(timerColor, Theme.Tween.Fast),
						Size = UDim2.new(0.5, -80, 0, 2),
						Position = UDim2.new(0.5, 80, 0, 40),
						AnchorPoint = Vector2.new(0, 0.5),
						Name = "DrainR",
					},
				},
			},
			-- The two outcomes
			scope:New "Frame" {
				Name = "Cards",
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 176),
				Position = UDim2.new(0, 0, 1, -PROTECT_H),
				AnchorPoint = Vector2.new(0, 1),
				[Children] = {
					scope:New "Frame" {
						Name = "DeeperSlot",
						BackgroundTransparency = 1,
						Size = UDim2.new(0.5, -8, 1, 0),
						[Children] = {
							choiceCard {
								Choice = "Deeper",
								Title = "DEEPER",
								Icon = "Down",
								Accent = C.Cyan,
								Key = "1",
								Pad = Enum.KeyCode.ButtonX,
								Headline = scope:Computed(function(use)
									return string.format("%s  <font size=\"14\" color=\"#9C98B4\">x%.2f</font>", Format.Cash(use(projected)), use(mult))
								end),
								Detail = scope:Computed(function(use)
									return string.format("if you survive B%d  ·  <font color=\"#FF4858\">fall and lose %s</font>", use(nextFloor), Format.Cash(use(bag)))
								end),
								Extra = scope:Tag {
									Text = "NEXT: BOSS FLOOR",
									Accent = C.Red,
									Height = 20,
									TextSize = 9,
									Position = UDim2.new(1, -40, 0, -10),
									AnchorPoint = Vector2.new(1, 0),
									Visible = nextIsBoss,
									ZIndex = 5,
								},
							},
						},
					},
					scope:New "Frame" {
						Name = "LeaveSlot",
						BackgroundTransparency = 1,
						Size = UDim2.new(0.5, -8, 1, 0),
						Position = UDim2.fromScale(1, 0),
						AnchorPoint = Vector2.new(1, 0),
						[Children] = {
							choiceCard {
								Choice = "Leave",
								Title = "LEAVE",
								Icon = "Coin",
								Accent = C.Gold,
								Key = "2",
								Pad = Enum.KeyCode.ButtonY,
								Headline = scope:Computed(function(use)
									return "BANK " .. Format.Cash(use(bank))
								end),
								Detail = scope:Computed(function(use)
									if use(Store.GoldenActive) then
										return '<font color="#FFCC58">golden hour x2 included</font>  ·  your run ends here'
									end
									return "safe forever  ·  your run ends here"
								end),
							},
						},
					},
				},
			},
			shopStrip(),
			protectRow(bag),
		},
	}
	root.Parent = layer
end

-- Input -----------------------------------------------------------------------------------------

local function bindActions(on: boolean)
	if on == actionsBound then
		return
	end
	actionsBound = on
	if on then
		ContextActionService:BindActionAtPriority("OMF_Deeper", function(_, inputState)
			if inputState == Enum.UserInputState.Begin then
				Decision.Choose("Deeper")
			end
			return Enum.ContextActionResult.Sink
		end, false, 3000, Enum.KeyCode.One, Enum.KeyCode.ButtonX)
		ContextActionService:BindActionAtPriority("OMF_Leave", function(_, inputState)
			if inputState == Enum.UserInputState.Begin then
				Decision.Choose("Leave")
			end
			return Enum.ContextActionResult.Sink
		end, false, 3000, Enum.KeyCode.Two, Enum.KeyCode.ButtonY)
	else
		ContextActionService:UnbindAction("OMF_Deeper")
		ContextActionService:UnbindAction("OMF_Leave")
	end
end

local function refresh(run)
	runV:set(run)
	local show = run ~= nil and run.Phase == "Decision" and run.You ~= nil and run.You.Status == "Alive"
	if not show then
		visible:set(false)
		bindActions(false)
		if not run or run.Phase ~= "Decision" then
			decisionKey = nil
			localChoice:set(nil)
		end
		return
	end
	local key = tostring(run.RunId) .. ":" .. tostring(run.Floor)
	local isNew = key ~= decisionKey
	if isNew then
		decisionKey = key
		localChoice:set(nil)
		lastSecond = -1
		total:set(math.max((run.EndsAt or 0) - workspace:GetServerTimeNow(), 1))
	end
	if run.You.Choice and not peek(localChoice) then
		localChoice:set(run.You.Choice)
	end
	visible:set(true)
	bindActions(true)
	if isNew then
		CameraShake.Shake(0.3, 0.25)
		task.delay(0.1, function()
			Kit.Select(deeperButton)
		end)
	end
end

function Decision.Start()
	build(Screen.Get("Run"))
	dataV:set(State.Data)
	State.DataChanged:Connect(function(data)
		dataV:set(data)
	end)
	State.RunChanged:Connect(refresh)
	refresh(State.Run)

	RunService.RenderStepped:Connect(function()
		if not peek(visible) then
			return
		end
		local run = State.Run
		if not run or not run.EndsAt then
			return
		end
		local r = math.max(run.EndsAt - workspace:GetServerTimeNow(), 0)
		remaining:set(r)
		local whole = math.ceil(r)
		if whole ~= lastSecond then
			lastSecond = whole
			if whole <= 3 and whole > 0 and not peek(localChoice) then
				Audio.Play("Countdown")
			end
		end
	end)
end

return Decision
