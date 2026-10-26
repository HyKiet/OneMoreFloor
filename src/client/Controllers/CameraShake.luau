-- Noise-based camera shake layered on top of the default camera.
-- Shake(intensity, duration) adds a decaying impulse; SetConstant(key, intensity) holds a steady rumble.

local RunService = game:GetService("RunService")

local CameraShake = {}

local impulses: { { Intensity: number, Duration: number, Started: number } } = {}
local constants: { [string]: number } = {}
local seed = math.random() * 1000

function CameraShake.Shake(intensity: number?, duration: number?)
	table.insert(impulses, {
		Intensity = math.clamp(intensity or 1, 0, 4),
		Duration = math.max(duration or 0.4, 0.05),
		Started = os.clock(),
	})
end

function CameraShake.SetConstant(key: string, intensity: number?)
	constants[key] = if intensity and intensity > 0 then intensity else nil
end

local function currentIntensity(now: number): number
	local total = 0
	for i = #impulses, 1, -1 do
		local impulse = impulses[i]
		local t = (now - impulse.Started) / impulse.Duration
		if t >= 1 then
			table.remove(impulses, i)
		else
			total += impulse.Intensity * (1 - t) ^ 2
		end
	end
	for _, value in constants do
		total += value
	end
	return math.min(total, 3)
end

function CameraShake.Start()
	RunService:BindToRenderStep("OMF_CameraShake", Enum.RenderPriority.Camera.Value + 1, function()
		local now = os.clock()
		local intensity = currentIntensity(now)
		if intensity <= 0.001 then
			return
		end
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		local t = now * 18
		local x = math.noise(t, seed) * intensity * 0.45
		local y = math.noise(t, seed + 50) * intensity * 0.45
		local roll = math.noise(t, seed + 100) * intensity * math.rad(1.6)
		local pitch = math.noise(t, seed + 150) * intensity * math.rad(0.8)
		camera.CFrame = camera.CFrame * CFrame.new(x, y, 0) * CFrame.Angles(pitch, 0, roll)
	end)
end

return CameraShake
