-- Lobby leaderboards (Leaderboards event) as SurfaceGuis on workspace.Lobby.Boards.*, styled as
-- hotel directory boards: brass frame, Michroma header, ranked rows. 14x18-stud boards → 560x720.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Net = require(ReplicatedStorage.Shared.Net)
local Format = require(ReplicatedStorage.Shared.Format)
local Theme = require(script.Parent.Parent.UI.Theme)
local Kit = require(script.Parent.Parent.UI.Kit)

local Children = Fusion.Children
local C = Theme.Color

local Leaderboard = {}

local BOARDS = {
	Deepest = {
		Title = "DEEPEST DIVERS",
		Sub = "ALL TIME",
		Accent = C.Cyan,
		Value = function(v)
			return "B" .. Format.Comma(v)
		end,
	},
	Daily = {
		Title = "DAILY ELEVATOR",
		Sub = "TODAY'S SHAFT",
		Accent = C.Magenta,
		Value = function(v)
			return "B" .. Format.Comma(v)
		end,
	},
	Cash = {
		Title = "RICHEST GUESTS",
		Sub = "LIFETIME CASH",
		Accent = C.Gold,
		Value = function(v)
			return Format.Cash(v)
		end,
	},
}

local RANK_COLORS = {
	[1] = Color3.fromRGB(255, 214, 120),
	[2] = Color3.fromRGB(214, 222, 236),
	[3] = Color3.fromRGB(214, 150, 96),
}

local scope = Fusion.scoped(Fusion, Kit)
local rowsV: { [string]: any } = {}
local guis: { [string]: SurfaceGui } = {}

for name in BOARDS do
	rowsV[name] = scope:Value({})
end

local function findBoard(name: string): BasePart?
	local lobby = workspace:FindFirstChild("Lobby")
	local boards = lobby and lobby:FindFirstChild("Boards")
	local board = boards and boards:FindFirstChild(name)
	if board and board:IsA("BasePart") then
		return board
	end
	if board and board:IsA("Model") then
		return board.PrimaryPart or board:FindFirstChildWhichIsA("BasePart")
	end
	return nil
end

local function row(inner: any, def, rank: number, entry): Frame
	local rankColor = RANK_COLORS[rank] or C.Muted
	return inner:New "Frame" {
		Name = "Row" .. rank,
		BackgroundColor3 = if rank % 2 == 1 then C.Panel2 else C.Panel,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 50),
		LayoutOrder = rank,
		[Children] = {
			Kit.Text(inner, {
				Text = string.format("%02d", rank),
				Font = Theme.Font.Display,
				TextSize = 24,
				Color = rankColor,
				Size = UDim2.new(0, 64, 1, 0),
				Position = UDim2.fromOffset(8, 0),
			}),
			if rank <= 3
				then inner:New "Frame" {
					BackgroundColor3 = rankColor,
					BorderSizePixel = 0,
					Size = UDim2.new(0, 3, 1, -16),
					Position = UDim2.fromOffset(2, 8),
				}
				else nil,
			Kit.Text(inner, {
				Text = tostring(entry.Name or "?"),
				Font = Theme.Font.Bold,
				TextSize = 26,
				Color = C.Ivory,
				XAlign = Enum.TextXAlignment.Left,
				Truncate = Enum.TextTruncate.AtEnd,
				Size = UDim2.new(1, -260, 1, 0),
				Position = UDim2.fromOffset(84, 0),
			}),
			Kit.Text(inner, {
				Text = def.Value(tonumber(entry.Value) or 0),
				Font = Theme.Font.Display,
				TextSize = 24,
				Color = def.Accent,
				XAlign = Enum.TextXAlignment.Right,
				Size = UDim2.new(0, 170, 1, 0),
				Position = UDim2.new(1, -16, 0, 0),
				AnchorPoint = Vector2.new(1, 0),
			}),
		},
	}
end

