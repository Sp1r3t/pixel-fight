--!strict
--[[
	Позы детализированного бойца (Sprites/Rig): скелет с локтями и коленями.

	Углы в градусах, смотрим вправо:
	  • lean — наклон корпуса вперёд (+) / назад (−); head — дополнительный наклон головы;
	  • sF / sB — плечо передней / задней руки: 0 — вниз, 90 — вперёд, 180 — вверх;
	    eF / eB — сгиб локтя: предплечье = плечо + сгиб (кулаки у лица — плечо ~40, сгиб ~110);
	  • hF / hB — бедро передней / задней ноги: 0 — вниз, + вперёд; kF / kB — сгиб колена:
	    голень = бедро − сгиб (колено сгибается назад);
	  • hip — высота бёдер (доля клетки спрайта, 0 — верх); если нет — ставим на пол по нижней ступне;
	  • drop — проседание (дыхание, шаги); x — сдвиг вперёд; rot — поворот всего тела (сальто, вертушки);
	  • glow — свечение магии в руках (0..1); aura — свечение вокруг тела (суперы);
	  • strike — какая часть оставляет шлейф удара: "handF" | "handB" | "footF" | "footB" | "weapon";
	  • open — открытые ладони (магия, толчки) вместо кулаков.

	Анимации ударов проигрываются по фреймдате (startup → active → recovery ↦ прогресс 0..1),
	поэтому поза «удара» всегда совпадает с активными кадрами на сервере.
	Особые приёмы — свои для каждого типа (SPECIALS), суперы — по способу доставки (SUPERS).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)

export type Pose = {
	lean: number,
	head: number?,
	sF: number,
	eF: number,
	sB: number,
	eB: number,
	hF: number,
	kF: number,
	hB: number,
	kB: number,
	hip: number?,
	drop: number?,
	x: number?,
	rot: number?,
	glow: number?,
	aura: number?,
	strike: string?,
	open: boolean?,
}

type Keys = { Pose }

-- Стойка: кулаки у лица, колени чуть согнуты.
local GUARD: Pose = { lean = 6, sF = 40, eF = 105, sB = 25, eB = 115, hF = 22, kF = 18, hB = -16, kB = 14 }

local function with(base: Pose, changes: { [string]: any }): Pose
	local pose = table.clone(base) :: any
	for key, value in changes do
		pose[key] = value
	end
	return pose :: Pose
end

local COMMON: { [string]: Keys } = {
	Idle = {
		GUARD,
		with(GUARD, { lean = 7, drop = 0.006, sF = 42, sB = 27 }),
		with(GUARD, { lean = 8, drop = 0.01, sF = 44, sB = 29, head = 2 }),
		with(GUARD, { lean = 7, drop = 0.006, sF = 42, sB = 27 }),
	},
	Walk = {
		with(GUARD, { hF = 30, kF = 10, hB = -22, kB = 20, sF = 34, sB = 30 }),
		with(GUARD, { hF = 12, kF = 30, hB = -8, kB = 8, drop = 0.012 }),
		with(GUARD, { hF = -6, kF = 12, hB = 14, kB = 40, drop = 0.004, sF = 46, sB = 22 }),
		with(GUARD, { hF = -22, kF = 20, hB = 30, kB = 10, sF = 48, sB = 20 }),
		with(GUARD, { hF = -8, kF = 8, hB = 12, kB = 30, drop = 0.012 }),
		with(GUARD, { hF = 14, kF = 40, hB = -6, kB = 12, drop = 0.004, sF = 36, sB = 28 }),
	},
	Dash = {
		{ lean = 22, sF = -20, eF = 30, sB = -40, eB = 30, hF = 40, kF = 30, hB = -40, kB = 50 },
		{ lean = 32, sF = -40, eF = 20, sB = -60, eB = 20, hF = 58, kF = 20, hB = -55, kB = 60, drop = 0.03 },
		{ lean = 28, sF = -30, eF = 25, sB = -50, eB = 25, hF = 48, kF = 25, hB = -45, kB = 55, drop = 0.02 },
		with(GUARD, { lean = 12 }),
	},
	Jump = {
		{ lean = 4, sF = 160, eF = 10, sB = 140, eB = 10, hF = 20, kF = 30, hB = -10, kB = 40, hip = 0.58 },
		{ lean = 10, sF = 110, eF = 60, sB = 90, eB = 70, hF = 95, kF = 120, hB = 70, kB = 110, hip = 0.56 },
		{ lean = 8, sF = 80, eF = 70, sB = 60, eB = 80, hF = 70, kF = 80, hB = 40, kB = 70, hip = 0.57 },
		{ lean = 4, sF = 60, eF = 60, sB = 40, eB = 70, hF = 30, kF = 30, hB = -5, kB = 20, hip = 0.6 },
	},
	Crouch = {
		with(GUARD, { lean = 14, hF = 60, kF = 110, hB = -10, kB = 115, sF = 50, sB = 35 }),
		with(GUARD, { lean = 18, hF = 70, kF = 125, hB = -5, kB = 130, sF = 55, sB = 40 }),
	},
	Block = {
		{ lean = -4, head = -6, sF = 70, eF = 120, sB = 60, eB = 125, hF = 26, kF = 22, hB = -24, kB = 20, x = -0.01 },
		{ lean = -8, head = -8, sF = 76, eF = 125, sB = 66, eB = 128, hF = 26, kF = 24, hB = -26, kB = 22, x = -0.015 },
	},
	-- «Рука»: прямой удар — замах, выпрямленная рука, удержание, возврат в стойку.
	Light = {
		with(GUARD, { sF = 30, eF = 120, lean = 4 }),
		with(GUARD, { sF = 92, eF = 0, lean = 16, x = 0.03, hF = 30, strike = "handF", head = 4 }),
		with(GUARD, { sF = 90, eF = 4, lean = 16, x = 0.03, hF = 30, strike = "handF", head = 4 }),
		with(GUARD, { sF = 50, eF = 90, lean = 8 }),
	},
	-- «Нога»: высокий удар ногой с разворотом корпуса.
	Heavy = {
		with(GUARD, { lean = -4, hF = 40, kF = 90, sF = 55, sB = 50 }),
		with(GUARD, { lean = -14, hF = 80, kF = 70, sF = 30, eF = 60, sB = 70, eB = 60 }),
		with(GUARD, { lean = -22, hF = 105, kF = 0, sF = 20, eF = 50, sB = 80, eB = 50, x = 0.02, strike = "footF" }),
		with(GUARD, { lean = -22, hF = 102, kF = 4, sF = 20, eF = 50, sB = 80, eB = 50, x = 0.02, strike = "footF" }),
		with(GUARD, { lean = -6, hF = 45, kF = 60 }),
	},
	CrouchLight = {
		with(GUARD, { lean = 16, hF = 60, kF = 110, hB = -10, kB = 115, sF = 50, eF = 100 }),
		with(GUARD, { lean = 22, hF = 62, kF = 112, hB = -8, kB = 118, sF = 88, eF = 0, x = 0.03, strike = "handF" }),
		with(GUARD, { lean = 16, hF = 60, kF = 110, hB = -10, kB = 115, sF = 55, eF = 90 }),
	},
	-- Подсечка: низкий удар ногой с опорой на руку.
	CrouchHeavy = {
		with(GUARD, { lean = 20, hF = 60, kF = 110, hB = -10, kB = 115 }),
		{ lean = 34, sF = 20, eF = 40, sB = 10, eB = 20, hF = 80, kF = 20, hB = -30, kB = 130, hip = 0.8 },
		{
			lean = 38,
			sF = 10,
			eF = 30,
			sB = 5,
			eB = 10,
			hF = 92,
			kF = 0,
			hB = -40,
			kB = 135,
			hip = 0.83,
			x = 0.02,
			strike = "footF",
		},
		with(GUARD, { lean = 18, hF = 60, kF = 110, hB = -10, kB = 115 }),
	},
	AirLight = {
		{ lean = 6, sF = 60, eF = 90, sB = 90, eB = 80, hF = 70, kF = 90, hB = 40, kB = 80, hip = 0.58 },
		{
			lean = 16,
			sF = 110,
			eF = 0,
			sB = 70,
			eB = 90,
			hF = 70,
			kF = 90,
			hB = 40,
			kB = 80,
			hip = 0.58,
			x = 0.03,
			strike = "handF",
		},
		{ lean = 8, sF = 70, eF = 80, sB = 80, eB = 80, hF = 70, kF = 90, hB = 40, kB = 80, hip = 0.58 },
	},
	-- Удар ногой в прыжке: нога вытянута вперёд-вниз.
	AirHeavy = {
		{ lean = -4, sF = 90, eF = 70, sB = 110, eB = 60, hF = 80, kF = 100, hB = 40, kB = 90, hip = 0.56 },
		{
			lean = -14,
			sF = 70,
			eF = 40,
			sB = 120,
			eB = 40,
			hF = 120,
			kF = 0,
			hB = 20,
			kB = 100,
			hip = 0.54,
			x = 0.02,
			strike = "footF",
		},
		{
			lean = -14,
			sF = 70,
			eF = 40,
			sB = 120,
			eB = 40,
			hF = 118,
			kF = 4,
			hB = 20,
			kB = 100,
			hip = 0.54,
			x = 0.02,
			strike = "footF",
		},
		{ lean = -2, sF = 80, eF = 70, sB = 100, eB = 60, hF = 70, kF = 90, hB = 40, kB = 90, hip = 0.57 },
	},
	Hit = {
		{
			lean = -26,
			head = -18,
			sF = -10,
			eF = 40,
			sB = -30,
			eB = 30,
			hF = 12,
			kF = 20,
			hB = -28,
			kB = 16,
			x = -0.03,
		},
		{
			lean = -16,
			head = -10,
			sF = 10,
			eF = 60,
			sB = -10,
			eB = 50,
			hF = 16,
			kF = 20,
			hB = -24,
			kB = 16,
			x = -0.015,
		},
	},
	Knockdown = {
		{ lean = -40, head = -20, sF = 30, eF = 30, sB = 10, eB = 30, hF = 40, kF = 30, hB = 20, kB = 20 },
		{
			lean = -70,
			head = -10,
			sF = 120,
			eF = 20,
			sB = 100,
			eB = 20,
			hF = 70,
			kF = 20,
			hB = 60,
			kB = 30,
			hip = 0.86,
		},
		{ lean = -84, sF = 170, eF = 10, sB = 160, eB = 20, hF = 86, kF = 10, hB = 82, kB = 30, hip = 0.9 },
		{ lean = -86, sF = 175, eF = 10, sB = 165, eB = 20, hF = 88, kF = 10, hB = 84, kB = 30, hip = 0.91 },
	},
	Win = {
		{ lean = -4, sF = 172, eF = 10, sB = 30, eB = 100, hF = 16, kF = 6, hB = -16, kB = 6 },
		{ lean = -6, sF = 176, eF = 4, sB = 28, eB = 105, hF = 16, kF = 6, hB = -16, kB = 6, drop = 0.01 },
		{ lean = -4, sF = 168, eF = 12, sB = 32, eB = 100, hF = 16, kF = 6, hB = -16, kB = 6 },
		{ lean = -2, sF = 160, eF = 20, sB = 35, eB = 95, hF = 16, kF = 6, hB = -16, kB = 6, drop = 0.006 },
	},
	Lose = {
		{ lean = 20, head = 20, sF = 10, eF = 10, sB = 5, eB = 10, hF = 60, kF = 110, hB = 40, kB = 120, hip = 0.76 },
		{ lean = 32, head = 26, sF = 5, eF = 5, sB = 0, eB = 5, hF = 78, kF = 130, hB = 70, kB = 135, hip = 0.8 },
	},
}

-- Общий «разгон» особого приёма и отход после него (середина — своя у каждого типа).
local CHARGE: Pose = with(GUARD, { lean = -6, sF = 10, eF = 60, sB = 0, eB = 60, glow = 0.4, open = true })

local SPECIALS: { [string]: Keys } = {
	-- Энергетический удар ладонями.
	Projectile = {
		CHARGE,
		with(GUARD, { lean = -10, sF = -20, eF = 70, sB = -30, eB = 70, glow = 0.8, open = true, hF = 30, kF = 30 }),
		with(GUARD, {
			lean = 16,
			sF = 88,
			eF = 0,
			sB = 84,
			eB = 6,
			glow = 1,
			open = true,
			x = 0.03,
			hF = 34,
			kF = 20,
			strike = "handF",
		}),
		with(
			GUARD,
			{ lean = 16, sF = 88, eF = 0, sB = 84, eB = 6, glow = 0.8, open = true, x = 0.03, hF = 34, kF = 20 }
		),
		with(GUARD, { lean = 8, sF = 60, eF = 60, glow = 0.3 }),
		GUARD,
	},
	-- Навесной бросок кометы вверх-вперёд.
	ArcProjectile = {
		CHARGE,
		with(GUARD, { lean = -14, sF = 150, eF = 20, sB = 130, eB = 30, glow = 0.9, open = true }),
		with(
			GUARD,
			{ lean = 10, sF = 125, eF = 0, sB = 60, eB = 40, glow = 1, open = true, strike = "handF", x = 0.02 }
		),
		with(GUARD, { lean = 10, sF = 118, eF = 5, sB = 60, eB = 40, glow = 0.6, open = true, x = 0.02 }),
		with(GUARD, { lean = 4, sF = 70, eF = 60, glow = 0.2 }),
		GUARD,
	},
	-- Бросок диска: замах за спину — бросок.
	Boomerang = {
		with(GUARD, { lean = -8, sF = -40, eF = 40, glow = 0.3 }),
		with(GUARD, { lean = -16, sF = -70, eF = 30, sB = 70, eB = 40, glow = 0.6, head = -4 }),
		with(
			GUARD,
			{ lean = 18, sF = 96, eF = 0, sB = -20, eB = 40, glow = 0.8, strike = "handF", x = 0.03, open = true }
		),
		with(GUARD, { lean = 18, sF = 90, eF = 10, sB = -20, eB = 40, glow = 0.4, x = 0.03, open = true }),
		with(GUARD, { lean = 8 }),
		GUARD,
	},
	-- Удар об землю: волна льда.
	GroundWave = {
		with(GUARD, { lean = -8, sF = 160, eF = 10, sB = 150, eB = 10, glow = 0.6, open = true }),
		with(GUARD, { lean = -12, sF = 175, eF = 0, sB = 165, eB = 0, glow = 0.9, open = true, hip = 0.6 }),
		with(GUARD, {
			lean = 34,
			sF = 30,
			eF = 10,
			sB = 20,
			eB = 10,
			glow = 1,
			open = true,
			strike = "handF",
			hF = 60,
			kF = 110,
			hB = -10,
			kB = 115,
		}),
		with(GUARD, {
			lean = 34,
			sF = 28,
			eF = 10,
			sB = 20,
			eB = 10,
			glow = 0.6,
			open = true,
			hF = 60,
			kF = 110,
			hB = -10,
			kB = 115,
		}),
		with(GUARD, { lean = 14, hF = 40, kF = 60 }),
		GUARD,
	},
	-- Реактивный рывок плечом.
	RushStrike = {
		with(GUARD, { lean = 20, hF = 60, kF = 110, hB = -10, kB = 115, glow = 0.4 }),
		{ lean = 50, sF = -60, eF = 20, sB = -70, eB = 20, hF = 20, kF = 30, hB = -50, kB = 60, glow = 0.8, x = 0.02 },
		{
			lean = 58,
			sF = 70,
			eF = 100,
			sB = -60,
			eB = 20,
			hF = 10,
			kF = 20,
			hB = -60,
			kB = 50,
			glow = 1,
			x = 0.04,
			strike = "handF",
		},
		{ lean = 58, sF = 70, eF = 100, sB = -60, eB = 20, hF = 10, kF = 20, hB = -60, kB = 50, glow = 0.8, x = 0.04 },
		with(GUARD, { lean = 20 }),
		GUARD,
	},
	-- Вращающийся удар ногой: два оборота с вытянутой ногой.
	SpinDash = {
		with(GUARD, { lean = 10, hF = 50, kF = 90, glow = 0.3 }),
		with(GUARD, { lean = 0, hF = 90, kF = 0, rot = 90, strike = "footF", sF = 120, eF = 20, sB = 60, eB = 20 }),
		with(GUARD, { lean = 0, hF = 95, kF = 0, rot = 270, strike = "footF", sF = 120, eF = 20, sB = 60, eB = 20 }),
		with(GUARD, { lean = 0, hF = 95, kF = 0, rot = 450, strike = "footF", sF = 120, eF = 20, sB = 60, eB = 20 }),
		with(GUARD, { lean = 0, hF = 90, kF = 0, rot = 630, strike = "footF", sF = 120, eF = 20, sB = 60, eB = 20 }),
		with(GUARD, { rot = 720 }),
	},
	-- Плечевой таран в броне.
	ArmorCharge = {
		with(GUARD, { lean = -6, sF = 30, eF = 120, glow = 0.4, aura = 0.3 }),
		with(GUARD, { lean = 10, sF = 20, eF = 130, sB = 10, eB = 130, glow = 0.7, aura = 0.6, hF = 40, kF = 40 }),
		with(GUARD, {
			lean = 36,
			sF = 60,
			eF = 110,
			sB = 30,
			eB = 120,
			glow = 1,
			aura = 0.8,
			hF = 50,
			kF = 30,
			hB = -40,
			kB = 30,
			x = 0.04,
			strike = "handF",
		}),
		with(GUARD, {
			lean = 36,
			sF = 60,
			eF = 110,
			sB = 30,
			eB = 120,
			glow = 0.8,
			aura = 0.6,
			hF = 50,
			kF = 30,
			hB = -40,
			kB = 30,
			x = 0.04,
		}),
		with(GUARD, { lean = 14 }),
		GUARD,
	},
	-- Неуязвимый апперкот со взлётом и сальто.
	RisingStrike = {
		with(GUARD, { lean = 20, hF = 60, kF = 110, hB = -10, kB = 115, glow = 0.5 }),
		{
			lean = 0,
			sF = 170,
			eF = 0,
			sB = 30,
			eB = 90,
			hF = 30,
			kF = 60,
			hB = -20,
			kB = 90,
			glow = 1,
			strike = "handF",
			hip = 0.5,
		},
		{
			lean = -10,
			sF = 175,
			eF = 0,
			sB = 40,
			eB = 80,
			hF = 60,
			kF = 90,
			hB = 20,
			kB = 100,
			glow = 1,
			strike = "handF",
			hip = 0.46,
			rot = -60,
		},
		{
			lean = 0,
			sF = 120,
			eF = 40,
			sB = 60,
			eB = 80,
			hF = 80,
			kF = 110,
			hB = 50,
			kB = 110,
			glow = 0.6,
			hip = 0.5,
			rot = -300,
		},
		{
			lean = 0,
			sF = 70,
			eF = 70,
			sB = 50,
			eB = 80,
			hF = 40,
			kF = 40,
			hB = 0,
			kB = 40,
			glow = 0.2,
			hip = 0.58,
			rot = -360,
		},
		with(GUARD, { rot = -360 }),
	},
	-- Пике ногой из прыжка.
	DiveKick = {
		{ lean = 4, sF = 150, eF = 20, sB = 130, eB = 20, hF = 60, kF = 90, hB = 30, kB = 80, hip = 0.56, glow = 0.3 },
		{
			lean = -30,
			sF = 160,
			eF = 10,
			sB = 150,
			eB = 10,
			hF = 90,
			kF = 120,
			hB = 60,
			kB = 120,
			hip = 0.54,
			glow = 0.6,
			rot = -20,
		},
		{
			lean = -20,
			sF = 140,
			eF = 20,
			sB = 120,
			eB = 20,
			hF = 60,
			kF = 0,
			hB = 20,
			kB = 100,
			hip = 0.54,
			glow = 1,
			rot = 40,
			strike = "footF",
		},
		{
			lean = -20,
			sF = 140,
			eF = 20,
			sB = 120,
			eB = 20,
			hF = 60,
			kF = 0,
			hB = 20,
			kB = 100,
			hip = 0.54,
			glow = 0.8,
			rot = 40,
			strike = "footF",
		},
		{ lean = 0, sF = 60, eF = 70, sB = 40, eB = 70, hF = 40, kF = 60, hB = 0, kB = 60, hip = 0.58 },
		GUARD,
	},
	-- Прыжок с мечом над головой и рубящий удар.
	OverheadLeap = {
		with(GUARD, { lean = 10, hF = 60, kF = 110, hB = -10, kB = 115, sF = 20, eF = 80, glow = 0.4 }),
		{
			lean = -10,
			sF = 175,
			eF = 20,
			sB = 170,
			eB = 30,
			hF = 70,
			kF = 100,
			hB = 20,
			kB = 100,
			hip = 0.5,
			glow = 0.8,
		},
		{
			lean = 30,
			sF = 60,
			eF = 0,
			sB = 55,
			eB = 10,
			hF = 60,
			kF = 70,
			hB = -10,
			kB = 60,
			hip = 0.54,
			glow = 1,
			strike = "weapon",
		},
		{
			lean = 34,
			sF = 40,
			eF = 0,
			sB = 35,
			eB = 10,
			hF = 50,
			kF = 90,
			hB = -20,
			kB = 100,
			glow = 0.8,
			strike = "weapon",
		},
		with(GUARD, { lean = 16, hF = 50, kF = 80 }),
		GUARD,
	},
	-- Исчезновение: печать руками, тень.
	Teleport = {
		with(GUARD, { lean = 10, sF = 60, eF = 100, sB = 70, eB = 90, glow = 0.5, open = true }),
		with(GUARD, {
			lean = 14,
			sF = 80,
			eF = 90,
			sB = 85,
			eB = 85,
			glow = 1,
			open = true,
			hF = 50,
			kF = 90,
			hB = -10,
			kB = 100,
		}),
		with(GUARD, { lean = 20, sF = 90, eF = 0, sB = -30, eB = 20, glow = 1, strike = "handF", x = 0.03 }),
		with(GUARD, { lean = 20, sF = 88, eF = 5, sB = -30, eB = 20, glow = 0.6, x = 0.03 }),
		with(GUARD, { lean = 8 }),
		GUARD,
	},
	-- Спокойная стойка контратаки: ладони вместе.
	Counter = {
		with(GUARD, { lean = -2, sF = 70, eF = 110, sB = 70, eB = 110, glow = 0.6, open = true, aura = 0.3 }),
		with(GUARD, {
			lean = -4,
			sF = 75,
			eF = 115,
			sB = 75,
			eB = 115,
			glow = 0.9,
			open = true,
			aura = 0.5,
			hF = 20,
			kF = 30,
			hB = -20,
			kB = 30,
		}),
		with(
			GUARD,
			{ lean = 18, sF = 90, eF = 0, sB = 80, eB = 10, glow = 1, open = true, strike = "handF", x = 0.03 }
		),
		with(GUARD, { lean = 18, sF = 88, eF = 4, sB = 80, eB = 10, glow = 0.7, open = true, x = 0.03 }),
		with(GUARD, { lean = 6 }),
		GUARD,
	},
	-- Захват: руки вперёд.
	CommandGrab = {
		with(GUARD, { lean = 6, sF = 60, eF = 60, sB = 50, eB = 60, glow = 0.3, open = true }),
		with(GUARD, { lean = 26, sF = 80, eF = 30, sB = 75, eB = 30, open = true, x = 0.02, hF = 40, kF = 30 }),
		with(
			GUARD,
			{ lean = 30, sF = 92, eF = 5, sB = 88, eB = 5, open = true, x = 0.04, strike = "handF", hF = 44, kF = 30 }
		),
		with(GUARD, { lean = 30, sF = 90, eF = 10, sB = 86, eB = 10, open = true, x = 0.04 }),
		with(GUARD, { lean = 10 }),
		GUARD,
	},
	-- Крюк на цепи: бросок и рывок на себя.
	Hook = {
		with(GUARD, { lean = -8, sF = -30, eF = 60, glow = 0.4 }),
		with(GUARD, { lean = -12, sF = 150, eF = 40, glow = 0.7, head = -4 }),
		with(GUARD, { lean = 16, sF = 95, eF = 0, sB = 30, eB = 90, glow = 1, strike = "handF", x = 0.03 }),
		with(GUARD, { lean = -6, sF = 60, eF = 90, sB = 30, eB = 100, glow = 0.6, x = -0.01 }),
		with(GUARD, { lean = 0 }),
		GUARD,
	},
	-- Выпад копьём.
	LongThrust = {
		with(GUARD, { lean = -8, sF = 60, eF = 60, sB = 40, eB = 80, glow = 0.3 }),
		with(
			GUARD,
			{ lean = -14, sF = 40, eF = 80, sB = 20, eB = 90, glow = 0.6, hF = 30, kF = 50, hB = -30, kB = 20 }
		),
		with(GUARD, {
			lean = 26,
			sF = 88,
			eF = 0,
			sB = 80,
			eB = 20,
			glow = 1,
			x = 0.05,
			hF = 60,
			kF = 40,
			hB = -50,
			kB = 10,
			strike = "weapon",
		}),
		with(
			GUARD,
			{ lean = 26, sF = 88, eF = 0, sB = 80, eB = 20, glow = 0.7, x = 0.05, hF = 60, kF = 40, hB = -50, kB = 10 }
		),
		with(GUARD, { lean = 8 }),
		GUARD,
	},
	-- Ловушка: бросок вниз.
	Trap = {
		with(GUARD, { lean = 0, sF = 120, eF = 40, glow = 0.4 }),
		with(GUARD, { lean = -6, sF = 150, eF = 30, glow = 0.7, open = true }),
		with(GUARD, { lean = 24, sF = 50, eF = 0, glow = 1, open = true, strike = "handF", hF = 40, kF = 60 }),
		with(GUARD, { lean = 24, sF = 45, eF = 5, glow = 0.6, open = true, hF = 40, kF = 60 }),
		with(GUARD, { lean = 8 }),
		GUARD,
	},
}

-- Суперы: разгон (руки вверх, свечение, аура) → удар в духе способа доставки → отход.
local POWER1: Pose = with(GUARD, { lean = -4, sF = 100, eF = 110, sB = 95, eB = 115, glow = 0.6, aura = 0.6 })
local POWER2: Pose = with(
	GUARD,
	{ lean = -10, head = -10, sF = 170, eF = 10, sB = 160, eB = 20, glow = 1, aura = 1, open = true, hip = 0.6 }
)
local RECOVER: Pose = with(GUARD, { lean = 8, glow = 0.3, aura = 0.3 })

local function superKeys(strike: { Pose }): Keys
	local keys: Keys = { POWER1, POWER2, POWER2 }
	for _, pose in strike do
		table.insert(keys, pose)
	end
	table.insert(keys, RECOVER)
	table.insert(keys, GUARD)
	return keys
end

local SUPERS: { [string]: Keys } = {
	Rush = superKeys({
		{
			lean = 44,
			sF = 92,
			eF = 0,
			sB = -50,
			eB = 30,
			hF = 40,
			kF = 30,
			hB = -50,
			kB = 50,
			glow = 1,
			aura = 1,
			x = 0.05,
			strike = "handF",
		},
		{
			lean = 40,
			sF = 90,
			eF = 5,
			sB = -50,
			eB = 30,
			hF = 40,
			kF = 30,
			hB = -50,
			kB = 50,
			glow = 0.8,
			aura = 0.8,
			x = 0.05,
		},
	}),
	Launcher = superKeys({
		{
			lean = 0,
			sF = 175,
			eF = 0,
			sB = 30,
			eB = 90,
			hF = 30,
			kF = 60,
			hB = -20,
			kB = 90,
			glow = 1,
			aura = 1,
			hip = 0.5,
			strike = "handF",
		},
		{
			lean = -6,
			sF = 170,
			eF = 10,
			sB = 40,
			eB = 80,
			hF = 60,
			kF = 90,
			hB = 20,
			kB = 100,
			glow = 0.8,
			aura = 0.8,
			hip = 0.52,
		},
	}),
	Beam = superKeys({
		{
			lean = 18,
			sF = 90,
			eF = 0,
			sB = 86,
			eB = 4,
			hF = 40,
			kF = 40,
			hB = -40,
			kB = 20,
			glow = 1,
			aura = 1,
			open = true,
			x = 0.02,
			strike = "handF",
		},
		{
			lean = 18,
			sF = 90,
			eF = 0,
			sB = 86,
			eB = 4,
			hF = 40,
			kF = 40,
			hB = -40,
			kB = 20,
			glow = 1,
			aura = 0.9,
			open = true,
			x = 0.02,
		},
	}),
	Barrage = superKeys({
		with(GUARD, { lean = 18, sF = 92, eF = 0, sB = 40, eB = 110, glow = 1, aura = 1, x = 0.03, strike = "handF" }),
		with(GUARD, { lean = 18, sF = 40, eF = 110, sB = 92, eB = 0, glow = 1, aura = 1, x = 0.03, strike = "handB" }),
	}),
	Grab = superKeys({
		with(
			GUARD,
			{ lean = 30, sF = 92, eF = 5, sB = 88, eB = 5, glow = 1, aura = 1, open = true, x = 0.04, strike = "handF" }
		),
		with(GUARD, { lean = 30, sF = 90, eF = 10, sB = 86, eB = 10, glow = 0.8, aura = 0.8, open = true, x = 0.04 }),
	}),
	Counter = superKeys({
		with(GUARD, { lean = -4, sF = 75, eF = 115, sB = 75, eB = 115, glow = 1, aura = 1, open = true }),
		with(GUARD, {
			lean = 18,
			sF = 90,
			eF = 0,
			sB = 80,
			eB = 10,
			glow = 1,
			aura = 1,
			open = true,
			x = 0.03,
			strike = "handF",
		}),
	}),
}

local RigPoses = {}

RigPoses.GUARD = GUARD
RigPoses.COMMON = COMMON
RigPoses.SPECIALS = SPECIALS
RigPoses.SUPERS = SUPERS

-- Ключевые позы анимации для персонажа: особый приём — по типу, супер — по способу доставки.
function RigPoses.keys(animation: Types.AnimationName, def: Types.CharacterDef): Keys
	if animation == "Special" then
		return SPECIALS[def.special.kind] or SPECIALS.Projectile
	elseif animation == "Super" then
		return SUPERS[def.super.delivery] or SUPERS.Rush
	end
	return COMMON[animation] or COMMON.Idle
end

local NUMERIC = { "lean", "head", "sF", "eF", "sB", "eB", "hF", "kF", "hB", "kB", "drop", "x", "rot", "glow", "aura" }

-- Плавный переход между двумя позами (t = 0..1).
function RigPoses.lerp(a: Pose, b: Pose, t: number): Pose
	local result = {} :: any
	local ra, rb = a :: any, b :: any
	for _, key in NUMERIC do
		local from = ra[key] or 0
		local to = rb[key] or 0
		result[key] = from + (to - from) * t
	end
	if a.hip and b.hip then
		result.hip = a.hip + (b.hip - a.hip) * t
	else
		result.hip = if t < 0.5 then a.hip else b.hip
	end
	result.strike = if t < 0.5 then a.strike else b.strike
	result.open = if t < 0.5 then a.open else b.open
	return result :: Pose
end

return RigPoses
