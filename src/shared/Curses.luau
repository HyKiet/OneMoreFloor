-- Curses are floor modifiers. Spectators vote for them; some floors roll one at random.
-- Server-side effects are applied by Run/Modifiers; Client = true curses are rendered by the client.

local Curses = {}

Curses.List = {
	{ Id = "Darkness", Name = "Lights Out", Desc = "The floor goes pitch black.", Color = Color3.fromRGB(60, 60, 90), Client = true },
	{ Id = "Fog", Name = "Thick Fog", Desc = "You can barely see a thing.", Color = Color3.fromRGB(180, 180, 200), Client = true },
	{ Id = "Tiny", Name = "Shrink Ray", Desc = "Everyone is tiny.", Color = Color3.fromRGB(120, 255, 180) },
	{ Id = "Giant", Name = "Growth Spurt", Desc = "Everyone is huge.", Color = Color3.fromRGB(255, 160, 80) },
	{ Id = "Speedy", Name = "Too Much Coffee", Desc = "Everyone runs 50% faster.", Color = Color3.fromRGB(255, 230, 80) },
	{ Id = "Sluggish", Name = "Molasses", Desc = "Everyone moves 30% slower.", Color = Color3.fromRGB(140, 100, 60) },
	{ Id = "Moon", Name = "Moon Gravity", Desc = "Gravity drops to 40%.", Color = Color3.fromRGB(200, 200, 255) },
	{ Id = "Heavy", Name = "Heavy Boots", Desc = "Gravity is 40% stronger.", Color = Color3.fromRGB(110, 110, 120) },
	{ Id = "Hyper", Name = "Hyper Mode", Desc = "The challenge is much harder.", Color = Color3.fromRGB(255, 50, 80) },
	{ Id = "Shaky", Name = "Earthquake", Desc = "The camera will not stop shaking.", Color = Color3.fromRGB(200, 140, 90), Client = true },
}

Curses.ById = {}
for _, curse in Curses.List do
	Curses.ById[curse.Id] = curse
end

-- Pairs that cancel each other out never appear together.
Curses.Conflicts = {
	Tiny = "Giant",
	Giant = "Tiny",
	Speedy = "Sluggish",
	Sluggish = "Speedy",
	Moon = "Heavy",
	Heavy = "Moon",
}

return Curses
