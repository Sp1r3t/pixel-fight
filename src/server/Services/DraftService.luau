--!strict
--[[
	DraftService — подготовка к бою из меню «Мультиплеер» (очередь, комната, против компьютера):

	  1. «Выбери бойца» (Draft.CharacterSeconds): каждый выбирает из своих открытых бойцов и жмёт «Готов».
	     Кто не успел — играет тем, кого выбрал в меню. Все готовы — дальше сразу.
	  2. «Выбери карту» (Draft.MapSeconds): голосование. Премиальную карту может выбрать только тот,
	     кто её купил, — но если она победила, на ней играют все. Ничья — случайная из лидеров,
	     никто не голосовал — случайная бесплатная. Все проголосовали — дальше сразу.
	  3. «Карта: …» (Draft.RevealSeconds) — показать выбор, затем onDone создаёт матч.

	Боты выбирают бойца сразу и не голосуют. Игрок вышел — его место занимает бот; если людей
	не осталось, подготовка отменяется. Клиенту уходит полное состояние (событие «Draft»)
	после каждого изменения. Все запросы проверяются сервером.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local BotNames = require(ReplicatedStorage.Shared.Config.BotNames)
local Arenas = require(ReplicatedStorage.Shared.Config.Arenas)
local CharacterRegistry = require(ReplicatedStorage.Shared.Characters.CharacterRegistry)
local Transport = require(ReplicatedStorage.Shared.Net.Transport)

local RequestRouter = require(script.Parent.Parent.Net.RequestRouter)
local DataService = require(script.Parent.DataService)

export type DraftSlot = {
	slot: number,
	team: number,
	player: Player?, -- nil — бот
	name: string,
	characterId: string,
	ready: boolean,
	vote: string?,
}

export type DraftResult = {
	slots: { DraftSlot },
	arenaId: string,
}

export type DraftConfig = {
	mode: string, -- для экрана: "Versus" | "Team" | "Cpu"
	slots: { DraftSlot },
	onDone: (result: DraftResult) -> (),
	onCancel: ((reason: string) -> ())?,
}

export type Draft = {
	id: number,
	mode: string,
	slots: { DraftSlot },
	phase: string, -- "Character" | "Map" | "Reveal"
	deadline: number, -- os.clock()
	arenaId: string?,
	onDone: (result: DraftResult) -> (),
	onCancel: ((reason: string) -> ())?,
	finished: boolean,
}

local DraftService = {
	Name = "DraftService",
}

local drafts: { [number]: Draft } = {}
local draftOf: { [Player]: Draft } = {}
local nextId = 0
local random = Random.new()

local function replacementName(draft: Draft): string
	local used: { [string]: boolean } = {}
	for _, slot in draft.slots do
		used[string.lower(slot.name)] = true
	end
	return BotNames.pick(random, used)
end

function DraftService.draftOf(player: Player): Draft?
	return draftOf[player]
end

local function slotOf(draft: Draft, player: Player): DraftSlot?
	for _, slot in draft.slots do
		if slot.player == player then
			return slot
		end
	end
	return nil
end

local function humans(draft: Draft): { Player }
	local list: { Player } = {}
	for _, slot in draft.slots do
		local player = slot.player
		if player then
			table.insert(list, player)
		end
	end
	return list
end

local function voteCounts(draft: Draft): { [string]: number }
	local counts: { [string]: number } = {}
	for _, slot in draft.slots do
		local vote = slot.vote
		if vote then
			counts[vote] = (counts[vote] or 0) + 1
		end
	end
	return counts
end

local function payloadFor(draft: Draft, player: Player): { [string]: any }
	local slots = {}
	for _, slot in draft.slots do
		table.insert(slots, {
			slot = slot.slot,
			team = slot.team,
			name = slot.name,
			characterId = slot.characterId,
			ready = slot.ready,
			-- Не раскрываем клиенту тип контроллера: все участники выглядят одинаково.
			bot = false,
			vote = slot.vote,
		})
	end
	local mine = slotOf(draft, player)
	return {
		id = draft.id,
		mode = draft.mode,
		phase = draft.phase,
		seconds = math.max(0, draft.deadline - os.clock()),
		localSlot = if mine then mine.slot else nil,
		slots = slots,
		votes = voteCounts(draft),
		arenaId = draft.arenaId,
	}
end

local function broadcast(draft: Draft)
	for _, player in humans(draft) do
		if player.Parent ~= nil then
			Transport.fireClient("MatchEvent", player, "Draft", payloadFor(draft, player))
		end
	end
end

local function setPhase(draft: Draft, phase: string, seconds: number)
	draft.phase = phase
	draft.deadline = os.clock() + seconds
end

-- Карта по голосам: больше голосов; ничья — случайная из лидеров; нет голосов — случайная бесплатная.
local function chooseArena(draft: Draft): string
	local counts = voteCounts(draft)
	local best = 0
	local leaders: { string } = {}
	for _, arena in Arenas.list do
		local count = counts[arena.id] or 0
		if count > best then
			best = count
			leaders = { arena.id }
		elseif count == best and count > 0 then
			table.insert(leaders, arena.id)
		end
	end
	if #leaders == 0 then
		leaders = table.clone(Arenas.free)
	end
	return leaders[random:NextInteger(1, #leaders)]
end

local function finish(draft: Draft)
	if draft.finished then
		return
	end
	draft.finished = true
	drafts[draft.id] = nil
	for _, player in humans(draft) do
		if draftOf[player] == draft then
			draftOf[player] = nil
		end
	end
	local ok, err = pcall(function(): string?
		draft.onDone({ slots = draft.slots, arenaId = draft.arenaId or Arenas.default })
		return nil
	end)
	if not ok then
		warn(`[DraftService] Ошибка при старте боя: {err}`)
	end
end

local function cancel(draft: Draft, reason: string)
	if draft.finished then
		return
	end
	draft.finished = true
	drafts[draft.id] = nil
	for _, player in humans(draft) do
		if draftOf[player] == draft then
			draftOf[player] = nil
		end
		if player.Parent ~= nil then
			Transport.fireClient("MatchEvent", player, "DraftCancelled", { id = draft.id, reason = reason })
		end
	end
	local onCancel = draft.onCancel
	if onCancel then
		onCancel(reason)
	end
end

local function toMap(draft: Draft)
	for _, slot in draft.slots do
		slot.ready = true
	end
	setPhase(draft, "Map", GameConfig.Draft.MapSeconds)
end

local function toReveal(draft: Draft)
	draft.arenaId = chooseArena(draft)
	setPhase(draft, "Reveal", GameConfig.Draft.RevealSeconds)
end

local function allHumans(draft: Draft, predicate: (slot: DraftSlot) -> boolean): boolean
	for _, slot in draft.slots do
		if slot.player and not predicate(slot) then
			return false
		end
	end
	return true
end

--[[
	Начать подготовку. slots — все бойцы матча (люди и боты) с бойцами по умолчанию.
	Игрок может быть только в одной подготовке: прежняя для него отменяется.
]]
function DraftService.start(config: DraftConfig): Draft
	nextId += 1
	local draft: Draft = {
		id = nextId,
		mode = config.mode,
		slots = config.slots,
		phase = "Character",
		deadline = os.clock() + GameConfig.Draft.CharacterSeconds,
		arenaId = nil,
		onDone = config.onDone,
		onCancel = config.onCancel,
		finished = false,
	}
	for _, slot in draft.slots do
		slot.ready = slot.player == nil
		slot.vote = nil
		local player = slot.player
		if player then
			local previous = draftOf[player]
			if previous and previous ~= draft then
				cancel(previous, "Replaced")
			end
			draftOf[player] = draft
		end
	end
	drafts[draft.id] = draft
	broadcast(draft)
	return draft
end

-- Покинуть подготовку (игрок вышел из игры или отменил): место занимает бот.
function DraftService.leave(player: Player)
	local draft = draftOf[player]
	if draft == nil then
		return
	end
	draftOf[player] = nil
	local slot = slotOf(draft, player)
	if slot then
		slot.player = nil
		slot.name = replacementName(draft)
		slot.ready = true
		slot.vote = nil
	end
	if #humans(draft) == 0 then
		cancel(draft, "Empty")
	else
		broadcast(draft)
	end
end

local function step()
	local now = os.clock()
	for _, draft in table.clone(drafts) do
		if now >= draft.deadline then
			if draft.phase == "Character" then
				toMap(draft)
				broadcast(draft)
			elseif draft.phase == "Map" then
				toReveal(draft)
				broadcast(draft)
			else
				finish(draft)
			end
		end
	end
end

local function readString(payload: unknown, key: string): string?
	if type(payload) ~= "table" then
		return nil
	end
	local value = (payload :: any)[key]
	return if type(value) == "string" then value else nil
end

function DraftService.Init()
	RequestRouter.register("DraftLeave", function(player: Player)
		if draftOf[player] == nil then
			return false, "NotInDraft"
		end
		DraftService.leave(player)
		return true, nil
	end)
	RequestRouter.register("DraftPick", function(player: Player, payload: unknown)
		local draft = draftOf[player]
		local slot = if draft then slotOf(draft, player) else nil
		if draft == nil or slot == nil then
			return false, "NotInDraft"
		end
		if draft.phase ~= "Character" then
			return false, "TooLate"
		end
		local characterId = readString(payload, "characterId")
		if characterId == nil or CharacterRegistry.get(characterId) == nil then
			return false, "BadRequest"
		end
		if not DataService.ownsCharacter(player, characterId) then
			return false, "CharacterNotAvailable"
		end
		slot.characterId = characterId
		broadcast(draft)
		return true, nil
	end)
	RequestRouter.register("DraftReady", function(player: Player)
		local draft = draftOf[player]
		local slot = if draft then slotOf(draft, player) else nil
		if draft == nil or slot == nil then
			return false, "NotInDraft"
		end
		if draft.phase ~= "Character" then
			return false, "TooLate"
		end
		slot.ready = true
		if allHumans(draft, function(other: DraftSlot): boolean
			return other.ready
		end) then
			toMap(draft)
		end
		broadcast(draft)
		return true, nil
	end)
	RequestRouter.register("DraftVote", function(player: Player, payload: unknown)
		local draft = draftOf[player]
		local slot = if draft then slotOf(draft, player) else nil
		if draft == nil or slot == nil then
			return false, "NotInDraft"
		end
		if draft.phase ~= "Map" then
			return false, "TooLate"
		end
		local arenaId = readString(payload, "arenaId")
		if arenaId == nil or Arenas.byId[arenaId] == nil then
			return false, "BadRequest"
		end
		if not DataService.ownsArena(player, arenaId) then
			return false, "ArenaLocked"
		end
		slot.vote = arenaId
		if allHumans(draft, function(other: DraftSlot): boolean
			return other.vote ~= nil
		end) then
			toReveal(draft)
		end
		broadcast(draft)
		return true, nil
	end)
end

function DraftService.Start()
	Players.PlayerRemoving:Connect(DraftService.leave)
	RunService.Heartbeat:Connect(step)
end

return DraftService
