--!strict
--[[
	Анимации бойцов по умолчанию: число кадров, частота и зацикленность.
	Спрайт-лист персонажа (Characters[..].sprites) может переопределить строку, число кадров и fps
	для каждой анимации. Анимации с driven = true (удары) проигрываются не по времени,
	а по фреймдате приёма: startup → active → recovery (см. client/Fight/AnimationSelect).
]]

local Types = require(script.Parent.Parent.Types)
local deepFreeze = require(script.Parent.Parent.Util.deepFreeze)

export type AnimationDef = {
	frames: number,
	fps: number,
	loop: boolean,
	driven: boolean,
	row: number, -- строка в стандартной раскладке спрайт-листа
}

local Animations: { [Types.AnimationName]: AnimationDef } = {
	Idle = { frames = 6, fps = 5, loop = true, driven = false, row = 0 },
	Walk = { frames = 6, fps = 10, loop = true, driven = false, row = 1 },
	Dash = { frames = 4, fps = 14, loop = false, driven = false, row = 2 },
	Jump = { frames = 4, fps = 8, loop = false, driven = false, row = 3 },
	Crouch = { frames = 2, fps = 16, loop = false, driven = false, row = 4 },
	Block = { frames = 2, fps = 16, loop = false, driven = false, row = 5 },
	Light = { frames = 4, fps = 0, loop = false, driven = true, row = 6 },
	Light2 = { frames = 4, fps = 0, loop = false, driven = true, row = 18 },
	Light3 = { frames = 4, fps = 0, loop = false, driven = true, row = 19 },
	BackJump = { frames = 16, fps = 24, loop = false, driven = false, row = 20 },
	Heavy = { frames = 5, fps = 0, loop = false, driven = true, row = 7 },
	Special = { frames = 6, fps = 0, loop = false, driven = true, row = 8 },
	Super = { frames = 8, fps = 0, loop = false, driven = true, row = 9 },
	Hit = { frames = 2, fps = 12, loop = false, driven = false, row = 10 },
	Knockdown = { frames = 4, fps = 10, loop = false, driven = false, row = 11 },
	WakeUp = { frames = 4, fps = 12, loop = false, driven = false, row = 21 },
	Win = { frames = 4, fps = 6, loop = true, driven = false, row = 12 },
	Lose = { frames = 2, fps = 4, loop = false, driven = false, row = 13 },
	-- Необязательные варианты ударов (если в листе их нет — берутся Light/Heavy).
	CrouchLight = { frames = 3, fps = 0, loop = false, driven = true, row = 14 },
	CrouchHeavy = { frames = 4, fps = 0, loop = false, driven = true, row = 15 },
	AirLight = { frames = 3, fps = 0, loop = false, driven = true, row = 16 },
	AirHeavy = { frames = 4, fps = 0, loop = false, driven = true, row = 17 },
}

-- Запасные анимации, если в спрайт-листе персонажа какой-то нет.
local FALLBACKS: { [Types.AnimationName]: Types.AnimationName } = {
	Dash = "Walk",
	Block = "Crouch",
	Special = "Heavy",
	Super = "Special",
	Lose = "Knockdown",
	Win = "Idle",
	CrouchLight = "Light",
	CrouchHeavy = "Heavy",
	AirLight = "Light",
	AirHeavy = "Heavy",
	Light2 = "Light",
	Light3 = "Light",
	BackJump = "Jump",
	WakeUp = "Crouch",
	Pulled = "Hit",
	Grabbed = "Hit",
	Lifted = "Hit",
	Thrown = "Knockdown",
	Launched = "Hit",
	Slammed = "Knockdown",
	Bound = "Hit",
	Suspended = "Hit",
}

return deepFreeze({
	defaults = Animations,
	fallbacks = FALLBACKS,
})
