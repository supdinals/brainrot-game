--!strict
-- FormatNumber.luau -- format angka singkat untuk UI: 1.2K, 3.4M, 5.6B, 7.8T.
-- Satu-satunya fungsi format angka; dipakai HUD, billboard, dan panel.

local FormatNumber = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi" }

function FormatNumber.Format(value: number): string
	if value ~= value then
		return "0"
	end
	if value < 0 then
		return "-" .. FormatNumber.Format(-value)
	end
	local tier = 0
	local scaled = value
	while scaled >= 1000 and tier < #SUFFIXES - 1 do
		scaled /= 1000
		tier += 1
	end
	if tier == 0 then
		return string.format("%d", math.floor(value))
	end
	if scaled >= 100 then
		return string.format("%.0f%s", scaled, SUFFIXES[tier + 1])
	elseif scaled >= 10 then
		return string.format("%.1f%s", scaled, SUFFIXES[tier + 1]):gsub("%.0", "")
	end
	return string.format("%.1f%s", scaled, SUFFIXES[tier + 1]):gsub("%.0", "")
end

return FormatNumber
