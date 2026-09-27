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
		AirJumpFactor = 0.9, -- двойной прыжок (2 на 2): доля скорости обычного прыжка
		AirControlSpeed = 0.85, -- управление в воздухе (2 на 2): доля скорости ходьбы
		AirAcceleration = 60, -- студ/с² разгона в воздухе
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

	-- Боевые правила (общие для всех персонажей).
	Combat = {
		-- Хитстоп: «замирание» обоих бойцов при попадании, кадры.
		HitstopBase = 5,
		HitstopPerDamage = 1 / 18,
		HitstopMax = 14,
		BlockHitstopFactor = 0.7,
		-- Масштабирование урона в комбо: каждый следующий удар слабее, но не меньше минимума.
		ComboScalingPerHit = 0.1,
		ComboScalingMin = 0.4,
		-- Контрудар (попадание в противника, который сам начал атаку).
		CounterHitDamage = 1.2,
		CounterHitStun = 4,
		-- Шкала супера: сколько единиц за 1 урон (с учётом множителя персонажа).
		MeterPerDamageDealt = 1.4,
		MeterPerDamageTaken = 0.8,
		MeterBlockFactor = 0.5, -- на блоке шкала растёт слабее
		-- Нокдаун: лежит, затем встаёт (в обоих состояниях неуязвим).
		KnockdownFrames = 36,
		WakeUpFrames = 14,
		AirHitPop = 16, -- студ/с вверх, когда попали по бойцу в воздухе
		PushFriction = 0.82, -- затухание отбрасывания за кадр
		ProximityGuardRange = 9, -- на таком расстоянии от атакующего «назад» = стойка блока
		CancelWindow = 10, -- кадров после активных, когда можно отменить удар в следующий
		SpecialCooldownFrames = 20,
		SuperFreezeFrames = 24, -- вспышка супера: всё замирает
		MaxLagCompensationFrames = 6, -- компенсация пинга: не больше 100 мс
		HurtboxWidth = 2.2,
		WakeUpInvulnerable = true,
	},

	Input = {
		BufferFrames = 8, -- нажатие «запоминается» на столько кадров
		MaxPacketsPerSecond = 75, -- лимит пакетов ввода от одного игрока
	},

	Net = {
		SnapshotRate = 30, -- снапшотов в секунду
		InterpolationDelay = 0.05, -- секунды задержки отрисовки для плавной интерполяции
	},

	-- Режим 2 на 2: четыре бойца одновременно на сцене с двумя этажами (Combat/Stage, TwoFloors).
	Team = {
		Size = 2,
	},

	Matchmaking = {
		TicketSeconds = 60, -- срок жизни записи в межсерверной очереди (продлевается, пока игрок ждёт)
		PollSeconds = 2, -- как часто сервер пытается собрать матч из межсерверной очереди
		ArrivalSeconds = 30, -- сколько сервер матча ждёт игроков после телепорта
		RoomCodeLength = 6,
		RoomSeconds = 900, -- сколько живёт приватная комната
		WinReward = 15, -- монеты за победу в матче из очереди
		BotFillSeconds = 20, -- столько ждём соперников в очереди, потом добавляем ботов
		BotLevel = 8, -- уровень ИИ ботов (кривая сложности боссов)
		BotWinReward = 5, -- монеты за победу в матче с ботами
	},
})

return GameConfig
