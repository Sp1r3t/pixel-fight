--!strict
--[[
	MatchFlow — раунды и таймер поверх симуляции (чистая логика, тестируется в Lune).

	Фазы: Intro → RoundStart («Round N», затем «Fight!») → Fight → RoundEnd → … → MatchEnd.
	  • раунд длится до GameConfig.Round.DurationSeconds; таймер стоит во время вспышки/ролика супера;
	  • K.O. — побеждает оставшийся на ногах; двойной K.O. — ничья;
	  • время вышло — побеждает больший % HP (не абсолютный HP); равный % — ничья;
	  • ничья даёт победу в раунде обоим; если так оба добрали нужное число — финальный раунд;
	  • матч до roundsToWin побед (2 в PvP, 3 против босса).

	Режим «эстафета» (2 на 2, config.teams): на арене всегда 1 на 1 — слот = команда.
	  • проигравший дуэль (K.O. или меньший % HP по времени) выбывает, после паузы (фаза Relay)
	    выходит его напарник с полным HP и шкалой супера выбывшего;
	  • победитель дуэли остаётся с текущим HP и восстанавливает Team.RegainFraction потерянного;
	  • у каждой дуэли свой таймер; раунд выигрывает команда, выбившая всех соперников;
	  • в чётных раундах порядок выхода бойцов в командах обратный.
]]

local GameConfig = require(script.Parent.Parent.Config.GameConfig)
local Simulation = require(script.Parent.Simulation)
local Fighter = require(script.Parent.Fighter)

type Sim = Simulation.Sim

export type Phase = "Intro" | "RoundStart" | "Fight" | "Relay" | "RoundEnd" | "MatchEnd"
export type RoundResult = "KO" | "Perfect" | "Time" | "Draw" | "DoubleKO"

-- Индексы фаз для снапшотов (0 — без раундов, например тренировка).
local PHASE_INDEX: { [string]: number } = {
	Intro = 1,
	RoundStart = 2,
	Fight = 3,
	RoundEnd = 4,
	MatchEnd = 5,
	Relay = 6,
}

export type FlowEvent = {
	kind: string, -- "RoundStart" | "Fight" | "DuelEnd" | "Relay" | "RoundEnd" | "MatchEnd"
	round: number,
	winner: number, -- 0 — ничья / нет
	result: string?,
	wins: { number },
	final: boolean?,
	slot: number?, -- Relay: в каком слоте сменился боец
	members: { number }?, -- эстафета: индекс активного участника каждой команды (в roster)
}

