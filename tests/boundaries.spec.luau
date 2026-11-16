--!strict
local Test = require("./Test")
local B = require("../src/BalanceLab")
local it, eq, near, throws, ok = Test.it, Test.eq, Test.near, Test.throws, Test.ok

local function upgrade(): any
	return { id = "helper", cost = { curve = "linear", base = 100, growth = 0 }, effect = { kind = "perSecond", curve = "linear", base = 1, growth = 0 }, maxLevel = 1 }
end

Test.suite("Boundaries")

it("finds held-currency milestones even immediately before an upgrade", function()
	local u = upgrade()
	u.cost.base = 10
	local r = B.simulate({ income = { perSecond = 1 }, upgrades = { u }, goal = { amount = 100 } })
	near(B.Simulate.timeAtBalance(r, 10), 10)
	near(B.Simulate.timeAtBalance(r, 50), 35)
	eq(B.Simulate.timeAtBalance(r, 101), nil)
end)

it("recognizes the goal before spending an equal-price eager purchase", function()
	for _, balance in { 0, 30 } do
		local r = B.simulate({ startingBalance = balance, income = { perSecond = 1 }, player = { strategy = "eager" }, upgrades = { upgrade() }, goal = { kind = "currency", amount = 100 } })
		near(r.goalTime, 100 - balance)
		eq(r.purchases, 0)
		eq(r.status, "reached")
	end
end)

it("reports computation caps even when rare loot has not reached the median", function()
	for _, pity in { 0, 100000 } do
		local r = B.simulate({ income = { perSecond = 1e6 }, goal = { kind = "loot", rollCost = 1, target = "Rare", pity = pity, table = { { name = "Rare", weight = 1 }, { name = "Common", weight = 999999999 } } } })
		eq(r.status, "limit")
		eq(r.goalTime, nil)
		eq((r.loot :: B.LootResult).simulatedRolls, B.Simulate.MAX_ROLLS)
		ok((B.Simulate.chanceAt(r, r.endTime) :: number) < 0.5, "median is not reached")
	end
end)

it("clips the longest wait to the median goal", function()
	local r = B.simulate({ startingBalance = 10, income = { perSecond = 1 }, goal = { kind = "loot", rollCost = 10, target = "Rare", table = { { name = "Rare", weight = 1 }, { name = "Common", weight = 1 } } } })
	near(r.goalTime, 0)
		eq(r.longestGap, nil)
end)

it("rejects generated curve values outside the supported range", function()
	for _, name in { "cost", "effect" } do
		local u = upgrade()
		u[name].curve, u[name].base, u[name].growth, u.maxLevel = "exponential", 1e30, 10, 2
		local c, problems = B.validate({ upgrades = { u }, goal = { amount = 1e30 } })
		eq(c, nil)
		Test.hasProblem(problems, "upgrades[1]." .. name, "generated values")
	end
end)

it("rejects mixed-key and sparse loot tables instead of silently dropping entries", function()
	for _, entries in {
		{ { name = "Rare", weight = 1 }, common = { name = "Common", weight = 999 } },
		{ [1] = { name = "Rare", weight = 1 }, [3] = { name = "Common", weight = 999 } },
	} do
		local c, problems = B.validate({ goal = { kind = "loot", rollCost = 1, target = "Rare", table = entries } })
		eq(c, nil)
		ok(#problems > 0, "bad list rejected")
	end
end)

it("evaluates zero and small-base exponential curves without intermediate overflow", function()
	local zero = { curve = "exponential", base = 0, growth = 10 } :: B.Curve
	near(B.Curve.at(zero, 309), 0)
	near(B.Curve.total(zero, 0, 1000), 0)
	local tiny = { curve = "exponential", base = 1e-300, growth = 10 } :: B.Curve
	near(B.Curve.at(tiny, 309), 1e9, 1e-12)
	near(B.Curve.total(tiny, 0, 310), 1e9 / 0.9, 1e-12)
	near(B.Curve.at({ curve = "linear", base = 0, growth = 2 }, 3), 6)
	near(B.Curve.total({ curve = "linear", base = 0, growth = 2 }, 0, 4), 12)
end)

it("keeps a guaranteed next pity roll exact at the minimum supported chance", function()
	eq(B.Loot.expectedRemaining(1e-9, 100, 99), 1)
	near(B.Loot.expected(1e-9, 2), 2 - 1e-9, 1e-12)
	throws(function() B.Loot.rollsFor(0.5, 0, 1) end, "q must")
end)

it("rejects impossible daily play and invalid public counters", function()
	local c, problems = B.validate({ player = { sessionMinutes = 1440, sessionsPerDay = 2 }, goal = { amount = 10 } })
	eq(c, nil)
	Test.hasProblem(problems, "player.sessionsPerDay", "1440")
	local valid = B.Config.assert({ upgrades = { upgrade() }, goal = { amount = 10 } })
	for _, owned in { -1, 1.5, 0 / 0, math.huge } do
		throws(function() B.costOf(valid, "helper", owned) end, "owned")
		throws(function() B.effectOf(valid, "helper", owned) end, "owned")
	end
	throws(function() B.simulate({ goal = { amount = 10 } }, { yieldEvery = 0 / 0 }) end, "yieldEvery")
	throws(function() Test.near(0 / 0, 1) end)
end)

return nil
