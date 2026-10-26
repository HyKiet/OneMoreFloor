-- First-session guide: a trail of neon chevrons on the lobby floor that marches toward the Normal
-- elevator, a pulsing ring on the boarding zone and a small "STEP IN" marker below the signage.
-- Shown until the player has finished a couple of runs; hidden inside the zone and during runs.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Fusion = require(ReplicatedStorage.Packages.Fusion)
local Theme = require(script.Parent.Parent.UI.Theme)
local Kit = require(script.Parent.Parent.UI.Kit)
local State = require(script.Parent.State)

local Children = Fusion.Children
local C = Theme.Color

local Guide = {}

local GUIDE_RUNS = 2 -- show until this many runs are done
local SPACING = 4 -- studs between chevrons
local MAX_CHEVRONS = 18
local START_GAP = 4 -- keep the trail off the player's feet
local REFRESH = 0.12

local player = Players.LocalPlayer
local folder: Folder? = nil
local chevrons: { { BasePart } } = {}
local ring: { BasePart } = {}
local RING_SEGMENTS = 24
local marker: BillboardGui? = nil
local markerScope: any = nil
local active = false

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include

local function zone(): BasePart?
	local lobby = workspace:FindFirstChild("Lobby")
	local elevators = lobby and lobby:FindFirstChild("Elevators")
	local normal = elevators and elevators:FindFirstChild("Normal")
	local part = normal and normal:FindFirstChild("BoardingZone", true)
	return if part and part:IsA("BasePart") then part else nil
end

local function neon(size: Vector3, parent: Instance): BasePart
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = C.Cyan
	part.Size = size
	part.Transparency = 1
	part.Parent = parent
	return part
end

local function insideZone(z: BasePart, position: Vector3): boolean
	local localPos = z.CFrame:PointToObjectSpace(position)
	local half = z.Size / 2
	return math.abs(localPos.X) <= half.X and math.abs(localPos.Z) <= half.Z and math.abs(localPos.Y) <= half.Y + 3
end

local function floorY(position: Vector3, fallback: number): number
	local lobby = workspace:FindFirstChild("Lobby")
	if not lobby then
		return fallback
	end
	rayParams.FilterDescendantsInstances = { lobby }
	local hit = workspace:Raycast(position + Vector3.new(0, 6, 0), Vector3.new(0, -14, 0), rayParams)
	return if hit then hit.Position.Y else fallback
end

local function build()
	if folder then
		return
	end
	local z = zone()
	if not z then
		return
	end
	folder = Instance.new("Folder")
	folder.Name = "OMF_Guide"
	folder.Parent = workspace
	for i = 1, MAX_CHEVRONS do
		chevrons[i] = {
			neon(Vector3.new(0.22, 0.06, 1.5), folder),
			neon(Vector3.new(0.22, 0.06, 1.5), folder),
		}
	end
	for i = 1, RING_SEGMENTS do
		ring[i] = neon(Vector3.new(0.2, 0.06, 1.1), folder)
	end

	-- Marker sits low, under the elevator's own signage.
	markerScope = Fusion.scoped(Fusion, Kit)
	local s = markerScope
	local bob = s:Value(0)
	marker = s:New "BillboardGui" {
		Name = "OMF_StepIn",
		Adornee = z,
		Size = UDim2.fromOffset(170, 54),
		StudsOffsetWorldSpace = s:Computed(function(use)
			return Vector3.new(0, -z.Size.Y / 2 + 4 + use(bob) * 0.4, 0)
		end),
		MaxDistance = 140,
		LightInfluence = 0,
		AlwaysOnTop = false,
		ResetOnSpawn = false,
		Parent = player:WaitForChild("PlayerGui"),
		[Children] = {
			Kit.Plate(s, {
				Size = UDim2.fromScale(1, 1),
				Accent = C.Cyan,
				Fill = 0.15,
				Inset = false,
				Children = {
					Kit.Eyebrow(s, {
						Text = "FIRST RIDE",
						Color = C.Brass,
						TextSize = 9,
						Height = 12,
						HAlign = Enum.HorizontalAlignment.Center,
						Position = UDim2.new(0.5, 0, 0, 8),
						AnchorPoint = Vector2.new(0.5, 0),
					}),
					Kit.Text(s, {
						Text = "STEP IN HERE",
						Font = Theme.Font.Display,
						TextSize = 15,
						Color = C.Ivory,
						Size = UDim2.new(1, 0, 0, 20),
						Position = UDim2.fromOffset(0, 24),
					}),
				},
			}),
		},
	}
	table.insert(s, RunService.Heartbeat:Connect(function()
		bob:set(math.sin(os.clock() * 2.6))
	end))
