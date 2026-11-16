--!strict
local Test = require("./Test")
local BalanceLab = require("../src/BalanceLab")

local Simulate = BalanceLab.Simulate
local Loot = BalanceLab.Loot
local it, eq, near, ok = Test.it, Test.eq, Test.near, Test.ok

local function config(overrides: { [string]: any }): any
	local raw: { [string]: any } = {
		name = "Test",
		income = { perSecond = 1 },
		goal = { kind = "currency", amount = 100 },
	}
	for key, value in overrides do
		raw[key] = value
	end
	return raw
end

local function flat(id: string, cost: number, gain: number, maxLevel: number?): any
	return {
		id = id,
		effect = { kind = "perSecond", curve = "linear", base = gain, growth = 0 },
		cost = { curve = "linear", base = cost, growth = 0 },
		maxLevel = maxLevel or 1,
	}
end

-- Structural invariants every run must satisfy, whatever the config.
local function checkTimeline(result: BalanceLab.Result)
	local timeline = result.timeline
	ok(timeline.count >= 1, "timeline has a start event")
	eq(timeline.kind[1], "start")
	for index = 1, timeline.count do
		ok(timeline.after[index] >= -1e-9, `balance never negative (event {index})`)
		ok(timeline.before[index] + 1e-9 >= timeline.after[index], `events never add currency (event {index})`)
		if index > 1 then
			local previous = index - 1
			local dt = timeline.time[index] - timeline.time[previous]
			ok(dt >= 0, `time never goes backwards (event {index})`)
			ok(timeline.income[index] + 1e-9 >= timeline.income[previous], `income never drops (event {index})`)
			-- Income is constant between events, so the balance before each event is exact.
			local expected = timeline.after[previous] + timeline.income[previous] * dt
			near(timeline.before[index], expected, 1e-9, `piecewise balance at event {index}`)
		end
	end
end

Test.suite("Simulate")

it("matches closed-form time with no upgrades", function()
	local result = Simulate.run(config({ income = { perSecond = 10 }, goal = { kind = "currency", amount = 1000 } }))
	eq(result.status, "reached")
	near(result.goalTime, 100)
	eq(result.purchases, 0)
	checkTimeline(result)
end)

it("reaches the goal at time 0 when the starting balance covers it", function()
	local result = Simulate.run(config({ startingBalance = 100 }))
	eq(result.status, "reached")
	eq(result.goalTime, 0)
end)

it("efficient player buys an upgrade only when it reaches the goal sooner", function()
	-- Saving: 100s. Buying (+1/s for 10): 10s + 100/2 = 60s.
	local worth = Simulate.run(config({ upgrades = { flat("helper", 10, 1) } }))
	near(worth.goalTime, 60)
	eq(worth.purchases, 1)
	-- Goal 15: saving 15s beats 10s + 15/2 = 17.5s.
	local notWorth = Simulate.run(config({
		upgrades = { flat("helper", 10, 1) },
		goal = { kind = "currency", amount = 15 },
	}))
	near(notWorth.goalTime, 15)
	eq(notWorth.purchases, 0)
	-- The eager player buys it anyway.
	local eager = Simulate.run(config({
		upgrades = { flat("helper", 10, 1) },
		goal = { kind = "currency", amount = 15 },
		player = { strategy = "eager" },
	}))
	near(eager.goalTime, 17.5)
	eq(eager.purchases, 1)
	checkTimeline(eager)
end)

it("efficient player picks the shortest payback first", function()
	-- Payback from zero balance at 1/s: cheap = 10 + 10/1 = 20s, big = 100 + 100/20 = 105s.
	local result = Simulate.run(config({
		upgrades = { flat("big", 100, 20), flat("cheap", 10, 1) },
		goal = { kind = "currency", amount = 1e6 },
	}))
	eq(result.timeline.kind[2], "upgrade")
	eq(result.config.upgrades[result.timeline.ref[2]].id, "cheap")
	checkTimeline(result)
end)

it("multiplier upgrades scale the whole income", function()
	local result = Simulate.run(config({
		income = { perSecond = 10 },
		upgrades = {
			{
				id = "boost",
				effect = { kind = "multiplier", curve = "linear", base = 1, growth = 0 },
				cost = { curve = "linear", base = 100, growth = 0 },
				maxLevel = 1,
			},
		},
		goal = { kind = "currency", amount = 10000 },
	}))
	-- 10s to afford, then 10000 / 20 = 500s.
	near(result.goalTime, 510)
	near(result.income, 20)
end)

