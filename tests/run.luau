--!strict
--[[
	Запуск тестов вне Roblox Studio:
	    lune run tests/run.luau
	(из корня репозитория). Ищет файлы tests/specs/*.spec.luau.

	Глобальные функции в спеках:
	  describe / it / expect                  — тест-раннер (tests/lib/TestKit.luau);
	  requireShared("Config", "Characters")   — require(ReplicatedStorage.Shared.Config.Characters);
	  newRuntime(options?)                    — эмуляция клиента/сервера Roblox (tests/lib/RobloxRuntime.luau);
	  newLoader(options?)                     — загрузчик модулей проекта (tests/lib/RobloxRequire.luau).
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local RobloxRequire = require("./lib/RobloxRequire")
local RobloxRuntime = require("./lib/RobloxRuntime")
local TestKit = require("./lib/TestKit")

local SPEC_DIR = "tests/specs"

local sharedLoader = RobloxRequire.new()

local files = fs.readDir(SPEC_DIR)
table.sort(files)

local failedTotal = 0
for _, file in files do
	if string.match(file, "%.spec%.luau$") then
		print(`\n{file}`)
		local chunk = luau.load(fs.readFile(`{SPEC_DIR}/{file}`), {
			debugName = file,
			environment = {
				describe = TestKit.describe,
				it = TestKit.it,
				expect = TestKit.expect,
				requireShared = function(...: string): any
					return sharedLoader.require(sharedLoader.get("ReplicatedStorage", "Shared", ...))
				end,
				newRuntime = RobloxRuntime.new,
				newLoader = RobloxRequire.new,
				Vector2 = roblox.Vector2,
			},
		})
		chunk()
		failedTotal += TestKit.run()
	end
end

if failedTotal > 0 then
	print(`\nУпавших тестов: {failedTotal}`)
	process.exit(1)
end
