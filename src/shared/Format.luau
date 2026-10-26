-- Number and time formatting for UI.

local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi" }

-- 950 -> "950", 1234 -> "1.23K", 15300000 -> "15.3M"
function Format.Short(n: number): string
	n = math.floor(n)
	local sign = if n < 0 then "-" else ""
	n = math.abs(n)
	if n < 1000 then
		return sign .. tostring(n)
	end
	local tier = math.min(math.floor(math.log10(n) / 3), #SUFFIXES - 1)
	local scaled = n / 1000 ^ tier
	local text
	if scaled >= 100 then
		text = string.format("%d", math.floor(scaled))
	elseif scaled >= 10 then
		text = string.format("%.1f", math.floor(scaled * 10) / 10)
	else
		text = string.format("%.2f", math.floor(scaled * 100) / 100)
	end
	return sign .. text .. SUFFIXES[tier + 1]
end

function Format.Cash(n: number): string
	return "$" .. Format.Short(n)
end

-- 1234567 -> "1,234,567"
function Format.Comma(n: number): string
	local s = tostring(math.floor(n))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (formatted:gsub("^,", ""))
end

function Format.Multiplier(m: number): string
	return string.format("x%.2f", m)
end

return Format
