--!strict
local Test = require("./Test")
local BalanceLab = require("../src/BalanceLab")

local Curve = BalanceLab.Curve
local Loot = BalanceLab.Loot
local Format = BalanceLab.Format

local it, eq, near, ok = Test.it, Test.eq, Test.near, Test.ok

Test.suite("Curve")

it("evaluates each curve kind at 0-based levels", function()
	near(Curve.at({ curve = "exponential", base = 10, growth = 1.5 }, 0), 10)
	near(Curve.at({ curve = "exponential", base = 10, growth = 1.5 }, 2), 22.5)
	near(Curve.at({ curve = "linear", base = 5, growth = 2 }, 3), 11)
	near(Curve.at({ curve = "power", base = 4, growth = 2 }, 2), 36)
end)

it("closed-form totals match summing every level", function()
	local curves: { BalanceLab.Curve } = {
		{ curve = "exponential", base = 25, growth = 1.16 },
		{ curve = "exponential", base = 7, growth = 1 },
		{ curve = "linear", base = 3, growth = 0.25 },
		{ curve = "power", base = 600, growth = 2.2 },
	}
	for _, curve in curves do
		for _, range in { { 0, 1 }, { 0, 10 }, { 4, 9 }, { 17, 40 } } do
			local sum = 0
			for level = range[1], range[2] - 1 do
				sum += Curve.at(curve, level)
			end
			near(Curve.total(curve, range[1], range[2]), sum, 1e-9, `{curve.curve} total {range[1]}..{range[2]}`)
		end
		eq(Curve.total(curve, 5, 5), 0, "empty range")
		eq(Curve.total(curve, 6, 2), 0, "reversed range")
	end
end)

Test.suite("Loot")

it("cumulative chance follows 1 - (1 - p)^n and pity guarantees", function()
	near(Loot.chanceWithin(0.5, 0, 1), 0.5)
	near(Loot.chanceWithin(0.5, 0, 2), 0.75)
	eq(Loot.chanceWithin(0.5, 0, 0), 0)
	eq(Loot.chanceWithin(0.01, 3, 3), 1)
	near(Loot.chanceWithin(0.01, 3, 2), 1 - 0.99 ^ 2)
	eq(Loot.chanceWithin(1, 0, 1), 1)
end)

it("rollsFor returns the smallest roll count reaching q", function()
	eq(Loot.rollsFor(0.5, 0, 0.5), 1)
	eq(Loot.rollsFor(0.5, 0, 0.75), 2)
	eq(Loot.rollsFor(0.5, 0, 0.9), 4)
	eq(Loot.rollsFor(0.001, 100, 0.5), 100, "pity caps the count")
	for _, p in { 0.3, 0.01, 0.001, 1e-6, 1e-9 } do
		for _, q in { 0.5, 0.9, 0.99, 0.999 } do
			local rolls = Loot.rollsFor(p, 0, q)
			ok(Loot.chanceWithin(p, 0, rolls) >= q, `p={p} q={q} reaches q`)
			ok(rolls == 1 or Loot.chanceWithin(p, 0, rolls - 1) < q, `p={p} q={q} is minimal`)
		end
	end
end)

it("expected rolls match the distribution, with and without pity", function()
	near(Loot.expected(0.25, 0), 4)
	near(Loot.expected(0.2, 1), 1)
	for _, case in { { 0.05, 30 }, { 0.001, 500 }, { 0.3, 4 } } do
		local p, pity = case[1], case[2]
		local mean = 0
		for k = 1, pity do
			local probability = if k < pity then (1 - p) ^ (k - 1) * p else (1 - p) ^ (pity - 1)
			mean += k * probability
		end
		near(Loot.expected(p, pity), mean, 1e-9, `p={p} pity={pity}`)
	end
	near(Loot.expectedRemaining(0.1, 0, 37), 10, 1e-12, "memoryless without pity")
	near(Loot.expectedRemaining(0.1, 10, 9), 1, 1e-12, "last pity roll is certain")
end)

Test.suite("Format")

it("abbreviates numbers to three significant digits", function()
	eq(Format.number(0), "0")
	eq(Format.number(12.5), "12.5")
	eq(Format.number(999), "999")
	eq(Format.number(1000), "1K")
	eq(Format.number(1234), "1.23K")
	eq(Format.number(999999), "1M")
	eq(Format.number(2.5e6), "2.5M")
	eq(Format.number(-45600), "-45.6K")
	eq(Format.number(1e33), "1.00e+33")
	eq(Format.number(0 / 0), "NaN")
	eq(Format.number(math.huge), "inf")
end)

it("formats durations, ticks, percentages, odds and days", function()
	eq(Format.duration(59), "59s")
	eq(Format.duration(60), "1m 00s")
	eq(Format.duration(3599.6), "1h 00m")
	eq(Format.duration(3 * 3600 + 5 * 60), "3h 05m")
	eq(Format.duration(360000), "100h")
	eq(Format.duration(nil), "-")
	eq(Format.duration(math.huge), "never")
	eq(Format.tick(0), "0")
	eq(Format.tick(900), "15m")
	eq(Format.tick(3600), "1h")
	eq(Format.tick(5400), "1h30")
	eq(Format.percent(0.005), "0.5%")
	eq(Format.percent(0.9), "90%")
	eq(Format.percent(0.999), "99.9%")
	eq(Format.percent(0.0001), "0.01%")
	eq(Format.odds(0.005), "1 in 200")
	eq(Format.odds(0.001), "1 in 1,000")
	eq(Format.integer(1234567), "1,234,567")
	eq(Format.day(0, 30, 2), "day 1")
	eq(Format.day(3600, 30, 2), "day 1")
	eq(Format.day(3601, 30, 2), "day 2")
end)

return nil
