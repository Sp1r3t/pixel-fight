--!strict
--[[
	FightController — клиентская сторона боя.

	  • MatchStart → строит арену и бойцов, включает камеру боя и отправку ввода, открывает экран боя;
	  • Snapshot   → кладёт снапшоты в буфер интерполяции;
	  • Events     → проигрывает эффекты в тот кадр, когда их «видно» на экране;
	  • каждый кадр → интерполирует состояние, обновляет бойцов, камеру и данные HUD;
	  • MatchEnd   → убирает всё и возвращает в меню.
	Клиент ничего не решает в бою — только показывает то, что прислал сервер.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CharacterRegistry = require(ReplicatedStorage.Shared.Characters.CharacterRegistry)
local Snapshot = require(ReplicatedStorage.Shared.Combat.Snapshot)
local Transport = require(ReplicatedStorage.Shared.Net.Transport)

local Arena = require(script.Parent.Parent.Fight.Arena)
local FighterView = require(script.Parent.Parent.Fight.FighterView)
local SnapshotBuffer = require(script.Parent.Parent.Fight.SnapshotBuffer)
local AppState = require(script.Parent.Parent.UI.AppState)
local CameraController = require(script.Parent.CameraController)
local EffectsController = require(script.Parent.EffectsController)
local InputController = require(script.Parent.InputController)
local UIController = require(script.Parent.UIController)

type NetEvent = { k: string, s: number, f: number, x: number?, y: number?, v: number? }

local FightController = {
	Name = "FightController",
}

local matchId: number? = nil
local arena: Arena.Arena? = nil
local views: { [number]: FighterView.FighterView } = {}
local buffer = SnapshotBuffer.new()
local pendingEvents: { NetEvent } = {}
local lastSample: SnapshotBuffer.Sample? = nil

local function cleanup()
	for _, view in views do
		view.destroy()
	end
	table.clear(views)
	if arena then
		arena.destroy()
		arena = nil
	end
	buffer.reset()
	table.clear(pendingEvents)
	lastSample = nil
	EffectsController.clear()
	InputController.setActive(false)
	CameraController.exitFight()
	matchId = nil
end

local function readSetup(payload: any): AppState.BattleInfo?
	if type(payload) ~= "table" or type(payload.matchId) ~= "number" or type(payload.fighters) ~= "table" then
		return nil
	end
	local fighters: { AppState.BattleFighter } = {}
	for _, fighter in payload.fighters do
		if
			type(fighter) == "table"
			and type(fighter.characterId) == "string"
			and CharacterRegistry.get(fighter.characterId)
		then
			table.insert(fighters, {
				slot = tonumber(fighter.slot) or #fighters + 1,
				characterId = fighter.characterId,
				playerName = if type(fighter.playerName) == "string" then fighter.playerName else nil,
				maxHealth = tonumber(fighter.maxHealth) or 1000,
			})
		end
	end
	if #fighters ~= 2 then
		return nil
	end
	return {
		matchId = payload.matchId,
		mode = if type(payload.mode) == "string" then payload.mode else "Training",
		arenaId = if type(payload.arenaId) == "string" then payload.arenaId else "dojo",
		localSlot = if type(payload.localSlot) == "number" then payload.localSlot else nil,
		fighters = fighters,
	}
end

local function onMatchStart(payload: any)
	local info = readSetup(payload)
	if info == nil then
		warn("[FightController] Некорректные данные начала матча")
		return
	end
	cleanup()
	matchId = info.matchId
	local built = Arena.build(info.arenaId, Workspace)
	arena = built
	for _, fighter in info.fighters do
		local def = CharacterRegistry.get(fighter.characterId)
		if def then
			views[fighter.slot] = FighterView.new(built.folder, def, fighter.slot)
		end
	end
	CameraController.enterFight()
	InputController.setActive(info.localSlot ~= nil)
	local state = UIController.getState()
	if state then
		AppState.enterBattle(state, info)
	end
end

local function onMatchEnd(payload: any)
	if type(payload) == "table" and payload.matchId ~= matchId then
		return -- конец уже неактуального матча
	end
	cleanup()
	local state = UIController.getState()
	if state then
		AppState.exitBattle(state)
		if type(payload) == "table" and payload.reason == "PlayerLeft" then
			AppState.notify(state, "Соперник покинул бой")
		end
	end
end

local function onEvents(events: any)
	if matchId == nil or type(events) ~= "table" then
		return
	end
	for _, event in events do
		if type(event) == "table" and type(event.k) == "string" and type(event.f) == "number" then
			table.insert(pendingEvents, event)
		end
	end
end

local function playEvent(event: NetEvent)
	local x, y = event.x or 0, event.y or 0
	if event.k == "Jump" or event.k == "Land" then
		EffectsController.dust(x, y, nil)
	elseif event.k == "Dash" or event.k == "Backdash" then
		local facing = if lastSample and lastSample.fighters[event.s] then lastSample.fighters[event.s].facing else 1
		-- Пыль летит назад от направления рывка.
		EffectsController.dust(x, y, if event.k == "Dash" then -facing else facing)
	end
end

local function onSnapshot(data: any)
	if matchId == nil or typeof(data) ~= "buffer" then
		return
	end
	local decoded = Snapshot.decode(data)
	if decoded then
		buffer.push(decoded, os.clock())
	end
end

local function onRenderStep(dt: number)
	if matchId == nil then
		return
	end
	local sample = buffer.sample(os.clock())
	if sample == nil then
		return
	end
	lastSample = sample

	local minX, maxX, topY = math.huge, -math.huge, 0
	for slot, fighter in sample.fighters do
		local view = views[slot]
		if view then
			view.update(fighter, dt)
		end
		minX = math.min(minX, fighter.x)
		maxX = math.max(maxX, fighter.x)
		topY = math.max(topY, fighter.y + 5.6)
	end
	if minX <= maxX then
		CameraController.setFocus(minX, maxX, topY)
	end

	-- События показываем тогда, когда до них «дошла» интерполированная картинка.
	local index = 1
	while index <= #pendingEvents do
		local event = pendingEvents[index]
		if event.f <= sample.frame + 0.5 then
			table.remove(pendingEvents, index)
			playEvent(event)
		else
			index += 1
		end
	end
end

-- Текущий кадр отображения (для тестов и HUD).
function FightController.getSample(): SnapshotBuffer.Sample?
	return lastSample
end

function FightController.getViews(): { [number]: FighterView.FighterView }
	return views
end

function FightController.Init()
	Transport.onClientEvent("Snapshot", onSnapshot)
	Transport.onClientEvent("MatchEvent", function(kind: any, payload: any)
		if kind == "MatchStart" then
			onMatchStart(payload)
		elseif kind == "MatchEnd" then
			onMatchEnd(payload)
		elseif kind == "Events" then
			onEvents(payload)
		end
	end)
end

function FightController.Start()
	RunService:BindToRenderStep("PixelFightRender", Enum.RenderPriority.Camera.Value, onRenderStep)
end

return FightController
