-- Payoff moments: cash-out card, relic reveal (spinning model on a deco sunburst) and confetti.
-- Reveals are queued so they never overlap; tap a card to skip it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Net = require(ReplicatedStorage.Shared.Net)
local Format = require(ReplicatedStorage.Shared.Format)
local Relics = require(ReplicatedStorage.Shared.Relics)
local Rarity = require(ReplicatedStorage.Shared.Rarity)
local Theme = require(script.Parent.Parent.UI.Theme)
local Kit = require(script.Parent.Parent.UI.Kit)
local RelicModel = require(script.Parent.Parent.Util.RelicModel)
local Screen = require(script.Parent.Screen)
local Audio = require(script.Parent.Audio)
local CameraShake = require(script.Parent.CameraShake)

local Children = Fusion.Children
local OnEvent = Fusion.OnEvent
local C = Theme.Color

local Celebration = {}

local CONFETTI = { C.Gold, C.BrassBright, C.Cyan, C.Ivory, C.Magenta }

local scope = Fusion.scoped(Fusion, Kit)
local overlay: Frame
local effects: Frame
local queue: { () -> () } = {}
local running = false

-- Confetti: plain frames on the Effects layer, tweened (no per-frame Lua).
function Celebration.Confetti(count: number?)
	if not effects then
		return
	end
	local rng = Random.new()
	for _ = 1, count or 60 do
		local w = rng:NextInteger(5, 10)
		local piece = Instance.new("Frame")
		piece.BackgroundColor3 = CONFETTI[rng:NextInteger(1, #CONFETTI)]
		piece.BorderSizePixel = 0
		piece.Size = UDim2.fromOffset(w, w * rng:NextNumber(1.6, 2.6))
		piece.Position = UDim2.fromScale(0.5, 0.46)
		piece.AnchorPoint = Vector2.new(0.5, 0.5)
		piece.Rotation = rng:NextInteger(0, 360)
		piece.Parent = effects
		local burst = UDim2.fromScale(0.5 + rng:NextNumber(-0.42, 0.42), 0.46 + rng:NextNumber(-0.38, 0.06))
		local out = TweenService:Create(piece, TweenInfo.new(rng:NextNumber(0.35, 0.55), Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
			Position = burst,
			Rotation = piece.Rotation + rng:NextInteger(-200, 200),
		})
		out.Completed:Once(function()
			local fall = rng:NextNumber(1.3, 2.3)
			TweenService:Create(piece, TweenInfo.new(fall, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
				Position = UDim2.new(burst.X.Scale + rng:NextNumber(-0.06, 0.06), 0, 1.1, 0),
				Rotation = piece.Rotation + rng:NextInteger(-420, 420),
				BackgroundTransparency = 0.4,
			}):Play()
			task.delay(fall + 0.05, function()
				piece:Destroy()
			end)
		end)
		out:Play()
	end
end

local function enqueue(fn: () -> ())
	table.insert(queue, fn)
	if running then
		return
	end
	running = true
	task.spawn(function()
		while #queue > 0 do
			local nextFn = table.remove(queue, 1)
			local ok, err = pcall(nextFn :: () -> ())
			if not ok then
				warn("[Celebration]", err)
			end
		end
		running = false
	end)
end

-- Builds a centred card in its own scope, holds it for `duration` (or until tapped), then fades.
-- `build(inner, shown)` returns the card's children. Yields.
local function present(size: Vector2, accent: Color3, duration: number, build: (any, any) -> { any })
	local inner = scope:innerScope()
	local shown = inner:Value(false)
	local closed = false
	-- Enter (not Reveal): the relic ViewportFrame would not render inside a CanvasGroup.
	local card = Kit.Enter(inner, {
		Name = "Celebration",
		Shown = shown,
		Size = UDim2.fromOffset(size.X, size.Y),
		Position = UDim2.fromScale(0.5, 0.47),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Offset = UDim2.fromOffset(0, 30),
		Speed = 20,
		Damping = 0.65,
		Children = {
			inner:New "UIScale" {
				Scale = inner:Computed(function(use)
					return if use(Screen.Layout) == "Wide" then 1 else 0.85
				end),
			},
			Kit.Plate(inner, {
				Size = UDim2.fromScale(1, 1),
				Accent = accent,
				Fill = 0.04,
				Children = build(inner, shown),
			}),
			inner:New "TextButton" {
				Name = "Skip",
				BackgroundTransparency = 1,
				Text = "",
				Size = UDim2.fromScale(1, 1),
				ZIndex = 50,
				[OnEvent "Activated"] = function()
					closed = true
				end,
			},
		},
	})
	card.Parent = overlay
	shown:set(true)
	local start = os.clock()
	while not closed and os.clock() - start < duration do
		task.wait(0.05)
	end
	shown:set(false)
	task.wait(0.3)
	Fusion.doCleanup(inner)
end

local function showCashOut(info)
	local amount = tonumber(info.Amount) or 0
	local bonus = tonumber(info.Bonus) or 0
	Celebration.Confetti(80)
	CameraShake.Shake(0.6, 0.4)
	Audio.Play("CashOut")
	present(Vector2.new(520, 290), C.Gold, 3.4, function(inner, shown)
		local target = inner:Computed(function(use)
			return if use(shown) then amount else 0
		end)
		return {
			inner:New "Frame" {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, -48, 1, -40),
				Position = UDim2.fromScale(0.5, 0.5),
				AnchorPoint = Vector2.new(0.5, 0.5),
				[Children] = {
					inner:New "UIListLayout" {
						Padding = UDim.new(0, 8),
						HorizontalAlignment = Enum.HorizontalAlignment.Center,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						SortOrder = Enum.SortOrder.LayoutOrder,
					},
					Kit.Eyebrow(inner, {
						Text = "YOU ESCAPED FROM FLOOR B" .. tostring(info.Floor or "?"),
						HAlign = Enum.HorizontalAlignment.Center,
						Color = C.Brass,
						TextSize = 11,
						LayoutOrder = 1,
					}),
					Kit.Counter(inner, {
						Value = target,
						TweenInfo = TweenInfo.new(1.1, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
						Format = function(n)
							return "+" .. Format.Cash(n)
						end,
						TextSize = 56,
						Color = C.Gold,
						Size = UDim2.new(1, 0, 0, 70),
						LayoutOrder = 2,
					}),
					Kit.Rule(inner, { Size = UDim2.new(0.6, 0, 0, 8), LayoutOrder = 3 }),
					Kit.Text(inner, {
						Text = if bonus > 0 then "BANKED  ·  INCLUDES +" .. Format.Cash(bonus) .. " BONUS" else "BANKED FOREVER",
						Font = Theme.Font.Display,
						TextSize = 12,
						Color = if bonus > 0 then C.Cyan else C.Muted,
						Size = UDim2.new(1, 0, 0, 18),
						LayoutOrder = 4,
					}),
					Kit.Text(inner, {
						Text = "Spend it on upgrades in the lobby, then ride again.",
						Font = Theme.Font.Body,
						TextSize = 15,
						Color = C.Muted,
						Size = UDim2.new(1, 0, 0, 20),
						LayoutOrder = 5,
					}),
				},
			},
		}
	end)
end

-- 12 thin rays that slowly turn behind the relic.
local function sunburst(inner: any, color: Color3, shown: any): Frame
	local rays = {}
	for i = 0, 15 do
		-- each ray lives in a full-size holder so rotation pivots on the hub
		table.insert(rays, inner:New "Frame" {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Rotation = i * 22.5,
			[Children] = {
				inner:New "Frame" {
					BackgroundColor3 = color,
					BorderSizePixel = 0,
					AnchorPoint = Vector2.new(0.5, 1),
					Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.new(0, if i % 2 == 0 then 3 else 1, 0.5, if i % 2 == 0 then 0 else -40),
					BackgroundTransparency = if i % 2 == 0 then 0.35 else 0.6,
					[Children] = {
						inner:New "UIGradient" {
							Rotation = 90,
							Transparency = NumberSequence.new({
								NumberSequenceKeypoint.new(0, 1),
								NumberSequenceKeypoint.new(0.75, 0.2),
								NumberSequenceKeypoint.new(0.9, 1),
								NumberSequenceKeypoint.new(1, 1),
							}),
						},
					},
				},
			},
		})
	end
	local spin = inner:Value(0)
	local connection = RunService.RenderStepped:Connect(function(dt)
		spin:set((Fusion.peek(spin) + dt * 12) % 360)
	end)
	table.insert(inner, connection)
	return inner:New "Frame" {
		Name = "Sunburst",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(300, 300),
		Position = UDim2.new(0.5, 0, 0, 160),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Rotation = spin,
		[Children] = {
			inner:New "UIScale" {
				Scale = inner:Spring(inner:Computed(function(use)
					return if use(shown) then 1 else 0.3
				end), 10, 0.7),
			},
			rays,
		},
	}
end

local function showRelic(info)
	local relic = Relics.ById[info.RelicId]
	if not relic then
		return
	end
	local rarityInfo = Rarity.Info[relic.Rarity] or Rarity.Info.Common
	local color = rarityInfo.Color
	if rarityInfo.Rank >= 4 then
		Celebration.Confetti(100)
		CameraShake.Shake(0.9, 0.5)
		Audio.Play("RelicRare")
	else
		Audio.Play("RelicReveal")
	end
	-- where it came from: a run drop (nil), a Relic Capsule or the Starter Pack
	local source = info.Source
	local eyebrow = if info.IsNew then "NEW RELIC" else "RELIC LEVEL " .. tostring(info.Level or 1)
	local footer = if info.IsNew then "Auto-equipped if you had a free slot" else "Stronger with every level"
	if source == "Capsule" then
		eyebrow = "RELIC CAPSULE  ·  " .. eyebrow
		footer = if info.IsNew then "Added to your vault" else "Duplicate: your copy levelled up"
	elseif source == "StarterPack" then
		eyebrow = "STARTER PACK  ·  " .. eyebrow
	end
	present(Vector2.new(400, 470), color, 3.8, function(inner, shown)
		local viewport = inner:New "ViewportFrame" {
			Name = "Model",
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(240, 220),
			Position = UDim2.new(0.5, 0, 0, 50),
			AnchorPoint = Vector2.new(0.5, 0),
			ZIndex = 2,
		}
		local model = RelicModel.mountRelic(viewport, relic, false)
		table.insert(inner, RelicModel.spin(viewport, model, 1.6))
		return {
			sunburst(inner, color, shown),
			Kit.Eyebrow(inner, {
				Text = eyebrow,
				Color = if info.IsNew then C.Gold else C.Cyan,
				HAlign = Enum.HorizontalAlignment.Center,
				TextSize = 12,
				Height = 18,
				Position = UDim2.new(0.5, 0, 0, 18),
				AnchorPoint = Vector2.new(0.5, 0),
			}),
			viewport,
			Kit.Text(inner, {
				Text = string.upper(relic.Name),
				Font = Theme.Font.Display,
				TextSize = 22,
				Size = UDim2.new(1, -30, 0, 30),
				Position = UDim2.new(0.5, 0, 0, 290),
				AnchorPoint = Vector2.new(0.5, 0),
			}),
			Kit.Tag(inner, {
				Text = string.upper(relic.Rarity),
				Accent = color,
				Height = 22,
				TextSize = 10,
				Position = UDim2.new(0.5, 0, 0, 328),
				AnchorPoint = Vector2.new(0.5, 0),
			}),
			Kit.Text(inner, {
				Text = relic.Desc,
				Font = Theme.Font.Bold,
				TextSize = 17,
				Color = C.Ivory:Lerp(C.Muted, 0.3),
				Wrapped = true,
				Size = UDim2.new(1, -50, 0, 44),
				Position = UDim2.new(0.5, 0, 0, 362),
				AnchorPoint = Vector2.new(0.5, 0),
			}),
			Kit.Text(inner, {
				Text = footer,
				Font = Theme.Font.Body,
				TextSize = 13,
				Color = C.Faint,
				Size = UDim2.new(1, -40, 0, 16),
				Position = UDim2.new(0.5, 0, 1, -16),
				AnchorPoint = Vector2.new(0.5, 1),
			}),
		}
	end)
end

function Celebration.Start()
	overlay = Screen.Get("Overlay")
	effects = Screen.Get("Effects")

	Net.Event("CashedOut").OnClientEvent:Connect(function(info)
		if typeof(info) == "table" then
			enqueue(function()
				showCashOut(info)
			end)
		end
	end)
	Net.Event("RelicFound").OnClientEvent:Connect(function(info)
		if typeof(info) == "table" then
			enqueue(function()
				showRelic(info)
			end)
		end
	end)
end

return Celebration
