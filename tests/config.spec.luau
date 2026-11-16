--!strict
local Test = require("./Test")
local BalanceLab = require("../src/BalanceLab")

local Config = BalanceLab.Config
local it, eq, ok, hasProblem = Test.it, Test.eq, Test.ok, Test.hasProblem

local function minimal(): any
	return {
		name = "Minimal",
		income = { perSecond = 10 },
		goal = { kind = "currency", amount = 1000 },
	}
end

local function problemsOf(raw: any): { BalanceLab.Problem }
	local config, problems = Config.validate(raw)
	eq(config, nil, "config")
	ok(#problems > 0, "expected problems")
	return problems
end

Test.suite("Config")

it("accepts every bundled preset and freezes the result deeply", function()
	for _, raw in BalanceLab.presets() do
		local config, problems = Config.validate(raw)
		ok(config ~= nil, `{raw.name}: {#problems} problems`)
		local frozen = config :: BalanceLab.Config
		ok(table.isfrozen(frozen), "root frozen")
		ok(table.isfrozen(frozen.upgrades[1].cost), "nested frozen")
		ok(table.isfrozen(frozen.goal), "goal frozen")
	end
end)

it("fills defaults for optional fields", function()
	local config = Config.assert(minimal())
	eq(config.currency, "Coins")
	eq(config.startingBalance, 0)
	eq(config.player.strategy, "efficient")
	eq(config.player.sessionMinutes, 30)
	eq(config.limits.maxHours, 200)
	eq(#config.upgrades, 0)
end)

it("rejects non-table configs and missing goals", function()
	hasProblem(problemsOf(42), "config", "must be a table")
	local raw = minimal()
	raw.goal = nil
	hasProblem(problemsOf(raw), "goal", "is required")
end)

it("rejects NaN, infinity, wrong types and out-of-range numbers with paths", function()
	local raw = minimal()
	raw.income.perSecond = 0 / 0
	hasProblem(problemsOf(raw), "income.perSecond", "finite")
	raw = minimal()
	raw.goal.amount = math.huge
	hasProblem(problemsOf(raw), "goal.amount", "finite")
	raw = minimal()
	raw.player = { actionsPerSecond = "fast" }
	hasProblem(problemsOf(raw), "player.actionsPerSecond", "finite")
	raw = minimal()
	raw.player = { sessionMinutes = 0 }
	hasProblem(problemsOf(raw), "player.sessionMinutes", "between 1 and 1440")
	raw = minimal()
	raw.goal.amount = 0
	hasProblem(problemsOf(raw), "goal.amount", "greater than 0")
	raw = minimal()
	raw.goal.amount = 1e31
	hasProblem(problemsOf(raw), "goal.amount", "between")
end)

it("reports unknown fields so typos are not silently ignored", function()
	local raw = minimal()
	raw.upgardes = {}
	hasProblem(problemsOf(raw), "config.upgardes", "not a recognised field")
	raw = minimal()
	raw.goal.rollCost = 5
	hasProblem(problemsOf(raw), "goal.rollCost", "only applies to loot goals")
end)

it("validates upgrades: ids, duplicates, curves, whole-number levels", function()
	local function upgrade(overrides: { [string]: any }): any
		local base: { [string]: any } = {
			id = "pick",
			effect = { kind = "perSecond", curve = "linear", base = 1, growth = 0 },
			cost = { curve = "exponential", base = 10, growth = 1.1 },
			maxLevel = 10,
		}
		for key, value in overrides do
			base[key] = value
		end
		return base
	end
	local raw = minimal()
	raw.upgrades = { upgrade({ id = "9lives" }) }
	hasProblem(problemsOf(raw), "upgrades[1].id", "start with a letter")
	raw.upgrades = { upgrade({}), upgrade({}) }
	hasProblem(problemsOf(raw), "upgrades[2].id", "duplicates upgrades[1].id")
	raw.upgrades = { upgrade({ cost = { curve = "exponential", base = 10, growth = 0.9 } }) }
	hasProblem(problemsOf(raw), "upgrades[1].cost.growth", "between 1 and 10")
	raw.upgrades = { upgrade({ cost = { curve = "cubic", base = 10, growth = 2 } }) }
	hasProblem(problemsOf(raw), "upgrades[1].cost.curve", "must be one of")
	raw.upgrades = { upgrade({ maxLevel = 2.5 }) }
	hasProblem(problemsOf(raw), "upgrades[1].maxLevel", "whole number")
	raw.upgrades = { upgrade({ effect = { kind = "luck", curve = "linear", base = 1, growth = 0 } }) }
	hasProblem(problemsOf(raw), "upgrades[1].effect.kind", "must be one of")
	raw.upgrades = { upgrade({ cost = { curve = "linear", base = 0, growth = 1 } }) }
	hasProblem(problemsOf(raw), "upgrades[1].cost.base", "greater than 0")
	raw.upgrades = {}
	for index = 1, Config.LIMITS.maxUpgrades + 1 do
		raw.upgrades[index] = upgrade({ id = `u{index}` })
	end
	hasProblem(problemsOf(raw), "upgrades", "at most")
end)

it("validates loot goals: target, weights, pity and minimum chance", function()
	local function loot(): any
		local raw = minimal()
		raw.goal = {
			kind = "loot",
			rollCost = 100,
			target = "Dragon",
			table = { { name = "Cat", weight = 99 }, { name = "Dragon", weight = 1 } },
		}
		return raw
	end
	local config = Config.assert(loot())
	Test.near(Config.chance(config), 0.01)
	eq(config.goal.pity, 0)
	local raw = loot()
	raw.goal.target = "Unicorn"
	hasProblem(problemsOf(raw), "goal.target", "must match")
	raw = loot()
	raw.goal.table[2].weight = -1
	hasProblem(problemsOf(raw), "goal.table[2].weight", "between")
	raw = loot()
	raw.goal.table[2].weight = 0
	hasProblem(problemsOf(raw), "goal.table[2].weight", "greater than 0")
	raw = loot()
	raw.goal.table[1].weight = 1e12
	raw.goal.table[2].weight = 1e-3
	hasProblem(problemsOf(raw), "goal.target", "at least")
	raw = loot()
	raw.goal.pity = 10.5
	hasProblem(problemsOf(raw), "goal.pity", "whole number")
	raw = loot()
	raw.goal.table = {}
	hasProblem(problemsOf(raw), "goal.table", "at least one")
	raw = loot()
	raw.goal.table[2].name = "Cat"
	hasProblem(problemsOf(raw), "goal.table[2].name", "duplicates")
end)

it("rejects text that is empty, too long or has control characters", function()
	local raw = minimal()
	raw.name = "   "
	hasProblem(problemsOf(raw), "name", "must not be empty")
	raw.name = string.rep("x", 61)
	hasProblem(problemsOf(raw), "name", "at most 60")
	raw.name = "line\nbreak"
	hasProblem(problemsOf(raw), "name", "control characters")
	raw.name = "\255bad"
	hasProblem(problemsOf(raw), "name", "UTF-8")
end)

it("rejects configs written for another format version", function()
	local raw = minimal()
	raw.format = 2
	hasProblem(problemsOf(raw), "format", "must be 1")
end)

it("assert raises one error listing every problem", function()
	local raw = minimal()
	raw.income.perSecond = -1
	raw.goal.amount = 0 / 0
	Test.throws(function()
		Config.assert(raw)
	end, "income.perSecond")
	Test.throws(function()
		Config.assert(raw)
	end, "goal.amount")
end)

it("toSource emits a module that round-trips through validate", function()
	for _, raw in BalanceLab.presets() do
		local config = Config.assert(raw)
		local source = Config.toSource(config)
		local chunk = (_G :: any).loadstring(source)
		ok(chunk ~= nil, "source compiles")
		local again = Config.assert(chunk())
		eq(Config.toSource(again), source, `{config.name} round-trip`)
	end
end)

it("draft returns a mutable deep copy", function()
	local config = Config.assert(BalanceLab.presets()[1])
	local draft = Config.draft(config)
	ok(not table.isfrozen(draft), "root mutable")
	ok(not table.isfrozen(draft.upgrades[1].cost), "nested mutable")
	draft.upgrades[1].cost.growth = 1.5
	eq(config.upgrades[1].cost.growth, 1.16, "original untouched")
end)

return nil
