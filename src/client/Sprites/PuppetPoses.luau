--!strict
--[[
	Ключевые позы процедурной «куклы» — временной замены спрайтов, пока нет арта.
	Углы в градусах: у рук и ног 0 — вниз, 90 — вперёд, 180 — вверх; lean > 0 — наклон вперёд.
	hip — высота бёдер в долях клетки спрайта (0 — верх, 1 — низ). Если не задана,
	кукла «ставится на пол» по нижней ступне. drop — небольшое проседание (дыхание, шаги).
]]

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)

export type Pose = {
	lean: number,
	armF: number,
	armB: number,
	legF: number,
	legB: number,
	hip: number?,
	drop: number?,
	x: number?,
	glow: number?,
}

local P: { [Types.AnimationName]: { Pose } } = {
	Idle = {
		{ lean = 4, armF = 35, armB = 20, legF = 14, legB = -14 },
		{ lean = 5, armF = 38, armB = 23, legF = 14, legB = -14, drop = 0.008 },
		{ lean = 6, armF = 40, armB = 25, legF = 14, legB = -14, drop = 0.012 },
		{ lean = 5, armF = 38, armB = 23, legF = 14, legB = -14, drop = 0.008 },
	},
	Walk = {
		{ lean = 6, armF = 10, armB = 45, legF = 26, legB = -22 },
		{ lean = 6, armF = 22, armB = 32, legF = 10, legB = -6, drop = 0.012 },
		{ lean = 6, armF = 35, armB = 20, legF = -8, legB = 10, drop = 0.004 },
		{ lean = 6, armF = 45, armB = 10, legF = -22, legB = 26 },
		{ lean = 6, armF = 32, armB = 22, legF = -6, legB = 10, drop = 0.012 },
		{ lean = 6, armF = 20, armB = 35, legF = 10, legB = -8, drop = 0.004 },
	},
	Dash = {
		{ lean = 18, armF = -15, armB = -30, legF = 35, legB = -35 },
		{ lean = 26, armF = -30, armB = -45, legF = 48, legB = -48, drop = 0.02 },
		{ lean = 22, armF = -20, armB = -35, legF = 40, legB = -40, drop = 0.01 },
		{ lean = 10, armF = 20, armB = 10, legF = 20, legB = -20 },
	},
	Jump = {
		{ lean = 4, armF = 150, armB = 130, legF = 30, legB = 5, hip = 0.6 },
		{ lean = 8, armF = 110, armB = 90, legF = 80, legB = 55, hip = 0.6 },
		{ lean = 6, armF = 80, armB = 60, legF = 60, legB = 30, hip = 0.6 },
		{ lean = 2, armF = 50, armB = 40, legF = 20, legB = -5, hip = 0.62 },
	},
	Crouch = {
		{ lean = 10, armF = 55, armB = 40, legF = 45, legB = -45 },
		{ lean = 14, armF = 65, armB = 50, legF = 58, legB = -55 },
	},
	Block = {
		{ lean = -4, armF = 135, armB = 120, legF = 18, legB = -24 },
		{ lean = -8, armF = 150, armB = 130, legF = 18, legB = -26, x = -0.01 },
	},
	Light = { -- «Рука»: замах → удар → удержание → возврат
		{ lean = 2, armF = 55, armB = 35, legF = 16, legB = -18 },
		{ lean = 14, armF = 92, armB = 15, legF = 20, legB = -22, x = 0.03 },
		{ lean = 14, armF = 92, armB = 15, legF = 20, legB = -22, x = 0.03 },
		{ lean = 6, armF = 55, armB = 30, legF = 16, legB = -18 },
	},
	Heavy = { -- «Нога»: высокий удар ногой
		{ lean = -4, armF = 45, armB = 60, legF = 30, legB = -12 },
		{ lean = -10, armF = 30, armB = 60, legF = 70, legB = -10 },
		{ lean = -18, armF = 20, armB = 55, legF = 102, legB = -8, x = 0.02 },
		{ lean = -18, armF = 20, armB = 55, legF = 102, legB = -8, x = 0.02 },
		{ lean = -6, armF = 40, armB = 45, legF = 40, legB = -14 },
	},
	Special = {
		{ lean = -8, armF = 25, armB = 20, legF = 20, legB = -20, glow = 0.3 },
		{ lean = -4, armF = 60, armB = 50, legF = 20, legB = -24, glow = 0.6 },
		{ lean = 18, armF = 95, armB = 85, legF = 28, legB = -26, x = 0.03, glow = 1 },
		{ lean = 18, armF = 95, armB = 85, legF = 28, legB = -26, x = 0.03, glow = 1 },
		{ lean = 8, armF = 70, armB = 55, legF = 20, legB = -20, glow = 0.5 },
		{ lean = 4, armF = 40, armB = 30, legF = 16, legB = -16, glow = 0.2 },
	},
	Super = {
		{ lean = -6, armF = 170, armB = 160, legF = 20, legB = -20, glow = 0.6 },
		{ lean = -8, armF = 175, armB = 165, legF = 22, legB = -22, glow = 1 },
		{ lean = 0, armF = 120, armB = 110, legF = 26, legB = -26, glow = 1 },
		{ lean = 22, armF = 95, armB = 90, legF = 34, legB = -30, x = 0.04, glow = 1 },
		{ lean = 22, armF = 95, armB = 90, legF = 34, legB = -30, x = 0.04, glow = 1 },
		{ lean = 12, armF = 80, armB = 60, legF = 26, legB = -26, glow = 0.7 },
		{ lean = 6, armF = 50, armB = 35, legF = 18, legB = -18, glow = 0.4 },
		{ lean = 4, armF = 38, armB = 22, legF = 14, legB = -14, glow = 0.1 },
	},
	CrouchLight = {
		{ lean = 14, armF = 60, armB = 45, legF = 50, legB = -48 },
		{ lean = 18, armF = 92, armB = 30, legF = 55, legB = -52, x = 0.03 },
		{ lean = 12, armF = 65, armB = 45, legF = 50, legB = -48 },
	},
	CrouchHeavy = { -- подсечка
		{ lean = 18, armF = 60, armB = 40, legF = 55, legB = -45 },
		{ lean = 30, armF = 70, armB = 20, legF = 80, legB = -60, hip = 0.8 },
		{ lean = 34, armF = 75, armB = 15, legF = 95, legB = -65, hip = 0.83, x = 0.02 },
		{ lean = 16, armF = 60, armB = 40, legF = 55, legB = -45 },
	},
	AirLight = {
		{ lean = 6, armF = 70, armB = 90, legF = 60, legB = 30, hip = 0.6 },
		{ lean = 14, armF = 110, armB = 70, legF = 70, legB = 40, hip = 0.6, x = 0.03 },
		{ lean = 8, armF = 80, armB = 80, legF = 60, legB = 30, hip = 0.6 },
	},
	AirHeavy = {
		{ lean = -4, armF = 90, armB = 110, legF = 70, legB = 40, hip = 0.58 },
		{ lean = -12, armF = 70, armB = 120, legF = 120, legB = 20, hip = 0.56, x = 0.02 },
		{ lean = -12, armF = 70, armB = 120, legF = 120, legB = 20, hip = 0.56, x = 0.02 },
		{ lean = -2, armF = 80, armB = 100, legF = 70, legB = 40, hip = 0.58 },
	},
	Hit = {
		{ lean = -24, armF = -20, armB = -35, legF = 10, legB = -26, x = -0.03 },
		{ lean = -14, armF = 5, armB = -10, legF = 12, legB = -22, x = -0.015 },
	},
	Knockdown = {
		{ lean = -40, armF = 30, armB = 10, legF = 40, legB = 20 },
		{ lean = -70, armF = 120, armB = 100, legF = 70, legB = 60, hip = 0.86 },
		{ lean = -84, armF = 170, armB = 160, legF = 86, legB = 82, hip = 0.9 },
		{ lean = -86, armF = 175, armB = 165, legF = 88, legB = 84, hip = 0.91 },
	},
	Win = {
		{ lean = -4, armF = 170, armB = 25, legF = 16, legB = -16 },
		{ lean = -6, armF = 176, armB = 20, legF = 16, legB = -16, drop = 0.01 },
		{ lean = -4, armF = 168, armB = 30, legF = 16, legB = -16 },
		{ lean = -2, armF = 160, armB = 35, legF = 16, legB = -16, drop = 0.006 },
	},
	Lose = {
		{ lean = 20, armF = 10, armB = 5, legF = 60, legB = 40, hip = 0.76 },
		{ lean = 32, armF = 5, armB = 0, legF = 78, legB = 70, hip = 0.8 },
	},
}

return table.freeze(P)
