"use strict";
/*
	Порт поз из src/client/Sprites/RigPoses.luau — те же цифры, тот же скелет
	(бёдра → корпус → шея → голова; плечо → локоть → кисть; бедро → колено → стопа),
	просто используются здесь для рендера пиксельных кадров вместо Roblox Frame.
	См. комментарий в RigPoses.luau за расшифровкой полей.
*/

const GUARD = { lean: 6, sF: 40, eF: 105, sB: 25, eB: 115, hF: 22, kF: 18, hB: -16, kB: 14 };

function w(base, changes) {
	return Object.assign({}, base, changes);
}

const COMMON = {
	// Спокойное дыхание: почти не меняется, лёгкое покачивание — не «рывок» вперёд-назад.
	Idle: [
		GUARD,
		w(GUARD, { lean: 6.3, drop: 0.003, sF: 41, sB: 26 }),
		w(GUARD, { lean: 6.6, drop: 0.006, sF: 42, sB: 27, head: 1 }),
		w(GUARD, { lean: 6.6, drop: 0.007, sF: 42, sB: 27, head: 1 }),
		w(GUARD, { lean: 6.3, drop: 0.003, sF: 41, sB: 26 }),
		GUARD,
	],
	Walk: [
		w(GUARD, { hF: 30, kF: 10, hB: -22, kB: 20, sF: 34, sB: 30 }),
		w(GUARD, { hF: 12, kF: 30, hB: -8, kB: 8, drop: 0.012 }),
		w(GUARD, { hF: -6, kF: 12, hB: 14, kB: 40, drop: 0.004, sF: 46, sB: 22 }),
		w(GUARD, { hF: -22, kF: 20, hB: 30, kB: 10, sF: 48, sB: 20 }),
		w(GUARD, { hF: -8, kF: 8, hB: 12, kB: 30, drop: 0.012 }),
		w(GUARD, { hF: 14, kF: 40, hB: -6, kB: 12, drop: 0.004, sF: 36, sB: 28 }),
	],
	Dash: [
		{ lean: 22, sF: -20, eF: 30, sB: -40, eB: 30, hF: 40, kF: 30, hB: -40, kB: 50 },
		{ lean: 32, sF: -40, eF: 20, sB: -60, eB: 20, hF: 58, kF: 20, hB: -55, kB: 60, drop: 0.03 },
		{ lean: 28, sF: -30, eF: 25, sB: -50, eB: 25, hF: 48, kF: 25, hB: -45, kB: 55, drop: 0.02 },
		w(GUARD, { lean: 12 }),
	],
	Jump: [
		{ lean: 4, sF: 160, eF: 10, sB: 140, eB: 10, hF: 20, kF: 30, hB: -10, kB: 40, hip: 0.58 },
		{ lean: 10, sF: 110, eF: 60, sB: 90, eB: 70, hF: 95, kF: 120, hB: 70, kB: 110, hip: 0.56 },
		{ lean: 8, sF: 80, eF: 70, sB: 60, eB: 80, hF: 70, kF: 80, hB: 40, kB: 70, hip: 0.57 },
		{ lean: 4, sF: 60, eF: 60, sB: 40, eB: 70, hF: 30, kF: 30, hB: -5, kB: 20, hip: 0.6 },
	],
	Crouch: [
		w(GUARD, { lean: 14, hF: 60, kF: 110, hB: -10, kB: 115, sF: 50, sB: 35 }),
		w(GUARD, { lean: 18, hF: 70, kF: 125, hB: -5, kB: 130, sF: 55, sB: 40 }),
	],
	Block: [
		{ lean: -4, head: -6, sF: 70, eF: 120, sB: 60, eB: 125, hF: 26, kF: 22, hB: -24, kB: 20, x: -0.01 },
		{ lean: -8, head: -8, sF: 76, eF: 125, sB: 66, eB: 128, hF: 26, kF: 24, hB: -26, kB: 22, x: -0.015 },
	],
	Light: [
		w(GUARD, { sF: 30, eF: 120, lean: 4 }),
		w(GUARD, { sF: 92, eF: 0, lean: 16, x: 0.03, hF: 30, strike: "handF", head: 4 }),
		w(GUARD, { sF: 90, eF: 4, lean: 16, x: 0.03, hF: 30, strike: "handF", head: 4 }),
		w(GUARD, { sF: 50, eF: 90, lean: 8 }),
	],
	Heavy: [
		w(GUARD, { lean: -4, hF: 40, kF: 90, sF: 55, sB: 50 }),
		w(GUARD, { lean: -14, hF: 80, kF: 70, sF: 30, eF: 60, sB: 70, eB: 60 }),
		w(GUARD, { lean: -22, hF: 105, kF: 0, sF: 20, eF: 50, sB: 80, eB: 50, x: 0.02, strike: "footF" }),
		w(GUARD, { lean: -22, hF: 102, kF: 4, sF: 20, eF: 50, sB: 80, eB: 50, x: 0.02, strike: "footF" }),
		w(GUARD, { lean: -6, hF: 45, kF: 60 }),
	],
	CrouchLight: [
		w(GUARD, { lean: 16, hF: 60, kF: 110, hB: -10, kB: 115, sF: 50, eF: 100 }),
		w(GUARD, { lean: 22, hF: 62, kF: 112, hB: -8, kB: 118, sF: 88, eF: 0, x: 0.03, strike: "handF" }),
		w(GUARD, { lean: 16, hF: 60, kF: 110, hB: -10, kB: 115, sF: 55, eF: 90 }),
	],
	CrouchHeavy: [
		w(GUARD, { lean: 20, hF: 60, kF: 110, hB: -10, kB: 115 }),
		{ lean: 34, sF: 20, eF: 40, sB: 10, eB: 20, hF: 80, kF: 20, hB: -30, kB: 130, hip: 0.8 },
		{ lean: 38, sF: 10, eF: 30, sB: 5, eB: 10, hF: 92, kF: 0, hB: -40, kB: 135, hip: 0.83, x: 0.02, strike: "footF" },
		w(GUARD, { lean: 18, hF: 60, kF: 110, hB: -10, kB: 115 }),
	],
	AirLight: [
		{ lean: 6, sF: 60, eF: 90, sB: 90, eB: 80, hF: 70, kF: 90, hB: 40, kB: 80, hip: 0.58 },
		{ lean: 16, sF: 110, eF: 0, sB: 70, eB: 90, hF: 70, kF: 90, hB: 40, kB: 80, hip: 0.58, x: 0.03, strike: "handF" },
		{ lean: 8, sF: 70, eF: 80, sB: 80, eB: 80, hF: 70, kF: 90, hB: 40, kB: 80, hip: 0.58 },
	],
	AirHeavy: [
		{ lean: -4, sF: 90, eF: 70, sB: 110, eB: 60, hF: 80, kF: 100, hB: 40, kB: 90, hip: 0.56 },
		{ lean: -14, sF: 70, eF: 40, sB: 120, eB: 40, hF: 120, kF: 0, hB: 20, kB: 100, hip: 0.54, x: 0.02, strike: "footF" },
		{ lean: -14, sF: 70, eF: 40, sB: 120, eB: 40, hF: 118, kF: 4, hB: 20, kB: 100, hip: 0.54, x: 0.02, strike: "footF" },
		{ lean: -2, sF: 80, eF: 70, sB: 100, eB: 60, hF: 70, kF: 90, hB: 40, kB: 90, hip: 0.57 },
	],
	Hit: [
		{ lean: -26, head: -18, sF: -10, eF: 40, sB: -30, eB: 30, hF: 12, kF: 20, hB: -28, kB: 16, x: -0.03 },
		{ lean: -16, head: -10, sF: 10, eF: 60, sB: -10, eB: 50, hF: 16, kF: 20, hB: -24, kB: 16, x: -0.015 },
	],
	Knockdown: [
		{ lean: -40, head: -20, sF: 30, eF: 30, sB: 10, eB: 30, hF: 40, kF: 30, hB: 20, kB: 20 },
		{ lean: -70, head: -10, sF: 120, eF: 20, sB: 100, eB: 20, hF: 70, kF: 20, hB: 60, kB: 30, hip: 0.86 },
		{ lean: -84, sF: 170, eF: 10, sB: 160, eB: 20, hF: 86, kF: 10, hB: 82, kB: 30, hip: 0.9 },
		{ lean: -86, sF: 175, eF: 10, sB: 165, eB: 20, hF: 88, kF: 10, hB: 84, kB: 30, hip: 0.91 },
	],
	Win: [
		{ lean: -4, sF: 172, eF: 10, sB: 30, eB: 100, hF: 16, kF: 6, hB: -16, kB: 6 },
		{ lean: -6, sF: 176, eF: 4, sB: 28, eB: 105, hF: 16, kF: 6, hB: -16, kB: 6, drop: 0.01 },
		{ lean: -4, sF: 168, eF: 12, sB: 32, eB: 100, hF: 16, kF: 6, hB: -16, kB: 6 },
		{ lean: -2, sF: 160, eF: 20, sB: 35, eB: 95, hF: 16, kF: 6, hB: -16, kB: 6, drop: 0.006 },
	],
	Lose: [
		{ lean: 20, head: 20, sF: 10, eF: 10, sB: 5, eB: 10, hF: 60, kF: 110, hB: 40, kB: 120, hip: 0.76 },
		{ lean: 32, head: 26, sF: 5, eF: 5, sB: 0, eB: 5, hF: 78, kF: 130, hB: 70, kB: 135, hip: 0.8 },
	],
};

