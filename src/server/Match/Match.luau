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

-- Versus — 1 на 1 игроков, Team — эстафета 2 на 2, Cpu — против компьютера.
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
	r: number?, -- номер раунда (события раундов)
	w: { number }?, -- победы в раундах (события раундов)
	fin: boolean?, -- финальный раунд
	ms: { number }?, -- эстафета: активные участники команд
}

-- Участник команды в эстафете 2 на 2.
export type TeamMember = {
	controller: SlotController,
	characterId: string,
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
	teams: { { TeamMember } }?, -- эстафета: слот = команда
	ranked: boolean, -- матч из общей очереди (награда за победу)
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
	-- Эстафета 2 на 2: участники команд; characters и controllers тогда берутся из первых участников.
	teams: { { TeamMember } }?,
	ranked: boolean?,
}

local Match = {}

local nextId = 0

function Match.new(config: MatchConfig): Match
	nextId += 1
	local characters = config.characters
	local controllers = config.controllers
	local rosters: { { string } }? = nil
	local teams = config.teams
	if teams then
		characters, controllers = {}, {}
		local list: { { string } } = {}
		for slot, team in teams do
			assert(#team > 0, `В команде {slot} нет участников`)
			characters[slot] = team[1].characterId
			controllers[slot] = team[1].controller
			local roster: { string } = {}
			for _, member in team do
				table.insert(roster, member.characterId)
			end
			list[slot] = roster
		end
		rosters = list
	end
	local sim = Simulation.new({ characters = characters, hpMultipliers = config.hpMultipliers })
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
		flow = if config.roundsToWin then MatchFlow.new({ roundsToWin = config.roundsToWin, teams = rosters }) else nil,
		presentation = config.presentation or {},
		boss = config.boss,
		teams = teams,
		ranked = config.ranked == true,
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

-- Команда (сторона) игрока: в эстафете — даже если он сейчас ждёт своей очереди.
function Match.teamOf(match: Match, player: Player): number?
	local teams = match.teams
	if teams then
		for slot, team in teams do
			for _, member in team do
				if member.controller.player == player then
					return slot
				end
			end
		end
		return nil
	end
	return Match.slotOf(match, player)
end

-- Номер участника команды для игрока (эстафета).
function Match.memberOf(match: Match, player: Player): number?
	local teams = match.teams
	if teams == nil then
		return nil
	end
	for _, team in teams do
		for index, member in team do
			if member.controller.player == player then
				return index
			end
		end
	end
	return nil
end

-- Эстафета: передать управление слотами активным участникам. Возвращает игроков, получивших управление.
function Match.syncControllers(match: Match): { Player }
	local teams = match.teams
	local flow = match.flow
	local handedOver: { Player } = {}
	if teams == nil or flow == nil then
		return handedOver
	end
	for slot, team in teams do
		local member = MatchFlow.activeMember(flow, slot)
		local entry = if member then team[member] else nil
		if entry and match.controllers[slot] ~= entry.controller then
			match.controllers[slot] = entry.controller
			match.characters[slot] = entry.characterId
			local player = entry.controller.player
			if player then
				table.insert(handedOver, player)
			end
		end
	end
	return handedOver
end

function Match.hasParticipant(match: Match, player: Player): boolean
	return table.find(match.participants, player) ~= nil
end

return Match
