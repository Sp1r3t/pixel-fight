--!strict
--[[
	MoveBook — где взять фреймдату приёма бойца: обычные удары (Config/Moves),
	особый приём и супер (Config/Characters). Плюс индексы приёмов для снапшотов.
]]

local Types = require(script.Parent.Parent.Types)
local Moves = require(script.Parent.Parent.Config.Moves)
local CharacterRegistry = require(script.Parent.Parent.Characters.CharacterRegistry)

local MoveBook = {}

local indexOf: { [string]: number } = {}
for index, id in Moves.ids do
	indexOf[id] = index
end

function MoveBook.toIndex(moveId: string?): number
	if moveId == nil then
		return 0
	end
	return indexOf[moveId] or 0
end

function MoveBook.fromIndex(index: number): string?
	return Moves.ids[index]
end

-- Фреймдата приёма для персонажа (nil — нет такого приёма).
function MoveBook.get(characterId: string, moveId: string): Types.MoveData?
	local normal = Moves.normals[moveId]
	if normal then
		return normal.data
	end
	local def = CharacterRegistry.get(characterId)
	if def == nil then
		return nil
	end
	if moveId == "Special" then
		return def.special.move
	elseif moveId == "Super" then
		return def.super.move
	end
	return nil
end

-- Во что можно отменить приём при попадании/блоке.
function MoveBook.cancels(moveId: string): { string }
	local normal = Moves.normals[moveId]
	if normal then
		return normal.cancels
	elseif moveId == "Special" then
		return Moves.specialCancels
	end
	return {}
end

-- Обычный удар (с масштабированием дальности) или особый приём/супер (своя дальность).
function MoveBook.isNormal(moveId: string): boolean
	return Moves.normals[moveId] ~= nil
end

function MoveBook.stance(moveId: string): Moves.Stance?
	local normal = Moves.normals[moveId]
	return if normal then normal.stance else nil
end

function MoveBook.totalFrames(move: Types.MoveData): number
	return move.startup + move.active + move.recovery
end

function MoveBook.isActive(move: Types.MoveData, frame: number): boolean
	return frame >= move.startup and frame < move.startup + move.active
end

return MoveBook