const CHARGE = w(GUARD, { lean: -6, sF: 10, eF: 60, sB: 0, eB: 60, glow: 0.4, open: true });

const SPECIALS = {
	Projectile: [
		CHARGE,
		w(GUARD, { lean: -10, sF: -20, eF: 70, sB: -30, eB: 70, glow: 0.8, open: true, hF: 30, kF: 30 }),
		w(GUARD, { lean: 16, sF: 88, eF: 0, sB: 84, eB: 6, glow: 1, open: true, x: 0.03, hF: 34, kF: 20, strike: "handF" }),
		w(GUARD, { lean: 16, sF: 88, eF: 0, sB: 84, eB: 6, glow: 0.8, open: true, x: 0.03, hF: 34, kF: 20 }),
		w(GUARD, { lean: 8, sF: 60, eF: 60, glow: 0.3 }),
		GUARD,
	],
	ArcProjectile: [
		CHARGE,
		w(GUARD, { lean: -14, sF: 150, eF: 20, sB: 130, eB: 30, glow: 0.9, open: true }),
		w(GUARD, { lean: 10, sF: 125, eF: 0, sB: 60, eB: 40, glow: 1, open: true, strike: "handF", x: 0.02 }),
		w(GUARD, { lean: 10, sF: 118, eF: 5, sB: 60, eB: 40, glow: 0.6, open: true, x: 0.02 }),
		w(GUARD, { lean: 4, sF: 70, eF: 60, glow: 0.2 }),
		GUARD,
	],
	Boomerang: [
		w(GUARD, { lean: -8, sF: -40, eF: 40, glow: 0.3 }),
		w(GUARD, { lean: -16, sF: -70, eF: 30, sB: 70, eB: 40, glow: 0.6, head: -4 }),
		w(GUARD, { lean: 18, sF: 96, eF: 0, sB: -20, eB: 40, glow: 0.8, strike: "handF", x: 0.03, open: true }),
		w(GUARD, { lean: 18, sF: 90, eF: 10, sB: -20, eB: 40, glow: 0.4, x: 0.03, open: true }),
		w(GUARD, { lean: 8 }),
		GUARD,
	],
	GroundWave: [
		w(GUARD, { lean: -8, sF: 160, eF: 10, sB: 150, eB: 10, glow: 0.6, open: true }),
		w(GUARD, { lean: -12, sF: 175, eF: 0, sB: 165, eB: 0, glow: 0.9, open: true, hip: 0.6 }),
		w(GUARD, { lean: 34, sF: 30, eF: 10, sB: 20, eB: 10, glow: 1, open: true, strike: "handF", hF: 60, kF: 110, hB: -10, kB: 115 }),
		w(GUARD, { lean: 34, sF: 28, eF: 10, sB: 20, eB: 10, glow: 0.6, open: true, hF: 60, kF: 110, hB: -10, kB: 115 }),
		w(GUARD, { lean: 14, hF: 40, kF: 60 }),
		GUARD,
	],
	RushStrike: [
		w(GUARD, { lean: 20, hF: 60, kF: 110, hB: -10, kB: 115, glow: 0.4 }),
		{ lean: 50, sF: -60, eF: 20, sB: -70, eB: 20, hF: 20, kF: 30, hB: -50, kB: 60, glow: 0.8, x: 0.02 },
		{ lean: 58, sF: 70, eF: 100, sB: -60, eB: 20, hF: 10, kF: 20, hB: -60, kB: 50, glow: 1, x: 0.04, strike: "handF" },
		{ lean: 58, sF: 70, eF: 100, sB: -60, eB: 20, hF: 10, kF: 20, hB: -60, kB: 50, glow: 0.8, x: 0.04 },
		w(GUARD, { lean: 20 }),
		GUARD,
	],
	SpinDash: [
		w(GUARD, { lean: 10, hF: 50, kF: 90, glow: 0.3 }),
		w(GUARD, { lean: 0, hF: 90, kF: 0, rot: 90, strike: "footF", sF: 120, eF: 20, sB: 60, eB: 20 }),
		w(GUARD, { lean: 0, hF: 95, kF: 0, rot: 270, strike: "footF", sF: 120, eF: 20, sB: 60, eB: 20 }),
		w(GUARD, { lean: 0, hF: 95, kF: 0, rot: 450, strike: "footF", sF: 120, eF: 20, sB: 60, eB: 20 }),
		w(GUARD, { lean: 0, hF: 90, kF: 0, rot: 630, strike: "footF", sF: 120, eF: 20, sB: 60, eB: 20 }),
		w(GUARD, { rot: 720 }),
	],
	ArmorCharge: [
		w(GUARD, { lean: -6, sF: 30, eF: 120, glow: 0.4, aura: 0.3 }),
		w(GUARD, { lean: 10, sF: 20, eF: 130, sB: 10, eB: 130, glow: 0.7, aura: 0.6, hF: 40, kF: 40 }),
		w(GUARD, { lean: 36, sF: 60, eF: 110, sB: 30, eB: 120, glow: 1, aura: 0.8, hF: 50, kF: 30, hB: -40, kB: 30, x: 0.04, strike: "handF" }),
		w(GUARD, { lean: 36, sF: 60, eF: 110, sB: 30, eB: 120, glow: 0.8, aura: 0.6, hF: 50, kF: 30, hB: -40, kB: 30, x: 0.04 }),
		w(GUARD, { lean: 14 }),
		GUARD,
	],
	RisingStrike: [
		w(GUARD, { lean: 20, hF: 60, kF: 110, hB: -10, kB: 115, glow: 0.5 }),
		{ lean: 0, sF: 170, eF: 0, sB: 30, eB: 90, hF: 30, kF: 60, hB: -20, kB: 90, glow: 1, strike: "handF", hip: 0.5 },
		{ lean: -10, sF: 175, eF: 0, sB: 40, eB: 80, hF: 60, kF: 90, hB: 20, kB: 100, glow: 1, strike: "handF", hip: 0.46, rot: -60 },
		{ lean: 0, sF: 120, eF: 40, sB: 60, eB: 80, hF: 80, kF: 110, hB: 50, kB: 110, glow: 0.6, hip: 0.5, rot: -300 },
		{ lean: 0, sF: 70, eF: 70, sB: 50, eB: 80, hF: 40, kF: 40, hB: 0, kB: 40, glow: 0.2, hip: 0.58, rot: -360 },
		w(GUARD, { rot: -360 }),
	],
	DiveKick: [
		{ lean: 4, sF: 150, eF: 20, sB: 130, eB: 20, hF: 60, kF: 90, hB: 30, kB: 80, hip: 0.56, glow: 0.3 },
		{ lean: -30, sF: 160, eF: 10, sB: 150, eB: 10, hF: 90, kF: 120, hB: 60, kB: 120, hip: 0.54, glow: 0.6, rot: -20 },
		{ lean: -20, sF: 140, eF: 20, sB: 120, eB: 20, hF: 60, kF: 0, hB: 20, kB: 100, hip: 0.54, glow: 1, rot: 40, strike: "footF" },
		{ lean: -20, sF: 140, eF: 20, sB: 120, eB: 20, hF: 60, kF: 0, hB: 20, kB: 100, hip: 0.54, glow: 0.8, rot: 40, strike: "footF" },
		{ lean: 0, sF: 60, eF: 70, sB: 40, eB: 70, hF: 40, kF: 60, hB: 0, kB: 60, hip: 0.58 },
		GUARD,
	],
	OverheadLeap: [
		w(GUARD, { lean: 10, hF: 60, kF: 110, hB: -10, kB: 115, sF: 20, eF: 80, glow: 0.4 }),
		{ lean: -10, sF: 175, eF: 20, sB: 170, eB: 30, hF: 70, kF: 100, hB: 20, kB: 100, hip: 0.5, glow: 0.8 },
		{ lean: 30, sF: 60, eF: 0, sB: 55, eB: 10, hF: 60, kF: 70, hB: -10, kB: 60, hip: 0.54, glow: 1, strike: "weapon" },
		{ lean: 34, sF: 40, eF: 0, sB: 35, eB: 10, hF: 50, kF: 90, hB: -20, kB: 100, glow: 0.8, strike: "weapon" },
		w(GUARD, { lean: 16, hF: 50, kF: 80 }),
		GUARD,
	],
	Teleport: [
		w(GUARD, { lean: 10, sF: 60, eF: 100, sB: 70, eB: 90, glow: 0.5, open: true }),
		w(GUARD, { lean: 14, sF: 80, eF: 90, sB: 85, eB: 85, glow: 1, open: true, hF: 50, kF: 90, hB: -10, kB: 100 }),
		w(GUARD, { lean: 20, sF: 90, eF: 0, sB: -30, eB: 20, glow: 1, strike: "handF", x: 0.03 }),
		w(GUARD, { lean: 20, sF: 88, eF: 5, sB: -30, eB: 20, glow: 0.6, x: 0.03 }),
		w(GUARD, { lean: 8 }),
		GUARD,
	],
	Counter: [
		w(GUARD, { lean: -2, sF: 70, eF: 110, sB: 70, eB: 110, glow: 0.6, open: true, aura: 0.3 }),
		w(GUARD, { lean: -4, sF: 75, eF: 115, sB: 75, eB: 115, glow: 0.9, open: true, aura: 0.5, hF: 20, kF: 30, hB: -20, kB: 30 }),
		w(GUARD, { lean: 18, sF: 90, eF: 0, sB: 80, eB: 10, glow: 1, open: true, strike: "handF", x: 0.03 }),
		w(GUARD, { lean: 18, sF: 88, eF: 4, sB: 80, eB: 10, glow: 0.7, open: true, x: 0.03 }),
		w(GUARD, { lean: 6 }),
		GUARD,
	],
	CommandGrab: [
		w(GUARD, { lean: 6, sF: 60, eF: 60, sB: 50, eB: 60, glow: 0.3, open: true }),
		w(GUARD, { lean: 26, sF: 80, eF: 30, sB: 75, eB: 30, open: true, x: 0.02, hF: 40, kF: 30 }),
		w(GUARD, { lean: 30, sF: 92, eF: 5, sB: 88, eB: 5, open: true, x: 0.04, strike: "handF", hF: 44, kF: 30 }),
		w(GUARD, { lean: 30, sF: 90, eF: 10, sB: 86, eB: 10, open: true, x: 0.04 }),
		w(GUARD, { lean: 10 }),
		GUARD,
	],
	Hook: [
		w(GUARD, { lean: -8, sF: -30, eF: 60, glow: 0.4 }),
		w(GUARD, { lean: -12, sF: 150, eF: 40, glow: 0.7, head: -4 }),
		w(GUARD, { lean: 16, sF: 95, eF: 0, sB: 30, eB: 90, glow: 1, strike: "handF", x: 0.03 }),
		w(GUARD, { lean: -6, sF: 60, eF: 90, sB: 30, eB: 100, glow: 0.6, x: -0.01 }),
		w(GUARD, { lean: 0 }),
		GUARD,
	],
	LongThrust: [
		w(GUARD, { lean: -8, sF: 60, eF: 60, sB: 40, eB: 80, glow: 0.3 }),
		w(GUARD, { lean: -14, sF: 40, eF: 80, sB: 20, eB: 90, glow: 0.6, hF: 30, kF: 50, hB: -30, kB: 20 }),
		w(GUARD, { lean: 26, sF: 88, eF: 0, sB: 80, eB: 20, glow: 1, x: 0.05, hF: 60, kF: 40, hB: -50, kB: 10, strike: "weapon" }),
		w(GUARD, { lean: 26, sF: 88, eF: 0, sB: 80, eB: 20, glow: 0.7, x: 0.05, hF: 60, kF: 40, hB: -50, kB: 10 }),
		w(GUARD, { lean: 8 }),
		GUARD,
	],
	Trap: [
		w(GUARD, { lean: 0, sF: 120, eF: 40, glow: 0.4 }),
		w(GUARD, { lean: -6, sF: 150, eF: 30, glow: 0.7, open: true }),
		w(GUARD, { lean: 24, sF: 50, eF: 0, glow: 1, open: true, strike: "handF", hF: 40, kF: 60 }),
		w(GUARD, { lean: 24, sF: 45, eF: 5, glow: 0.6, open: true, hF: 40, kF: 60 }),
		w(GUARD, { lean: 8 }),
		GUARD,
	],
};

