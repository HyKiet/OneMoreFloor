-- Sound library. Ids are Creator Store audio assets; 0 means "not chosen yet" and is skipped silently.
-- Picks favour Roblox-licensed libraries (Pro Sound Effects "(SFX)" and APM Music) so they play in any experience.

local Sounds = {
	-- UI
	Click = { Id = 9119717523, Volume = 0.5 }, -- Switch Click On Or Off Toggle Button 2 (SFX)
	Toast = { Id = 9125540237, Volume = 0.4 }, -- Electronic Tinkles Sharp Relay Falling Beeps (SFX)
	Purchase = { Id = 9113728042, Volume = 0.6 }, -- Cash Register 1 (SFX)
	Error = { Id = 9114279239, Volume = 0.5 }, -- Electronic Beep Buzzy Honking Clicking 2 (SFX)

	-- Run flow
	ElevatorDing = { Id = 1840084286, Volume = 0.7 }, -- Musical Doorbell (d) (APM)
	ElevatorHum = { Id = 9112812234, Volume = 0.4, Looped = true }, -- Landing Craft Interior 2 (SFX), constant hum loop
	DoorOpen = { Id = 9114305290, Volume = 0.6 }, -- Elevator Doors Open Close 9 (SFX)
	Countdown = { Id = 9125531715, Volume = 0.6 }, -- Electronic Blips Sharp Crystalline Beeps (SFX)
	Go = { Id = 9114402205, Volume = 0.7 }, -- Dual Air Horns 2 (SFX)
	Eliminated = { Id = 9120769331, Volume = 0.8 }, -- Wind Whoosh Sonic Boom Low End Impact 1 (SFX)
	Survived = { Id = 1840076509, Volume = 0.7 }, -- Through the Roof (sting) (APM)
	CashOut = { Id = 1836473422, Volume = 0.8 }, -- Victory Fanfare Sting (APM)
	Coin = { Id = 1169755927, Volume = 0.4 }, -- Coin Collect - SFX (free to use per uploader)
	BagGrow = { Id = 9125541142, Volume = 0.5 }, -- Electronic Tinkles Sharp Relay Falling Beeps 2 (SFX)
	RelicReveal = { Id = 1839881844, Volume = 0.8 }, -- Spinning Around (b) (APM)
	RelicRare = { Id = 9040193225, Volume = 0.9 }, -- SOS (sting), glossy 80s synth (APM)
	CurseApplied = { Id = 9038129814, Volume = 0.7 }, -- Ghosting The Machine End Stab (APM)

	-- Hazards
	Warning = { Id = 9114285303, Volume = 0.5 }, -- Electronic Door Beeps And Chatter 2 (SFX)
	Laser = { Id = 9116227010, Volume = 0.5 }, -- Laser Blasts Transporter Elements 4 (SFX)
	Impact = { Id = 9116673944, Volume = 0.7 }, -- Metal Impact Heavy Clunking Hits Scraping 4 (SFX)
	Explosion = { Id = 9114224675, Volume = 0.8 }, -- Earthquake Explosion 5 (SFX)
	Whoosh = { Id = 9126229267, Volume = 0.5 }, -- Whoosh By Fast Airy Swooshing Whipping Thuds 1 (SFX)
	Alarm = { Id = 9119661640, Volume = 0.6 }, -- Submarine Alarm Casualty Electronic Siren 1 (SFX)

	-- Music
	LobbyMusic = { Id = 1842214884, Volume = 0.3, Looped = true }, -- Mellowment, light relaxed easy listening (APM)
	RunMusic = { Id = 1843764058, Volume = 0.25, Looped = true }, -- Rhythm Drone 44 (APM)
	TenseMusic = { Id = 1843712358, Volume = 0.3, Looped = true }, -- Moving Drone 47 (APM)
}

return Sounds
