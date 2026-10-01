--!strict
--[[
	CharacterRegistry — доступ к конфигу персонажей и проверка правил баланса.
	Не использует Roblox API, поэтому тестируется вне Studio (см. tests/).
]]

local Types = require(script.Parent.Parent.Types)
local Balance = require(script.Parent.Parent.Config.Balance)
local GameConfig = require(script.Parent.Parent.Config.GameConfig)
local CharactersConfig = require(script.Parent.Parent.Config.Characters)
local CharacterSprites = require(script.Parent.Parent.Config.CharacterSprites)
local deepFreeze = require(script.Parent.Parent.Util.deepFreeze)

type CharacterDef = Types.CharacterDef
type DerivedStats = Types.DerivedStats
type StatRatings = Types.StatRatings
type MoveData = Types.MoveData

local STAT_NAMES: { string } = { "health", "damage", "speed", "range", "superGain" }

-- Рейтинги в том же порядке, что и STAT_NAMES.
local function statRatings(stats: StatRatings): { number }
	return { stats.health, stats.damage, stats.speed, stats.range, stats.superGain }
end

local function scaled(rating: number, scale: Balance.StatScale): number
	return scale.base + (rating - 5) * scale.step
end

local byId: { [string]: CharacterDef } = {}
local ordered: { CharacterDef } = table.clone(CharactersConfig)
table.sort(ordered, function(a: CharacterDef, b: CharacterDef): boolean
	return a.order < b.order
end)
for _, def in ordered do
	-- Пиксель-арт лист (Config/CharacterSprites), если для персонажа уже загружен в Roblox;
	-- иначе def.sprites остаётся nil и SpriteAnimator рисует процедурного Rig, как раньше.
	(def :: any).sprites = CharacterSprites.get(def.id)
	byId[def.id] = def
end
deepFreeze(CharactersConfig)
table.freeze(ordered)

local CharacterRegistry = {}

-- Все персонажи в порядке отображения. Таблицы заморожены — не изменяйте их.
function CharacterRegistry.list(): { CharacterDef }
	return ordered
end

function CharacterRegistry.get(id: string): CharacterDef?
	return byId[id]
end

function CharacterRegistry.isFree(id: string): boolean
	local def = byId[id]
	return def ~= nil and def.unlock == "Free"
end

-- Реальные значения характеристик, которые использует симуляция боя.
function CharacterRegistry.getDerivedStats(def: CharacterDef): DerivedStats
	local scaling = Balance.StatScaling
	return {
		maxHealth = math.floor(scaled(def.stats.health, scaling.health) + 0.5),
		damageMultiplier = scaled(def.stats.damage, scaling.damage),
		walkSpeed = scaled(def.stats.speed, scaling.speed),
		rangeMultiplier = scaled(def.stats.range, scaling.range),
		superGainMultiplier = scaled(def.stats.superGain, scaling.superGain),
	}
end

local function isHexColor(value: string): boolean
	return string.match(value, "^#%x%x%x%x%x%x$") ~= nil
end

local function validateMove(errors: { string }, where: string, move: MoveData)
	if move.startup < 1 then
		table.insert(errors, `{where}: startup должен быть >= 1`)
	end
	if move.active < 1 then
		table.insert(errors, `{where}: active должен быть >= 1`)
	end
	if move.recovery < 0 then
		table.insert(errors, `{where}: recovery не может быть отрицательным`)
	end
	if move.chip > move.damage then
		table.insert(errors, `{where}: урон по блоку больше урона`)
	end
	if move.guard == "Unblockable" and move.chip ~= 0 then
		table.insert(errors, `{where}: неблокируемый приём не может иметь chip-урон`)
	end
	if move.hitbox.w <= 0 or move.hitbox.h <= 0 then
		table.insert(errors, `{where}: хитбокс должен иметь положительный размер`)
	end
	if move.hits ~= nil and move.hits < 1 then
		table.insert(errors, `{where}: hits должен быть >= 1`)
	end
end

local function checkBand(errors: { string }, where: string, damage: number, band: Balance.DamageBand?)
	if band == nil then
		table.insert(errors, `{where}: нет диапазона урона для этого типа приёма`)
	elseif damage < band.min or damage > band.max then
		table.insert(errors, `{where}: урон {damage} вне диапазона {band.min}..{band.max}`)
	end
end

