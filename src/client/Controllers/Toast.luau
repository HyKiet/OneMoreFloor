-- Stacked notifications from the server's Toast event (and local callers via Toast.Show).
-- Slim ink plates that slide in from the right edge; newest on top, max four.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Net = require(ReplicatedStorage.Shared.Net)
local Theme = require(script.Parent.Parent.UI.Theme)
local Kit = require(script.Parent.Parent.UI.Kit)
local Screen = require(script.Parent.Screen)
local Audio = require(script.Parent.Audio)

local Children = Fusion.Children
local C = Theme.Color

local Toast = {}

local STYLES = {
	info = { Color = C.Cyan, Icon = "Diamond" },
	good = { Color = C.Green, Icon = "Check" },
	bad = { Color = C.Red, Icon = "Close" },
	rare = { Color = C.Gold, Icon = "Star" },
}

local MAX_TOASTS = 4
local HOLD = 3.4

local scope = Fusion.scoped(Fusion, Kit)
local container: Frame
local order = 0
local live: { { Frame: Instance, Scope: any, Shown: any } } = {}

local function dismiss(entry)
	if entry.Gone then
		return
	end
	entry.Gone = true
	entry.Shown:set(false)
	task.delay(0.35, function()
		Fusion.doCleanup(entry.Scope)
	end)
	local index = table.find(live, entry)
	if index then
		table.remove(live, index)
	end
end

function Toast.Show(text: string, style: string?)
	if not container then
		return
	end
	local s = STYLES[style or "info"] or STYLES.info
	order += 1
	local inner = scope:innerScope()
	local shown = inner:Value(false)
	local frame = Kit.Enter(inner, {
		Name = "Toast",
		Shown = shown,
		LayoutOrder = -order,
		Size = UDim2.fromOffset(380, 46),
		Offset = UDim2.fromOffset(60, 0),
		Speed = 26,
		Children = {
			Kit.Plate(inner, {
				Size = UDim2.fromScale(1, 1),
				Accent = C.BrassDim,
				Brackets = false,
				Inset = false,
				Children = {
					inner:New "Frame" {
						Name = "Signal",
						BackgroundColor3 = s.Color,
						BorderSizePixel = 0,
						Size = UDim2.new(0, 3, 1, -12),
						Position = UDim2.fromOffset(6, 6),
					},
					Kit.Icon(inner, {
						Name = s.Icon,
						Color = s.Color,
						Size = UDim2.fromOffset(16, 16),
						Position = UDim2.new(0, 20, 0.5, 0),
						AnchorPoint = Vector2.new(0, 0.5),
					}),
					Kit.Text(inner, {
						Text = text,
						Font = Theme.Font.Bold,
						TextSize = 15,
						Color = C.Ivory,
						XAlign = Enum.TextXAlignment.Left,
						Truncate = Enum.TextTruncate.AtEnd,
						Size = UDim2.new(1, -60, 1, 0),
						Position = UDim2.fromOffset(46, 0),
					}),
				},
			}),
		},
	})
	frame.Parent = container
	shown:set(true)
	local entry = { Frame = frame, Scope = inner, Shown = shown }
	table.insert(live, 1, entry)
	while #live > MAX_TOASTS do
		dismiss(live[#live])
	end
	Audio.Play(if style == "bad" then "Error" else "Toast")
	task.delay(HOLD, function()
		dismiss(entry)
	end)
end

function Toast.Start()
	container = scope:New "Frame" {
		Name = "ToastStack",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(380, 230),
		Position = scope:Computed(function(use)
			-- below the bag plate in runs; same spot in the lobby so it never jumps
			return if use(Screen.Layout) == "Wide" then UDim2.new(1, -12, 0, 176) else UDim2.new(1, -12, 0, 140)
		end),
		AnchorPoint = Vector2.new(1, 0),
		Parent = Screen.Get("Toasts"),
		[Children] = {
			scope:New "UIListLayout" {
				Padding = UDim.new(0, 6),
				HorizontalAlignment = Enum.HorizontalAlignment.Right,
				SortOrder = Enum.SortOrder.LayoutOrder,
			},
		},
	}

	Net.Event("Toast").OnClientEvent:Connect(function(text, style)
		if typeof(text) == "string" then
			Toast.Show(text, style)
		end
	end)
end

return Toast
