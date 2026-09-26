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

export type MatchMode = "Training" | "Boss" | "Versus" | "Team" | "Private"

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
	r: number?, -- номер раунда (события раундов)
	w: { number }?, -- победы в раундах (события раундов)
	fin: boolean?, -- финальный раунд
}

-- Как показывать бойца клиентам (боссы выглядят и называются по-своему).
export type Presentation = {
	displayName: string?,
	palette: Types.Palette?,
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
	flow: MatchFlow.Flow?, -- раунды (nil — без раундов, например тренировка)
	presentation: { [number]: Presentation }, -- по слотам
	boss: BossInfo?,
	-- Вызывается один раз, когда матч закончился (любым способом).
	onFinished: ((match: Match, result: MatchResult) -> ())?,
	data: { [string]: any }, -- данные режима (боссы, эстафета и т.п.)
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
	presentation: { [number]: Presentation }?,
	boss: BossInfo?,
}

local Match = {}

local nextId = 0

function Match.new(config: MatchConfig): Match
	nextId += 1
	local sim = Simulation.new({ characters = config.characters, hpMultipliers = config.hpMultipliers })
	for slot, controller in config.controllers do
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
		controllers = config.controllers,
		characters = table.clone(config.characters),
		participants = table.clone(config.participants),
		accumulator = 0,
		framesSinceSnapshot = 0,
		pendingEvents = {},
		ended = false,
		flow = if config.roundsToWin then MatchFlow.new({ roundsToWin = config.roundsToWin }) else nil,
		presentation = config.presentation or {},
		boss = config.boss,
		onFinished = config.onFinished,
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

function Match.hasParticipant(match: Match, player: Player): boolean
	return table.find(match.participants, player) ~= nil
end

return Match
