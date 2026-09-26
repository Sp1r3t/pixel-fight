--!strict
--[[
	DataService — сохранения игрока.  [этап 9]

	Ответственность:
	• профиль игрока через ProfileStore (сессионная блокировка — защита от дюпа и потери данных);
	• открытые персонажи, прогресс по боссам, валюта, настройки управления;
	• миграции версий профиля и значения по умолчанию;
	• публикация состояния профиля клиенту (→ Fusion Values в UI).

	Пока (до этапа 9) профилей нет: доступны только бесплатные персонажи.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CharacterRegistry = require(ReplicatedStorage.Shared.Characters.CharacterRegistry)

local DataService = {
	Name = "DataService",
}

-- Может ли игрок играть этим персонажем.
function DataService.ownsCharacter(_player: Player, characterId: string): boolean
	return CharacterRegistry.isFree(characterId)
end

function DataService.Init() end

function DataService.Start() end

return DataService