--[[
	Проверяет конфиг персонажей на соответствие правилам баланса.
	Возвращает список ошибок (пустой — всё в порядке).
	Можно передать свой список персонажей (используется в тестах).
]]
function CharacterRegistry.validate(characters: { CharacterDef }?): { string }
	local list = characters or ordered
	local errors: { string } = {}
	local seenIds: { [string]: boolean } = {}
	local seenOrders: { [number]: boolean } = {}
	local seenSpecialKinds: { [string]: string } = {}
	local seenCinematics: { [string]: string } = {}
	local freeCount, paidCount = 0, 0
	local freeSums: { [string]: number } = {}
	local paidSums: { [string]: number } = {}
	for _, statName in STAT_NAMES do
		freeSums[statName] = 0
		paidSums[statName] = 0
	end

	for index, def in list do
		local where = `персонаж #{index} ({def.id})`

		if string.match(def.id, "^[a-z][a-z0-9]*$") == nil then
			table.insert(
				errors,
				`{where}: id должен состоять из строчных латинских букв и цифр`
			)
		end
		if seenIds[def.id] then
			table.insert(errors, `{where}: повторяющийся id`)
		end
		seenIds[def.id] = true
		if seenOrders[def.order] then
			table.insert(errors, `{where}: повторяющийся order {def.order}`)
		end
		seenOrders[def.order] = true

		-- Бюджет силы.
		local sum = 0
		local ratings = statRatings(def.stats)
		for statIndex, statName in STAT_NAMES do
			local rating = ratings[statIndex]
			sum += rating
			if rating < Balance.StatMin or rating > Balance.StatMax or rating % 1 ~= 0 then
				table.insert(
					errors,
					`{where}: рейтинг {statName}={rating} вне допустимых {Balance.StatMin}..{Balance.StatMax}`
				)
			end
			if def.unlock == "Paid" then
				paidSums[statName] += rating
			else
				freeSums[statName] += rating
			end
		end
		if sum ~= Balance.StatBudget then
			table.insert(
				errors,
				`{where}: сумма рейтингов {sum}, а бюджет силы = {Balance.StatBudget}`
			)
		end

		if def.unlock == "Paid" then
			paidCount += 1
		else
			freeCount += 1
		end

		-- Косметика: Deluxe — только у платных, и это единственное их отличие.
		local isDeluxe = def.cosmetics.tier == "Deluxe"
		if isDeluxe ~= (def.unlock == "Paid") then
			table.insert(
				errors,
				`{where}: tier косметики Deluxe должен быть ровно у платных персонажей`
			)
		end
		if not isDeluxe and (def.cosmetics.aura ~= nil or def.cosmetics.cinematicBackdrop ~= nil) then
			table.insert(
				errors,
				`{where}: ауры и фоны суперов предназначены только для Deluxe`
			)
		end
		for _, color in { def.palette.primary, def.palette.secondary, def.palette.accent, def.cosmetics.superFlash } do
			if not isHexColor(color) then
				table.insert(errors, `{where}: цвет "{color}" не в формате #RRGGBB`)
			end
		end

		-- Особый приём.
		validateMove(errors, `{where} special`, def.special.move)
		checkBand(errors, `{where} special`, def.special.move.damage, Balance.SpecialDamageBands[def.special.kind])
		local specialOwner = seenSpecialKinds[def.special.kind]
		if specialOwner ~= nil then
			table.insert(
				errors,
				`{where}: тип особого приёма {def.special.kind} уже занят ({specialOwner})`
			)
		end
		seenSpecialKinds[def.special.kind] = def.id

		-- Супер.
		local super = def.super
		validateMove(errors, `{where} super`, super.move)
		checkBand(errors, `{where} super`, super.move.damage, Balance.SuperDamageBands[super.delivery])
		if super.move.startup < Balance.SuperMinStartup or super.move.startup > Balance.SuperMaxStartup then
			table.insert(
				errors,
				`{where} super: startup {super.move.startup} вне {Balance.SuperMinStartup}..{Balance.SuperMaxStartup}`
			)
		end
		if super.cinematic.hits < 1 or super.cinematic.duration <= 0 then
			table.insert(errors, `{where} super: некорректные параметры ролика`)
		end
		local cinematicOwner = seenCinematics[super.cinematic.style]
		if cinematicOwner ~= nil then
			table.insert(
				errors,
				`{where}: сценарий супера {super.cinematic.style} уже занят ({cinematicOwner})`
			)
		end
		seenCinematics[super.cinematic.style] = def.id
	end

	if characters == nil then
		if freeCount ~= GameConfig.Roster.FreeCount then
			table.insert(
				errors,
				`бесплатных персонажей {freeCount}, нужно {GameConfig.Roster.FreeCount}`
			)
		end
		if paidCount ~= GameConfig.Roster.PaidCount then
			table.insert(
				errors,
				`платных персонажей {paidCount}, нужно {GameConfig.Roster.PaidCount}`
			)
		end
	end

	-- No pay-to-win: платные в среднем не сильнее бесплатных ни по одной характеристике.
	if freeCount > 0 and paidCount > 0 then
		for _, statName in STAT_NAMES do
			local freeAverage = freeSums[statName] / freeCount
			local paidAverage = paidSums[statName] / paidCount
			if paidAverage - freeAverage > Balance.MaxPaidStatSkew then
				table.insert(
					errors,
					string.format(
						"средний рейтинг %s у платных (%.2f) выше, чем у бесплатных (%.2f), больше чем на %.2f",
						statName,
						paidAverage,
						freeAverage,
						Balance.MaxPaidStatSkew
					)
				)
			end
		end
	end

	return errors
end

-- Бросает ошибку со списком всех нарушений. Вызывается сервером при старте.
function CharacterRegistry.assertValid()
	local errors = CharacterRegistry.validate()
	if #errors > 0 then
		error(
			"[CharacterRegistry] Конфиг персонажей нарушает правила баланса:\n  "
				.. table.concat(errors, "\n  "),
			2
		)
	end
end

return CharacterRegistry
