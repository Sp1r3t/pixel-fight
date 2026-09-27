--[[
	Турнир «ИИ против ИИ» для проверки баланса бойцов (без Roblox, в Lune):

	    lune run tests/tools/balance.luau [уровень ИИ=15] [матчей на пару=2]

	Каждый боец играет с каждым (стороны меняются), оба под управлением ИИ одного уровня.
	Матч — до одной победы. Печатает процент побед каждого бойца и худшие/лучшие пары.
	Цель баланса: у всех бойцов 40–60% побед.
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
local CharacterRegistry = shared("Characters", "CharacterRegistry")
local BossRegistry = shared("Characters", "BossRegistry")
local BossAI = server("AI", "BossAI")

local level = tonumber(process.args[1]) or 15
local perPair = tonumber(process.args[2]) or 2

local function duel(a: string, b: string, seed: number): number
	local sim = Simulation.new({ characters = { a, b } })
	sim.fighters[1].tapDash = false
	sim.fighters[2].tapDash = false
	local flow = MatchFlow.new({ roundsToWin = 1 })
	MatchFlow.start(flow, sim)
	local profile = BossRegistry.profileForLevel(level)
	local brainA = BossAI.new(profile, seed * 7919)
	local brainB = BossAI.new(profile, seed * 104729)
	local frames = 0
	while not flow.finished and frames < 20000 do
		Simulation.step(sim, { BossAI.think(brainA, sim, 1), BossAI.think(brainB, sim, 2) })
		MatchFlow.step(flow, sim)
		frames += 1
	end
	return flow.matchWinner
end

local ids = {}
for _, def in CharacterRegistry.list() do
	table.insert(ids, def.id)
end

local wins: { [string]: number } = {}
local games: { [string]: number } = {}
local pairScore: { [string]: number } = {}
local started = os.clock()
local seed = 0
for _, a in ids do
	for _, b in ids do
		if a < b then
			local aWins = 0
			for round = 1, perPair * 2 do
				seed += 1
				local swap = round % 2 == 0
				local winner = if swap then duel(b, a, seed) else duel(a, b, seed)
				local aWon = (winner == 1 and not swap) or (winner == 2 and swap)
				local bWon = (winner == 2 and not swap) or (winner == 1 and swap)
				if aWon then
					aWins += 1
					wins[a] = (wins[a] or 0) + 1
				elseif bWon then
					wins[b] = (wins[b] or 0) + 1
				end
				games[a] = (games[a] or 0) + 1
				games[b] = (games[b] or 0) + 1
			end
			pairScore[`{a} vs {b}`] = aWins / (perPair * 2)
		end
	end
end

table.sort(ids, function(x, y)
	return (wins[x] or 0) / games[x] > (wins[y] or 0) / games[y]
end)
print(
	`Уровень ИИ {level}, матчей на пару {perPair * 2}, {string.format("%.1f", os.clock() - started)} с`
)
for _, id in ids do
	local rate = (wins[id] or 0) / games[id]
	local def = CharacterRegistry.get(id)
	print(
		string.format(
			"  %-8s %5.1f%%  %s",
			id,
			rate * 100,
			if def and def.unlock == "Paid" then "(платный)" else ""
		)
	)
end
local extremes = {}
for key, score in pairScore do
	table.insert(extremes, { key = key, score = score })
end
table.sort(extremes, function(x, y)
	return math.abs(x.score - 0.5) > math.abs(y.score - 0.5)
end)
print("Самые перекошенные пары:")
for index = 1, math.min(8, #extremes) do
	print(string.format("  %-20s %3.0f%%", extremes[index].key, extremes[index].score * 100))
end
