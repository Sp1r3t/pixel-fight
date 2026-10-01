--!strict
--[[
	Match — один бой на сервере: симуляция + кто управляет каждым бойцом + кому слать снапшоты.
	На одном сервере одновременно может идти много матчей (например, бои с боссами разных игроков).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Simulation = require(ReplicatedStorage.Shared.Combat.Simulation)
local MatchFlow = require(ReplicatedStorage.Shared.Combat.MatchFlow)
local InputBits = require(ReplicatedStorage.Shared.Combat.InputBits)
local Types = require(ReplicatedStorage.Shared.Types)

-- Versus — 1 на 1 игроков, Team — 2 на 2 (четыре бойца на двух этажах), Cpu — против компьютера.
export type MatchMode = "Training" | "Boss" | "Versus" | "Team" | "Cpu"

export type ControllerKind = "Player" | "Dummy" | "AI"

export type SlotController = {
	kind: ControllerKind,
	player: Player?,
	-- Для ИИ: функция, выдающая ввод на кадр (этап 6).
	think: ((sim: Simulation.Sim, slot: number) -> InputBits.FrameInput)?,
}

export type NetEvent = {
	k: string, -- тип события
	s: number, -- слот бойца
	f: number, -- кадр симуляции
	x: number?,
	y: number?,
	v: number?,
	a: number?, -- слот атакующего
	t: string?, -- уточнение ("Counter", сценарий супера, ...)
	d: number?, -- второй участник (ролик супера: слот того, кого бьют)
	r: number?, -- номер раунда (события раундов)
	w: { number }?, -- победы в раундах (события раундов)
	fin: boolean?, -- финальный раунд
}

-- Как показывать бойца клиентам (боссы выглядят и называются по-своему).
export type Presentation = {
	displayName: string?,
	palette: Types.Palette?,
	visualStyle: string?,
}

-- Кого игрок встречает в режиме боссов (для экрана боя).
export type BossInfo = {
	id: string,
	order: number,
	name: string,
	title: string,
}

export type MatchResult = {
	winner: number, -- слот победителя (0 — нет)
	wins: { number },
	reason: string,
}

export type Match = {
	id: number,
	mode: MatchMode,
	arenaId: string,
	sim: Simulation.Sim,
	controllers: { SlotController },
	characters: { string },
	participants: { Player }, -- кто получает снапшоты (игроки и зрители)
	accumulator: number,
	framesSinceSnapshot: number,
	pendingEvents: { NetEvent },
	ended: boolean,
	paused: boolean, -- серверная пауза одиночного боя во время окна покупки
	flow: MatchFlow.Flow?, -- раунды (nil — без раундов, например тренировка)
	presentation: { [number]: Presentation }, -- по слотам
	boss: BossInfo?,
	stage: string, -- сцена: "Duel" или "TwoFloors"
	ranked: boolean, -- матч из общей очереди (награда за победу)
	-- Вызывается один раз, когда матч закончился (любым способом).
	onFinished: ((match: Match, result: MatchResult) -> ())?,
	beforeFinish: ((match: Match, result: MatchResult) -> boolean)?, -- false откладывает завершение
	data: { [string]: any }, -- данные режима (боссы, боты в матче и т.п.)
}

export type MatchConfig = {
	mode: MatchMode,
	arenaId: string,
	characters: { string },
	controllers: { SlotController },
	participants: { Player },
	hpMultipliers: { number }?,
	roundsToWin: number?, -- nil — без раундов
	onFinished: ((match: Match, result: MatchResult) -> ())?,
	beforeFinish: ((match: Match, result: MatchResult) -> boolean)?,
	presentation: { [number]: Presentation }?,
	boss: BossInfo?,
	teams: { number }?, -- команда каждого слота (по умолчанию слоты 1, 3 — команда 1; 2, 4 — команда 2)
	stage: string?, -- "Duel" (по умолчанию) или "TwoFloors"
	ranked: boolean?,
}

local Match = {}

local nextId = 0

function Match.new(config: MatchConfig): Match
	nextId += 1
	local characters = config.characters
	local controllers = config.controllers
	local stage = config.stage or "Duel"
	local sim = Simulation.new({
		characters = characters,
		teams = config.teams,
		hpMultipliers = config.hpMultipliers,
		stage = stage,
	})
	-- Apply concept body classes before the initial health totals are announced.
	local CombatProfiles = require(ReplicatedStorage.Shared.Config.CombatProfiles)
	for slot, presentation in config.presentation or {} do
		local fighter = sim.fighters[slot]
		local profile = if presentation.visualStyle then CombatProfiles.get(presentation.visualStyle) else nil
		if fighter and profile then
			fighter.combatProfile = profile.id
			fighter.stats = table.clone(fighter.stats)
			local healthScale = if profile.role == "tank" then 1.2 elseif profile.role == "agile" then 0.9 else 1
			local speedScale = if profile.role == "tank" then 0.8 elseif profile.role == "agile" then 1.18 else 1
			fighter.stats.maxHealth = math.floor(fighter.stats.maxHealth * healthScale + 0.5)
			fighter.stats.walkSpeed *= speedScale
			fighter.maxHealth = math.floor(fighter.stats.maxHealth * fighter.hpMultiplier + 0.5)
			fighter.health = fighter.maxHealth
		end
	end
	for slot, controller in controllers do
		-- ИИ делает рывки кнопкой: двойное нажатие направления ему не нужно.
		if controller.kind ~= "Player" and sim.fighters[slot] then
			sim.fighters[slot].tapDash = false
		end
	end
	return {
		id = nextId,
		mode = config.mode,
		arenaId = config.arenaId,
		sim = sim,
		controllers = controllers,
		characters = table.clone(characters),
		participants = table.clone(config.participants),
		accumulator = 0,
		framesSinceSnapshot = 0,
		pendingEvents = {},
		ended = false,
		paused = false,
		flow = if config.roundsToWin then MatchFlow.new({ roundsToWin = config.roundsToWin }) else nil,
		presentation = config.presentation or {},
		boss = config.boss,
		stage = stage,
		ranked = config.ranked == true,
		onFinished = config.onFinished,
		beforeFinish = config.beforeFinish,
		data = {},
	}
end

-- Слот, которым управляет игрок (или nil, если игрок только зритель).
function Match.slotOf(match: Match, player: Player): number?
	for slot, controller in match.controllers do
		if controller.kind == "Player" and controller.player == player then
			return slot
		end
	end
	return nil
end

-- Команда игрока в матче (nil — игрок только зритель).
function Match.teamOf(match: Match, player: Player): number?
	local slot = Match.slotOf(match, player)
	if slot == nil then
		return nil
	end
	local fighter = match.sim.fighters[slot]
	return if fighter then fighter.team else nil
end

function Match.hasParticipant(match: Match, player: Player): boolean
	return table.find(match.participants, player) ~= nil
end

return Match
