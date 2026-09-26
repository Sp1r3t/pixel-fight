-- Проверки конфига персонажей и правил «бюджета силы» (no pay-to-win).

local Balance = requireShared("Config", "Balance")
local GameConfig = requireShared("Config", "GameConfig")
local CharacterRegistry = requireShared("Characters", "CharacterRegistry")

local STAT_NAMES = { "health", "damage", "speed", "range", "superGain" }

local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, child in value do
		copy[key] = deepCopy(child)
	end
	return copy
end

local function rosterCopy()
	local list = {}
	for _, def in CharacterRegistry.list() do
		table.insert(list, deepCopy(def))
	end
	return list
end

describe("Ростер", function()
	it("конфиг проходит все правила баланса", function()
		expect(CharacterRegistry.validate()).toBeEmpty()
	end)

	it("16 персонажей: 10 бесплатных и 6 платных", function()
		local free, paid = 0, 0
		for _, def in CharacterRegistry.list() do
			if def.unlock == "Free" then
				free += 1
			else
				paid += 1
			end
		end
		expect(#CharacterRegistry.list()).toBe(16)
		expect(free).toBe(GameConfig.Roster.FreeCount)
		expect(paid).toBe(GameConfig.Roster.PaidCount)
	end)

	it("у каждого персонажа одинаковый бюджет силы", function()
		for _, def in CharacterRegistry.list() do
			local sum = 0
			for _, stat in STAT_NAMES do
				sum += def.stats[stat]
			end
			expect(sum).toBe(Balance.StatBudget)
		end
	end)

	it("список отсортирован по order, поиск по id работает", function()
		local previous = 0
		for _, def in CharacterRegistry.list() do
			expect(def.order > previous).toBeTruthy()
			previous = def.order
			expect(CharacterRegistry.get(def.id)).toBe(def)
		end
		expect(CharacterRegistry.get("nobody")).toBe(nil)
	end)

	it("конфиг заморожен от случайных изменений", function()
		local def = CharacterRegistry.list()[1]
		expect(table.isfrozen(def)).toBeTruthy()
		expect(table.isfrozen(def.stats)).toBeTruthy()
		expect(table.isfrozen(def.special.move.hitbox)).toBeTruthy()
	end)
end)

describe("Производные характеристики", function()
	it("средний рейтинг 5 даёт базовые значения", function()
		local rook = CharacterRegistry.get("rook")
		local derived = CharacterRegistry.getDerivedStats(rook)
		expect(derived.maxHealth).toBe(1000)
		expect(derived.damageMultiplier).toBeCloseTo(1)
		expect(derived.walkSpeed).toBeCloseTo(10)
		expect(derived.rangeMultiplier).toBeCloseTo(1)
		expect(derived.superGainMultiplier).toBeCloseTo(1)
	end)

	it("больше HP ↔ меньше чего-то другого (компромисс)", function()
		local brakk = CharacterRegistry.getDerivedStats(CharacterRegistry.get("brakk"))
		local mira = CharacterRegistry.getDerivedStats(CharacterRegistry.get("mira"))
		expect(brakk.maxHealth > mira.maxHealth).toBeTruthy()
		expect(brakk.walkSpeed < mira.walkSpeed).toBeTruthy()
	end)
end)

describe("Валидатор ловит нарушения", function()
	it("лишний рейтинг сверх бюджета", function()
		local list = rosterCopy()
		list[1].stats.damage += 1
		expect(CharacterRegistry.validate(list)).toContainMatch("бюджет силы")
	end)

	it("урон супера вне диапазона своего типа", function()
		local list = rosterCopy()
		list[2].super.move.damage = 999
		expect(CharacterRegistry.validate(list)).toContainMatch("вне диапазона")
	end)

	it("платный персонаж сильнее бесплатных в среднем", function()
		local list = rosterCopy()
		for _, def in list do
			if def.unlock == "Paid" then
				def.stats.damage = Balance.StatMax
			end
		end
		expect(CharacterRegistry.validate(list)).toContainMatch(
			"средний рейтинг damage у платных"
		)
	end)

	it("аура у бесплатного персонажа", function()
		local list = rosterCopy()
		list[1].cosmetics.aura = "EmberAura"
		expect(CharacterRegistry.validate(list)).toContainMatch("только для Deluxe")
	end)

	it("повторяющийся тип особого приёма", function()
		local list = rosterCopy()
		list[2].special.kind = list[1].special.kind
		expect(CharacterRegistry.validate(list)).toContainMatch("уже занят")
	end)

	it("неблокируемый приём с уроном по блоку", function()
		local list = rosterCopy()
		list[3].special.move.chip = 10
		expect(CharacterRegistry.validate(list)).toContainMatch("неблокируемый")
	end)
end)
