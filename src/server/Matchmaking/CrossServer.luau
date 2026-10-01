--!strict
--[[
	CrossServer — межсерверная очередь и приватные комнаты через MemoryStoreService.

	Устройство:
	  • очередь режима — MemoryStoreSortedMap "mm_queue_<mode>": ключ — UserId, sortKey — время входа
	    (первым пришёл — первым подобран), запись живёт TicketSeconds и продлевается, пока игрок ждёт;
	  • сборка матча: сервер берёт самые старые записи и «захватывает» каждую атомарным UpdateAsync
	    (claimed = ключ матча). Если хоть одну уже захватил другой сервер — отпускает свои и пробует позже.
	    Так один игрок никогда не попадает в два матча;
	  • для собранного матча резервируется сервер (TeleportService:ReserveServer) и каждому игроку пишется
	    «билет» в "mm_tickets": код доступа и состав. Сервер, где ждёт игрок, читает билет и телепортирует его;
	  • приватные комнаты: "mm_rooms" (HashMap) — код → JobId сервера хозяина, чтобы друг с другого
	    сервера мог к нему перейти.

	Модуль не обращается к game напрямую: сервисы и идентификаторы передаются в new() — так логика
	проверяется в тестах на поддельном MemoryStore с несколькими «серверами».
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local Settings = GameConfig.Matchmaking

export type Deps = {
	memoryStore: any, -- MemoryStoreService (или подделка в тестах)
	teleport: any, -- TeleportService
	placeId: number,
	jobId: string,
	now: () -> number, -- время для порядка очереди (os.time / часы теста)
}

export type QueueEntry = {
	userId: number,
	characterId: string,
	jobId: string,
	joinedAt: number,
	claimed: string?, -- ключ матча, если запись уже захвачена
}

export type RosterEntry = {
	userId: number,
	characterId: string,
	team: number,
}

export type Ticket = {
	matchKey: string,
	accessCode: string,
	mode: string,
	roster: { RosterEntry },
	fillBots: boolean?,
}

export type Cross = {
	deps: Deps,
	counter: number,
}

local CrossServer = {}

local TICKET_SECONDS = 120
local SCAN_FACTOR = 4 -- сколько записей просматривать сверх размера матча

function CrossServer.new(deps: Deps): Cross
	return { deps = deps, counter = 0 }
end

local function queueMap(cross: Cross, mode: string): any
	return cross.deps.memoryStore:GetSortedMap(`mm_queue_{mode}`)
end

local function ticketMap(cross: Cross): any
	return cross.deps.memoryStore:GetSortedMap("mm_tickets")
end

local function roomMap(cross: Cross): any
	return cross.deps.memoryStore:GetHashMap("mm_rooms")
end

-- Вызов MemoryStore с защитой: сеть и лимиты могут отказать — это не должно ронять сервер.
local function try<T>(callback: () -> T): (boolean, T?)
	local ok, result = pcall(callback)
	if not ok then
		warn(`[CrossServer] MemoryStore: {result}`)
		return false, nil
	end
	return true, result
end

-- Встать в очередь режима (или продлить запись).
function CrossServer.join(cross: Cross, mode: string, userId: number, characterId: string, joinedAt: number): boolean
	local entry: QueueEntry = {
		userId = userId,
		characterId = characterId,
		jobId = cross.deps.jobId,
		joinedAt = joinedAt,
	}
	local ok = try(function()
		return queueMap(cross, mode):SetAsync(tostring(userId), entry, Settings.TicketSeconds, joinedAt)
	end)
	return ok
end

function CrossServer.leave(cross: Cross, mode: string, userId: number)
	try(function()
		return queueMap(cross, mode):RemoveAsync(tostring(userId))
	end)
end

local function release(cross: Cross, mode: string, keys: { string }, matchKey: string)
	for _, key in keys do
		try(function()
			return queueMap(cross, mode):UpdateAsync(key, function(value: any, sortKey: any): (any, any)
				if type(value) == "table" and value.claimed == matchKey then
					value.claimed = nil
					return value, sortKey
				end
				return nil, nil
			end, Settings.TicketSeconds)
		end)
	end
end

--[[
	Попробовать собрать один матч из size игроков. Состав: команды чередуются по порядку очереди
	(1-й, 3-й — команда 1; 2-й, 4-й — команда 2). Возвращает билет собранного матча или nil.
]]
function CrossServer.form(cross: Cross, mode: string, size: number): Ticket?
	local map = queueMap(cross, mode)
	local ok, range = try(function(): any
		return map:GetRangeAsync(Enum.SortDirection.Ascending, size * SCAN_FACTOR)
	end)
	if not ok or type(range) ~= "table" then
		return nil
	end
	local candidates: { { key: string, value: QueueEntry } } = {}
	for _, item in range :: { any } do
		local value = item.value
		if type(value) == "table" and value.claimed == nil and type(value.userId) == "number" then
			table.insert(candidates, { key = item.key, value = value })
			if #candidates == size then
				break
			end
		end
	end
	local fillBots = mode == "Team" and size == 4 and #candidates == 3
	if #candidates < size and not fillBots then
		return nil
	end

	cross.counter += 1
	local matchKey = `{cross.deps.jobId}:{cross.deps.now()}:{cross.counter}`
	local claimed: { string } = {}
	for _, candidate in candidates do
		local claimOk, result = try(function(): any
			return map:UpdateAsync(candidate.key, function(value: any, sortKey: any): (any, any)
				if type(value) ~= "table" or value.claimed ~= nil then
					return nil, nil -- уже занят другим сервером или вышел из очереди
				end
				value.claimed = matchKey
				return value, sortKey
			end, Settings.TicketSeconds)
		end)
		if not claimOk or result == nil then
			release(cross, mode, claimed, matchKey)
			return nil
		end
		table.insert(claimed, candidate.key)
	end

	local reserved, accessCode = try(function(): any
		return (cross.deps.teleport:ReserveServer(cross.deps.placeId))
	end)
	if not reserved or type(accessCode) ~= "string" then
		release(cross, mode, claimed, matchKey)
		return nil
	end

	local roster: { RosterEntry } = {}
	for index, candidate in candidates do
		table.insert(roster, {
			userId = candidate.value.userId,
			characterId = candidate.value.characterId,
			team = if index % 2 == 1 then 1 else 2,
		})
	end
	local ticket: Ticket = {
		matchKey = matchKey,
		accessCode = accessCode,
		mode = mode,
		roster = roster,
		fillBots = if fillBots then true else nil,
	}
	for _, entry in roster do
		try(function()
			return ticketMap(cross):SetAsync(tostring(entry.userId), ticket, TICKET_SECONDS)
		end)
	end
	for _, key in claimed do
		try(function()
			return map:RemoveAsync(key)
		end)
	end
	return ticket
end

-- Билет игрока, если его матч собран (билет удаляется при чтении).
function CrossServer.takeTicket(cross: Cross, userId: number): Ticket?
	local key = tostring(userId)
	local ok, ticket = try(function(): any
		return (ticketMap(cross):GetAsync(key))
	end)
	if not ok or type(ticket) ~= "table" then
		return nil
	end
	try(function()
		return ticketMap(cross):RemoveAsync(key)
	end)
	return ticket :: Ticket
end

-- Приватная комната видна другим серверам.
function CrossServer.registerRoom(cross: Cross, code: string, mode: string)
	try(function()
		return roomMap(cross):SetAsync(code, { jobId = cross.deps.jobId, mode = mode }, Settings.RoomSeconds)
	end)
end

function CrossServer.findRoom(cross: Cross, code: string): { jobId: string, mode: string }?
	local ok, value = try(function(): any
		return (roomMap(cross):GetAsync(code))
	end)
	if ok and type(value) == "table" and type(value.jobId) == "string" and type(value.mode) == "string" then
		return { jobId = value.jobId, mode = value.mode }
	end
	return nil
end

function CrossServer.removeRoom(cross: Cross, code: string)
	try(function()
		return roomMap(cross):RemoveAsync(code)
	end)
end

return CrossServer
