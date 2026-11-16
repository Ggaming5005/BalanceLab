--!strict
-- Validates raw config tables (Luau or decoded JSON) into frozen, fully defaulted configs.

local Curve = require("./Curve")

export type Effect = Curve.Curve & { kind: "perAction" | "perSecond" | "multiplier" }

export type Upgrade = {
	id: string,
	name: string,
	effect: Effect,
	cost: Curve.Curve,
	maxLevel: number,
}

export type LootEntry = { name: string, weight: number }

export type Goal = {
	kind: "currency" | "loot",
	name: string,
	amount: number?,
	rollCost: number?,
	target: string?,
	table: { LootEntry }?,
	pity: number?,
}

export type Config = {
	format: number,
	name: string,
	currency: string,
	startingBalance: number,
	income: { perSecond: number, perAction: number },
	player: {
		actionsPerSecond: number,
		sessionMinutes: number,
		sessionsPerDay: number,
		strategy: "efficient" | "eager",
	},
	upgrades: { Upgrade },
	goal: Goal,
	limits: { maxHours: number },
}

export type Problem = { path: string, message: string }

local Config = {}

Config.FORMAT = 1

Config.LIMITS = table.freeze({
	maxAmount = 1e30,
	maxUpgrades = 12,
	maxLevel = 1000,
	maxGrowth = 10,
	maxActionsPerSecond = 20,
	maxSessionMinutes = 1440,
	minSessionsPerDay = 0.1,
	maxSessionsPerDay = 24,
	maxHours = 10000,
	maxLootEntries = 50,
	maxWeight = 1e12,
	maxPity = 100000,
	minChance = 1e-9,
})

Config.EFFECTS = table.freeze({ "perAction", "perSecond", "multiplier" })
Config.STRATEGIES = table.freeze({ "efficient", "eager" })
Config.GOALS = table.freeze({ "currency", "loot" })

local LIMITS = Config.LIMITS

type Reader = { problems: { Problem } }

local function report(reader: Reader, path: string, message: string)
	table.insert(reader.problems, { path = path, message = message })
end

local function show(value: number): string
	if value >= 1e6 then
		return string.format("%g", value)
	end
	return tostring(value)
end

