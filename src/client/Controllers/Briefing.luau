-- Centre-screen storytelling: the challenge briefing (floor, name, hint, curses; boss variant),
-- the "GO" call and short banners from ctx:Announce / Effect "Banner".

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Curses = require(ReplicatedStorage.Shared.Curses)
local Theme = require(script.Parent.Parent.UI.Theme)
local Kit = require(script.Parent.Parent.UI.Kit)
local Screen = require(script.Parent.Screen)
local State = require(script.Parent.State)
local Audio = require(script.Parent.Audio)
local CameraShake = require(script.Parent.CameraShake)

local Children = Fusion.Children
local peek = Fusion.peek
local C = Theme.Color

local Briefing = {}

local scope = Fusion.scoped(Fusion, Kit)

local briefShown = scope:Value(false)
local brief = scope:Value(nil :: any) -- { Floor, Boss, Name, Hint, Curses }
local briefToken = 0
local currentBanner: any = nil -- `shown` Value of the banner on screen
local layer: Frame

-- Banner ----------------------------------------------------------------------------------------

-- Short, punchy centre text (e.g. "RED LIGHT!"). Replaces any banner already showing.
function Briefing.Banner(text: string, color: Color3?, duration: number?)
	if not layer then
		return
	end
	if currentBanner then
		currentBanner:set(false)
	end
	local inner = scope:innerScope()
	local shown = inner:Value(false)
	currentBanner = shown
	local accent = color or C.Ivory
	local punch = inner:Spring(inner:Computed(function(use)
		return if use(shown) then 1 else 1.5
	end), 28, 0.6)
	local fade = inner:Spring(inner:Computed(function(use)
		return if use(shown) then 0 else 1
	end), 24, 1)
	local frame = inner:New "Frame" {
		Name = "Banner",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(900, 120),
		Position = UDim2.fromScale(0.5, 0.33),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = layer,
		[Children] = {
			inner:New "UIScale" { Scale = punch },
			Kit.Text(inner, {
				Text = string.upper(text),
				Font = Theme.Font.Display,
				TextSize = 64,
				Color = accent,
				Transparency = fade,
				Size = UDim2.new(1, 0, 0, 80),
				Stroke = 3,
				StrokeTransparency = inner:Computed(function(use)
					return 0.25 + 0.75 * math.clamp(use(fade), 0, 1)
				end),
			}),
			-- deco underline that draws outwards
			inner:New "Frame" {
				BackgroundColor3 = accent,
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 88),
				BackgroundTransparency = fade,
				Size = inner:Spring(inner:Computed(function(use)
					return if use(shown) then UDim2.fromOffset(260, 2) else UDim2.fromOffset(0, 2)
				end), 18, 1),
			},
		},
	}
	local _ = frame
	shown:set(true)
	task.delay(duration or 1.3, function()
		shown:set(false)
		if currentBanner == shown then
			currentBanner = nil
		end
	end)
	task.delay((duration or 1.3) + 0.5, function()
		Fusion.doCleanup(inner)
	end)
end

-- Briefing --------------------------------------------------------------------------------------