const POWER1 = w(GUARD, { lean: -4, sF: 100, eF: 110, sB: 95, eB: 115, glow: 0.6, aura: 0.6 });
const POWER2 = w(GUARD, { lean: -10, head: -10, sF: 170, eF: 10, sB: 160, eB: 20, glow: 1, aura: 1, open: true, hip: 0.6 });
const RECOVER = w(GUARD, { lean: 8, glow: 0.3, aura: 0.3 });

function superKeys(strike) {
	return [POWER1, POWER2, POWER2, ...strike, RECOVER, GUARD];
}

const SUPERS = {
	Rush: superKeys([
		{ lean: 44, sF: 92, eF: 0, sB: -50, eB: 30, hF: 40, kF: 30, hB: -50, kB: 50, glow: 1, aura: 1, x: 0.05, strike: "handF" },
		{ lean: 40, sF: 90, eF: 5, sB: -50, eB: 30, hF: 40, kF: 30, hB: -50, kB: 50, glow: 0.8, aura: 0.8, x: 0.05 },
	]),
	Launcher: superKeys([
		{ lean: 0, sF: 175, eF: 0, sB: 30, eB: 90, hF: 30, kF: 60, hB: -20, kB: 90, glow: 1, aura: 1, hip: 0.5, strike: "handF" },
		{ lean: -6, sF: 170, eF: 10, sB: 40, eB: 80, hF: 60, kF: 90, hB: 20, kB: 100, glow: 0.8, aura: 0.8, hip: 0.52 },
	]),
	Beam: superKeys([
		{ lean: 18, sF: 90, eF: 0, sB: 86, eB: 4, hF: 40, kF: 40, hB: -40, kB: 20, glow: 1, aura: 1, open: true, x: 0.02, strike: "handF" },
		{ lean: 18, sF: 90, eF: 0, sB: 86, eB: 4, hF: 40, kF: 40, hB: -40, kB: 20, glow: 1, aura: 0.9, open: true, x: 0.02 },
	]),
	Barrage: superKeys([
		w(GUARD, { lean: 18, sF: 92, eF: 0, sB: 40, eB: 110, glow: 1, aura: 1, x: 0.03, strike: "handF" }),
		w(GUARD, { lean: 18, sF: 40, eF: 110, sB: 92, eB: 0, glow: 1, aura: 1, x: 0.03, strike: "handB" }),
	]),
	Grab: superKeys([
		w(GUARD, { lean: 30, sF: 92, eF: 5, sB: 88, eB: 5, glow: 1, aura: 1, open: true, x: 0.04, strike: "handF" }),
		w(GUARD, { lean: 30, sF: 90, eF: 10, sB: 86, eB: 10, glow: 0.8, aura: 0.8, open: true, x: 0.04 }),
	]),
	Counter: superKeys([
		w(GUARD, { lean: -4, sF: 75, eF: 115, sB: 75, eB: 115, glow: 1, aura: 1, open: true }),
		w(GUARD, { lean: 18, sF: 90, eF: 0, sB: 80, eB: 10, glow: 1, aura: 1, open: true, x: 0.03, strike: "handF" }),
	]),
};

