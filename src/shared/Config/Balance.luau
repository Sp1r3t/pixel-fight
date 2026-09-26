--!strict
--[[
	Правила баланса («бюджет силы»). Чистые данные; проверку выполняет CharacterRegistry.validate().

	Принцип no pay-to-win:
	  1. У КАЖДОГО персонажа (бесплатного и платного) сумма рейтингов характеристик = StatBudget.
	     Больше урона ⇒ меньше HP/скорости/дальности и т.д.
	  2. Урон особых приёмов и суперов ограничен диапазонами, которые зависят только от ТИПА приёма,
	     а не от того, платный персонаж или нет. Более надёжные/безопасные типы бьют слабее.
	  3. Средние рейтинги платных персонажей не могут превышать средние бесплатных больше чем на MaxPaidStatSkew.
	  4. Косметика (ауры, шлейфы, фоны суперов) не участвует в боевых расчётах вообще.
]]

local Types = require(script.Parent.Parent.Types)
local deepFreeze = require(script.Parent.Parent.Util.deepFreeze)

export type DamageBand = { min: number, max: number }
export type StatScale = { base: number, step: number }

local function band(min: number, max: number): DamageBand
	return { min = min, max = max }
end

local statScaling = {
	health = { base = 1000, step = 60 }, -- 820..1180 HP
	damage = { base = 1.0, step = 0.06 }, -- множитель урона 0.82..1.18
	speed = { base = 10, step = 0.8 }, -- 7.6..12.4 студ/с
	range = { base = 1.0, step = 0.06 }, -- множитель дальности 0.82..1.18
	superGain = { base = 1.0, step = 0.08 }, -- множитель набора супера 0.76..1.24
}

-- Допустимый базовый урон особого приёма по типу.
local specialDamageBands: { [Types.SpecialKind]: DamageBand } = {
	Projectile = band(60, 80),
	ArcProjectile = band(60, 80),
	Boomerang = band(50, 70), -- может попасть дважды (туда и обратно)
	GroundWave = band(60, 80),
	RushStrike = band(80, 100),
	SpinDash = band(80, 100),
	ArmorCharge = band(80, 100),
	RisingStrike = band(90, 110), -- неуязвимый старт, но опасен при промахе
	DiveKick = band(70, 90),
	OverheadLeap = band(80, 100),
	Teleport = band(70, 90),
	Counter = band(100, 120), -- срабатывает только если противник атаковал
	CommandGrab = band(120, 140), -- неблокируемый, но короткий и медленный
	Hook = band(40, 60), -- слабый, зато притягивает и открывает комбо
	LongThrust = band(70, 90),
	Trap = band(60, 80),
}

-- Допустимый базовый урон супера по способу доставки.
local superDamageBands: { [Types.SuperDelivery]: DamageBand } = {
	Rush = band(280, 320),
	Launcher = band(270, 300),
	Beam = band(230, 260), -- быстрый и на весь экран — поэтому слабее
	Barrage = band(230, 260),
	Grab = band(300, 340), -- неблокируемый, но только вплотную
	Counter = band(320, 360), -- впустую, если противник не атаковал
}

local Balance = deepFreeze({
	StatBudget = 25,
	StatMin = 2,
	StatMax = 8,
	-- Максимальное превышение среднего рейтинга платных над бесплатными (по каждой характеристике).
	MaxPaidStatSkew = 0.75,

	-- Перевод рейтинга в реальное значение: base + (rating - 5) * step.
	StatScaling = statScaling,

	SpecialDamageBands = specialDamageBands,

	SuperDamageBands = superDamageBands,

	-- Ограничения фреймдаты суперов: стартап не быстрее SuperMinStartup кадров
	-- (плюс вспышка-заморозка, на которую можно отреагировать).
	SuperMinStartup = 4,
	SuperMaxStartup = 14,
})

return Balance
