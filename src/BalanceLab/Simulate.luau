--!strict
-- Deterministic, event-driven progression model.
-- Income only changes when something is bought, so the run jumps from purchase to purchase and the
-- timeline is exact: balance rises linearly between events and drops at each purchase.

local Config = require("./Config")
local Curve = require("./Curve")
local Loot = require("./Loot")

export type Options = {
	-- Called every `yieldEvery` steps; pass a yielding function (e.g. task.wait) to keep Studio responsive.
	yield: (() -> ())?,
	isCancelled: (() -> boolean)?,
	yieldEvery: number?,
	maxSteps: number?,
}

export type EventKind = "start" | "upgrade" | "roll" | "goal" | "end"

-- Struct-of-arrays keeps long runs compact and makes time lookups a binary search.
export type Timeline = {
	count: number,
	time: { number },
	before: { number },
	after: { number },
	income: { number },
	kind: { EventKind },
	ref: { number },
	level: { number },
}

export type Quantile = { q: number, rolls: number, time: number? }

export type LootResult = {
	chance: number,
	pity: number,
	expected: number,
	simulatedRolls: number,
	rollTimes: { number },
	quantiles: { Quantile },
}

export type Gap = { from: number, to: number, duration: number, label: string }

export type Status = "reached" | "horizon" | "stalled" | "limit" | "cancelled"

export type Result = {
	status: Status,
	message: string,
	config: Config.Config,
	goalTime: number?,
	endTime: number,
	income: number,
	balance: number,
	earned: number,
	spentUpgrades: number,
	spentRolls: number,
	purchases: number,
	levels: { [string]: number },
	longestGap: Gap?,
	timeline: Timeline,
	loot: LootResult?,
	steps: number,
}

local Simulate = {}

Simulate.MAX_STEPS = 100000
Simulate.MAX_ROLLS = 50000
Simulate.QUANTILES = table.freeze({ 0.5, 0.9, 0.99 })
-- Loot runs continue until this share of modeled players would own the target.
Simulate.COVERAGE = 0.999

local MAX_AMOUNT = Config.LIMITS.maxAmount

local function findGap(timeline: Timeline, config: Config.Config, finish: number): Gap?
	local best: Gap? = nil
	local last = 0
	local function consider(to: number, label: string)
		local duration = to - last
		if duration > 0 and (best == nil or duration > (best :: Gap).duration) then
			best = { from = last, to = to, duration = duration, label = label }
		end
		last = to
	end
	for index = 1, timeline.count do
		if timeline.time[index] > finish then break end
		local kind = timeline.kind[index]
		if kind == "upgrade" then
			local upgrade = config.upgrades[timeline.ref[index]]
			consider(timeline.time[index], `{upgrade.name} level {timeline.level[index]}`)
		elseif kind == "roll" then
			consider(timeline.time[index], `roll {timeline.ref[index]}`)
		end
	end
	consider(finish, config.goal.name)
	return best
end

