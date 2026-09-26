--!strict
--[[
	Кривая сложности боссов — ТОЛЬКО данные.
	Профиль ИИ конкретного босса собирает BossRegistry.profile(): уровень берётся из тира
	(линейно от первого к последнему боссу тира), «характер» — из стиля босса.

	Тиры (номера боссов):
	   1–5  лёгкие       — медленная реакция, редко блокирует, много ошибок, комбо почти не делает;
	   6–10 средние      — блокирует примерно через раз, наказывает очевидные промахи;
	  11–14 сложные      — уверенный блок, короткие комбо с проверкой попадания, сбивает прыжки;
	  15–19 очень сложные — реагирует быстрее человека, читает привычки, длинные комбо в супер;
	     20 почти невозможный — реакция 5 кадров, почти не ошибается.

	Параметры core — «мастерство» (растут от тира к тиру). Параметры стиля не делают босса
	сильнее, а меняют манеру боя (дистанция, агрессия, прыжки, любимые приёмы).
]]

local Types = require(script.Parent.Parent.Types)
local deepFreeze = require(script.Parent.Parent.Util.deepFreeze)

-- { значение у первого босса тира, значение у последнего }.
export type Range = { number }

export type TierCurve = {
	reactionFrames: Range,
	thinkInterval: Range,
	blockChance: Range,
	guardRead: Range,
	punishChance: Range,
	antiAirChance: Range,
	comboSkill: Range,
	superUsage: Range,
	readChance: Range,
	mistakeChance: Range,
}

export type Tier = {
	id: Types.DifficultyTier,
	name: string, -- для интерфейса
	first: number,
	last: number,
	curve: TierCurve,
}

export type StyleTraits = {
	name: string,
	aggression: number,
	jumpChance: number,
	dashChance: number,
	specialChance: number,
	preferredRange: number,
	-- Небольшие сдвиги мастерства (например, «черепаха» блокирует чуть чаще, но реже нападает).
	bias: { [string]: number },
}

local TIERS: { Tier } = {
	{
		id = "Easy",
		name = "Лёгкий",
		first = 1,
		last = 5,
		curve = {
			reactionFrames = { 30, 24 },
			thinkInterval = { 26, 20 },
			blockChance = { 0.08, 0.22 },
			guardRead = { 0.3, 0.45 },
			punishChance = { 0.05, 0.2 },
			antiAirChance = { 0.05, 0.18 },
			comboSkill = { 0.1, 0.25 },
			superUsage = { 0.1, 0.3 },
			readChance = { 0, 0.05 },
			mistakeChance = { 0.35, 0.25 },
		},
	},
	{
		id = "Medium",
		name = "Средний",
		first = 6,
		last = 10,
		curve = {
			reactionFrames = { 20, 16 },
			thinkInterval = { 18, 14 },
			blockChance = { 0.35, 0.5 },
			guardRead = { 0.5, 0.62 },
			punishChance = { 0.35, 0.5 },
			antiAirChance = { 0.25, 0.4 },
			comboSkill = { 0.35, 0.5 },
			superUsage = { 0.4, 0.55 },
			readChance = { 0.15, 0.3 },
			mistakeChance = { 0.18, 0.12 },
		},
	},
	{
		id = "Hard",
		name = "Сложный",
		first = 11,
		last = 14,
		curve = {
			reactionFrames = { 15, 12 },
			thinkInterval = { 12, 10 },
			blockChance = { 0.55, 0.65 },
			guardRead = { 0.68, 0.76 },
			punishChance = { 0.55, 0.68 },
			antiAirChance = { 0.5, 0.62 },
			comboSkill = { 0.6, 0.72 },
			superUsage = { 0.65, 0.75 },
			readChance = { 0.35, 0.5 },
			mistakeChance = { 0.1, 0.07 },
		},
	},
	{
		id = "VeryHard",
		name = "Очень сложный",
		first = 15,
		last = 19,
		curve = {
			reactionFrames = { 11, 8 },
			thinkInterval = { 9, 7 },
			blockChance = { 0.72, 0.85 },
			guardRead = { 0.8, 0.9 },
			punishChance = { 0.75, 0.88 },
			antiAirChance = { 0.7, 0.85 },
			comboSkill = { 0.8, 0.92 },
			superUsage = { 0.82, 0.92 },
			readChance = { 0.6, 0.78 },
			mistakeChance = { 0.05, 0.03 },
		},
	},
	{
		id = "Final",
		name = "Почти невозможный",
		first = 20,
		last = 20,
		curve = {
			reactionFrames = { 5, 5 },
			thinkInterval = { 5, 5 },
			blockChance = { 0.95, 0.95 },
			guardRead = { 0.97, 0.97 },
			punishChance = { 0.97, 0.97 },
			antiAirChance = { 0.95, 0.95 },
			comboSkill = { 1, 1 },
			superUsage = { 1, 1 },
			readChance = { 0.9, 0.9 },
			mistakeChance = { 0.01, 0.01 },
		},
	},
}

local STYLES: { [string]: StyleTraits } = { -- ключи — Types.AiStyle
	Balanced = {
		name = "Универсал",
		aggression = 0.5,
		jumpChance = 0.12,
		dashChance = 0.15,
		specialChance = 0.2,
		preferredRange = 4.5,
		bias = {},
	},
	Rushdown = {
		name = "Напор",
		aggression = 0.8,
		jumpChance = 0.12,
		dashChance = 0.35,
		specialChance = 0.15,
		preferredRange = 3,
		bias = { blockChance = -0.05 },
	},
	Zoner = {
		name = "Держит дистанцию",
		aggression = 0.25,
		jumpChance = 0.05,
		dashChance = 0.08,
		specialChance = 0.45,
		preferredRange = 7.5,
		bias = { antiAirChance = 0.05 },
	},
	Turtle = {
		name = "Глухая защита",
		aggression = 0.25,
		jumpChance = 0.05,
		dashChance = 0.05,
		specialChance = 0.15,
		preferredRange = 5,
		bias = { blockChance = 0.08, punishChance = 0.05 },
	},
	Aerial = {
		name = "Воздушный бой",
		aggression = 0.55,
		jumpChance = 0.35,
		dashChance = 0.1,
		specialChance = 0.2,
		preferredRange = 5,
		bias = {},
	},
	Grappler = {
		name = "Борец",
		aggression = 0.6,
		jumpChance = 0.08,
		dashChance = 0.25,
		specialChance = 0.3,
		preferredRange = 2.8,
		bias = {},
	},
	Counter = {
		name = "Контратака",
		aggression = 0.3,
		jumpChance = 0.05,
		dashChance = 0.1,
		specialChance = 0.25,
		preferredRange = 4,
		bias = { punishChance = 0.08, blockChance = 0.04 },
	},
	Trickster = {
		name = "Хитрец",
		aggression = 0.6,
		jumpChance = 0.2,
		dashChance = 0.3,
		specialChance = 0.3,
		preferredRange = 4.5,
		bias = { readChance = 0.05 },
	},
}

return deepFreeze({
	tiers = TIERS,
	styles = STYLES,
})
