--!strict
-- Level curves shared by the simulator and by game code that wants the same prices.

export type Kind = "exponential" | "linear" | "power"

export type Curve = {
	curve: Kind,
	base: number,
	growth: number,
}

local Curve = {}

Curve.KINDS = table.freeze({ "exponential", "linear", "power" }) :: { Kind }

-- Value for buying level `level + 1` when `level` levels are owned (level is 0-based).
function Curve.at(curve: Curve, level: number): number
	if curve.base == 0 and curve.curve ~= "linear" then return 0 end
	local kind = curve.curve
	if kind == "exponential" then
		local factor = curve.growth ^ level
		if factor == math.huge or factor == 0 then
			return math.exp(math.log(curve.base) + level * math.log(curve.growth))
		end
		return curve.base * factor
	elseif kind == "linear" then
		return curve.base + curve.growth * level
	end
	return curve.base * (level + 1) ^ curve.growth
end

-- Sum of Curve.at for owned levels in [from, to), e.g. the price of buying several levels at once.
function Curve.total(curve: Curve, from: number, to: number): number
	local count = to - from
	if count <= 0 or curve.base == 0 and curve.curve ~= "linear" then
		return 0
	end
	local kind = curve.curve
	if kind == "exponential" then
		local growth = curve.growth
		if growth == 1 then
			return curve.base * count
		end
		if math.abs(growth - 1) < 1e-5 then
			local sum = 0
			for level = from, to - 1 do sum += Curve.at(curve, level) end
			return sum
		end
		if growth > 1 then
			return Curve.at(curve, to - 1) * ((1 - (1 / growth) ^ count) / (1 - 1 / growth))
		end
		return Curve.at(curve, from) * ((1 - growth ^ count) / (1 - growth))
	elseif kind == "linear" then
		return count * curve.base + curve.growth * (from + to - 1) * count / 2
	end
	local sum = 0
	for level = from, to - 1 do
		sum += Curve.at(curve, level)
	end
	return sum
end

-- Short human description of what `growth` means for a curve kind.
function Curve.describe(curve: Curve): string
	local kind = curve.curve
	if kind == "exponential" then
		return `×{curve.growth} per level`
	elseif kind == "linear" then
		return `+{curve.growth} per level`
	end
	return `(level)^{curve.growth}`
end

return table.freeze(Curve)
