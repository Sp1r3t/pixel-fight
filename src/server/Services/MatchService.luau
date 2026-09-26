--!strict
--[[
	MatchService — жизненный цикл матчей на сервере.

	  • фиксированный шаг симуляции 60 Гц (накопитель времени по Heartbeat);
	  • ввод бойцов: игроки — через InputService, ИИ/манекен — локально на сервере;
	  • рассылка снапшотов (двоичный buffer) и событий боя участникам матча;
	  • запросы клиентов: StartTraining, LeaveMatch.
	Раунды, таймер и победы добавляются на этапе 4, боссы — на этапе 6, PvP — на этапе 7.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Arenas = require(ReplicatedStorage.Shared.Config.Arenas)
local CharacterRegistry = require(ReplicatedStorage.Shared.Characters.CharacterRegistry)
local Simulation = require(ReplicatedStorage.Shared.Combat.Simulation)
local Snapshot = require(ReplicatedStorage.Shared.Combat.Snapshot)
local InputBits = require(ReplicatedStorage.Shared.Combat.InputBits)
local Transport = require(ReplicatedStorage.Shared.Net.Transport)

local Match = require(script.Parent.Parent.Match.Match)
local TrainingRules = require(script.Parent.Parent.Match.TrainingRules)
local RequestRouter = require(script.Parent.Parent.Net.RequestRouter)
local InputService = require(script.Parent.InputService)
local DataService = require(script.Parent.DataService)

type Match = Match.Match

local STEP = 1 / GameConfig.TickRate
local MAX_STEPS_PER_HEARTBEAT = 5
local SNAPSHOT_INTERVAL = math.max(1, math.floor(GameConfig.TickRate / GameConfig.Net.SnapshotRate + 0.5))

local MatchService = {
	Name = "MatchService",
}

local matches: { [number]: Match } = {}
local matchOfPlayer: { [Player]: Match } = {}

-- Колбэки режимов: вызываются после каждого шага симуляции (раунды, боссы и т.д.).
local stepHooks: { (match: Match) -> () } = {}

function MatchService.addStepHook(hook: (match: Match) -> ())
	table.insert(stepHooks, hook)
end

function MatchService.getMatchOf(player: Player): Match?
	return matchOfPlayer[player]
end

function MatchService.getMatches(): { [number]: Match }
	return matches
end

local function sendSetup(match: Match, player: Player)
	local fighters = {}
	for slot, characterId in match.characters do
		local controller = match.controllers[slot]
		table.insert(fighters, {
			slot = slot,
			characterId = characterId,
			playerName = if controller.player then controller.player.DisplayName else nil,
			maxHealth = match.sim.fighters[slot].maxHealth,
		})
	end
	Transport.fireClient("MatchEvent", player, "MatchStart", {
		matchId = match.id,
		mode = match.mode,
		arenaId = match.arenaId,
		localSlot = Match.slotOf(match, player),
		fighters = fighters,
		tickRate = GameConfig.TickRate,
	})
end

function MatchService.create(config: Match.MatchConfig): Match
	local match = Match.new(config)
	matches[match.id] = match
	for _, player in match.participants do
		local previous = matchOfPlayer[player]
		if previous and previous ~= match then
			MatchService.finish(previous, "Replaced")
		end
		matchOfPlayer[player] = match
		InputService.clearPending(player)
		sendSetup(match, player)
	end
	return match
end

function MatchService.finish(match: Match, reason: string, result: any?)
	if match.ended then
		return
	end
	match.ended = true
	matches[match.id] = nil
	for _, player in match.participants do
		if matchOfPlayer[player] == match then
			matchOfPlayer[player] = nil
		end
		if player.Parent ~= nil then
			Transport.fireClient(
				"MatchEvent",
				player,
				"MatchEnd",
				{ matchId = match.id, reason = reason, result = result }
			)
		end
	end
end

-- Отправить событие боя всем участникам вместе с ближайшим снапшотом.
function MatchService.queueEvent(match: Match, event: Match.NetEvent)
	table.insert(match.pendingEvents, event)
end

local function gatherInputs(match: Match, now: number): { InputBits.FrameInput }
	local inputs = {}
	for slot, controller in match.controllers do
		if controller.kind == "Player" and controller.player then
			inputs[slot] = InputService.consume(controller.player, now)
		elseif controller.kind == "AI" and controller.think then
			inputs[slot] = controller.think(match.sim, slot)
		else
			inputs[slot] = InputBits.empty()
		end
	end
	return inputs
end

local function broadcast(match: Match)
	local fighters = {}
	for _, fighter in match.sim.fighters do
		table.insert(fighters, Snapshot.fromFighter(fighter))
	end
	local encoded = Snapshot.encode({
		frame = match.sim.frame,
		phase = match.data.phase or 0,
		timer = match.data.timer or 0,
		fighters = fighters,
		projectiles = {},
	})
	local events = if #match.pendingEvents > 0 then match.pendingEvents else nil
	match.pendingEvents = {}
	for _, player in match.participants do
		Transport.fireClient("Snapshot", player, encoded)
		if events then
			Transport.fireClient("MatchEvent", player, "Events", events)
		end
	end
end

function MatchService.stepMatch(match: Match, now: number)
	Simulation.step(match.sim, gatherInputs(match, now))
	for _, event in match.sim.events do
		table.insert(match.pendingEvents, {
			k = event.kind,
			s = event.slot,
			f = match.sim.frame,
			x = event.x,
			y = event.y,
			v = event.value,
			a = event.attacker,
			t = event.tag,
		})
	end
	for _, hook in stepHooks do
		if match.ended then
			break
		end
		hook(match)
	end
	if match.ended then
		return
	end
	match.framesSinceSnapshot += 1
	if match.framesSinceSnapshot >= SNAPSHOT_INTERVAL then
		match.framesSinceSnapshot = 0
		broadcast(match)
	end
end

local function onHeartbeat(dt: number)
	local now = os.clock()
	for _, match in matches do
		match.accumulator = math.min(match.accumulator + dt, STEP * MAX_STEPS_PER_HEARTBEAT)
		while match.accumulator >= STEP - 1e-9 and not match.ended do
			match.accumulator -= STEP
			MatchService.stepMatch(match, now)
		end
	end
end

----------------------------------------------------------------------------------------------
-- Запросы клиентов
----------------------------------------------------------------------------------------------

local function readCharacterId(player: Player, payload: unknown): string?
	if type(payload) ~= "table" then
		return nil
	end
	local characterId = (payload :: any).characterId
	if type(characterId) ~= "string" or CharacterRegistry.get(characterId) == nil then
		return nil
	end
	if not DataService.ownsCharacter(player, characterId) then
		return nil
	end
	return characterId
end

-- Тренировка: игрок против неподвижного манекена.
function MatchService.startTraining(player: Player, characterId: string): Match
	local dummyId = if characterId == "rook" then "brakk" else "rook"
	return MatchService.create({
		mode = "Training",
		arenaId = Arenas.default,
		characters = { characterId, dummyId },
		controllers = {
			{ kind = "Player", player = player },
			{ kind = "Dummy" },
		},
		participants = { player },
	})
end

function MatchService.Init()
	MatchService.addStepHook(TrainingRules.step)

	RequestRouter.register("StartTraining", function(player: Player, payload: unknown)
		local characterId = readCharacterId(player, payload)
		if characterId == nil then
			return false, "CharacterNotAvailable"
		end
		local match = MatchService.startTraining(player, characterId)
		return true, match.id
	end)

	RequestRouter.register("LeaveMatch", function(player: Player)
		local match = matchOfPlayer[player]
		if match == nil then
			return false, "NotInMatch"
		end
		MatchService.finish(match, "Left")
		return true, nil
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		local match = matchOfPlayer[player]
		if match then
			MatchService.finish(match, "PlayerLeft")
		end
	end)
end

function MatchService.Start()
	RunService.Heartbeat:Connect(onHeartbeat)
end

return MatchService
