--!strict
--[[
	Protocol — форматы данных матчмейкинга: режимы, коды комнат, данные телепорта.
	Данные телепорта приходят вместе с игроком (Player:GetJoinData) и формально от клиента —
	поэтому всё проверяется так же строго, как сетевые запросы.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local CharacterRegistry = require(ReplicatedStorage.Shared.Characters.CharacterRegistry)

local CrossServer = require(script.Parent.CrossServer)

export type Mode = "Versus" | "Team"

export type RoomJoin = {
	code: string,
	characterId: string,
}

local Protocol = {}

Protocol.MATCH_KIND = "PixelFightMatch"
Protocol.ROOM_KIND = "PixelFightRoom"

-- Без похожих символов (0/O, 1/I/L), чтобы код было легко продиктовать другу.
local CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"

-- Сколько игроков нужно для матча режима.
function Protocol.groupSize(mode: string): number?
	if mode == "Versus" then
		return 2
	elseif mode == "Team" then
		return 2 * GameConfig.Team.Size
	end
	return nil
end

function Protocol.readMode(value: unknown): Mode?
	if value == "Versus" or value == "Team" then
		return value :: Mode
	end
	return nil
end

function Protocol.newRoomCode(random: Random): string
	local chars = table.create(GameConfig.Matchmaking.RoomCodeLength, "")
	for index = 1, GameConfig.Matchmaking.RoomCodeLength do
		local position = random:NextInteger(1, #CODE_ALPHABET)
		chars[index] = string.sub(CODE_ALPHABET, position, position)
	end
	return table.concat(chars)
end

-- Код комнаты из ввода игрока: регистр и пробелы не важны; nil — код некорректный.
function Protocol.normalizeCode(value: unknown): string?
	if type(value) ~= "string" or #value > 32 then
		return nil
	end
	local code = string.upper((string.gsub(value, "[%s%-]", "")))
	if #code ~= GameConfig.Matchmaking.RoomCodeLength then
		return nil
	end
	for index = 1, #code do
		if string.find(CODE_ALPHABET, string.sub(code, index, index), 1, true) == nil then
			return nil
		end
	end
	return code
end

-- Данные телепорта на сервер матча. Возвращает билет или nil, если данные некорректны.
function Protocol.readMatch(data: unknown): CrossServer.Ticket?
	if type(data) ~= "table" then
		return nil
	end
	local raw = data :: { [string]: any }
	if raw.kind ~= Protocol.MATCH_KIND or type(raw.matchKey) ~= "string" or type(raw.accessCode) ~= "string" then
		return nil
	end
	local mode = Protocol.readMode(raw.mode)
	local size = if mode then Protocol.groupSize(mode) else nil
	if mode == nil or size == nil or type(raw.roster) ~= "table" or #raw.roster ~= size then
		return nil
	end
	local roster: { CrossServer.RosterEntry } = {}
	local seen: { [number]: boolean } = {}
	for _, entry in raw.roster do
		if
			type(entry) ~= "table"
			or type(entry.userId) ~= "number"
			or seen[entry.userId]
			or type(entry.characterId) ~= "string"
			or CharacterRegistry.get(entry.characterId) == nil
			or (entry.team ~= 1 and entry.team ~= 2)
		then
			return nil
		end
		seen[entry.userId] = true
		table.insert(roster, { userId = entry.userId, characterId = entry.characterId, team = entry.team })
	end
	return { matchKey = raw.matchKey, accessCode = raw.accessCode, mode = mode, roster = roster }
end

function Protocol.encodeMatch(ticket: CrossServer.Ticket): { [string]: any }
	return {
		kind = Protocol.MATCH_KIND,
		matchKey = ticket.matchKey,
		accessCode = ticket.accessCode,
		mode = ticket.mode,
		roster = ticket.roster,
	}
end

function Protocol.readRoomJoin(data: unknown): RoomJoin?
	if type(data) ~= "table" then
		return nil
	end
	local raw = data :: { [string]: any }
	local code = Protocol.normalizeCode(raw.code)
	if raw.kind ~= Protocol.ROOM_KIND or code == nil or type(raw.characterId) ~= "string" then
		return nil
	end
	return { code = code, characterId = raw.characterId }
end

function Protocol.encodeRoomJoin(join: RoomJoin): { [string]: any }
	return { kind = Protocol.ROOM_KIND, code = join.code, characterId = join.characterId }
end

return Protocol