// Совпадает по рядам с Config/Animations.luau (0..11) — этого хватает, дальше работает автозамена.
const ROWS = ["Idle", "Walk", "Dash", "Jump", "Crouch", "Block", "Light", "Heavy", "Special", "Super", "Hit", "Knockdown"];
const ROW_META = {
	Idle: { frames: 6, loop: true },
	Walk: { frames: 6, loop: true },
	Dash: { frames: 4, loop: false },
	Jump: { frames: 4, loop: false },
	Crouch: { frames: 2, loop: false },
	Block: { frames: 2, loop: false },
	Light: { frames: 4, loop: false },
	Heavy: { frames: 5, loop: false },
	Special: { frames: 6, loop: false },
	Super: { frames: 8, loop: false },
	Hit: { frames: 2, loop: false },
	Knockdown: { frames: 4, loop: false },
};

function keysFor(animation, specialKind, superDelivery) {
	if (animation === "Special") return SPECIALS[specialKind] || SPECIALS.Projectile;
	if (animation === "Super") return SUPERS[superDelivery] || SUPERS.Rush;
	return COMMON[animation] || COMMON.Idle;
}

const NUMERIC = ["lean", "head", "sF", "eF", "sB", "eB", "hF", "kF", "hB", "kB", "drop", "x", "rot", "glow", "aura"];