local function isFinite(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

local function readTable(reader: Reader, value: any, path: string, known: { string }?): { [any]: any }
	if value == nil then
		return {}
	end
	if type(value) ~= "table" then
		report(reader, path, "must be a table")
		return {}
	end
	if known then
		for key in value do
			if type(key) ~= "string" or not table.find(known, key) then
				report(reader, `{path}.{tostring(key)}`, "is not a recognised field")
			end
		end
	end
	return value
end

local function readNumber(reader: Reader, value: any, path: string, min: number, max: number, default: number?, integer: boolean?): number
	if value == nil and default ~= nil then
		return default
	end
	if value == nil then
		report(reader, path, "is required")
		return min
	end
	if type(value) ~= "number" or not isFinite(value) then
		report(reader, path, "must be a finite number")
		return default or min
	end
	if integer and value % 1 ~= 0 then
		report(reader, path, "must be a whole number")
		return math.floor(value)
	end
	if value < min or value > max then
		report(reader, path, `must be between {show(min)} and {show(max)}`)
		return math.clamp(value, min, max)
	end
	return value
end

local function readPositive(reader: Reader, value: any, path: string, max: number): number
	local before = #reader.problems
	local number = readNumber(reader, value, path, 0, max)
	if #reader.problems == before and number <= 0 then
		report(reader, path, "must be greater than 0")
	end
	return number
end

local function readText(reader: Reader, value: any, path: string, maxLength: number, default: string?): string
	if value == nil and default ~= nil then
		return default
	end
	if type(value) ~= "string" then
		report(reader, path, "must be text")
		return default or ""
	end
	local text = string.match(value, "^%s*(.-)%s*$") or ""
	local length = utf8.len(text)
	if text == "" then
		report(reader, path, "must not be empty")
	elseif length == nil then
		report(reader, path, "must be valid UTF-8 text")
	elseif length > maxLength then
		report(reader, path, `must be at most {maxLength} characters`)
	elseif string.find(text, "%c") then
		report(reader, path, "must not contain control characters")
	end
	return text
end

local function readChoice(reader: Reader, value: any, path: string, choices: { any }, default: string?): any
	if value == nil and default ~= nil then
		return default
	end
	if table.find(choices, value) then
		return value
	end
	local names = {}
	for _, choice in choices do
		table.insert(names, `"{choice}"`)
	end
	report(reader, path, `must be one of {table.concat(names, ", ")}`)
	return default or choices[1]
end

local COST_FIELDS = { "curve", "base", "growth" }
local EFFECT_FIELDS = { "kind", "curve", "base", "growth" }

local function readCurve(reader: Reader, value: any, path: string, isCost: boolean): { [string]: any }
	if value == nil then
		report(reader, path, "is required")
		return { curve = "linear", base = if isCost then 1 else 0, growth = 0 }
	end
	local raw = readTable(reader, value, path, if isCost then COST_FIELDS else EFFECT_FIELDS)
	local kind = readChoice(reader, raw.curve, `{path}.curve`, Curve.KINDS, "exponential")
	local base
	if isCost then
		base = readPositive(reader, raw.base, `{path}.base`, LIMITS.maxAmount)
	else
		base = readNumber(reader, raw.base, `{path}.base`, 0, LIMITS.maxAmount)
	end
	local growth
	if kind == "exponential" then
		growth = readNumber(reader, raw.growth, `{path}.growth`, if isCost then 1 else 0.01, LIMITS.maxGrowth, 1)
	elseif kind == "linear" then
		growth = readNumber(reader, raw.growth, `{path}.growth`, 0, LIMITS.maxAmount, 0)
	else
		growth = readNumber(reader, raw.growth, `{path}.growth`, 0, LIMITS.maxGrowth, 1)
	end
	return { curve = kind, base = base, growth = growth }
end

local ROOT_FIELDS = { "format", "name", "currency", "startingBalance", "income", "player", "upgrades", "goal", "limits" }
local UPGRADE_FIELDS = { "id", "name", "effect", "cost", "maxLevel" }
local GOAL_FIELDS = { "kind", "name", "amount", "rollCost", "target", "table", "pity" }

local function readUpgrades(reader: Reader, value: any): { Upgrade }
	local list = readTable(reader, value, "upgrades")
	if #list > LIMITS.maxUpgrades then
		report(reader, "upgrades", `must have at most {LIMITS.maxUpgrades} entries`)
	end
	for key in list do
		if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > #list then
			report(reader, "upgrades", "must be a list")
			break
		end
	end
	local upgrades = {}
	local seen = {}
	for index = 1, math.min(#list, LIMITS.maxUpgrades) do
		local path = `upgrades[{index}]`
		local raw = readTable(reader, list[index], path, UPGRADE_FIELDS)
		local id = readText(reader, raw.id, `{path}.id`, 24)
		if id ~= "" and not string.match(id, "^[%a_][%w_]*$") then
			report(reader, `{path}.id`, "must start with a letter and use only letters, digits and _")
		elseif seen[id] then
			report(reader, `{path}.id`, `duplicates upgrades[{seen[id]}].id`)
		end
		seen[id] = seen[id] or index
		local beforeCurves = #reader.problems
		local effect = readCurve(reader, raw.effect, `{path}.effect`, false)
		if type(raw.effect) == "table" then
			effect.kind = readChoice(reader, raw.effect.kind, `{path}.effect.kind`, Config.EFFECTS)
		else
			effect.kind = "perSecond"
		end
		local cost = readCurve(reader, raw.cost, `{path}.cost`, true)
		local maxLevel = readNumber(reader, raw.maxLevel, `{path}.maxLevel`, 1, LIMITS.maxLevel, nil, true)
		if #reader.problems == beforeCurves then
			for _, spec in { { "effect", effect }, { "cost", cost } } do
				local curve = spec[2] :: any
				local maximum = math.max(Curve.at(curve, 0), Curve.at(curve, maxLevel - 1))
				if not isFinite(maximum) or maximum > LIMITS.maxAmount then
					report(reader, `{path}.{spec[1]}`, `generated values exceed {show(LIMITS.maxAmount)} before maxLevel`)
				end
			end
		end
		table.insert(upgrades, {
			id = id,
			name = readText(reader, raw.name, `{path}.name`, 40, id),
			effect = effect :: any,
			cost = cost :: any,
			maxLevel = maxLevel,
		})
	end
	return upgrades
end

local function readGoal(reader: Reader, value: any): Goal
	if value == nil then
		report(reader, "goal", "is required")
	end
	local raw = readTable(reader, value, "goal", GOAL_FIELDS)
	local kind = readChoice(reader, raw.kind, "goal.kind", Config.GOALS, "currency")
	local goal: Goal = {
		kind = kind,
		name = readText(reader, raw.name, "goal.name", 60, if kind == "loot" then "Loot target" else "Milestone"),
	}
	if kind == "currency" then
		goal.amount = readPositive(reader, raw.amount, "goal.amount", LIMITS.maxAmount)
		for _, field in { "rollCost", "target", "table", "pity" } do
			if raw[field] ~= nil then
				report(reader, `goal.{field}`, "only applies to loot goals")
			end
		end
		return goal
	end
	if raw.amount ~= nil then
		report(reader, "goal.amount", "only applies to currency goals")
	end
	goal.rollCost = readPositive(reader, raw.rollCost, "goal.rollCost", LIMITS.maxAmount)
	goal.pity = readNumber(reader, raw.pity, "goal.pity", 0, LIMITS.maxPity, 0, true)
	local target = readText(reader, raw.target, "goal.target", 40)
	local list = readTable(reader, raw.table, "goal.table")
	for key in list do
		if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > #list then
			report(reader, "goal.table", "must be a list")
			break
		end
	end
	if #list == 0 then
		report(reader, "goal.table", "must list at least one entry")
	elseif #list > LIMITS.maxLootEntries then
		report(reader, "goal.table", `must have at most {LIMITS.maxLootEntries} entries`)
	end
	local entries = {}
	local total = 0
	local targetWeight = 0
	local names = {}
	for index = 1, math.min(#list, LIMITS.maxLootEntries) do
		local path = `goal.table[{index}]`
		local entry = readTable(reader, list[index], path, { "name", "weight" })
		local name = readText(reader, entry.name, `{path}.name`, 40)
		local weight = readPositive(reader, entry.weight, `{path}.weight`, LIMITS.maxWeight)
		if names[name] then
			report(reader, `{path}.name`, `duplicates goal.table[{names[name]}].name`)
		end
		names[name] = names[name] or index
		total += weight
		if name == target then
			targetWeight += weight
		end
		table.insert(entries, { name = name, weight = weight })
	end
	if target ~= "" and #entries > 0 and not names[target] then
		report(reader, "goal.target", "must match a goal.table entry name")
	elseif total > 0 and targetWeight / total < LIMITS.minChance then
		report(reader, "goal.target", `drop chance must be at least {show(LIMITS.minChance)}`)
	end
	goal.target = target
	goal.table = entries
	return goal
end

local function deepFreeze<T>(value: T): T
	if type(value) == "table" and not table.isfrozen(value :: any) then
		for _, child in value :: any do
			deepFreeze(child)
		end
		table.freeze(value :: any)
	end
	return value
end

-- Returns a frozen normalized config, or nil and the list of problems (each with a field path).
function Config.validate(raw: any): (Config?, { Problem })
	local reader: Reader = { problems = {} }
	if type(raw) ~= "table" then
		report(reader, "config", "must be a table")
		return nil, reader.problems
	end
	readTable(reader, raw, "config", ROOT_FIELDS)
	if raw.format ~= nil and raw.format ~= Config.FORMAT then
		report(reader, "format", `must be {Config.FORMAT} (this file targets a different BalanceLab version)`)
	end
	local income = readTable(reader, raw.income, "income", { "perSecond", "perAction" })
	local player = readTable(reader, raw.player, "player", { "actionsPerSecond", "sessionMinutes", "sessionsPerDay", "strategy" })
	local limits = readTable(reader, raw.limits, "limits", { "maxHours" })

	local config: Config = {
		format = Config.FORMAT,
		name = readText(reader, raw.name, "name", 60, "Untitled"),
		currency = readText(reader, raw.currency, "currency", 24, "Coins"),
		startingBalance = readNumber(reader, raw.startingBalance, "startingBalance", 0, LIMITS.maxAmount, 0),
		income = {
			perSecond = readNumber(reader, income.perSecond, "income.perSecond", 0, LIMITS.maxAmount, 0),
			perAction = readNumber(reader, income.perAction, "income.perAction", 0, LIMITS.maxAmount, 0),
		},
		player = {
			actionsPerSecond = readNumber(reader, player.actionsPerSecond, "player.actionsPerSecond", 0, LIMITS.maxActionsPerSecond, 0),
			sessionMinutes = readNumber(reader, player.sessionMinutes, "player.sessionMinutes", 1, LIMITS.maxSessionMinutes, 30),
			sessionsPerDay = readNumber(reader, player.sessionsPerDay, "player.sessionsPerDay", LIMITS.minSessionsPerDay, LIMITS.maxSessionsPerDay, 1),
			strategy = readChoice(reader, player.strategy, "player.strategy", Config.STRATEGIES, "efficient"),
		},
		upgrades = readUpgrades(reader, raw.upgrades),
		goal = readGoal(reader, raw.goal),
		limits = {
			maxHours = readNumber(reader, limits.maxHours, "limits.maxHours", 1, LIMITS.maxHours, 200),
		},
	}
	if config.player.sessionMinutes * config.player.sessionsPerDay > 1440 then
		report(reader, "player.sessionsPerDay", "session length times sessions per day must not exceed 1440 minutes")
	end
	if #reader.problems > 0 then
		return nil, reader.problems
	end
	return deepFreeze(config), reader.problems
end

-- Validates or raises one readable error listing every problem.
function Config.assert(raw: any): Config
	local config, problems = Config.validate(raw)
	if config then
		return config
	end
	local lines = {}
	for _, problem in problems do
		table.insert(lines, `{problem.path} {problem.message}`)
	end
	error("BalanceLab config is invalid:\n  " .. table.concat(lines, "\n  "), 2)
end

-- Drop chance of the loot target (0 for currency goals).
function Config.chance(config: Config): number
	local goal = config.goal
	if goal.kind ~= "loot" then
		return 0
	end
	local total, hit = 0, 0
	for _, entry in goal.table :: { LootEntry } do
		total += entry.weight
		if entry.name == goal.target then
			hit += entry.weight
		end
	end
	return if total > 0 then hit / total else 0
end

-- Mutable deep copy for editors.
function Config.draft(config: any): any
	if type(config) ~= "table" then
		return config
	end
	local copy = {}
	for key, value in config do
		copy[key] = Config.draft(value)
	end
	return copy
end

local function encodeNumber(value: number): string
	if value % 1 == 0 and math.abs(value) < 1e15 then
		return string.format("%d", value)
	end
	for digits = 6, 17 do
		local text = string.format(`%.{digits}g`, value)
		if tonumber(text) == value then
			return text
		end
	end
	return string.format("%.17g", value)
end

local KEY_ORDER = {
	"format", "name", "currency", "startingBalance", "income", "player", "upgrades", "goal", "limits",
	"id", "kind", "curve", "base", "growth", "effect", "cost", "maxLevel",
	"perSecond", "perAction", "actionsPerSecond", "sessionMinutes", "sessionsPerDay", "strategy",
	"amount", "rollCost", "target", "pity", "table", "weight", "maxHours",
}
local RANK = {}
for index, key in KEY_ORDER do
	RANK[key] = index
end

local function encodeValue(value: any, indent: string, out: { string })
	local kind = type(value)
	if kind == "number" then
		table.insert(out, encodeNumber(value))
	elseif kind == "string" then
		table.insert(out, string.format("%q", value))
	elseif kind == "boolean" then
		table.insert(out, tostring(value))
	elseif kind == "table" then
		local inner = indent .. "\t"
		if #value > 0 then
			table.insert(out, "{\n")
			for _, item in value do
				table.insert(out, inner)
				encodeValue(item, inner, out)
				table.insert(out, ",\n")
			end
		else
			local keys = {}
			for key in value do
				table.insert(keys, key)
			end
			table.sort(keys, function(a, b)
				local ra, rb = RANK[a] or math.huge, RANK[b] or math.huge
				if ra == rb then
					return tostring(a) < tostring(b)
				end
				return ra < rb
			end)
			if #keys == 0 then
				table.insert(out, "{}")
				return
			end
			table.insert(out, "{\n")
			for _, key in keys do
				table.insert(out, `{inner}{key} = `)
				encodeValue(value[key], inner, out)
				table.insert(out, ",\n")
			end
		end
		table.insert(out, indent .. "}")
	else
		error(`cannot encode {kind}`)
	end
end

-- Deterministic Luau source for a ModuleScript that returns the config.
function Config.toSource(config: Config): string
	local out = { "-- BalanceLab config. Edit values here or in the BalanceLab plugin.\nreturn " }
	encodeValue(config, "", out)
	table.insert(out, "\n")
	return table.concat(out)
end

return table.freeze(Config)