-- Команда в эстафете.
export type Team = {
	roster: { string }, -- персонажи участников (индекс = номер участника)
	order: { number }, -- порядок выхода в текущем раунде (номера участников)
	active: number, -- позиция текущего бойца в order (больше #order — команда выбита)
}

export type Flow = {
	phase: Phase,
	phaseFrame: number,
	round: number,
	wins: { number },
	roundsToWin: number,
	roundFrames: number,
	timer: number, -- оставшиеся кадры раунда
	roundWinner: number,
	roundResult: RoundResult?,
	matchWinner: number,
	finished: boolean, -- матч окончен, итоги показаны
	events: { FlowEvent },
	teams: { Team }?, -- эстафета 2 на 2 (nil — обычный бой 1 на 1)
	relaySlots: { boolean }, -- какие слоты сменят бойца после паузы Relay
}

export type FlowConfig = {
	roundsToWin: number,
	roundSeconds: number?,
	teams: { { string } }?, -- эстафета: персонажи участников каждой команды
}

-- Длительность фаз в кадрах.
local INTRO_FRAMES = 90
local ROUND_BANNER_FRAMES = 60 -- «Round N»
local FIGHT_BANNER_FRAMES = 30 -- «Fight!» (бой уже можно начинать)
local ROUND_END_FRAMES = 150
local WIN_POSE_DELAY = 60
local MATCH_END_FRAMES = 180
local RELAY_FRAMES = GameConfig.Team.RelayPauseFrames

local MatchFlow = {}

MatchFlow.PHASE_INDEX = table.freeze(PHASE_INDEX)

function MatchFlow.phaseIndex(phase: Phase): number
	return PHASE_INDEX[phase] or 0
end

function MatchFlow.new(config: FlowConfig): Flow
	local seconds = config.roundSeconds or GameConfig.Round.DurationSeconds
	local teams: { Team }? = nil
	if config.teams then
		local list: { Team } = {}
		for index, roster in config.teams do
			assert(#roster > 0, `В команде {index} нет бойцов`)
			local order: { number } = {}
			for member = 1, #roster do
				order[member] = member
			end
			list[index] = { roster = table.clone(roster), order = order, active = 1 }
		end
		assert(#list == 2, "Эстафета рассчитана на две команды")
		teams = list
	end
	return {
		phase = "Intro",
		phaseFrame = 0,
		round = 1,
		wins = { 0, 0 },
		roundsToWin = config.roundsToWin,
		roundFrames = math.floor(seconds * GameConfig.TickRate),
		timer = math.floor(seconds * GameConfig.TickRate),
		roundWinner = 0,
		roundResult = nil,
		matchWinner = 0,
		finished = false,
		events = {},
		teams = teams,
		relaySlots = { false, false },
	}
end

-- Номер активного участника команды в слоте (nil — не эстафета или команда выбита).
function MatchFlow.activeMember(flow: Flow, slot: number): number?
	local teams = flow.teams
	if teams == nil then
		return nil
	end
	local team = teams[slot]
	return team.order[team.active]
end

local function activeMembers(flow: Flow): { number }?
	if flow.teams == nil then
		return nil
	end
	return { MatchFlow.activeMember(flow, 1) or 0, MatchFlow.activeMember(flow, 2) or 0 }
end

local function setPhase(flow: Flow, phase: Phase)
	flow.phase = phase
	flow.phaseFrame = 0
end

local function isFinalRound(flow: Flow): boolean
	return flow.wins[1] == flow.roundsToWin - 1 and flow.wins[2] == flow.roundsToWin - 1
end

local function push(flow: Flow, kind: string, winner: number, result: string?, slot: number?)
	table.insert(flow.events, {
		kind = kind,
		round = flow.round,
		winner = winner,
		result = result,
		wins = table.clone(flow.wins),
		final = isFinalRound(flow),
		slot = slot,
		members = activeMembers(flow),
	})
end

-- Выпустить в слот нового бойца, сохранив шкалу супера команды.
local function sendIn(sim: Sim, slot: number, characterId: string)
	local meter = sim.fighters[slot].meter
	local fighter = Simulation.replaceFighter(sim, slot, characterId, sim.fighters[slot].hpMultiplier)
	fighter.meter = meter
end

-- Эстафета: в начале раунда команды выставляют первых бойцов (в чётных раундах — в обратном порядке).
local function prepareTeams(flow: Flow, sim: Sim)
	local teams = flow.teams
	if teams == nil then
		return
	end
	for slot, team in teams do
		local count = #team.roster
		for position = 1, count do
			team.order[position] = if flow.round % 2 == 0 then count - position + 1 else position
		end
		team.active = 1
		local characterId = team.roster[team.order[1]]
		if sim.fighters[slot].characterId ~= characterId then
			sendIn(sim, slot, characterId)
		end
	end
	flow.relaySlots = { false, false }
end

-- Начать матч: бойцы в позах вступления, ввод выключен.
function MatchFlow.start(flow: Flow, sim: Sim)
	sim.inputEnabled = false
	Simulation.resetPositions(sim)
	for _, fighter in sim.fighters do
		Fighter.setState(fighter, "Intro")
	end
	setPhase(flow, "Intro")
end

local function startRound(flow: Flow, sim: Sim)
	prepareTeams(flow, sim)
	Simulation.resetPositions(sim)
	Simulation.restoreHealth(sim)
	sim.inputEnabled = false
	flow.timer = flow.roundFrames
	flow.roundWinner = 0
	flow.roundResult = nil
	setPhase(flow, "RoundStart")
	push(flow, "RoundStart", 0, nil)
end

local function healthRatio(fighter: Fighter.Fighter): number
	return if fighter.maxHealth > 0 then fighter.health / fighter.maxHealth else 0
end

local function endRound(flow: Flow, sim: Sim, winner: number, result: RoundResult)
	sim.inputEnabled = false
	flow.roundWinner = winner
	flow.roundResult = result
	if winner == 0 then
		flow.wins[1] += 1
		flow.wins[2] += 1
	else
		flow.wins[winner] += 1
	end
	setPhase(flow, "RoundEnd")
	push(flow, "RoundEnd", winner, result)
end

-- Эстафета: конец дуэли — выбывшие уходят, раунд кончается, когда команда выбита.
local function checkDuelEnd(flow: Flow, sim: Sim, teams: { Team })
	local a, b = sim.fighters[1], sim.fighters[2]
	local out: { boolean } = { false, false }
	local result: RoundResult
	if a.ko or b.ko then
		out = { a.ko, b.ko }
		result = if a.ko and b.ko then "DoubleKO" else "KO"
	elseif flow.timer <= 0 then
		local ratioA, ratioB = healthRatio(a), healthRatio(b)
		if math.abs(ratioA - ratioB) < 1e-9 then
			out = { true, true }
		else
			out = { ratioA < ratioB, ratioB < ratioA }
		end
		result = "Time"
	else
		return
	end

	local exhausted: { boolean } = { false, false }
	for slot, team in teams do
		if out[slot] then
			team.active += 1
		end
		exhausted[slot] = team.active > #team.order
	end
	if exhausted[1] or exhausted[2] then
		local winner = if exhausted[1] and exhausted[2] then 0 elseif exhausted[1] then 2 else 1
		endRound(flow, sim, winner, if winner == 0 and result ~= "Time" then "DoubleKO" else result)
		return
	end
	sim.inputEnabled = false
	flow.relaySlots = out
	local duelWinner = if out[1] and out[2] then 0 elseif out[1] then 2 else 1
	setPhase(flow, "Relay")
	push(flow, "DuelEnd", duelWinner, result)
end

-- Эстафета: выходят напарники выбывших, победитель дуэли восстанавливает часть HP.
local function relay(flow: Flow, sim: Sim, teams: { Team })
	for slot, team in teams do
		local fighter = sim.fighters[slot]
		if flow.relaySlots[slot] then
			sendIn(sim, slot, team.roster[team.order[team.active]])
		else
			local lost = fighter.maxHealth - fighter.health
			fighter.health =
				math.min(fighter.maxHealth, fighter.health + math.floor(lost * GameConfig.Team.RegainFraction + 0.5))
		end
	end
	Simulation.resetPositions(sim)
	sim.inputEnabled = false
	flow.timer = flow.roundFrames
	setPhase(flow, "RoundStart")
	for slot, replaced in flow.relaySlots do
		if replaced then
			push(flow, "Relay", 0, nil, slot)
		end
	end
	flow.relaySlots = { false, false }
end

-- Проверка конца раунда во время боя.
local function checkRoundEnd(flow: Flow, sim: Sim)
	local teams = flow.teams
	if teams then
		checkDuelEnd(flow, sim, teams)
		return
	end
	local a, b = sim.fighters[1], sim.fighters[2]
	if a.ko or b.ko then
		if a.ko and b.ko then
			endRound(flow, sim, 0, "DoubleKO")
		else
			local winner = if a.ko then 2 else 1
			local winnerFighter = sim.fighters[winner]
			local perfect = winnerFighter.health >= winnerFighter.maxHealth
			endRound(flow, sim, winner, if perfect then "Perfect" else "KO")
		end
		return
	end
	if flow.timer <= 0 then
		local ratioA, ratioB = healthRatio(a), healthRatio(b)
		if math.abs(ratioA - ratioB) < 1e-9 then
			endRound(flow, sim, 0, "Draw")
		else
			endRound(flow, sim, if ratioA > ratioB then 1 else 2, "Time")
		end
	end
end

local function poseWinner(flow: Flow, sim: Sim)
	for _, fighter in sim.fighters do
		local won = flow.roundWinner == fighter.slot or (flow.roundWinner == 0 and not fighter.ko)
		if
			not fighter.ko
			and not Fighter.isAirborne(fighter)
			and fighter.state ~= "Win"
			and fighter.state ~= "Lose"
		then
			if won and flow.roundWinner ~= 0 then
				Fighter.setState(fighter, "Win")
			elseif flow.roundWinner ~= 0 then
				Fighter.setState(fighter, "Lose")
			end
			fighter.vx = 0
		end
	end
end

-- Шаг раундов. Вызывается сервером после каждого Simulation.step.
function MatchFlow.step(flow: Flow, sim: Sim)
	table.clear(flow.events)
	flow.phaseFrame += 1
	local phase = flow.phase

	if phase == "Intro" then
		if flow.phaseFrame >= INTRO_FRAMES then
			startRound(flow, sim)
		end
	elseif phase == "RoundStart" then
		if flow.phaseFrame == ROUND_BANNER_FRAMES then
			sim.inputEnabled = true
			push(flow, "Fight", 0, nil)
		end
		if flow.phaseFrame >= ROUND_BANNER_FRAMES + FIGHT_BANNER_FRAMES then
			setPhase(flow, "Fight")
		end
		if sim.inputEnabled then
			checkRoundEnd(flow, sim)
		end
	elseif phase == "Fight" then
		if not Simulation.isPaused(sim) then
			flow.timer = math.max(0, flow.timer - 1)
		end
		-- Пока идёт ролик супера, раунд не заканчивается: сначала досмотрим.
		if sim.cinematic == nil then
			checkRoundEnd(flow, sim)
		end
	elseif phase == "Relay" then
		local teams = flow.teams
		if teams and flow.phaseFrame >= RELAY_FRAMES then
			relay(flow, sim, teams)
		end
	elseif phase == "RoundEnd" then
		if flow.phaseFrame == WIN_POSE_DELAY then
			poseWinner(flow, sim)
		end
		if flow.phaseFrame >= ROUND_END_FRAMES then
			local a, b = flow.wins[1], flow.wins[2]
			local target = flow.roundsToWin
			if (a >= target or b >= target) and a ~= b then
				flow.matchWinner = if a > b then 1 else 2
				setPhase(flow, "MatchEnd")
				push(flow, "MatchEnd", flow.matchWinner, nil)
			else
				-- Оба добрали нужное число ничьими — продолжаем до перевеса.
				if a >= target and b >= target then
					flow.wins[1] = target - 1
					flow.wins[2] = target - 1
				end
				flow.round += 1
				startRound(flow, sim)
			end
		end
	elseif phase == "MatchEnd" then
		if flow.phaseFrame == 1 then
			poseWinner(flow, sim)
		end
		if flow.phaseFrame >= MATCH_END_FRAMES then
			flow.finished = true
		end
	end
end

-- Секунды на таймере для отображения.
function MatchFlow.timerSeconds(flow: Flow): number
	return math.ceil(flow.timer / GameConfig.TickRate)
end

return MatchFlow
