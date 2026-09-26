--!strict
--[[
	BossRegistry — доступ к конфигу боссов, сборка профиля ИИ и проверка правил.
	Не использует Roblox API: работает на сервере, на клиенте (карта боссов) и в тестах.
]]

local Types = require(script.Parent.Parent.Types)
local Balance = require(script.Parent.Parent.Config.Balance)
local GameConfig = require(script.Parent.Parent.Config.GameConfig)
local Arenas = require(script.Parent.Parent.Config.Arenas)
local AiDifficulty = require(script.Parent.Parent.Config.AiDifficulty)
local BossesConfig = require(script.Parent.Parent.Config.Bosses)
local CharacterRegistry = require(script.Parent.CharacterRegistry)
local deepFreeze = require(script.Parent.Parent.Util.deepFreeze)

type BossDef = Types.BossDef
type AiProfile = Types.AiProfile

export type MechanicInfo = {
	name: string,
	description: string,
}

-- Названия и описания механик для интерфейса.
local MECHANICS: { [string]: MechanicInfo } = { -- ключи — Types.BossMechanic
	IronSkin = {
		name = "Железная кожа",
		description = "Первый удар каждой серии — вполсилы",
	},
	Regeneration = {
		name = "Регенерация",
		description = "Лечится, если 3 секунды не получает урон",
	},
	Enrage = { name = "Ярость", description = "Ниже 35% HP бьёт сильнее" },
	Vampiric = {
		name = "Вампиризм",
		description = "Лечится частью нанесённого урона",
	},
	Momentum = { name = "Напор", description = "Супер копится быстрее" },
	SuperStart = {
		name = "Готов к бою",
		description = "Начинает раунд с полной шкалой супера",
	},
	Mirror = { name = "Отражение", description = "Сражается вашим бойцом" },
}

local CORE_PARAMS: { string } = {
	"reactionFrames",
	"thinkInterval",
	"blockChance",
	"guardRead",
	"punishChance",
	"antiAirChance",
	"comboSkill",
	"superUsage",
	"readChance",
	"mistakeChance",
}

local ordered: { BossDef } = table.clone(BossesConfig)
table.sort(ordered, function(a: BossDef, b: BossDef): boolean
	return a.order < b.order
end)
local byId: { [string]: BossDef } = {}
for _, def in ordered do
	byId[def.id] = def
end
deepFreeze(BossesConfig)
table.freeze(ordered)

local BossRegistry = {}

BossRegistry.MECHANICS = deepFreeze(MECHANICS)

-- Все боссы по порядку. Таблицы заморожены.
function BossRegistry.list(): { BossDef }
	return ordered
end

function BossRegistry.get(id: string): BossDef?
	return byId[id]
end

function BossRegistry.byOrder(order: number): BossDef?
	return ordered[order]
end

function BossRegistry.count(): number
	return #ordered
end

