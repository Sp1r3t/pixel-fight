--!strict
--[[
	MatchmakingService — мультиплеер.

	Режимы:
	  • Versus — 1 на 1 до 2 побед; Team — 2 на 2 до 2 побед: четыре бойца на сцене с двумя этажами
	    (нижние слоты 1–2, верхние 3–4; команды: 1-й и 3-й против 2-го и 4-го);
	  • Cpu — бой против компьютера выбранного уровня (ИИ боссов), 1 на 1 или 2 на 2 с ботами.
	Если соперники не нашлись за Matchmaking.BotFillSeconds, пустые места занимают боты.

	Подбор соперников:
	  1. очередь этого сервера: как только набралось нужное число игроков — матч начинается сразу;
	  2. межсерверная очередь (MemoryStoreService, модуль CrossServer): если на сервере соперников нет,
	     игрок ждёт в общей очереди; собранный матч получает зарезервированный сервер
	     (TeleportService:ReserveServer), и игроки телепортируются туда с данными матча;
	  3. сервер матча (зарезервированный) ждёт всех игроков из состава, проводит матч и возвращает
	     всех в лобби. Не пришли за ArrivalSeconds — пришедшие возвращаются в лобби.

	Приватные матчи: хозяин создаёт комнату и получает код; друг вводит код. Друг на том же сервере
	входит сразу, на другом — телепортируется на сервер хозяина (код ищется в MemoryStore).

	Межсерверная часть включается только в опубликованной игре (не в Studio): в Studio
	MemoryStore/Teleport недоступны или ограничены, и работает подбор внутри сервера.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Arenas = require(ReplicatedStorage.Shared.Config.Arenas)
local CharacterRegistry = require(ReplicatedStorage.Shared.Characters.CharacterRegistry)
local BossRegistry = require(ReplicatedStorage.Shared.Characters.BossRegistry)
local Transport = require(ReplicatedStorage.Shared.Net.Transport)

local BossAI = require(script.Parent.Parent.AI.BossAI)
local Match = require(script.Parent.Parent.Match.Match)
local RequestRouter = require(script.Parent.Parent.Net.RequestRouter)
local CrossServer = require(script.Parent.Parent.Matchmaking.CrossServer)
local Protocol = require(script.Parent.Parent.Matchmaking.Protocol)
local MatchService = require(script.Parent.MatchService)
local DataService = require(script.Parent.DataService)

type Mode = Protocol.Mode

type Entry = {
	player: Player,
	characterId: string,
	mode: Mode,
	joinedAt: number, -- os.time(): порядок в межсерверной очереди
	refreshedAt: number, -- os.clock() последнего продления записи в MemoryStore
	queuedAt: number, -- os.clock() входа в очередь (для ботов)
}

type Room = {
	code: string,
	mode: Mode,
	host: Player,
	members: { Entry },
	createdAt: number,
}

local MatchmakingService = {
	Name = "MatchmakingService",
}

-- Уровни «против компьютера» на экране выбора режима (номер босса по кривой сложности).
MatchmakingService.CPU_LEVELS = table.freeze({ 3, 8, 13, 18 })

local queues: { [string]: { Entry } } = { Versus = {}, Team = {} }
local queuedOf: { [Player]: Entry } = {}
local rooms: { [string]: Room } = {}
local roomOf: { [Player]: Room } = {}
local pendingRoomJoin: { [Player]: Protocol.RoomJoin } = {}
local random = Random.new()

local cross: CrossServer.Cross? = nil
local polling = false
local pollTimer = 0

-- Сервер матча (зарезервированный): ожидаемый состав и кто уже пришёл.
local isMatchServer = false
local expected: CrossServer.Ticket? = nil
local arrived: { [number]: Player } = {}
local arrivalDeadline = 0
local reservedStarted = false

----------------------------------------------------------------------------------------------
-- Статус для клиента
----------------------------------------------------------------------------------------------

local function send(player: Player, payload: { [string]: any })
	if player.Parent ~= nil then
		Transport.fireClient("MatchEvent", player, "Queue", payload)
	end
end

local function roomPayload(room: Room, player: Player): { [string]: any }
	local members = {}
	for _, member in room.members do
		table.insert(members, { name = member.player.DisplayName, characterId = member.characterId })
	end
	return {
		status = "Room",
		code = room.code,
		mode = room.mode,
		host = room.host == player,
		members = members,
		capacity = Protocol.groupSize(room.mode),
	}
end

local function broadcastRoom(room: Room)
	for _, member in room.members do
		send(member.player, roomPayload(room, member.player))
	end
end

----------------------------------------------------------------------------------------------
-- Очередь и комнаты
----------------------------------------------------------------------------------------------

local function removeFromQueue(player: Player, notifyIdle: boolean)
	local entry = queuedOf[player]
	if entry == nil then
		return
	end
	queuedOf[player] = nil
	local queue = queues[entry.mode]
	local index = table.find(queue, entry)
	if index then
		table.remove(queue, index)
	end
	local active = cross
	if active then
		task.spawn(CrossServer.leave, active, entry.mode, player.UserId)
	end
	if notifyIdle then
		send(player, { status = "Idle" })
	end
end

local function closeRoom(room: Room, reason: string?)
	rooms[room.code] = nil
	for _, member in room.members do
		if roomOf[member.player] == room then
			roomOf[member.player] = nil
		end
		if reason then
			send(member.player, { status = "Idle", reason = reason })
		end
	end
	local active = cross
	if active then
		task.spawn(CrossServer.removeRoom, active, room.code)
	end
end

local function leaveRoom(player: Player, notifyIdle: boolean)
	local room = roomOf[player]
	if room == nil then
		return
	end
	roomOf[player] = nil
	for index, member in room.members do
		if member.player == player then
			table.remove(room.members, index)
			break
		end
	end
	if notifyIdle then
		send(player, { status = "Idle" })
	end
	if room.host == player or #room.members == 0 then
		closeRoom(room, "RoomClosed")
	else
		broadcastRoom(room)
	end
end

-- Игрок занят: в бою, в очереди или в комнате.
function MatchmakingService.isQueued(player: Player): boolean
	return queuedOf[player] ~= nil
end

function MatchmakingService.getRoom(player: Player): Room?
	return roomOf[player]
end

----------------------------------------------------------------------------------------------
-- Запуск матчей
----------------------------------------------------------------------------------------------

local function randomArena(): string
	local list = Arenas.list
	return list[random:NextInteger(1, #list)].id
end

local function returnToLobby(players: { Player })
	local present: { Player } = {}
	for _, player in players do
		if player.Parent ~= nil then
			table.insert(present, player)
		end
	end
	if #present == 0 then
		return
	end
	local ok, err = pcall(function()
		local TeleportService = game:GetService("TeleportService")
		TeleportService:TeleportAsync(game.PlaceId, present)
	end)
	if not ok then
		warn(`[Matchmaking] Не удалось вернуть игроков в лобби: {err}`)
	end
end

local function onPvpFinished(match: Match.Match, result: Match.MatchResult)
	local reward = if match.ranked
		then GameConfig.Matchmaking.WinReward
		elseif (match.data.bots or 0) > 0 and not match.data.private then GameConfig.Matchmaking.BotWinReward
		else 0
	if reward > 0 and result.reason == "Finished" and result.winner ~= 0 then
		for _, player in match.participants do
			if Match.teamOf(match, player) == result.winner and player.Parent ~= nil then
				DataService.addCoins(player, reward)
				Transport.fireClient("MatchEvent", player, "Reward", { coins = reward })
			end
		end
	end
	if isMatchServer then
		-- Сервер матча одноразовый: после матча все возвращаются в лобби.
		local players = table.clone(match.participants)
		task.delay(4, returnToLobby, players)
	end
end

local function randomCharacter(): string
	local roster = CharacterRegistry.list()
	return roster[random:NextInteger(1, #roster)].id
end

--[[
	Начать матч. entries — игроки в порядке подбора: слот = номер в списке; нечётные слоты — команда 1,
	чётные — команда 2 (в 2 на 2 слоты 1–2 начинают внизу, 3–4 — на втором этаже).
	fillBots — занять свободные слоты ботами. Награда за победу — только в матчах из очереди.
]]
function MatchmakingService.startMatch(
	mode: Mode,
	entries: { Entry },
	ranked: boolean,
	fillBots: boolean?,
	private: boolean?
): Match.Match
	local size = Protocol.groupSize(mode) :: number
	local participants: { Player } = {}
	local characters: { string } = {}
	local controllers: { Match.SlotController } = {}
	local presentation: { [number]: Match.Presentation } = {}
	for slot, entry in entries do
		table.insert(participants, entry.player)
		removeFromQueue(entry.player, false)
		send(entry.player, { status = "Found" })
		characters[slot] = entry.characterId
		controllers[slot] = { kind = "Player", player = entry.player }
	end
	local bots = 0
	if fillBots then
		for slot = #entries + 1, size do
			bots += 1
			local characterId = randomCharacter()
			local def = CharacterRegistry.get(characterId)
			characters[slot] = characterId
			controllers[slot] = {
				kind = "AI",
				think = BossAI.controller(
					BossRegistry.profileForLevel(GameConfig.Matchmaking.BotLevel),
					random:NextInteger(1, 2 ^ 30)
				),
			}
			presentation[slot] = { displayName = `{if def then def.displayName else characterId} (BOT)` }
		end
	end
	assert(#characters == size, "Не хватает бойцов для матча")
	local match = MatchService.create({
		mode = mode,
		arenaId = randomArena(),
		characters = characters,
		controllers = controllers,
		participants = participants,
		roundsToWin = GameConfig.RoundsToWin.Versus,
		ranked = ranked and bots == 0,
		stage = if mode == "Team" then "TwoFloors" else "Duel",
		presentation = presentation,
		onFinished = onPvpFinished,
	})
	match.data.bots = bots
	match.data.private = private == true
	return match
end

-- Бой против компьютера: ИИ уровня level. Team — 2 на 2: игрок с ботом-напарником против двух ботов.
function MatchmakingService.startCpu(
	player: Player,
	characterId: string,
	level: number,
	seed: number?,
	mode: Mode?
): Match.Match
	leaveRoom(player, false)
	removeFromQueue(player, false)
	local size = if mode == "Team" then 4 else 2
	local characters: { string } = { characterId }
	local controllers: { Match.SlotController } = { { kind = "Player", player = player } }
	local presentation: { [number]: Match.Presentation } = {}
	local baseSeed = seed or random:NextInteger(1, 2 ^ 30)
	for slot = 2, size do
		local opponentId = randomCharacter()
		local def = CharacterRegistry.get(opponentId)
		characters[slot] = opponentId
		controllers[slot] =
			{ kind = "AI", think = BossAI.controller(BossRegistry.profileForLevel(level), baseSeed + slot) }
		presentation[slot] = { displayName = `{if def then def.displayName else opponentId} (CPU)` }
	end
	return MatchService.create({
		mode = "Cpu",
		arenaId = randomArena(),
		characters = characters,
		controllers = controllers,
		participants = { player },
		roundsToWin = GameConfig.RoundsToWin.Versus,
		stage = if mode == "Team" then "TwoFloors" else "Duel",
		presentation = presentation,
	})
end

-- Собрать матчи из очереди этого сервера.
local function tryLocal(mode: Mode)
	local size = Protocol.groupSize(mode) :: number
	local queue = queues[mode]
	-- Игроки, которые тем временем ушли в другой бой, из очереди выбывают.
	for index = #queue, 1, -1 do
		local entry = queue[index]
		if entry.player.Parent == nil or MatchService.getMatchOf(entry.player) ~= nil then
			removeFromQueue(entry.player, true)
		end
	end
	while #queue >= size do
		local group = table.move(queue, 1, size, 1, {})
		MatchmakingService.startMatch(mode, group, true)
	end
end

----------------------------------------------------------------------------------------------
-- Межсерверная часть
----------------------------------------------------------------------------------------------

local function teleportToMatch(player: Player, ticket: CrossServer.Ticket)
	send(player, { status = "Teleporting" })
	local ok, err = pcall(function()
		local TeleportService = game:GetService("TeleportService")
		local options = Instance.new("TeleportOptions")
		options.ReservedServerAccessCode = ticket.accessCode
		options:SetTeleportData(Protocol.encodeMatch(ticket))
		TeleportService:TeleportAsync(game.PlaceId, { player }, options)
	end)
	if not ok then
		warn(`[Matchmaking] Телепорт на сервер матча не удался: {err}`)
		send(player, { status = "Idle", reason = "TeleportFailed" })
	end
end

-- Один проход межсерверного подбора (вызывается раз в PollSeconds).
function MatchmakingService.pollCrossServer()
	local active = cross
	if active == nil or polling then
		return
	end
	polling = true
	local ok, err = pcall(function()
		for mode, queue in queues do
			if #queue > 0 then
				local now = os.clock()
				for _, entry in table.clone(queue) do
					if now - entry.refreshedAt >= GameConfig.Matchmaking.TicketSeconds / 3 then
						entry.refreshedAt = now
						CrossServer.join(active, mode, entry.player.UserId, entry.characterId, entry.joinedAt)
					end
				end
				CrossServer.form(active, mode, Protocol.groupSize(mode) :: number)
			end
		end
		for _, queue in queues do
			for _, entry in table.clone(queue) do
				local ticket = CrossServer.takeTicket(active, entry.player.UserId)
				if ticket and queuedOf[entry.player] == entry then
					removeFromQueue(entry.player, false)
					teleportToMatch(entry.player, ticket)
				end
			end
		end
	end)
	polling = false
	if not ok then
		warn(`[Matchmaking] Ошибка межсерверного подбора: {err}`)
	end
end

-- Сервер матча: все из состава на месте — начинаем.
local function tryStartReserved()
	local ticket = expected
	if ticket == nil or reservedStarted then
		return
	end
	for _, member in ticket.roster do
		local player: Player? = arrived[member.userId]
		if player == nil or player.Parent == nil then
			return
		end
	end
	reservedStarted = true
	local entries: { Entry } = {}
	-- Порядок: команда 1, команда 2, команда 1, ... — как ожидает startMatch.
	local byTeam: { { Entry } } = { {}, {} }
	for _, member in ticket.roster do
		local player = arrived[member.userId]
		local characterId = if DataService.ownsCharacter(player, member.characterId) then member.characterId else "rook"
		table.insert(byTeam[member.team], {
			player = player,
			characterId = characterId,
			mode = ticket.mode :: Mode,
			joinedAt = 0,
			refreshedAt = 0,
			queuedAt = 0,
		})
	end
	for index = 1, math.max(#byTeam[1], #byTeam[2]) do
		for team = 1, 2 do
			local entry = byTeam[team][index]
			if entry then
				table.insert(entries, entry)
			end
		end
	end
	MatchmakingService.startMatch(ticket.mode :: Mode, entries, true)
end

local function readJoinData(player: Player): any
	local ok, data = pcall(function()
		return player:GetJoinData()
	end)
	if ok and type(data) == "table" then
		return data.TeleportData
	end
	return nil
end

local function onPlayerAdded(player: Player)
	local data = readJoinData(player)
	if isMatchServer then
		local ticket = Protocol.readMatch(data)
		if expected == nil and ticket then
			expected = ticket
			arrivalDeadline = os.clock() + GameConfig.Matchmaking.ArrivalSeconds
		end
		local current = expected
		local listed = false
		if current and ticket and ticket.matchKey == current.matchKey then
			for _, member in current.roster do
				listed = listed or member.userId == player.UserId
			end
		end
		if listed then
			arrived[player.UserId] = player
			tryStartReserved()
		else
			task.defer(returnToLobby, { player })
		end
		return
	end
	local join = Protocol.readRoomJoin(data)
	if join then
		-- Войдём в комнату, когда клиент будет готов принимать события (запрос ClientReady).
		pendingRoomJoin[player] = join
	end
end

-- Слишком долго ждут соперников — добавляем ботов (дети не должны скучать в очереди).
local function checkBotFill()
	if isMatchServer then
		return
	end
	local now = os.clock()
	for mode, queue in queues do
		local first = queue[1]
		if first and now - first.queuedAt >= GameConfig.Matchmaking.BotFillSeconds then
			local size = Protocol.groupSize(mode) :: number
			local group = table.move(queue, 1, math.min(size, #queue), 1, {})
			MatchmakingService.startMatch(mode :: Mode, group, false, true)
		end
	end
end

local function checkArrivals()
	if not isMatchServer or reservedStarted or expected == nil then
		return
	end
	if os.clock() >= arrivalDeadline then
		reservedStarted = true
		local present: { Player } = {}
		for _, player in arrived do
			table.insert(present, player)
			send(player, { status = "Idle", reason = "OpponentMissing" })
		end
		task.delay(3, returnToLobby, present)
	end
end

local function expireRooms()
	local now = os.clock()
	for _, room in table.clone(rooms) do
		if now - room.createdAt > GameConfig.Matchmaking.RoomSeconds then
			closeRoom(room, "RoomExpired")
		end
	end
end

----------------------------------------------------------------------------------------------
-- Запросы клиентов
----------------------------------------------------------------------------------------------

local function readCharacter(player: Player, value: unknown): string?
	if type(value) ~= "string" or CharacterRegistry.get(value) == nil then
		return nil
	end
	return if DataService.ownsCharacter(player, value) then value else nil
end

local function joinRoom(player: Player, room: Room, characterId: string): (boolean, any)
	if roomOf[player] == room then
		return true, room.code
	end
	if #room.members >= (Protocol.groupSize(room.mode) :: number) then
		return false, "RoomFull"
	end
	leaveRoom(player, false)
	removeFromQueue(player, false)
	local entry: Entry = {
		player = player,
		characterId = characterId,
		mode = room.mode,
		joinedAt = os.time(),
		refreshedAt = 0,
		queuedAt = os.clock(),
	}
	table.insert(room.members, entry)
	roomOf[player] = room
	if #room.members >= (Protocol.groupSize(room.mode) :: number) then
		local members = table.clone(room.members)
		closeRoom(room, nil)
		MatchmakingService.startMatch(room.mode, members, false, false, true)
	else
		broadcastRoom(room)
	end
	return true, room.code
end

local function registerRequests()
	RequestRouter.register("QueueJoin", function(player: Player, payload: unknown)
		if type(payload) ~= "table" then
			return false, "BadRequest"
		end
		local readMode = Protocol.readMode((payload :: any).mode)
		if readMode == nil then
			return false, "BadRequest"
		end
		local mode: Mode = readMode :: Mode
		local characterId = readCharacter(player, (payload :: any).characterId)
		if characterId == nil then
			return false, "CharacterNotAvailable"
		end
		if MatchService.getMatchOf(player) ~= nil then
			return false, "InMatch"
		end
		leaveRoom(player, false)
		removeFromQueue(player, false)
		local entry: Entry = {
			player = player,
			characterId = characterId,
			mode = mode,
			joinedAt = os.time(),
			refreshedAt = os.clock(),
			queuedAt = os.clock(),
		}
		table.insert(queues[mode], entry)
		queuedOf[player] = entry
		send(player, { status = "Searching", mode = mode })
		tryLocal(mode)
		local active = cross
		if active and queuedOf[player] == entry then
			task.spawn(CrossServer.join, active, mode, player.UserId, characterId, entry.joinedAt)
		end
		return true, nil
	end)

	RequestRouter.register("QueueLeave", function(player: Player)
		removeFromQueue(player, true)
		return true, nil
	end)

	RequestRouter.register("RoomCreate", function(player: Player, payload: unknown)
		if type(payload) ~= "table" then
			return false, "BadRequest"
		end
		local readMode = Protocol.readMode((payload :: any).mode)
		if readMode == nil then
			return false, "BadRequest"
		end
		local mode: Mode = readMode :: Mode
		local characterId = readCharacter(player, (payload :: any).characterId)
		if characterId == nil then
			return false, "CharacterNotAvailable"
		end
		if MatchService.getMatchOf(player) ~= nil then
			return false, "InMatch"
		end
		leaveRoom(player, false)
		removeFromQueue(player, false)
		local code = Protocol.newRoomCode(random)
		while rooms[code] do
			code = Protocol.newRoomCode(random)
		end
		local room: Room = { code = code, mode = mode, host = player, members = {}, createdAt = os.clock() }
		rooms[code] = room
		local active = cross
		if active then
			task.spawn(CrossServer.registerRoom, active, code, mode)
		end
		joinRoom(player, room, characterId)
		return true, code
	end)

	RequestRouter.register("RoomJoin", function(player: Player, payload: unknown)
		if type(payload) ~= "table" then
			return false, "BadRequest"
		end
		local code = Protocol.normalizeCode((payload :: any).code)
		if code == nil then
			return false, "BadCode"
		end
		local characterId = readCharacter(player, (payload :: any).characterId)
		if characterId == nil then
			return false, "CharacterNotAvailable"
		end
		if MatchService.getMatchOf(player) ~= nil then
			return false, "InMatch"
		end
		local room = rooms[code]
		if room then
			return joinRoom(player, room, characterId)
		end
		local active = cross
		if active then
			local info = CrossServer.findRoom(active, code)
			if info and info.jobId ~= game.JobId then
				send(player, { status = "Teleporting" })
				local ok, err = pcall(function()
					local TeleportService = game:GetService("TeleportService")
					local options = Instance.new("TeleportOptions")
					options.ServerInstanceId = info.jobId
					options:SetTeleportData(Protocol.encodeRoomJoin({ code = code, characterId = characterId }))
					TeleportService:TeleportAsync(game.PlaceId, { player }, options)
				end)
				if ok then
					return true, "Teleporting"
				end
				warn(`[Matchmaking] Телепорт к другу не удался: {err}`)
				send(player, { status = "Idle", reason = "TeleportFailed" })
				return false, "TeleportFailed"
			end
		end
		return false, "RoomNotFound"
	end)

	RequestRouter.register("RoomLeave", function(player: Player)
		leaveRoom(player, true)
		return true, nil
	end)

	RequestRouter.register("StartCpu", function(player: Player, payload: unknown)
		if type(payload) ~= "table" then
			return false, "BadRequest"
		end
		local level = (payload :: any).level
		if type(level) ~= "number" or table.find(MatchmakingService.CPU_LEVELS, level) == nil then
			return false, "BadRequest"
		end
		local characterId = readCharacter(player, (payload :: any).characterId)
		if characterId == nil then
			return false, "CharacterNotAvailable"
		end
		local mode: Mode? = Protocol.readMode((payload :: any).mode)
		local match = MatchmakingService.startCpu(player, characterId, level, nil, mode)
		return true, match.id
	end)

	-- Хозяин комнаты начинает матч сразу: свободные места займут боты.
	RequestRouter.register("RoomStart", function(player: Player)
		local room = roomOf[player]
		if room == nil then
			return false, "NotInRoom"
		end
		if room.host ~= player then
			return false, "NotHost"
		end
		local members = table.clone(room.members)
		closeRoom(room, nil)
		MatchmakingService.startMatch(room.mode, members, false, true, true)
		return true, nil
	end)

	-- Клиент готов принимать события: завершить вход в комнату после телепорта к другу.
	RequestRouter.register("ClientReady", function(player: Player)
		local join = pendingRoomJoin[player]
		pendingRoomJoin[player] = nil
		if join == nil then
			return true, nil
		end
		local room = rooms[join.code]
		local characterId = readCharacter(player, join.characterId) or "rook"
		if room == nil then
			send(player, { status = "Idle", reason = "RoomNotFound" })
			return true, nil
		end
		joinRoom(player, room, characterId)
		return true, nil
	end)
end

----------------------------------------------------------------------------------------------
-- Жизненный цикл
----------------------------------------------------------------------------------------------

-- Доступна ли межсерверная часть (опубликованная игра, не Studio).
local function crossServerAvailable(): boolean
	return game.PlaceId ~= 0 and not RunService:IsStudio()
end

function MatchmakingService.Init()
	registerRequests()
	isMatchServer = game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0
	if crossServerAvailable() then
		local ok, memoryStore = pcall(function()
			return game:GetService("MemoryStoreService")
		end)
		local teleportOk, teleport = pcall(function()
			return game:GetService("TeleportService")
		end)
		if ok and teleportOk then
			cross = CrossServer.new({
				memoryStore = memoryStore,
				teleport = teleport,
				placeId = game.PlaceId,
				jobId = game.JobId,
				now = os.time,
			})
		end
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player: Player)
		removeFromQueue(player, false)
		leaveRoom(player, false)
		pendingRoomJoin[player] = nil
		if isMatchServer then
			arrived[player.UserId] = nil
		end
	end)
end

function MatchmakingService.Start()
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	RunService.Heartbeat:Connect(function(dt: number)
		checkArrivals()
		checkBotFill()
		expireRooms()
		pollTimer += dt
		if pollTimer >= GameConfig.Matchmaking.PollSeconds then
			pollTimer = 0
			if cross and not polling then
				task.spawn(MatchmakingService.pollCrossServer)
			end
		end
	end)
end

return MatchmakingService
