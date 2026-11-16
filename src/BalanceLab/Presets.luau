--!strict
-- Example configs. Numbers are illustrative modeled assumptions, not data from live games.

local Presets = {}

Presets.list = {
	{
		name = "Crystal Mine",
		currency = "Gems",
		income = { perSecond = 0, perAction = 1 },
		player = { actionsPerSecond = 2.5, sessionMinutes = 20, sessionsPerDay = 2, strategy = "efficient" },
		upgrades = {
			{
				id = "pickaxe",
				name = "Pickaxe",
				effect = { kind = "perAction", curve = "exponential", base = 1, growth = 1.08 },
				cost = { curve = "exponential", base = 25, growth = 1.16 },
				maxLevel = 100,
			},
			{
				id = "drone",
				name = "Mining Drone",
				effect = { kind = "perSecond", curve = "exponential", base = 3, growth = 1.09 },
				cost = { curve = "exponential", base = 200, growth = 1.17 },
				maxLevel = 100,
			},
			{
				id = "lantern",
				name = "Gem Lantern",
				effect = { kind = "multiplier", curve = "linear", base = 0.15, growth = 0 },
				cost = { curve = "exponential", base = 2000, growth = 1.6 },
				maxLevel = 12,
			},
		},
		goal = { kind = "currency", name = "Unlock Crystal Caves", amount = 10000000 },
		limits = { maxHours = 200 },
	},
	{
		name = "Factory Tycoon",
		currency = "Cash",
		startingBalance = 50,
		income = { perSecond = 2, perAction = 0 },
		player = { actionsPerSecond = 0, sessionMinutes = 45, sessionsPerDay = 1, strategy = "efficient" },
		upgrades = {
			{
				id = "dropper",
				name = "Dropper",
				effect = { kind = "perSecond", curve = "linear", base = 3, growth = 0 },
				cost = { curve = "exponential", base = 25, growth = 1.1 },
				maxLevel = 150,
			},
			{
				id = "refinery",
				name = "Refinery",
				effect = { kind = "perSecond", curve = "exponential", base = 40, growth = 1.1 },
				cost = { curve = "exponential", base = 2500, growth = 1.18 },
				maxLevel = 80,
			},
			{
				id = "conveyor",
				name = "Fast Conveyor",
				effect = { kind = "multiplier", curve = "linear", base = 0.05, growth = 0 },
				cost = { curve = "power", base = 600, growth = 2.2 },
				maxLevel = 30,
			},
		},
		goal = { kind = "currency", name = "First Rebirth", amount = 1000000000 },
		limits = { maxHours = 200 },
	},
	{
		name = "Pet Hatchery",
		currency = "Coins",
		income = { perSecond = 0, perAction = 2 },
		player = { actionsPerSecond = 3, sessionMinutes = 20, sessionsPerDay = 3, strategy = "efficient" },
		upgrades = {
			{
				id = "magnet",
				name = "Coin Magnet",
				effect = { kind = "perAction", curve = "linear", base = 1, growth = 0 },
				cost = { curve = "exponential", base = 30, growth = 1.2 },
				maxLevel = 40,
			},
			{
				id = "fountain",
				name = "Coin Fountain",
				effect = { kind = "perSecond", curve = "linear", base = 5, growth = 1 },
				cost = { curve = "exponential", base = 300, growth = 1.22 },
				maxLevel = 30,
			},
			{
				id = "slots",
				name = "Pet Slot",
				effect = { kind = "multiplier", curve = "linear", base = 0.15, growth = 0 },
				cost = { curve = "exponential", base = 500, growth = 1.9 },
				maxLevel = 8,
			},
		},
		goal = {
			kind = "loot",
			name = "Hatch a Mythic Dragon",
			rollCost = 2500,
			target = "Mythic Dragon",
			pity = 0,
			table = {
				{ name = "Bunny", weight = 55 },
				{ name = "Fox", weight = 30 },
				{ name = "Owl", weight = 12.4 },
				{ name = "Phoenix", weight = 2.5 },
				{ name = "Mythic Dragon", weight = 0.1 },
			},
		},
		limits = { maxHours = 200 },
	},
}

return Presets