-- Тир сложности по номеру босса.
function BossRegistry.tierOf(order: number): AiDifficulty.Tier
	for _, tier in AiDifficulty.tiers do
		if order >= tier.first and order <= tier.last then
			return tier
		end
	end
	local tiers = AiDifficulty.tiers
	return if order < tiers[1].first then tiers[1] else tiers[#tiers]
end

-- Уровень мастерства ИИ по номеру босса (без поправок стиля) — для тестов кривой сложности.
function BossRegistry.coreSkill(order: number): { [string]: number }
	local tier = BossRegistry.tierOf(order)
	local span = tier.last - tier.first
	local t = if span > 0 then math.clamp((order - tier.first) / span, 0, 1) else 0
	local curve = tier.curve :: any
	local result: { [string]: number } = {}
	for _, name in CORE_PARAMS do
		local range: { number } = curve[name]
		result[name] = range[1] + (range[2] - range[1]) * t
	end
	return result
end

local function clamp01(value: number): number
	return math.clamp(value, 0, 1)
end

-- Полный профиль ИИ босса: мастерство по номеру + характер по стилю + точечные поправки.
function BossRegistry.profile(def: BossDef): AiProfile
	local core = BossRegistry.coreSkill(def.order)
	local style = AiDifficulty.styles[def.ai.style] or AiDifficulty.styles.Balanced
	for name, delta in style.bias do
		if core[name] then
			core[name] += delta
		end
	end
	local profile: AiProfile = {
		reactionFrames = math.max(1, math.floor(core.reactionFrames + 0.5)),
		thinkInterval = math.max(1, math.floor(core.thinkInterval + 0.5)),
		blockChance = clamp01(core.blockChance),
		guardRead = clamp01(core.guardRead),
		punishChance = clamp01(core.punishChance),
		antiAirChance = clamp01(core.antiAirChance),
		comboSkill = clamp01(core.comboSkill),
		superUsage = clamp01(core.superUsage),
		readChance = clamp01(core.readChance),
		mistakeChance = clamp01(core.mistakeChance),
		aggression = style.aggression,
		jumpChance = style.jumpChance,
		dashChance = style.dashChance,
		specialChance = style.specialChance,
		preferredRange = style.preferredRange,
	}
	local overrides = def.ai.overrides
	if overrides then
		local writable = profile :: any
		for name, value in overrides do
			if writable[name] ~= nil then
				writable[name] = value
			end
		end
	end
	return profile
end

-- Профиль для произвольного уровня (быстрые бои против компьютера, тесты).
function BossRegistry.profileForLevel(order: number, style: Types.AiStyle?): AiProfile
	local template = ordered[math.clamp(math.floor(order), 1, #ordered)]
	local def = table.clone(template) :: any
	def.order = math.clamp(math.floor(order), 1, #ordered)
	def.ai = { style = style or "Balanced" }
	return BossRegistry.profile(def)
end

local function isHexColor(value: string): boolean
	return string.match(value, "^#%x%x%x%x%x%x$") ~= nil
end

-- Проверить конфиг боссов. Возвращает список ошибок (пустой — всё в порядке).
function BossRegistry.validate(bosses: { BossDef }?): { string }
	local list = bosses or BossesConfig
	local errors: { string } = {}
	local seenIds: { [string]: boolean } = {}
	local seenOrders: { [number]: boolean } = {}
	if #list ~= GameConfig.BossCount then
		table.insert(errors, `Боссов должно быть {GameConfig.BossCount}, сейчас {#list}`)
	end
	for _, def in list do
		local where = `босс {def.id}`
		if seenIds[def.id] then
			table.insert(errors, `{where}: повторяющийся id`)
		end
		seenIds[def.id] = true
		if seenOrders[def.order] then
			table.insert(errors, `{where}: повторяющийся номер {def.order}`)
		end
		seenOrders[def.order] = true
		if CharacterRegistry.get(def.character) == nil then
			table.insert(errors, `{where}: неизвестный персонаж {def.character}`)
		end
		if Arenas.byId[def.arena] == nil then
			table.insert(errors, `{where}: неизвестная арена {def.arena}`)
		end
		if def.hpMultiplier < 1 or def.hpMultiplier > Balance.BossMaxHpMultiplier then
			table.insert(errors, `{where}: hpMultiplier вне 1..{Balance.BossMaxHpMultiplier}`)
		end
		if AiDifficulty.styles[def.ai.style] == nil then
			table.insert(errors, `{where}: неизвестный стиль ИИ {def.ai.style}`)
		end
		for _, mechanic in def.mechanics do
			if MECHANICS[mechanic] == nil then
				table.insert(errors, `{where}: неизвестная механика {mechanic}`)
			end
		end
		for _, color in { def.palette.primary, def.palette.secondary, def.palette.accent } do
			if not isHexColor(color) then
				table.insert(errors, `{where}: цвет {color} не в формате #RRGGBB`)
			end
		end
		if def.reward < 0 then
			table.insert(errors, `{where}: награда не может быть отрицательной`)
		end
	end
	for order = 1, #list do
		if not seenOrders[order] then
			table.insert(errors, `Нет босса с номером {order}`)
		end
	end
	return errors
end

function BossRegistry.assertValid()
	local errors = BossRegistry.validate()
	if #errors > 0 then
		error("Ошибки в конфиге боссов:\n  " .. table.concat(errors, "\n  "))
	end
end

return BossRegistry
