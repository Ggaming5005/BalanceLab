-- Standalone test entry: luau tests/run.luau
local Test = require("./Test")

require("./core.spec")
require("./config.spec")
require("./simulate.spec")
require("./boundaries.spec")

local _, failed = Test.run()
if failed > 0 then
	error(`{failed} test(s) failed`, 0)
end
