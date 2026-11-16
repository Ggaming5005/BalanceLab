--!strict
-- Exact first-success maths for independent rolls with an optional hard pity.
-- `pity` = N means roll N is guaranteed if the target has not dropped earlier; 0 disables it.

local Loot = {}

-- log(1 - p) without catastrophic cancellation for tiny p.
local function log1m(p: number): number
	if p < 1e-4 then
		return -(p + p * p / 2 + p * p * p / 3)
	end
	return math.log(1 - p)
end

local function oneMinusExp(x: number): number
	if math.abs(x) < 1e-5 then
		return -x * (1 + x / 2 + x * x / 6 + x * x * x / 24)
	end
	return 1 - math.exp(x)
end

local function checkProbability(p: number, pity: number)
	assert(p > 0 and p <= 1, "p must be greater than 0 and at most 1")
	assert(pity >= 0 and pity < math.huge and pity % 1 == 0, "pity must be a nonnegative whole number")
end

-- Probability that the target has dropped within `rolls` rolls.
function Loot.chanceWithin(p: number, pity: number, rolls: number): number
	checkProbability(p, pity)
	assert(rolls >= 0 and rolls < math.huge and rolls % 1 == 0, "rolls must be a nonnegative whole number")
	if rolls <= 0 then
		return 0
	end
	if p >= 1 or (pity > 0 and rolls >= pity) then
		return 1
	end
	return oneMinusExp(rolls * log1m(p))
end

-- Smallest roll count whose cumulative chance reaches q (0 < q < 1).
function Loot.rollsFor(p: number, pity: number, q: number): number
	checkProbability(p, pity)
	assert(q > 0 and q < 1, "q must be greater than 0 and less than 1")
	if p >= 1 then
		return 1
	end
	local estimate = math.log(1 - q) / log1m(p)
	local rolls = math.max(1, math.ceil(estimate - 1e-9))
	if pity > 0 then
		rolls = math.min(rolls, pity)
	end
	-- The closed form can be off by one after floating-point rounding; settle it exactly.
	while rolls > 1 and Loot.chanceWithin(p, pity, rolls - 1) >= q do
		rolls -= 1
	end
	local guard = 0
	while Loot.chanceWithin(p, pity, rolls) < q and guard < 64 do
		rolls += 1
		guard += 1
	end
	return rolls
end

-- Expected rolls until the first drop.
function Loot.expected(p: number, pity: number): number
	return Loot.expectedRemaining(p, pity, 0)
end

-- Expected further rolls after `failures` misses; memoryless unless pity is close.
function Loot.expectedRemaining(p: number, pity: number, failures: number): number
	checkProbability(p, pity)
	assert(failures >= 0 and failures < math.huge and failures % 1 == 0, "failures must be a nonnegative whole number")
	if p >= 1 then
		return 1
	end
	if pity > 0 then
		local left = math.max(1, pity - failures)
		if left == 1 then return 1 end
		return oneMinusExp(left * log1m(p)) / p
	end
	return 1 / p
end

return table.freeze(Loot)
