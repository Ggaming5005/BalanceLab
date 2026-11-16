-- Standalone: luau examples/Compare.luau
local BalanceLab = require("../src/BalanceLab")
local raw = BalanceLab.presets()[1]
local before = BalanceLab.simulate(raw)
raw.upgrades[1].cost.growth = 1.13
local after = BalanceLab.simulate(raw)
print(raw.name, BalanceLab.Format.duration(before.goalTime), "->", BalanceLab.Format.duration(after.goalTime))
print(BalanceLab.compare(before, after).text)
return { before = before, after = after }
