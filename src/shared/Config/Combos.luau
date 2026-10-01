--!strict
--[[
	Комбо — 28 простых связок: 12 общих (для всех бойцов) и 16 фирменных (по одной на бойца).

	Комбо — это удары одного бойца, которые попали подряд, пока противник не успел прийти в себя.
	Удары записываются «жетонами»:
	  L  — 👊 «Рука» стоя        H  — 🦶 «Нога» стоя
	  cL — ⬇👊 в приседе          cH — ⬇🦶 в приседе (подсечка)
	  jL — ⬆👊 в прыжке           jH — ⬆🦶 в прыжке
	  S  — ✨ особый приём         SU — ⚡ супер
	Комбо засчитывается, если его жетоны идут подряд внутри серии. Если подходят несколько —
	засчитывается самое длинное (при равной длине — фирменное).

	Все комбо короткие (2–4 удара) и собраны из естественных цепочек отмен (Config/Moves):
	детям не нужно учить сложные команды. Общие комбо — только из обычных ударов, поэтому выходят
	у любого бойца; приёмы и суперы — в фирменных (у каждого бойца свои тайминги). Что каждое комбо
	реально выполнимо, проверяет тест (tests/specs/Combos.spec.luau).

	reward — монеты за первое выполнение (один раз на профиль).
]]

local deepFreeze = require(script.Parent.Parent.Util.deepFreeze)

export type Token = "L" | "H" | "cL" | "cH" | "jL" | "jH" | "S" | "SU"

export type Combo = {
	id: string,
	name: string, -- название на экране
	inputs: { Token },
	character: string?, -- фирменное комбо этого бойца (nil — для всех)
	hint: string, -- как сделать, простыми словами
	reward: number,
}

local UNIVERSAL_REWARD = 20
local SIGNATURE_REWARD = 40

