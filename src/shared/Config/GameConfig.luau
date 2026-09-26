--!strict
--[[
	Глобальные константы игры. Чистые данные — логика живёт в симуляции и сервисах.
	Расстояния — в студах, время — в кадрах симуляции (TickRate кадров = 1 секунда).
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

	-- Движение и «физика» арены.
	Physics = {
		ArenaHalfWidth = 22, -- арена от -22 до +22 студов по X
		MaxSeparation = 26, -- бойцы не могут разойтись дальше (помещаются в кадр камеры)
		StartDistance = 8, -- расстояние между бойцами в начале раунда
		Gravity = 120, -- студ/с²
		JumpVelocity = 42, -- студ/с вверх: высота ≈ 7.3, время в воздухе ≈ 42 кадра
		JumpSquatFrames = 3, -- подготовка к прыжку
		LandingFrames = 3, -- приземление
		JumpForwardSpeedFactor = 1.0, -- горизонтальная скорость прыжка = скорость ходьбы × фактор
		BackWalkFactor = 0.8, -- назад ходят медленнее
		DashFrames = 16,
		DashDistance = 5.5,
		BackdashFrames = 18,
		BackdashDistance = 4.5,
		BackdashInvulnerableFrames = 5,
		DoubleTapWindow = 12, -- кадры между двумя нажатиями направления для рывка
		-- Размеры тела (относительно ног бойца).
		PushWidth = 2.0,
		StandHeight = 5.6,
		CrouchHeight = 3.8,
		AirPushBottom = 1.5, -- в воздухе «толкающий» прямоугольник поднят: можно перепрыгнуть
		AirPushTop = 4.5,
	},

	Input = {
		BufferFrames = 8, -- нажатие «запоминается» на столько кадров
		MaxPacketsPerSecond = 75, -- лимит пакетов ввода от одного игрока
	},

	Net = {
		SnapshotRate = 30, -- снапшотов в секунду
		InterpolationDelay = 0.05, -- секунды задержки отрисовки для плавной интерполяции
	},
})

return GameConfig
