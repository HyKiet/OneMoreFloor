-- Client-side mirror of server state: the current run snapshot and the profile data.
-- Other controllers read State.Run / State.Data and listen to RunChanged / DataChanged.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local Signal = require(ReplicatedStorage.Packages.Signal)

local State = {
	Run = nil :: any, -- RunUpdate payload or nil
	Data = nil :: any, -- Data payload or nil
	RunChanged = Signal.new(), -- (newRun, oldRun)
	DataChanged = Signal.new(), -- (newData, oldData)
	PhaseChanged = Signal.new(), -- (newPhase, oldPhase, run) fires on phase or floor change
}

-- True when the local player is an active (alive or dead-spectating) member of a run.
function State.InRun(): boolean
	local run = State.Run
	return run ~= nil and run.You ~= nil and run.You.Status ~= "Left" and run.Phase ~= nil
end

function State.Status(): string?
	local run = State.Run
	return run and run.You and run.You.Status
end

function State.Start()
	Net.Event("RunUpdate").OnClientEvent:Connect(function(run)
		local old = State.Run
		State.Run = run
		State.RunChanged:Fire(run, old)
		local newPhase = run and run.Phase
		local oldPhase = old and old.Phase
		local newFloor = run and run.Floor
		local oldFloor = old and old.Floor
		if newPhase ~= oldPhase or newFloor ~= oldFloor or (run and old and run.RunId ~= old.RunId) then
			State.PhaseChanged:Fire(newPhase, oldPhase, run)
		end
	end)
	Net.Event("Data").OnClientEvent:Connect(function(data)
		local old = State.Data
		State.Data = data
		State.DataChanged:Fire(data, old)
	end)
end

return State