function lerpPose(a, b, t) {
	const out = {};
	for (const key of NUMERIC) out[key] = (a[key] || 0) + ((b[key] || 0) - (a[key] || 0)) * t;
	out.hip = a.hip !== undefined && b.hip !== undefined ? a.hip + (b.hip - a.hip) * t : t < 0.5 ? a.hip : b.hip;
	out.strike = t < 0.5 ? a.strike : b.strike;
	out.open = t < 0.5 ? a.open : b.open;
	return out;
}

// Сэмплирует позу для конкретного (0-based) кадра ряда анимации — кадры равномерно
// покрывают ключевые позы (как RigPoses.keys + прогресс по фреймдате в Rig.show).
function poseForFrame(animation, frameIndex, frameCount, specialKind, superDelivery) {
	const keys = keysFor(animation, specialKind, superDelivery);
	if (keys.length === 1) return keys[0];
	const progress = frameCount <= 1 ? 0 : frameIndex / (frameCount - 1);
	const pos = Math.min(progress, 1) * (keys.length - 1);
	const index = Math.floor(pos);
	const nextIndex = Math.min(index + 1, keys.length - 1);
	return lerpPose(keys[index], keys[nextIndex], pos - index);
}

module.exports = { GUARD, COMMON, SPECIALS, SUPERS, ROWS, ROW_META, keysFor, lerpPose, poseForFrame };