local LIST: { Combo } = {
	-- Общие комбо — только обычные удары, поэтому выходят у любого бойца.
	{
		id = "one_two",
		name = "Двойка",
		inputs = { "L", "L" },
		hint = "Два раза быстро «Рука».",
		reward = UNIVERSAL_REWARD,
	},
	{
		id = "triple",
		name = "Тройка",
		inputs = { "L", "L", "L" },
		hint = "Три раза «Рука» подряд.",
		reward = UNIVERSAL_REWARD,
	},
	{
		id = "jab_kick",
		name = "С ноги",
		inputs = { "L", "H" },
		hint = "«Рука», и сразу «Нога».",
		reward = UNIVERSAL_REWARD,
	},
	{
		id = "classic",
		name = "Классика",
		inputs = { "L", "L", "H" },
		hint = "«Рука», «Рука», «Нога».",
		reward = UNIVERSAL_REWARD,
	},
	{
		id = "low_double",
		name = "Низкая двойка",
		inputs = { "cL", "cL" },
		hint = "Присядь и дважды «Рука».",
		reward = UNIVERSAL_REWARD,
	},
	{
		id = "machine_gun",
		name = "Пулемёт",
		inputs = { "cL", "cL", "cL" },
		hint = "Присядь и трижды быстро «Рука».",
		reward = UNIVERSAL_REWARD,
	},
	{
		id = "sweep",
		name = "Подсечка",
		inputs = { "cL", "cH" },
		hint = "Присядь: «Рука», потом «Нога» — противник падает.",
		reward = UNIVERSAL_REWARD,
	},
	{
		id = "double_sweep",
		name = "Двойная подсечка",
		inputs = { "cL", "cL", "cH" },
		hint = "Присядь: «Рука», «Рука», «Нога».",
		reward = UNIVERSAL_REWARD,
	},
	{
		id = "dive_in",
		name = "Налёт",
		inputs = { "jH", "L" },
		hint = "Прыгни к противнику, в воздухе «Нога», приземлился — «Рука».",
		reward = UNIVERSAL_REWARD,
	},
	{
		id = "sky_jab",
		name = "Небесный удар",
		inputs = { "jL", "L" },
		hint = "Прыгни к противнику, в воздухе «Рука», приземлился — снова «Рука».",
		reward = UNIVERSAL_REWARD,
	},
	{
		id = "dive_kick",
		name = "Налёт с ноги",
		inputs = { "jH", "L", "H" },
		hint = "Прыгни: в воздухе «Нога», приземлился — «Рука», «Нога».",
		reward = UNIVERSAL_REWARD,
	},
	{
		id = "dive_low",
		name = "Налёт снизу",
		inputs = { "jH", "cL" },
		hint = "Прыгни: в воздухе «Нога», приземлился — присядь и «Рука».",
		reward = UNIVERSAL_REWARD,
	},

	-- Фирменные комбо — по одному на бойца, с его приёмом или супером.
	{
		id = "rook_vanguard",
		name = "Ладонь авангарда",
		character = "rook",
		inputs = { "L", "H", "S" },
		hint = "«Рука», «Нога», «Приём» — энергетическая ладонь в упор.",
		reward = SIGNATURE_REWARD,
	},
	{
		id = "mira_cyclone",
		name = "Вихрь",
		character = "mira",
		inputs = { "L", "H", "S" },
		hint = "«Рука», «Нога», «Приём» — и Мира закручивается вихрем.",
		reward = SIGNATURE_REWARD,
	},
	{
		id = "brakk_avalanche",
		name = "Лавина",
		character = "brakk",
		inputs = { "jH", "H" },
		hint = "Прыгни: в воздухе «Нога», приземлился — снова «Нога».",
		reward = SIGNATURE_REWARD,
	},
	{
		id = "juno_orbit",
		name = "Орбита",
		character = "juno",
		inputs = { "L", "L", "H", "S" },
		hint = "«Рука», «Рука», «Нога», потом «Приём» — диск летит по орбите.",
		reward = SIGNATURE_REWARD,
	},
	{
		id = "sable_shadow",
		name = "Удар из тени",
		character = "sable",
		inputs = { "L", "H", "S" },
		hint = "«Рука», «Нога», «Приём» — Сейбл исчезает и бьёт со спины.",
		reward = SIGNATURE_REWARD,
	},
	{
		id = "dax_knockout",
		name = "Нокаутёр",
		character = "dax",
		inputs = { "L", "L", "H", "S" },
		hint = "«Рука», «Рука», «Нога», «Приём» — рывок в броне.",
		reward = SIGNATURE_REWARD,
	},
	{
		id = "wren_talons",
		name = "Когти сокола",
		character = "wren",
		inputs = { "jH", "H", "S" },
		hint = "Прыгни: в воздухе «Нога», приземлился — снова «Нога», потом «Приём».",
		reward = SIGNATURE_REWARD,
	},
	{
		id = "sorren_lotus",
		name = "Лотос",
		character = "sorren",
		inputs = { "jH", "L", "L" },
		hint = "Прыгни: в воздухе «Нога», приземлился — «Рука», «Рука».",
		reward = SIGNATURE_REWARD,
	},
	{
		id = "pike_spear",
		name = "Длинное копьё",
		character = "pike",
		inputs = { "L", "H", "S" },
		hint = "«Рука», «Нога», «Приём» — выпад копьём.",
		reward = SIGNATURE_REWARD,
	},
	{
		id = "zip_rocket",
		name = "Ракета",
		character = "zip",
		inputs = { "L", "L", "S" },
		hint = "«Рука», «Рука», «Приём» — Зип врезается ракетой.",
		reward = SIGNATURE_REWARD,
	},
	{
		id = "ashka_phoenix",
		name = "Взлёт феникса",
		character = "ashka",
		inputs = { "L", "L", "S" },
		hint = "«Рука», «Рука», «Приём» — огненный апперкот.",
		reward = SIGNATURE_REWARD,
	},
	{
		id = "glacia_frost",
		name = "Ледяная дорожка",
		character = "glacia",
		inputs = { "H", "S" },
		hint = "«Нога», и сразу «Приём» — лёд бежит по полу.",
		reward = SIGNATURE_REWARD,
	},
	{
		id = "tempest_thunder",
		name = "Гром и молния",
		character = "tempest",
		inputs = { "L", "L", "H", "S" },
		hint = "«Рука», «Рука», «Нога», «Приём» — прыжок с ударом грома.",
		reward = SIGNATURE_REWARD,
	},
	{
		id = "byte_overload",
		name = "Перегрузка",
		character = "byte",
		inputs = { "L", "L", "SU" },
		hint = "Когда шкала полная: «Рука», «Рука», «Супер».",
		reward = SIGNATURE_REWARD,
	},
	{
		id = "morrow_reaper",
		name = "Крюк жнеца",
		character = "morrow",
		inputs = { "L", "H", "S" },
		hint = "«Рука», «Нога», «Приём» — крюк притягивает противника.",
		reward = SIGNATURE_REWARD,
	},
	{
		id = "astra_supernova",
		name = "Сверхновая",
		character = "astra",
		inputs = { "H", "SU" },
		hint = "Когда шкала полная: «Нога», и сразу «Супер».",
		reward = SIGNATURE_REWARD,
	},
}

-- Иконки жетонов (для экрана комбо и подсказок): id пиксельных иконок (Client/UI/PixelIcons),
-- 1 — для простого удара/приёма, 2 — стрелка (присед/прыжок) + удар.
local TOKEN_ICONS: { [string]: { string } } = {
	L = { "punch" },
	H = { "kick" },
	cL = { "arrow_down", "punch" },
	cH = { "arrow_down", "kick" },
	jL = { "arrow_up", "punch" },
	jH = { "arrow_up", "kick" },
	S = { "special" },
	SU = { "lightning" },
}

local byId: { [string]: Combo } = {}
local indexOf: { [string]: number } = {}
for index, combo in LIST do
	byId[combo.id] = combo
	indexOf[combo.id] = index
end

return deepFreeze({
	list = LIST,
	byId = byId,
	indexOf = indexOf,
	tokenIcons = TOKEN_ICONS,
	MAX = 30, -- не больше 30 комбо: иначе дети запутаются (проверяется тестом)
})
