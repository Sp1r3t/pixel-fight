--!strict
--[[
	MatchFlow — раунды и таймер поверх симуляции (чистая логика, тестируется в Lune).

	Фазы: Intro → RoundStart («Round N», затем «Fight!») → Fight → RoundEnd → … → MatchEnd.
	  • раунд длится до GameConfig.Round.DurationSeconds; таймер стоит во время вспышки/ролика супера;
	  • побеждает команда, выбившая всех бойцов соперников (в 1 на 1 — единственного);
	    выбиты все сразу — двойной K.O. (ничья);
	  • время вышло — побеждает больший общий % HP команды (не абсолютный HP); равный — ничья;
	  • ничья даёт победу в раунде обеим командам; если так обе добрали нужное число — финальный раунд;
	  • матч до roundsToWin побед (2 в PvP, 3 против босса).
	В 2 на 2 выбитый боец лежит до конца раунда, его напарник продолжает бой.
]]

local GameConfig = require(script.Parent.Parent.Config.GameConfig)
local Simulation = require(script.Parent.Simulation)
local Fighter = require(script.Parent.Fighter)

type Sim = Simulation.Sim

export type Phase = "Intro" | "RoundStart" | "Fight" | "RoundEnd" | "MatchEnd"
export type RoundResult = "KO" | "Perfect" | "Time" | "Draw" | "DoubleKO"

-- Индексы фаз для снапшотов (0 — без раундов, например тренировка).
local PHASE_INDEX: { [string]: number } = {
	Intro = 1,
	RoundStart = 2,
	Fight = 3,
	RoundEnd = 4,
	MatchEnd = 5,
}

export type FlowEvent = {
	kind: string, -- "RoundStart" | "Fight" | "RoundEnd" | "MatchEnd"
	round: number,
	winner: number, -- команда-победитель (0 — ничья / нет)
	result: string?,
	wins: { number }, -- победы команд в раундах
	final: boolean?,
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
	matchWinner: number, -- команда
	finished: boolean, -- матч окончен, итоги показаны
	events: { FlowEvent },
}

export type FlowConfig = {
	roundsToWin: number,
	roundSeconds: number?,
}

-- Длительность фаз в кадрах.
local INTRO_FRAMES = 90
local ROUND_BANNER_FRAMES = 60 -- «Round N»
local FIGHT_BANNER_FRAMES = 30 -- «Fight!» (бой уже можно начинать)
local ROUND_END_FRAMES = 150
local WIN_POSE_DELAY = 60
local MATCH_END_FRAMES = 180

local MatchFlow = {}

MatchFlow.PHASE_INDEX = table.freeze(PHASE_INDEX)

function MatchFlow.phaseIndex(phase: Phase): number
	return PHASE_INDEX[phase] or 0
end

function MatchFlow.new(config: FlowConfig): Flow
	local seconds = config.roundSeconds or GameConfig.Round.DurationSeconds
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
	}
end

local function setPhase(flow: Flow, phase: Phase)
	flow.phase = phase
	flow.phaseFrame = 0
end

local function isFinalRound(flow: Flow): boolean
	return flow.wins[1] == flow.roundsToWin - 1 and flow.wins[2] == flow.roundsToWin - 1
end

local function push(flow: Flow, kind: string, winner: number, result: string?)
	table.insert(flow.events, {
		kind = kind,
		round = flow.round,
		winner = winner,
		result = result,
		wins = table.clone(flow.wins),
		final = isFinalRound(flow),
	})
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
	Simulation.resetPositions(sim)
	Simulation.restoreHealth(sim)
	sim.inputEnabled = false
	flow.timer = flow.roundFrames
	flow.roundWinner = 0
	flow.roundResult = nil
	setPhase(flow, "RoundStart")
	push(flow, "RoundStart", 0, nil)
end

export type TeamStatus = {
	alive: { number }, -- сколько бойцов команды на ногах
	health: { number }, -- суммарное HP
	maxHealth: { number },
}

-- Состояние команд: сколько бойцов не выбито и суммарное здоровье.
function MatchFlow.teamStatus(sim: Sim): TeamStatus
	local status: TeamStatus = { alive = { 0, 0 }, health = { 0, 0 }, maxHealth = { 0, 0 } }
	for _, fighter in sim.fighters do
		local team = fighter.team
		if not fighter.ko then
			status.alive[team] += 1
		end
		status.health[team] += fighter.health
		status.maxHealth[team] += fighter.maxHealth
	end
	return status
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

-- Проверка конца раунда во время боя.
local function checkRoundEnd(flow: Flow, sim: Sim)
	local status = MatchFlow.teamStatus(sim)
	local alive = status.alive
	if alive[1] == 0 or alive[2] == 0 then
		if alive[1] == 0 and alive[2] == 0 then
			endRound(flow, sim, 0, "DoubleKO")
		else
			local winner = if alive[1] == 0 then 2 else 1
			local perfect = status.health[winner] >= status.maxHealth[winner]
			endRound(flow, sim, winner, if perfect then "Perfect" else "KO")
		end
		return
	end
	if flow.timer <= 0 then
		local ratioA = if status.maxHealth[1] > 0 then status.health[1] / status.maxHealth[1] else 0
		local ratioB = if status.maxHealth[2] > 0 then status.health[2] / status.maxHealth[2] else 0
		if math.abs(ratioA - ratioB) < 1e-9 then
			endRound(flow, sim, 0, "Draw")
		else
			endRound(flow, sim, if ratioA > ratioB then 1 else 2, "Time")
		end
	end
end

local function poseWinner(flow: Flow, sim: Sim)
	for _, fighter in sim.fighters do
		if
			not fighter.ko
			and not Fighter.isAirborne(fighter)
			and fighter.state ~= "Win"
			and fighter.state ~= "Lose"
			and flow.roundWinner ~= 0
		then
			Fighter.setState(fighter, if fighter.team == flow.roundWinner then "Win" else "Lose")
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
				-- Обе добрали нужное число ничьими — продолжаем до перевеса.
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