local function build(name: string)
	local def = BOARDS[name]
	local part = findBoard(name)
	if not def or not part then
		return
	end
	local existing = guis[name]
	if existing and existing.Parent then
		existing.Adornee = part
		return
	end
	local rows = rowsV[name]
	local gui = scope:New "SurfaceGui" {
		Name = "OMF_Board_" .. name,
		Adornee = part,
		Face = Enum.NormalId.Front,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = 40,
		LightInfluence = 0,
		Brightness = 1.25,
		ResetOnSpawn = false,
		ZOffset = 1,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
		[Children] = {
			Kit.Plate(scope, {
				Size = UDim2.new(1, -24, 1, -24),
				Position = UDim2.fromScale(0.5, 0.5),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Accent = def.Accent,
				Fill = 0.02,
				StrokeWeight = 3,
				Children = {
					Kit.Eyebrow(scope, {
						Text = def.Sub,
						Color = C.Brass,
						TextSize = 16,
						Height = 22,
						HAlign = Enum.HorizontalAlignment.Center,
						Position = UDim2.new(0.5, 0, 0, 30),
						AnchorPoint = Vector2.new(0.5, 0),
					}),
					Kit.Text(scope, {
						Text = def.Title,
						Font = Theme.Font.Display,
						TextSize = 40,
						Color = def.Accent,
						Size = UDim2.new(1, -40, 0, 50),
						Position = UDim2.new(0.5, 0, 0, 58),
						AnchorPoint = Vector2.new(0.5, 0),
					}),
					Kit.Rule(scope, {
						Size = UDim2.new(1, -80, 0, 10),
						Position = UDim2.new(0.5, 0, 0, 118),
						AnchorPoint = Vector2.new(0.5, 0),
						DiamondColor = def.Accent,
					}),
					scope:New "Frame" {
						Name = "Rows",
						BackgroundTransparency = 1,
						Size = UDim2.new(1, -48, 1, -170),
						Position = UDim2.new(0.5, 0, 0, 144),
						AnchorPoint = Vector2.new(0.5, 0),
						[Children] = {
							scope:New "UIListLayout" {
								Padding = UDim.new(0, 4),
								SortOrder = Enum.SortOrder.LayoutOrder,
							},
							scope:Computed(function(use, inner)
								local list = use(rows)
								if #list == 0 then
									return inner:New "Frame" {
										Name = "Empty",
										BackgroundTransparency = 1,
										Size = UDim2.new(1, 0, 0, 300),
										[Children] = {
											Kit.Icon(inner, {
												Name = "Diamond",
												Color = def.Accent,
												Size = UDim2.fromOffset(26, 26),
												Position = UDim2.new(0.5, 0, 0, 120),
												AnchorPoint = Vector2.new(0.5, 0),
											}),
											Kit.Text(inner, {
												Text = "NO RIDERS YET",
												Font = Theme.Font.Display,
												TextSize = 26,
												Color = C.Ivory,
												Size = UDim2.new(1, 0, 0, 34),
												Position = UDim2.fromOffset(0, 164),
											}),
											Kit.Text(inner, {
												Text = "Ride the elevator and put your name on the board.",
												Font = Theme.Font.Body,
												TextSize = 22,
												Color = C.Muted,
												Wrapped = true,
												Size = UDim2.new(1, -40, 0, 60),
												Position = UDim2.new(0.5, 0, 0, 206),
												AnchorPoint = Vector2.new(0.5, 0),
											}),
										},
									}
								end
								local out = {}
								for rank = 1, math.min(#list, 10) do
									table.insert(out, row(inner, def, rank, list[rank]))
								end
								return out
							end),
						},
					},
				},
			}),
		},
	}
	guis[name] = gui
end

local function buildAll()
	for name in BOARDS do
		local ok, err = pcall(build, name)
		if not ok then
			warn("[Leaderboard]", name, err)
		end
	end
end

function Leaderboard.Start()
	Net.Event("Leaderboards").OnClientEvent:Connect(function(boards)
		if typeof(boards) ~= "table" then
			return
		end
		for name, list in boards do
			if typeof(list) == "table" and rowsV[name] then
				rowsV[name]:set(list)
			end
		end
		buildAll()
	end)
	-- The lobby may load after us; build placeholders once it exists.
	task.spawn(function()
		local lobby = workspace:WaitForChild("Lobby", 30)
		if lobby then
			lobby:WaitForChild("Boards", 30)
			buildAll()
		end
	end)
end

return Leaderboard