end

local function clear()
	if folder then
		folder:Destroy()
		folder = nil
	end
	table.clear(chevrons)
	table.clear(ring)
	if markerScope then
		Fusion.doCleanup(markerScope)
		markerScope = nil
	end
	marker = nil
end

local function wanted(): boolean
	local data = State.Data
	return data ~= nil and (data.TotalRuns or 0) < GUIDE_RUNS and not player:GetAttribute("InRun")
end

-- Lays the chevrons along the floor from the player to the zone centre.
local lastLayout = 0
local function layoutTrail(now: number)
	local z = zone()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not z or not root then
		return
	end
	local inside = insideZone(z, root.Position)
	if marker then
		marker.Enabled = not inside
	end
	local bottom = z.Position.Y - z.Size.Y / 2
	local from = Vector3.new(root.Position.X, 0, root.Position.Z)
	local to = Vector3.new(z.Position.X, 0, z.Position.Z)
	local delta = to - from
	local distance = delta.Magnitude
	local dir = if distance > 0.01 then delta.Unit else Vector3.new(0, 0, -1)
	local yaw = math.atan2(-dir.X, -dir.Z)
	for i, pair in chevrons do
		local d = START_GAP + (i - 1) * SPACING
		local visible = not inside and d < distance - 3
		pair[1]:SetAttribute("On", visible)
		if visible then
			local p = from + dir * d
			local y = floorY(Vector3.new(p.X, bottom, p.Z), bottom) + 0.05
			local base = CFrame.new(p.X, y, p.Z) * CFrame.Angles(0, yaw, 0)
			-- two arms meeting at the tip (pointing along -Z of `base`)
			pair[1].CFrame = base * CFrame.new(-0.45, 0, 0.1) * CFrame.Angles(0, math.rad(-40), 0)
			pair[2].CFrame = base * CFrame.new(0.45, 0, 0.1) * CFrame.Angles(0, math.rad(40), 0)
		end
	end
	lastLayout = now
end

local function animate()
	local now = os.clock()
	if now - lastLayout >= REFRESH then
		layoutTrail(now)
	end
	-- marching wave toward the elevator
	for i, pair in chevrons do
		local on = pair[1]:GetAttribute("On")
		local wave = 0.5 + 0.5 * math.sin(now * 5 - i * 0.7)
		local t = if on then 0.75 - wave * 0.6 else 1
		pair[1].Transparency = t
		pair[2].Transparency = t
	end
	local z = zone()
	if z and #ring > 0 then
		-- dashed ring that slowly turns and breathes on the boarding zone
		local pulse = 0.5 + 0.5 * math.sin(now * 3)
		local inside = marker ~= nil and not marker.Enabled
		local radius = 4.2 + pulse * 0.35
		local centre = Vector3.new(z.Position.X, z.Position.Y - z.Size.Y / 2 + 0.06, z.Position.Z)
		for i, segment in ring do
			local a = (i / RING_SEGMENTS) * math.pi * 2 + now * 0.35
			segment.CFrame = CFrame.new(centre + Vector3.new(math.cos(a) * radius, 0, math.sin(a) * radius)) * CFrame.Angles(0, -a, 0)
			segment.Transparency = if inside then 1 else 0.45 - pulse * 0.3
		end
	end
end

local function refresh()
	local want = wanted()
	if want and not active then
		active = true
		build()
	elseif not want and active then
		active = false
		clear()
	end
end

function Guide.Start()
	State.DataChanged:Connect(refresh)
	player:GetAttributeChangedSignal("InRun"):Connect(refresh)
	RunService.RenderStepped:Connect(function()
		if active then
			if not folder then
				build()
			end
			if folder then
				animate()
			end
		end
	end)
	refresh()
end

return Guide
