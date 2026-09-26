--!strict
--[[
	Крошечный тест-раннер: describe/it + expect.
]]

local TestKit = {}

type TestCase = { name: string, fn: () -> () }

local cases: { TestCase } = {}
local prefix: { string } = {}

function TestKit.describe(name: string, body: () -> ())
	table.insert(prefix, name)
	body()
	table.remove(prefix)
end

function TestKit.it(name: string, fn: () -> ())
	local fullName = table.concat(prefix, " › ")
	table.insert(cases, { name = if fullName == "" then name else `{fullName} › {name}`, fn = fn })
end

local function fail(message: string)
	error(message, 3)
end

function TestKit.expect(actual: any)
	return {
		toBe = function(expected: any)
			if actual ~= expected then
				fail(`ожидалось {tostring(expected)}, получено {tostring(actual)}`)
			end
		end,
		toBeCloseTo = function(expected: number, epsilon: number?)
			if math.abs(actual - expected) > (epsilon or 1e-6) then
				fail(`ожидалось ≈{expected}, получено {actual}`)
			end
		end,
		toBeTruthy = function()
			if not actual then
				fail(`ожидалось истинное значение, получено {tostring(actual)}`)
			end
		end,
		toBeEmpty = function()
			if #actual ~= 0 then
				fail(
					`ожидался пустой список, получено {#actual}:\n    `
						.. table.concat(actual, "\n    ")
				)
			end
		end,
		toContainMatch = function(pattern: string)
			for _, item in actual do
				if string.find(item, pattern) then
					return
				end
			end
			fail(
				`ни одна строка не содержит "{pattern}":\n    ` .. table.concat(actual, "\n    ")
			)
		end,
	}
end

-- Запускает все зарегистрированные тесты. Возвращает количество упавших.
function TestKit.run(): number
	local failed = 0
	for _, case in cases do
		local ok, err = pcall(case.fn)
		if ok then
			print(`  ✓ {case.name}`)
		else
			failed += 1
			print(`  ✗ {case.name}\n      {err}`)
		end
	end
	print(`\n{#cases - failed} пройдено, {failed} упало, всего {#cases}`)
	table.clear(cases)
	return failed
end

return TestKit