it("per-action income uses the modeled action rate", function()
	local result = Simulate.run(config({
		income = { perSecond = 0, perAction = 2 },
		player = { actionsPerSecond = 4 },
		goal = { kind = "currency", amount = 800 },
	}))
	near(result.goalTime, 100)
end)

it("reports stalled runs instead of inventing a time", function()
	local result = Simulate.run(config({ income = { perSecond = 0 } }))
	eq(result.status, "stalled")
	eq(result.goalTime, nil)
	ok(string.find(result.message, "Income is 0", 1, true) ~= nil, "message explains")
end)

it("spends a starting balance even when base income is zero", function()
	local result = Simulate.run(config({
		income = { perSecond = 0 },
		startingBalance = 10,
		upgrades = { flat("first", 10, 2) },
	}))
	eq(result.status, "reached")
	near(result.goalTime, 50)
end)

it("stops at the play-time horizon", function()
	local result = Simulate.run(config({
		income = { perSecond = 0.001 },
		goal = { kind = "currency", amount = 1e9 },
		limits = { maxHours = 1 },
	}))
	eq(result.status, "horizon")
	eq(result.goalTime, nil)
	eq(result.endTime, 3600)
	near(result.balance, 3.6)
	eq(result.timeline.kind[result.timeline.count], "end")
end)

it("stops at the step limit", function()
	local result = Simulate.run(config({
		upgrades = { flat("tiny", 0.001, 0.0001, 1000) },
		goal = { kind = "currency", amount = 1e6 },
	}), { maxSteps = 5 })
	eq(result.status, "limit")
	eq(result.steps, 6)
end)

