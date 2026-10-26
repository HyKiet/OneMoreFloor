-- Plays Shared.Sounds entries locally and crossfades lobby/run music.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Sounds = require(ReplicatedStorage.Shared.Sounds)
local UIKit = require(script.Parent.Parent.Util.UIKit)
local Kit = require(script.Parent.Parent.UI.Kit)

local Audio = {}

local music: { [string]: Sound } = {}
local currentTrack: string? = nil
local loops: { [string]: Sound } = {}

local function makeSound(name: string): Sound?
	local def = Sounds[name]
	if not def or not def.Id or def.Id == 0 then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = "OMF_" .. name
	sound.SoundId = "rbxassetid://" .. tostring(def.Id)
	sound.Volume = def.Volume or 0.5
	sound.Looped = def.Looped == true
	return sound
end

-- Fire-and-forget one-shot. Silently skips sounds without an id.
function Audio.Play(name: string, pitch: number?)
	local sound = makeSound(name)
	if not sound then
		return
	end
	sound.PlaybackSpeed = pitch or 1
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	task.delay(15, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
end

-- Starts/stops a named looping sound (e.g. ElevatorHum).
function Audio.Loop(name: string, on: boolean)
	local existing = loops[name]
	if on then
		if existing then
			return
		end
		local sound = makeSound(name)
		if not sound then
			return
		end
		sound.Looped = true
		sound.Parent = SoundService
		sound:Play()
		loops[name] = sound
	elseif existing then
		loops[name] = nil
		local target = existing
		TweenService:Create(target, TweenInfo.new(0.4), { Volume = 0 }):Play()
		task.delay(0.45, function()
			target:Destroy()
		end)
	end
end

local function setTrack(name: string?)
	if currentTrack == name then
		return
	end
	currentTrack = name
	for trackName, sound in music do
		if trackName ~= name then
			TweenService:Create(sound, TweenInfo.new(1.2), { Volume = 0 }):Play()
		end
	end
	if name then
		local sound = music[name]
		if not sound then
			local created = makeSound(name)
			if not created then
				return
			end
			created.Looped = true
			created.Volume = 0
			created.Parent = SoundService
			created:Play()
			music[name] = created
			sound = created
		end
		local def = Sounds[name]
		TweenService:Create(sound :: Sound, TweenInfo.new(1.2), { Volume = def.Volume or 0.3 }):Play()
	end
end

function Audio.Start()
	UIKit.ClickSound = function()
		Audio.Play("Click")
	end
	Kit.ClickSound = function()
		Audio.Play("Click")
	end
	local player = Players.LocalPlayer
	local function update()
		if player:GetAttribute("InRun") then
			setTrack("RunMusic")
		else
			setTrack("LobbyMusic")
		end
	end
	player:GetAttributeChangedSignal("InRun"):Connect(update)
	update()
end

return Audio
