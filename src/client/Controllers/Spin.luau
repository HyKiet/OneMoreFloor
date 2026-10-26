-- Client-side spin + bob for parts tagged "Spin" (coins, bag pickups). Purely cosmetic.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Spin = {}

local TAG = "Spin"
local tracked: { [BasePart]: { Base: CFrame, Phase: number } } = {}

local function add(instance: Instance)
	if instance:IsA("BasePart") then
		tracked[instance] = { Base = instance.CFrame, Phase = math.random() * math.pi * 2 }
	end
end

local function remove(instance: Instance)
	if instance:IsA("BasePart") then
		tracked[instance] = nil
	end
end

function Spin.Start()
	for _, instance in CollectionService:GetTagged(TAG) do
		add(instance)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(add)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(remove)

	RunService.RenderStepped:Connect(function()
		local t = os.clock()
		for part, info in tracked do
			if not part.Parent then
				tracked[part] = nil
			else
				local speed = part:GetAttribute("SpinSpeed") or 2.5
				part.CFrame = info.Base
					* CFrame.new(0, math.sin(t * 2.4 + info.Phase) * 0.35, 0)
					* CFrame.Angles(0, t * speed + info.Phase, 0)
			end
		end
	end)
end

return Spin
