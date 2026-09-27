--[[
	Прогон 2 на 2 «ИИ против ИИ» на сцене с двумя этажами (без Roblox, в Lune):

	    lune run tests/tools/team-duel.luau [уровень=8] [матчей=4] [подробно=0]

	Проверяет, что боты дерутся на своих этажах, а оставшись без соперника на этаже —
	переходят на другой (прыжок через дыру вверх или спрыгивание вниз). Печатает итоги раундов,
	переходы между этажами и время раундов.
]]

local process = require("@lune/process")
local RobloxRequire = require("../lib/RobloxRequire")

local loader = RobloxRequire.new()
local function shared(...)
	return loader.require(loader.get("ReplicatedStorage", "Shared", ...))
end
local function server(...)
	return loader.require(loader.get("ServerScriptService", "Server", ...))
end

local Simulation = shared("Combat", "Simulation")
local MatchFlow = shared("Combat", "MatchFlow")
local Stage = shared("Combat", "Stage")
local CharacterRegistry = shared("Characters", "CharacterRegistry")
local BossRegistry = shared("Characters", "BossRegistry")
local BossAI = server("AI", "BossAI")

local level = tonumber(process.args[1]) or 8
local matches = tonumber(process.args[2]) or 4
local verbose = process.args[3] == "1"

local roster = CharacterRegistry.list()
local totals = { rounds = 0, timeouts = 0, floorChanges = 0, frames = 0, wins = { 0, 0 } }

for index = 1, matches do
	local characters = {}
	for slot = 1, 4 do
		characters[slot] = roster[((index * 3 + slot * 5) % #roster) + 1].id
	end
	local sim = Simulation.new({ characters = characters, stage = "TwoFloors" })
	local flow = MatchFlow.new({ roundsToWin = 2 })
	MatchFlow.start(flow, sim)
	local controllers = {}
	for slot = 1, 4 do
		controllers[slot] = BossAI.controller(BossRegistry.profileForLevel(level), index * 100 + slot)
	end
	local levels = {}
	local roundFrames = 0
	for _ = 1, 60 * 60 * 6 do
		local inputs = {}
		for slot = 1, 4 do
			inputs[slot] = controllers[slot](sim, slot)
		end
		Simulation.step(sim, inputs)
		MatchFlow.step(flow, sim)
		if flow.phase == "Fight" then
			roundFrames += 1
		end
		for slot, fighter in sim.fighters do
			local current = Stage.levelOf(sim.stage, fighter.floorY)
			if levels[slot] ~= nil and levels[slot] ~= current and fighter.y == fighter.floorY then
				totals.floorChanges += 1
				if verbose then
					print(
						`  кадр {sim.frame}: боец {slot} ({fighter.characterId}) перешёл на этаж {current}`
					)
				end
			end
			if fighter.y == fighter.floorY then
				levels[slot] = current
			end
		end
		for _, event in flow.events do
			if event.kind == "RoundStart" then
				table.clear(levels) -- бойцы вернулись на стартовые места: это не переход
			elseif event.kind == "RoundEnd" then
				totals.rounds += 1
				totals.frames += roundFrames
				if event.result == "Time" or event.result == "Draw" then
					totals.timeouts += 1
				end
				local status = MatchFlow.teamStatus(sim)
				print(
					`матч {index}, раунд {event.round}: {event.result}, победила команда {event.winner}, `
						.. `живы {status.alive[1]}:{status.alive[2]}, {math.floor(roundFrames / 60)} с`
				)
				roundFrames = 0
			elseif event.kind == "MatchEnd" then
				totals.wins[event.winner] += 1
			end
		end
		if flow.finished then
			break
		end
	end
end

print(
	`итого: раундов {totals.rounds}, по времени {totals.timeouts}, переходов между этажами {totals.floorChanges}, `
		.. `средний раунд {if totals.rounds > 0 then math.floor(totals.frames / totals.rounds / 60) else 0} с, `
		.. `победы команд {totals.wins[1]}:{totals.wins[2]}`
)
