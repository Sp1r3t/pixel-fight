--!strict
--[[
	Схема профиля игрока (сохраняемые данные) и его «публичный» вид для клиента.

	Профиль хранит только то, что нельзя вычислить: валюта, прогресс боссов, купленные бойцы,
	настройки управления. Бесплатные персонажи доступны всегда и в профиль не пишутся.
	Сохранение (ProfileStore с сессионной блокировкой) и миграции — DataService, этап 9.
]]

local CharacterRegistry = require(script.Parent.Parent.Characters.CharacterRegistry)
local ControlsLayout = require(script.Parent.Parent.Config.ControlsLayout)

export type PlayerData = {
	version: number,
	coins: number,
	-- Сколько боссов пройдено по порядку: открыт босс bossProgress + 1.
	bossProgress: number,
	-- Сколько раз побеждён каждый босс (первая победа даёт награду).
	bossClears: { [string]: number },
	-- Купленные платные персонажи.
	ownedCharacters: { [string]: boolean },
	controls: ControlsLayout.Layout,
}

-- То, что видит клиент (без служебных полей).
export type PublicProfile = {
	coins: number,
	bossProgress: number,
	bossClears: { [string]: number },
	ownedCharacters: { [string]: boolean }, -- все доступные персонажи (бесплатные + купленные)
	controls: ControlsLayout.Layout,
}

local VERSION = 1

local ProfileSchema = {}

ProfileSchema.VERSION = VERSION

function ProfileSchema.default(): PlayerData
	return {
		version = VERSION,
		coins = 0,
		bossProgress = 0,
		bossClears = {},
		ownedCharacters = {},
		controls = ControlsLayout.default(),
	}
end

function ProfileSchema.toPublic(data: PlayerData): PublicProfile
	local owned: { [string]: boolean } = {}
	for _, def in CharacterRegistry.list() do
		if def.unlock == "Free" or data.ownedCharacters[def.id] then
			owned[def.id] = true
		end
	end
	return {
		coins = data.coins,
		bossProgress = data.bossProgress,
		bossClears = table.clone(data.bossClears),
		ownedCharacters = owned,
		controls = ControlsLayout.copy(data.controls),
	}
end

return ProfileSchema