local function buildBriefing()
	local isBoss = scope:Computed(function(use)
		local b = use(brief)
		return b ~= nil and b.Boss == true
	end)
	local accent = scope:Computed(function(use)
		return if use(isBoss) then C.Red else C.Cyan
	end)
	local lineWidth = scope:Spring(scope:Computed(function(use)
		return if use(briefShown) then 1 else 0
	end), 14, 1)
	local titleDrop = scope:Spring(scope:Computed(function(use)
		return if use(briefShown) then 0 else -22
	end), 22, 0.65)
	local curses = scope:Computed(function(use)
		local b = use(brief)
		return (b and b.Curses) or {}
	end)
	local wide = scope:Computed(function(use)
		return use(Screen.Layout) == "Wide"
	end)

	local function rail(y: number)
		return scope:New "Frame" {
			BackgroundColor3 = accent,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0, y),
			Size = scope:Computed(function(use)
				return UDim2.new(0.8 * use(lineWidth), 0, 0, 1)
			end),
			[Children] = {
				scope:New "UIGradient" {
					Transparency = NumberSequence.new({
						NumberSequenceKeypoint.new(0, 1),
						NumberSequenceKeypoint.new(0.5, 0),
						NumberSequenceKeypoint.new(1, 1),
					}),
				},
			},
		}
	end

	local root = scope:Reveal {
		Name = "Briefing",
		Shown = briefShown,
		Size = UDim2.new(1, 0, 0, 250),
		Position = UDim2.fromScale(0, 0.4),
		AnchorPoint = Vector2.new(0, 0.5),
		Offset = UDim2.fromOffset(0, 0),
		HiddenScale = 1,
		Speed = 18,
		Children = {
			scope:New "UIScale" {
				Scale = scope:Computed(function(use)
					return if use(wide) then 1 else 0.85
				end),
			},
			-- ink band, fading out at both ends
			scope:New "Frame" {
				Name = "Band",
				BackgroundColor3 = C.Ink,
				BackgroundTransparency = 0.25,
				BorderSizePixel = 0,
				Size = UDim2.new(1, 0, 0, 190),
				Position = UDim2.fromScale(0.5, 0.5),
				AnchorPoint = Vector2.new(0.5, 0.5),
				[Children] = {
					scope:New "UIGradient" {
						Transparency = NumberSequence.new({
							NumberSequenceKeypoint.new(0, 1),
							NumberSequenceKeypoint.new(0.22, 0),
							NumberSequenceKeypoint.new(0.78, 0),
							NumberSequenceKeypoint.new(1, 1),
						}),
					},
				},
			},
			rail(30),
			rail(220),
			scope:New "Frame" {
				Name = "Content",
				BackgroundTransparency = 1,
				Size = UDim2.new(0, 860, 0, 170),
				Position = UDim2.fromScale(0.5, 0.5),
				AnchorPoint = Vector2.new(0.5, 0.5),
				[Children] = {
					scope:New "UIListLayout" {
						Padding = UDim.new(0, 6),
						HorizontalAlignment = Enum.HorizontalAlignment.Center,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						SortOrder = Enum.SortOrder.LayoutOrder,
					},
					scope:Eyebrow {
						Text = scope:Computed(function(use)
							local b = use(brief)
							if not b then
								return ""
							end
							return if b.Boss then "BOSS FLOOR  B" .. tostring(b.Floor) else "FLOOR  B" .. tostring(b.Floor)
						end),
						Color = accent,
						BulletColor = accent,
						TextSize = 14,
						Height = 20,
						HAlign = Enum.HorizontalAlignment.Center,
						LayoutOrder = 1,
					},
					scope:New "Frame" {
						Name = "TitleHolder",
						BackgroundTransparency = 1,
						Size = UDim2.new(1, 0, 0, 66),
						LayoutOrder = 2,
						[Children] = {
							scope:Text {
								Text = scope:Computed(function(use)
									local b = use(brief)
									return b and string.upper(b.Name or "") or ""
								end),
								Font = Theme.Font.Display,
								TextSize = 52,
								Color = C.Ivory,
								Size = UDim2.fromScale(1, 1),
								Position = scope:Computed(function(use)
									return UDim2.fromOffset(0, use(titleDrop))
								end),
								Stroke = 2,
								StrokeTransparency = 0.4,
							},
						},
					},
					scope:Text {
						Text = scope:Computed(function(use)
							local b = use(brief)
							return b and b.Hint or ""
						end),
						Font = Theme.Font.Bold,
						TextSize = 20,
						Color = C.Ivory:Lerp(C.Muted, 0.35),
						Wrapped = true,
						Size = UDim2.new(1, 0, 0, 28),
						LayoutOrder = 3,
					},
					scope:New "Frame" {
						Name = "Curses",
						BackgroundTransparency = 1,
						Size = UDim2.new(1, 0, 0, 24),
						LayoutOrder = 4,
						Visible = scope:Computed(function(use)
							return #use(curses) > 0
						end),
						[Children] = {
							scope:New "UIListLayout" {
								FillDirection = Enum.FillDirection.Horizontal,
								HorizontalAlignment = Enum.HorizontalAlignment.Center,
								Padding = UDim.new(0, 8),
								SortOrder = Enum.SortOrder.LayoutOrder,
							},
							scope:ForPairs(curses, function(_use, inner, index, id)
								local curse = Curses.ById[id]
								return index, Kit.Tag(inner, {
									Text = "CURSED · " .. string.upper(curse and curse.Name or tostring(id)),
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
			},
		},
	}
	root.Parent = layer
end

local function showBriefing(run)
	local challenge = run.Challenge
	if not challenge then
		return
	end
	briefToken += 1
	local token = briefToken
	brief:set({
		Floor = run.Floor,
		Boss = run.IsBoss == true,
		Name = challenge.Name,
		Hint = challenge.Hint,
		Curses = run.Curses or {},
	})
	briefShown:set(false)
	task.defer(function()
		briefShown:set(true)
	end)
	if run.IsBoss then
		CameraShake.Shake(1.2, 0.6)
		Audio.Play("Alarm")
	else
		CameraShake.Shake(0.4, 0.25)
		Audio.Play("Countdown")
	end
	local now = workspace:GetServerTimeNow()
	local hold = math.clamp((run.EndsAt or now + 3) - now - 0.3, 1.2, 5)
	task.delay(hold, function()
		if token == briefToken then
			briefShown:set(false)
		end
	end)
end

function Briefing.Start()
	layer = Screen.Get("Overlay")
	buildBriefing()
	State.PhaseChanged:Connect(function(phase, _old, run)
		if not run or not run.You then
			briefShown:set(false)
			return
		end
		if phase == "Briefing" then
			showBriefing(run)
		elseif phase == "Challenge" then
			briefShown:set(false)
			if run.You.Status == "Alive" then
				Briefing.Banner("GO", C.Cyan, 0.8)
				Audio.Play("Go")
			end
		elseif phase == "Ended" then
			briefShown:set(false)
			Briefing.Banner("RUN OVER", C.Muted, 1.6)
		end
	end)
end

return Briefing
