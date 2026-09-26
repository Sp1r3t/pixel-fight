--!strict
--[[
	Глобальные константы игры. Чистые данные — логика живёт в сервисах.
	Значения физики/движения добавятся на этапе 2, боевые тайминги — на этапе 3.
]]

local deepFreeze = require(script.Parent.Parent.Util.deepFreeze)

local GameConfig = deepFreeze({
	-- Частота серверной симуляции боя (кадров в секунду). Вся фреймдата задаётся в этих кадрах.
	TickRate = 60,

	Round = {
		DurationSeconds = 60, -- максимальная длительность раунда
		-- Если время вышло — побеждает тот, у кого больше % HP (не абсолютного HP).
		TimeoutByHealthPercent = true,
	},

	-- Сколько побед в раундах нужно для победы в матче.
	RoundsToWin = {
		Versus = 2, -- 1 на 1 и 2 на 2
		Boss = 3, -- одиночный режим против боссов
	},

	SuperMeter = {
		Max = 1000, -- полная шкала = один супер
	},

	Roster = {
		FreeCount = 10,
		PaidCount = 6,
	},

	BossCount = 20,
})

return GameConfig