it("yields on schedule and can be cancelled between yields", function()
	local preset = BalanceLab.presets()[1]
	local yields = 0
	local full = Simulate.run(preset, {
		yieldEvery = 10,
		yield = function()
			yields += 1
		end,
	})
	eq(yields, full.steps // 10, "one yield per 10 steps")

	local cancelAfter = 3
	yields = 0
	local cancelled = Simulate.run(preset, {
		yieldEvery = 10,
		yield = function()
			yields += 1
		end,
		isCancelled = function()
			return yields >= cancelAfter
		end,
	})
	eq(cancelled.status, "cancelled")
	eq(cancelled.goalTime, nil)
	eq(cancelled.steps, cancelAfter * 10)
end)

it("cancellation works with a coroutine-yielding host", function()
	local stop = false
	local thread = coroutine.create(function()
		return Simulate.run(BalanceLab.presets()[2], {
			yieldEvery = 5,
			yield = coroutine.yield,
			isCancelled = function()
				return stop
			end,
		})
	end)
	local okResume = coroutine.resume(thread)
	ok(okResume, "first resume")
	eq(coroutine.status(thread), "suspended", "yielded to the host")
	stop = true
	local resumed, result = coroutine.resume(thread)
	ok(resumed, "second resume")
	eq(result.status, "cancelled")
end)

it("is deterministic: identical inputs give identical timelines", function()
	for _, preset in BalanceLab.presets() do
		local a = Simulate.run(preset)
		local b = Simulate.run(preset)
		eq(a.timeline.count, b.timeline.count, "event count")
		for index = 1, a.timeline.count do
			eq(a.timeline.time[index], b.timeline.time[index], "time")
			eq(a.timeline.after[index], b.timeline.after[index], "balance")
		end
	end
end)

it("bundled presets satisfy timeline invariants and reach their goal", function()
	for _, preset in BalanceLab.presets() do
		local result = Simulate.run(preset)
		eq(result.status, "reached", preset.name)
		ok(result.goalTime ~= nil and (result.goalTime :: number) > 0, `{preset.name} goal time`)
		checkTimeline(result)
		ok(result.longestGap ~= nil, "longest gap computed")
	end
end)

it("currency goal time equals the last event plus the final save", function()
	local result = Simulate.run(BalanceLab.presets()[1])
	local timeline = result.timeline
	local last = timeline.count - 1
	eq(timeline.kind[timeline.count], "goal")
	local saving = (result.config.goal.amount :: number - timeline.after[last]) / timeline.income[last]
	near(result.goalTime, timeline.time[last] + saving, 1e-9)
end)

it("balanceAt, incomeAt and chanceAt read the exact timeline", function()
	local result = Simulate.run(BalanceLab.presets()[1])
	local timeline = result.timeline
	for _, index in { 2, 10, timeline.count - 1 } do
		near(Simulate.balanceAt(result, timeline.time[index]), timeline.after[index], 1e-9)
		eq(Simulate.incomeAt(result, timeline.time[index]), timeline.income[index])
	end
	eq(Simulate.balanceAt(result, -1), nil)
	eq(Simulate.balanceAt(result, result.endTime + 1), nil)
	eq(Simulate.chanceAt(result, 1), nil, "no loot goal")
end)

it("loot goals derive percentiles from the exact roll distribution", function()
	local result = Simulate.run(BalanceLab.presets()[3])
	local loot = result.loot :: BalanceLab.LootResult
	ok(loot ~= nil, "loot result")
	near(loot.chance, 0.001)
	eq(loot.simulatedRolls, Loot.rollsFor(0.001, 0, Simulate.COVERAGE))
	for _, quantile in loot.quantiles do
		eq(quantile.rolls, Loot.rollsFor(0.001, 0, quantile.q))
		eq(quantile.time, loot.rollTimes[quantile.rolls])
		local chance = Simulate.chanceAt(result, quantile.time :: number) :: number
		ok(chance >= quantile.q, `chance at p{quantile.q * 100} time`)
	end
	eq(result.goalTime, loot.quantiles[1].time, "goal time is the median")
	eq(Simulate.chanceAt(result, 0), 0)
	for index = 2, #loot.rollTimes do
		ok(loot.rollTimes[index] >= loot.rollTimes[index - 1], "roll times ordered")
	end
	checkTimeline(result)
end)

it("pity caps the roll schedule and the upper percentiles", function()
	local raw = BalanceLab.presets()[3]
	raw.goal.pity = 300
	local result = Simulate.run(raw)
	local loot = result.loot :: BalanceLab.LootResult
	eq(loot.simulatedRolls, 300)
	eq(loot.quantiles[3].rolls, 300)
	eq(loot.quantiles[3].time, loot.rollTimes[300])
	eq(Simulate.chanceAt(result, loot.rollTimes[300]), 1)
end)

it("a certain drop needs exactly one roll", function()
	local result = Simulate.run(config({
		goal = { kind = "loot", rollCost = 50, target = "Only", table = { { name = "Only", weight = 1 } } },
	}))
	local loot = result.loot :: BalanceLab.LootResult
	eq(loot.simulatedRolls, 1)
	near(result.goalTime, 50)
	for _, quantile in loot.quantiles do
		near(quantile.time, 50)
	end
end)

it("loot runs report unreached percentiles as missing at the horizon", function()
	local result = Simulate.run(config({
		income = { perSecond = 1 },
		limits = { maxHours = 1 },
		goal = { kind = "loot", rollCost = 100, target = "Rare", table = { { name = "Rare", weight = 1 }, { name = "Common", weight = 999 } } },
	}))
	eq(result.status, "horizon")
	eq(result.goalTime, nil)
	eq((result.loot :: BalanceLab.LootResult).quantiles[3].time, nil)
end)

it("compare describes faster, slower and unreachable edits", function()
	local base = Simulate.run(config({}))
	local slower = Simulate.run(config({ goal = { kind = "currency", amount = 150 } }))
	local stalled = Simulate.run(config({ income = { perSecond = 0 } }))
	local delta = BalanceLab.compare(base, slower)
	near(delta.seconds, 50)
	near(delta.ratio, 1.5)
	ok(string.find(delta.text, "50% slower", 1, true) ~= nil, delta.text)
	ok(string.find(BalanceLab.compare(slower, base).text, "faster", 1, true) ~= nil, "faster")
	eq(BalanceLab.compare(base, base).text, "No change")
	eq(BalanceLab.compare(base, stalled).text, "The edited run no longer reaches the goal")
end)

it("costOf and effectOf expose the same curves to game code", function()
	local config = BalanceLab.Config.assert(BalanceLab.presets()[1])
	near(BalanceLab.costOf(config, "pickaxe", 0), 25)
	near(BalanceLab.costOf(config, "pickaxe", 2), 25 * 1.16 ^ 2)
	eq(BalanceLab.costOf(config, "lantern", 12), nil, "maxed")
	near(BalanceLab.effectOf(config, "lantern", 4), 0.6)
	near(BalanceLab.effectOf(config, "lantern", 99), 1.8, 1e-9, "clamped to max level")
	Test.throws(function()
		BalanceLab.costOf(config, "nope", 0)
	end, "unknown upgrade")
end)

it("rejects invalid configs before simulating", function()
	Test.throws(function()
		Simulate.run({ goal = { kind = "currency", amount = -5 } })
	end, "goal.amount")
end)

return nil