function Simulate.run(raw: any, options: Options?): Result
	local config = Config.assert(raw)
	local opts: Options = options or {}
	for _, name in { "yieldEvery", "maxSteps" } do
		local value = (opts :: any)[name]
		assert(value == nil or (type(value) == "number" and value == value and value < math.huge and value >= 1 and value % 1 == 0), name .. " must be a positive whole number")
	end
	local yieldEvery = math.max(1, opts.yieldEvery or 1000)
	local maxSteps = math.clamp(opts.maxSteps or Simulate.MAX_STEPS, 1, Simulate.MAX_STEPS)

	local upgrades = config.upgrades
	local goal = config.goal
	local isLoot = goal.kind == "loot"
	local eager = config.player.strategy == "eager"
	local actions = config.player.actionsPerSecond
	local horizon = config.limits.maxHours * 3600

	local levels = table.create(#upgrades, 0)
	local nextCost = table.create(#upgrades, math.huge)
	local perSecond = config.income.perSecond
	local perAction = config.income.perAction
	local multiplier = 1

	local function rate(): number
		return (perSecond + perAction * actions) * multiplier
	end

	local function refreshCost(index: number)
		local upgrade = upgrades[index]
		local cost = math.huge
		if levels[index] < upgrade.maxLevel then
			cost = Curve.at(upgrade.cost, levels[index])
			if cost ~= cost or cost <= 0 or cost > MAX_AMOUNT then
				cost = math.huge
			end
		end
		nextCost[index] = cost
	end

	local function nextGain(index: number): number
		return Curve.at(upgrades[index].effect, levels[index])
	end

	-- Income per second added by buying the next level of `index` right now.
	local function deltaOf(index: number): number
		local gain = nextGain(index)
		local kind = upgrades[index].effect.kind
		if kind == "perSecond" then
			return gain * multiplier
		elseif kind == "perAction" then
			return gain * actions * multiplier
		end
		return (perSecond + perAction * actions) * gain
	end

	local function buy(index: number)
		local gain = nextGain(index)
		local kind = upgrades[index].effect.kind
		if kind == "perSecond" then
			perSecond += gain
		elseif kind == "perAction" then
			perAction += gain
		else
			multiplier += gain
		end
		levels[index] += 1
		refreshCost(index)
	end

	local chance = if isLoot then Config.chance(config) else 0
	local pity = goal.pity or 0
	local rollCost = goal.rollCost or 0
	local coverageTarget = if isLoot then Loot.rollsFor(chance, pity, Simulate.COVERAGE) else 0
	local rollTarget = math.min(coverageTarget, Simulate.MAX_ROLLS)
	local rolls = 0
	local rollTimes: { number } = {}

	-- What the modeled player still plans to spend on the goal.
	local function goalNeed(): number
		if isLoot then
			return rollCost * Loot.expectedRemaining(chance, pity, rolls)
		end
		return goal.amount :: number
	end

	-- Returns the upgrade to work toward, or 0 to work toward the goal itself.
	local function choose(balance: number, income: number): number
		if eager then
			-- Buys the cheapest useful upgrade whenever it costs no more than the goal step.
			local best, bestCost = 0, math.huge
			for index = 1, #upgrades do
				local cost = nextCost[index]
				if cost < bestCost and deltaOf(index) > 0 then
					best, bestCost = index, cost
				end
			end
			local goalCost = if isLoot then rollCost else goal.amount :: number
			return if bestCost <= goalCost then best else 0
		end
		-- Payback-period greedy: the upgrade that pays for itself soonest (time to afford plus
		-- cost / income gained), but only if buying it still reaches the goal sooner than saving.
		-- While saving, every candidate's payback falls at the same rate or stays fixed once
		-- affordable, so the choice never changes between events and the jump-ahead stays exact.
		local need = goalNeed()
		local saveTime = if income > 0 then math.max(need - balance, 0) / income else math.huge
		local best, bestPayback = 0, math.huge
		for index = 1, #upgrades do
			local cost = nextCost[index]
			local delta = if cost < math.huge then deltaOf(index) else 0
			if delta > 0 then
				local wait, finish
				if cost <= balance then
					wait = 0
					finish = math.max(need - (balance - cost), 0) / (income + delta)
				elseif income > 0 then
					wait = (cost - balance) / income
					finish = wait + need / (income + delta)
				else
					wait, finish = math.huge, math.huge
				end
				local payback = wait + cost / delta
				-- Strict comparisons: ties keep the earlier choice so equal options never flip-flop.
				if finish < saveTime * (1 - 1e-12) and payback < bestPayback then
					best, bestPayback = index, payback
				end
			end
		end
		return best
	end

	local timeline: Timeline = {
		count = 0,
		time = {},
		before = {},
		after = {},
		income = {},
		kind = {},
		ref = {},
		level = {},
	}
	local t = 0
	local balance = config.startingBalance

	local function push(kind: EventKind, ref: number, level: number, before: number)
		local n = timeline.count + 1
		timeline.count = n
		timeline.time[n] = t
		timeline.before[n] = before
		timeline.after[n] = balance
		timeline.income[n] = rate()
		timeline.kind[n] = kind
		timeline.ref[n] = ref
		timeline.level[n] = level
	end

	for index = 1, #upgrades do
		refreshCost(index)
	end
	push("start", 0, 0, balance)

	local status: Status
	local message = ""
	local goalTime: number? = nil
	local earned, spentUpgrades, spentRolls, purchases, steps = 0, 0, 0, 0, 0

	while true do
		if not isLoot and balance >= goal.amount :: number then
			status = "reached"
			goalTime = t
			push("goal", 0, 0, balance)
			break
		elseif isLoot and rolls >= rollTarget then
			status = if rolls >= coverageTarget then "reached" else "limit"
			if status == "limit" then message = `Roll schedule capped at {Simulate.MAX_ROLLS} rolls.` end
			break
		end
		steps += 1
		if steps > maxSteps then
			status = "limit"
			message = `Stopped after {maxSteps} events. Lower max levels or raise cost growth.`
			break
		end
		if opts.yield and steps % yieldEvery == 0 then
			opts.yield()
		end
		if opts.isCancelled and opts.isCancelled() then
			status = "cancelled"
			message = "Cancelled"
			break
		end

		local income = rate()
		local pick = choose(balance, income)
		local price = if pick > 0 then nextCost[pick] elseif isLoot then rollCost else goal.amount :: number
		if price > balance then
			if income <= 0 then
				status = "stalled"
				message = "Income is 0 and nothing affordable raises it."
				break
			end
			local wait = (price - balance) / income
			if t + wait > horizon then
				earned += income * (horizon - t)
				balance += income * (horizon - t)
				t = horizon
				status = "horizon"
				message = `Not reached within {config.limits.maxHours} h of modeled play.`
				break
			end
			t += wait
			earned += price - balance
			-- Land exactly on the price so rounding can never leave a tiny negative balance.
			balance = price
		end
		if not isLoot and balance >= goal.amount :: number then
			continue
		end
		if pick == 0 and not isLoot then
			continue
		end
		local before = balance
		balance -= price
		if pick > 0 then
			spentUpgrades += price
			purchases += 1
			buy(pick)
			push("upgrade", pick, levels[pick], before)
		else
			spentRolls += price
			rolls += 1
			rollTimes[rolls] = t
			push("roll", rolls, 0, before)
		end
	end

	if status ~= "reached" then
		push("end", 0, 0, balance)
	end

	local loot: LootResult? = nil
	if isLoot then
		local quantiles: { Quantile } = {}
		for _, q in Simulate.QUANTILES do
			local needed = Loot.rollsFor(chance, pity, q)
			table.insert(quantiles, { q = q, rolls = needed, time = rollTimes[needed] })
		end
		goalTime = quantiles[1].time
		loot = {
			chance = chance,
			pity = pity,
			expected = Loot.expected(chance, pity),
			simulatedRolls = rolls,
			rollTimes = rollTimes,
			quantiles = quantiles,
		}
	end

	local levelMap = {}
	for index, upgrade in upgrades do
		levelMap[upgrade.id] = levels[index]
	end

	return {
		status = status,
		message = message,
		config = config,
		goalTime = goalTime,
		endTime = t,
		income = rate(),
		balance = balance,
		earned = earned,
		spentUpgrades = spentUpgrades,
		spentRolls = spentRolls,
		purchases = purchases,
		levels = levelMap,
		longestGap = findGap(timeline, config, goalTime or t),
		timeline = timeline,
		loot = loot,
		steps = steps,
	}
end

-- Index of the last event at or before `t` (1 when t precedes every event).
local function lastAt(times: { number }, count: number, t: number): number
	local low, high = 1, count
	while low < high do
		local mid = (low + high + 1) // 2
		if times[mid] <= t then
			low = mid
		else
			high = mid - 1
		end
	end
	return low
end

-- Exact modeled balance at play time `t`, or nil outside the simulated range.
function Simulate.balanceAt(result: Result, t: number): number?
	local timeline = result.timeline
	if t < 0 or t > result.endTime then
		return nil
	end
	local index = lastAt(timeline.time, timeline.count, t)
	return timeline.after[index] + timeline.income[index] * (t - timeline.time[index])
end

function Simulate.incomeAt(result: Result, t: number): number?
	local timeline = result.timeline
	if t < 0 or t > result.endTime then
		return nil
	end
	return timeline.income[lastAt(timeline.time, timeline.count, t)]
end

-- First moment the wallet holds this amount, including just before a purchase.
function Simulate.timeAtBalance(result: Result, amount: number): number?
	assert(amount >= 0 and amount < math.huge, "amount must be finite and nonnegative")
	local timeline = result.timeline
	if timeline.after[1] >= amount then return 0 end
	for i = 2, timeline.count do
		if timeline.before[i] >= amount then
			return timeline.time[i - 1] + (amount - timeline.after[i - 1]) / timeline.income[i - 1]
		end
	end
	return nil
end

-- Share of modeled players who own the loot target by play time `t` (exact under the model).
function Simulate.chanceAt(result: Result, t: number): number?
	local loot = result.loot
	if not loot or t < 0 or t > result.endTime then
		return nil
	end
	local times = loot.rollTimes
	local count = #times
	if count == 0 or times[1] > t then
		return 0
	end
	return Loot.chanceWithin(loot.chance, loot.pity, lastAt(times, count, t))
end

return table.freeze(Simulate)
