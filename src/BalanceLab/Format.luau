--!strict
-- Compact number, duration and percentage formatting for summaries and chart axes.

local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No" }

local function trimZeros(text: string): string
	if string.find(text, "%.") then
		text = string.gsub(text, "0+$", "")
		text = string.gsub(text, "%.$", "")
	end
	return text
end

local function digits(value: number): string
	if value >= 100 then
		return string.format("%.0f", value)
	elseif value >= 10 then
		return trimZeros(string.format("%.1f", value))
	end
	return trimZeros(string.format("%.2f", value))
end

-- 1234 -> "1.23K", 2500000 -> "2.5M"; three significant digits above 1000.
function Format.number(value: number): string
	if value ~= value then
		return "NaN"
	elseif value == math.huge or value == -math.huge then
		return if value > 0 then "inf" else "-inf"
	end
	local sign = if value < 0 then "-" else ""
	value = math.abs(value)
	if value < 1000 then
		local text = digits(value)
		if text ~= "1000" then
			return sign .. text
		end
	end
	local tier = math.max(1, math.floor(math.log10(value) / 3))
	local scaled = value / 10 ^ (tier * 3)
	if scaled >= 999.5 then
		tier += 1
		scaled /= 1000
	end
	if tier >= #SUFFIXES then
		return sign .. string.format("%.2e", value)
	end
	return sign .. digits(scaled) .. SUFFIXES[tier + 1]
end

-- 1234567 -> "1,234,567"
function Format.integer(value: number): string
	local text = string.format("%d", math.floor(value + 0.5))
	local sign, body = string.match(text, "^(-?)(%d+)$")
	if not body then
		return text
	end
	local grouped = string.reverse((string.gsub(string.reverse(body), "(%d%d%d)", "%1,")))
	grouped = string.gsub(grouped, "^,", "")
	return (sign or "") .. grouped
end

-- Play time: "45s", "12m 30s", "3h 05m", "142h".
function Format.duration(seconds: number?): string
	if seconds == nil or seconds ~= seconds or seconds < 0 then
		return "-"
	elseif seconds == math.huge then
		return "never"
	end
	local whole = math.floor(seconds + 0.5)
	if whole < 60 then
		return `{whole}s`
	end
	local minutes = whole // 60
	if minutes < 60 then
		return string.format("%dm %02ds", minutes, whole % 60)
	end
	local hours = minutes // 60
	if hours < 100 then
		return string.format("%dh %02dm", hours, minutes % 60)
	end
	return `{Format.integer(hours)}h`
end

-- Axis tick label for a time value: "0", "45s", "15m", "1h", "1h30".
function Format.tick(seconds: number): string
	local whole = math.floor(seconds + 0.5)
	if whole == 0 then
		return "0"
	elseif whole < 60 then
		return `{whole}s`
	elseif whole < 3600 then
		return `{whole // 60}m`
	end
	local hours, minutes = whole // 3600, (whole % 3600) // 60
	if minutes == 0 then
		return `{Format.integer(hours)}h`
	end
	return string.format("%dh%02d", hours, minutes)
end

-- 0.005 -> "0.5%", 0.9 -> "90%", 0.99912 -> "99.9%"
function Format.percent(share: number): string
	local value = share * 100
	if value == 0 or value >= 10 then
		return `{trimZeros(string.format("%.1f", value))}%`
	elseif value >= 0.1 then
		return `{trimZeros(string.format("%.2f", value))}%`
	end
	return `{string.format("%.2g", value)}%`
end

-- "1 in 200"
function Format.odds(chance: number): string
	if chance <= 0 then
		return "never"
	end
	local inverse = 1 / chance
	if inverse < 10 then
		return `1 in {trimZeros(string.format("%.2f", inverse))}`
	end
	return `1 in {Format.integer(inverse)}`
end

-- Calendar day on which a play-time moment falls for a session profile: "day 3".
-- A goal reached exactly at the end of a day's play counts as that day.
function Format.day(seconds: number, sessionMinutes: number, sessionsPerDay: number): string
	local perDay = sessionMinutes * sessionsPerDay * 60
	return `day {Format.integer(math.max(1, math.ceil(seconds / perDay - 1e-9)))}`
end

return table.freeze(Format)
