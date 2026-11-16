--!strict
-- Minimal test harness for standalone Luau. Counts come from the runs, never from constants.

local Test = {}

type Case = { name: string, fn: () -> () }

local cases: { Case } = {}
local currentSuite = ""

function Test.suite(name: string)
	currentSuite = name
end

function Test.it(name: string, fn: () -> ())
	table.insert(cases, { name = `{currentSuite} > {name}`, fn = fn })
end

local function describe(value: any): string
	if type(value) == "string" then
		return string.format("%q", value)
	end
	return tostring(value)
end

function Test.eq(actual: any, expected: any, label: string?)
	if actual ~= expected then
		error(`{label or "value"}: expected {describe(expected)}, got {describe(actual)}`, 2)
	end
end

function Test.near(actual: number?, expected: number, tolerance: number?, label: string?)
	local tol = tolerance or 1e-9
	if type(actual) ~= "number" or actual ~= actual or math.abs(actual) == math.huge or math.abs(actual - expected) > tol * math.max(1, math.abs(expected)) then
		error(`{label or "value"}: expected ~{expected}, got {describe(actual)}`, 2)
	end
end

function Test.ok(condition: any, label: string?)
	if not condition then
		error(label or "expected a truthy value", 2)
	end
end

function Test.throws(fn: () -> (), pattern: string?)
	local ok, err = pcall(fn)
	if ok then
		error("expected an error", 2)
	end
	if pattern and not string.find(tostring(err), pattern, 1, true) then
		error(`error {describe(tostring(err))} does not mention {describe(pattern)}`, 2)
	end
end

-- True when `problems` has an entry for `path` whose message contains `fragment`.
function Test.hasProblem(problems: { { path: string, message: string } }, path: string, fragment: string?)
	for _, problem in problems do
		if problem.path == path and (fragment == nil or string.find(problem.message, fragment, 1, true)) then
			return
		end
	end
	local seen = {}
	for _, problem in problems do
		table.insert(seen, `{problem.path}: {problem.message}`)
	end
	error(`no problem at {path}{if fragment then ` mentioning "{fragment}"` else ""}; got [{table.concat(seen, "; ")}]`, 2)
end

function Test.run(): (number, number)
	local passed, failed = 0, 0
	for _, case in cases do
		local ok, err = pcall(case.fn)
		if ok then
			passed += 1
			print(`  ok    {case.name}`)
		else
			failed += 1
			print(`  FAIL  {case.name}\n        {err}`)
		end
	end
	print(`\n{passed} passed, {failed} failed, {passed + failed} total`)
	return passed, failed
end

return Test
