--!strict
--[[
	Схема профиля игрока (сохраняемые данные), миграции версий и «публичный» вид для клиента.

	Профиль хранит только то, что нельзя вычислить: валюта, прогресс боссов, купленные бойцы,
	настройки управления и обработанные покупки. Бесплатные персонажи доступны всегда и в профиль
	не пишутся. Хранение и сессионная блокировка — DataService (ProfileStore).

	Миграции: migrate() приводит любые сохранённые данные (старые версии, повреждённые поля) к
	текущей схеме — неизвестные поля отбрасываются, числа проверяются, недостающее берётся по умолчанию.
]]

local CharacterRegistry = require(script.Parent.Parent.Characters.CharacterRegistry)
local ControlsLayout = require(script.Parent.Parent.Config.ControlsLayout)
local GameConfig = require(script.Parent.Parent.Config.GameConfig)

export type PlayerData = {
	version: number,
	coins: number,
	-- Сколько боссов пройдено по порядку: открыт босс bossProgress + 1.
	bossProgress: number,
	-- Сколько раз побеждён каждый босс (первая победа даёт награду).
	bossClears: { [string]: number },
	-- Купленные платные персонажи (Game Pass, Robux или монеты).
	ownedCharacters: { [string]: boolean },
	controls: ControlsLayout.Layout,
	-- Обработанные покупки Developer Products: PurchaseId → os.time(). Защита от повторной выдачи.
	purchases: { [string]: number },
}

-- То, что видит клиент (без служебных полей).
export type PublicProfile = {
	coins: number,
	bossProgress: number,
	bossClears: { [string]: number },
	ownedCharacters: { [string]: boolean }, -- все доступные персонажи (бесплатные + купленные)
	controls: ControlsLayout.Layout,
}

local VERSION = 2
local MAX_PURCHASES = 100 -- сколько последних покупок помнить (Roblox повторяет чек не дольше нескольких дней)
local MAX_COINS = 1e9

local ProfileSchema = {}

ProfileSchema.VERSION = VERSION
ProfileSchema.MAX_PURCHASES = MAX_PURCHASES

function ProfileSchema.default(): PlayerData
	return {
		version = VERSION,
		coins = 0,
		bossProgress = 0,
		bossClears = {},
		ownedCharacters = {},
		controls = ControlsLayout.default(),
		purchases = {},
	}
end

local function integer(value: unknown, min: number, max: number): number
	if type(value) ~= "number" or value ~= value then
		return min
	end
	return math.clamp(math.floor(value), min, max)
end

--[[
	Привести сохранённые данные к текущей схеме. Изменяет и возвращает ту же таблицу
	(ProfileStore держит ссылку на profile.Data).
]]
function ProfileSchema.migrate(raw: { [any]: any }): PlayerData
	local data = raw :: any

	data.coins = integer(data.coins, 0, MAX_COINS)
	data.bossProgress = integer(data.bossProgress, 0, GameConfig.BossCount)

	local clears: { [string]: number } = {}
	if type(data.bossClears) == "table" then
		for id, count in data.bossClears do
			if type(id) == "string" and type(count) == "number" and count > 0 then
				clears[id] = integer(count, 0, 1e6)
			end
		end
	end
	data.bossClears = clears

	local owned: { [string]: boolean } = {}
	if type(data.ownedCharacters) == "table" then
		for id, value in data.ownedCharacters do
			local def = if type(id) == "string" then CharacterRegistry.get(id) else nil
			if def and def.unlock == "Paid" and value == true then
				owned[id] = true
			end
		end
	end
	data.ownedCharacters = owned

	data.controls = ControlsLayout.sanitize(data.controls)

	-- v1 → v2: появился журнал покупок.
	local purchases: { [string]: number } = {}
	if type(data.purchases) == "table" then
		for id, time in data.purchases do
			if type(id) == "string" and type(time) == "number" then
				purchases[id] = time
			end
		end
	end
	data.purchases = purchases
	ProfileSchema.trimPurchases(data)

	-- Отбросить неизвестные поля (например, от будущих или удалённых версий).
	local known = {
		version = true,
		coins = true,
		bossProgress = true,
		bossClears = true,
		ownedCharacters = true,
		controls = true,
		purchases = true,
	}
	for key in table.clone(data) do
		if not known[key] then
			data[key] = nil
		end
	end
	data.version = VERSION
	return data :: PlayerData
end

-- Оставить только последние MAX_PURCHASES записей о покупках.
function ProfileSchema.trimPurchases(data: PlayerData)
	local list: { { id: string, time: number } } = {}
	for id, time in data.purchases do
		table.insert(list, { id = id, time = time })
	end
	if #list <= MAX_PURCHASES then
		return
	end
	table.sort(list, function(a, b): boolean
		return a.time > b.time
	end)
	for index = MAX_PURCHASES + 1, #list do
		data.purchases[list[index].id] = nil
	end
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
