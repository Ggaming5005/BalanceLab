--!strict
-- BalanceLab: deterministic progression modeling for one currency, upgrade curves and one goal.
-- Pure Luau; runs in Roblox (server, client, plugin) and in standalone Luau.

local Config = require("@self/Config")
local Curve = require("@self/Curve")
local Format = require("@self/Format")
local Loot = require("@self/Loot")
local Presets = require("@self/Presets")
local Simulate = require("@self/Simulate")

export type Config = Config.Config
export type Problem = Config.Problem
export type Curve = Curve.Curve
export type Result = Simulate.Result
export type LootResult = Simulate.LootResult
export type Options = Simulate.Options

export type Comparison = {
	before: number?,
	after: number?,
	seconds: number?,
	ratio: number?,
	text: string,
}

local BalanceLab = {}

BalanceLab.VERSION = "0.1.0"

BalanceLab.Config = Config
BalanceLab.Curve = Curve
BalanceLab.Format = Format
BalanceLab.Loot = Loot
BalanceLab.Simulate = Simulate

BalanceLab.validate = Config.validate
BalanceLab.simulate = Simulate.run
BalanceLab.toSource = Config.toSource

local function checkOwned(owned: number)
	assert(owned >= 0 and owned < math.huge and owned % 1 == 0, "owned must be a nonnegative whole number")
end

-- Price of the next level of an upgrade when `owned` levels are owned; nil once maxed.
-- Lets game code charge exactly what the analysed config says.
function BalanceLab.costOf(config: Config, upgradeId: string, owned: number): number?
	checkOwned(owned)
	for _, upgrade in config.upgrades do
		if upgrade.id == upgradeId then
			if owned >= upgrade.maxLevel then
				return nil
			end
			return Curve.at(upgrade.cost, owned)
		end
	end
	error(`unknown upgrade "{upgradeId}"`, 2)
end

-- Total effect granted by `owned` levels of an upgrade.
function BalanceLab.effectOf(config: Config, upgradeId: string, owned: number): number
	checkOwned(owned)
	for _, upgrade in config.upgrades do
		if upgrade.id == upgradeId then
			return Curve.total(upgrade.effect, 0, math.min(owned, upgrade.maxLevel))
		end
	end
	error(`unknown upgrade "{upgradeId}"`, 2)
end

-- Compares modeled time to goal (median time for loot goals) between two runs.
function BalanceLab.compare(before: Result, after: Result): Comparison
	local a, b = before.goalTime, after.goalTime
	if a == nil or b == nil then
		local text = if a == nil and b == nil then "Neither run reaches the goal"
			elseif a == nil then "Only the edited run reaches the goal"
			else "The edited run no longer reaches the goal"
		return { before = a, after = b, text = text }
	end
	local seconds = b - a
	local ratio = if a > 0 then b / a else nil
	local text
	if math.abs(seconds) < 0.5 then
		text = "No change"
	elseif ratio == nil then
		text = `{Format.duration(math.abs(seconds))} slower`
	elseif ratio > 1 then
		text = `{Format.percent(ratio - 1)} slower ({Format.duration(seconds)} more play)`
	else
		text = `{Format.percent(1 - ratio)} faster ({Format.duration(-seconds)} less play)`
	end
	return { before = a, after = b, seconds = seconds, ratio = ratio, text = text }
end

-- Fresh mutable copies of the bundled example configs.
function BalanceLab.presets(): { any }
	local list = {}
	for _, preset in Presets.list do
		table.insert(list, Config.draft(preset))
	end
	return list
end

return table.freeze(BalanceLab)
