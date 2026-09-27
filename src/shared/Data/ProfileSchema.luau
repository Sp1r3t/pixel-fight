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
local Arenas = require(script.Parent.Parent.Config.Arenas)
local ControlsLayout = require(script.Parent.Parent.Config.ControlsLayout)
local Combos = require(script.Parent.Parent.Config.Combos)
local Cosmetics = require(script.Parent.Parent.Config.Cosmetics)
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
	-- Купленные премиальные карты.
	ownedArenas: { [string]: boolean },
	controls: ControlsLayout.Layout,
	-- Обработанные покупки Developer Products: PurchaseId → os.time(). Защита от повторной выдачи.
	purchases: { [string]: number },
	-- Найденные комбо (Config/Combos): за первое выполнение — награда.
	combos: { [string]: boolean },
	-- v5: кристаллы (за Robux), купленная косметика, что надето, ежедневная награда.
	crystals: number,
	items: { [string]: boolean },
	equipped: Equipped,
	daily: Daily,
	starterPack: boolean,
}

-- Надетая косметика: облик для каждого бойца, эффект ударов, финишер (nil — стандартные).
export type Equipped = {
	skins: { [string]: string },
	hitEffect: string?,
	koEffect: string?,
}

-- Ежедневная награда: номер дня (UTC, os.time() // 86400) последнего получения и длина серии.
export type Daily = {
	day: number,
	streak: number,
}

-- То, что видит клиент (без служебных полей).
export type PublicProfile = {
	coins: number,
	bossProgress: number,
	bossClears: { [string]: number },
	ownedCharacters: { [string]: boolean }, -- все доступные персонажи (бесплатные + купленные)
	ownedArenas: { [string]: boolean }, -- все доступные карты (бесплатные + купленные)
	controls: ControlsLayout.Layout,
	combos: { [string]: boolean }, -- найденные комбо
	crystals: number,
	items: { [string]: boolean }, -- вся доступная косметика (бесплатная + купленная + VIP)
	equipped: Equipped,
	daily: Daily,
	starterPack: boolean,
	vip: boolean,
}

local VERSION = 5
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
		ownedArenas = {},
		controls = ControlsLayout.default(),
		purchases = {},
		combos = {},
		crystals = 0,
		items = {},
		equipped = { skins = {} },
		daily = { day = 0, streak = 0 },
		starterPack = false,
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

	-- v2 → v3: купленные премиальные карты.
	local arenas: { [string]: boolean } = {}
	if type(data.ownedArenas) == "table" then
		for id, value in data.ownedArenas do
			local arena = if type(id) == "string" then Arenas.byId[id] else nil
			if arena and arena.premium and value == true then
				arenas[id] = true
			end
		end
	end
	data.ownedArenas = arenas

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

	-- v3 → v4: найденные комбо (только существующие).
	local combos: { [string]: boolean } = {}
	if type(data.combos) == "table" then
		for id, value in data.combos do
			if type(id) == "string" and Combos.byId[id] and value == true then
				combos[id] = true
			end
		end
	end
	data.combos = combos

	-- v4 → v5: кристаллы и косметика.
	data.crystals = integer(data.crystals, 0, MAX_COINS)
	local items: { [string]: boolean } = {}
	if type(data.items) == "table" then
		for id, value in data.items do
			local item = if type(id) == "string" then Cosmetics.byId[id] else nil
			-- Храним только купленное: бесплатное и VIP доступны и так.
			if item and value == true and (item.currency == "Coins" or item.currency == "Crystals") then
				items[id] = true
			end
		end
	end
	data.items = items
	local rawEquipped = if type(data.equipped) == "table" then data.equipped else {}
	local equipped: Equipped = { skins = {} }
	if type(rawEquipped.skins) == "table" then
		for characterId, skinId in rawEquipped.skins do
			local item = if type(skinId) == "string" then Cosmetics.byId[skinId] else nil
			if type(characterId) == "string" and item and item.kind == "Skin" and item.character == characterId then
				equipped.skins[characterId] = skinId
			end
		end
	end
	for _, slot in { "hitEffect", "koEffect" } do
		local id = rawEquipped[slot]
		local item = if type(id) == "string" then Cosmetics.byId[id] else nil
		local kind = if slot == "hitEffect" then "HitEffect" else "KoEffect"
		if item and item.kind == kind then
			(equipped :: any)[slot] = id
		end
	end
	data.equipped = equipped
	local rawDaily = if type(data.daily) == "table" then data.daily else {}
	data.daily = { day = integer(rawDaily.day, 0, 1e9), streak = integer(rawDaily.streak, 0, 7) }
	data.starterPack = data.starterPack == true

	-- Отбросить неизвестные поля (например, от будущих или удалённых версий).
	local known = {
		version = true,
		coins = true,
		bossProgress = true,
		bossClears = true,
		ownedCharacters = true,
		ownedArenas = true,
		controls = true,
		purchases = true,
		combos = true,
		crystals = true,
		items = true,
		equipped = true,
		daily = true,
		starterPack = true,
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

-- Доступна ли косметика игроку (бесплатная, купленная или VIP).
function ProfileSchema.hasItem(data: PlayerData, itemId: string, vip: boolean): boolean
	local item = Cosmetics.byId[itemId]
	if item == nil then
		return false
	end
	if item.currency == "Free" then
		return true
	elseif item.currency == "Vip" then
		return vip
	end
	return data.items[itemId] == true
end

function ProfileSchema.toPublic(data: PlayerData, vip: boolean?): PublicProfile
	local owned: { [string]: boolean } = {}
	for _, def in CharacterRegistry.list() do
		if def.unlock == "Free" or data.ownedCharacters[def.id] then
			owned[def.id] = true
		end
	end
	local arenas: { [string]: boolean } = {}
	for _, arena in Arenas.list do
		if not arena.premium or data.ownedArenas[arena.id] then
			arenas[arena.id] = true
		end
	end
	local items: { [string]: boolean } = {}
	for _, item in Cosmetics.items do
		if ProfileSchema.hasItem(data, item.id, vip == true) then
			items[item.id] = true
		end
	end
	return {
		coins = data.coins,
		bossProgress = data.bossProgress,
		bossClears = table.clone(data.bossClears),
		ownedCharacters = owned,
		ownedArenas = arenas,
		controls = ControlsLayout.copy(data.controls),
		combos = table.clone(data.combos),
		crystals = data.crystals,
		items = items,
		equipped = {
			skins = table.clone(data.equipped.skins),
			hitEffect = data.equipped.hitEffect,
			koEffect = data.equipped.koEffect,
		},
		daily = table.clone(data.daily),
		starterPack = data.starterPack,
		vip = vip == true,
	}
end

return ProfileSchema
