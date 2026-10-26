-- Design tokens for the "midnight art-deco elevator" UI.
-- Brass hairlines on ink panels; neon is reserved for signals, matching the lobby lighting:
--   Cyan = Normal elevator / go / DEEPER, Magenta = Daily elevator, Gold = money / LEAVE,
--   Red = danger, Violet = curses & spectators.

local Theme = {}

Theme.Color = {
	Ink = Color3.fromRGB(7, 8, 18),
	Panel = Color3.fromRGB(13, 15, 31),
	Panel2 = Color3.fromRGB(21, 24, 46),
	Panel3 = Color3.fromRGB(31, 35, 64),
	Line = Color3.fromRGB(52, 54, 86),

	Brass = Color3.fromRGB(212, 174, 104),
	BrassBright = Color3.fromRGB(247, 218, 152),
	BrassDim = Color3.fromRGB(116, 94, 58),

	Ivory = Color3.fromRGB(246, 240, 226),
	Muted = Color3.fromRGB(156, 152, 180),
	Faint = Color3.fromRGB(88, 88, 118),

	Cyan = Color3.fromRGB(78, 228, 255),
	Gold = Color3.fromRGB(255, 204, 88),
	Red = Color3.fromRGB(255, 72, 88),
	Magenta = Color3.fromRGB(255, 70, 172),
	Violet = Color3.fromRGB(170, 120, 255),
	Green = Color3.fromRGB(104, 236, 160),
}

local BUILDER = "rbxasset://fonts/families/BuilderSans.json"

Theme.Font = {
	-- Michroma matches the lobby's neon signage; used for titles and every number.
	Display = Font.new("rbxasset://fonts/families/Michroma.json", Enum.FontWeight.Regular),
	Body = Font.new(BUILDER, Enum.FontWeight.Medium),
	Bold = Font.new(BUILDER, Enum.FontWeight.Bold),
	Heavy = Font.new(BUILDER, Enum.FontWeight.ExtraBold),
}

-- Type scale (virtual pixels; Screen scales the whole canvas).
Theme.Text = {
	Eyebrow = 13,
	Small = 15,
	Body = 18,
	Label = 20,
	Title = 28,
	Hero = 44,
	Giant = 72,
}

Theme.Space = { XS = 4, S = 8, M = 12, L = 16, XL = 24, XXL = 32 }

Theme.Radius = 3 -- deco = crisp corners; ornaments do the decorating

-- Spring presets: { speed, damping }.
Theme.Spring = {
	Snappy = { 32, 0.78 },
	Soft = { 18, 0.95 },
	Bouncy = { 28, 0.55 },
	Slow = { 10, 1 },
}

Theme.Tween = {
	Fast = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Base = TweenInfo.new(0.26, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
	Count = TweenInfo.new(0.7, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
	Linear = TweenInfo.new(0.2, Enum.EasingStyle.Linear),
}

function Theme.lerp(a: Color3, b: Color3, t: number): Color3
	return a:Lerp(b, t)
end

return Theme
