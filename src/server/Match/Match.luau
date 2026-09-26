--!strict
--[[
	Match — один бой на сервере: симуляция + кто управляет каждым бойцом + кому слать снапшоты.
	На одном сервере одновременно может идти много матчей (например, бои с боссами разных игроков).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Simulation = require(ReplicatedStorage.Shared.Combat.Simulation)
local InputBits = require(ReplicatedStorage.Shared.Combat.InputBits)

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
	data: { [string]: any }, -- данные режима (боссы, раунды и т.п.)
}

export type MatchConfig = {
	mode: MatchMode,
	arenaId: string,
	characters: { string },
	controllers: { SlotController },
	participants: { Player },
	hpMultipliers: { number }?,
}

local Match = {}

local nextId = 0

function Match.new(config: MatchConfig): Match
	nextId += 1
	return {
		id = nextId,
		mode = config.mode,
		arenaId = config.arenaId,
		sim = Simulation.new({ characters = config.characters, hpMultipliers = config.hpMultipliers }),
		controllers = config.controllers,
		characters = table.clone(config.characters),
		participants = table.clone(config.participants),
		accumulator = 0,
		framesSinceSnapshot = 0,
		pendingEvents = {},
		ended = false,
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
